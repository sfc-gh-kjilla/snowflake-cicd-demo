#!/usr/bin/env bash
# Concourse task entrypoint for the DCM path.
#   DCM_ACTION=plan   -> create project if missing, run plan, print the changes
#   DCM_ACTION=deploy -> plan, deploy (alias = release tag, or SHA in DEV), seed, smoke test, record
set -euo pipefail

pip install --quiet --disable-pip-version-check uv
uv tool install --quiet snowflake-cli
export PATH="$HOME/.local/bin:$PATH"
snow --version

case "${AUTH_MODE}" in
  oidc)
    export SNOWFLAKE_AUTHENTICATOR=WORKLOAD_IDENTITY
    export SNOWFLAKE_WORKLOAD_IDENTITY_PROVIDER=OIDC
    unset SNOWFLAKE_USER SNOWFLAKE_PRIVATE_KEY_RAW
    ;;
  keypair)
    export SNOWFLAKE_AUTHENTICATOR=SNOWFLAKE_JWT
    unset SNOWFLAKE_TOKEN
    ;;
  *)
    echo "Unknown AUTH_MODE '${AUTH_MODE}' (expected oidc or keypair)" >&2
    exit 1
    ;;
esac

# Release tag (UAT/PROD) or branch (DEV).
GIT_REF="$(cat release/tag 2>/dev/null || echo main)"

cd repo
GIT_SHA="$(cat .git/ref 2>/dev/null || git rev-parse HEAD)"
TARGET="${DCM_TARGET}"            # DEV | UAT | PROD (manifest target)
DB="${TARGET_DB}"

snow connection test -x

echo "--- Ensure DCM project exists for target ${TARGET}"
snow dcm create --target "${TARGET}" --from dcm --if-not-exists -x

echo "--- DCM plan (${TARGET})"
(cd dcm && snow dcm plan --target "${TARGET}" --save-output -x)
# The CLI prints the CREATE/ALTER/DROP tree above. Summarise it, fail if the
# plan isn't SUCCESSFUL, and block drops of data-holding objects (database,
# schema, table, stage) when BLOCK_DROPS=true (UAT/PROD), the pattern used by
# Snowflake's sample DCM workflows. Set ALLOW_DROPS=true on a re-run to accept
# a reviewed, intentional drop.
python3 - <<'EOF'
import collections, json, os, pathlib, sys
plan = json.loads(pathlib.Path("dcm/out/plan_result.json").read_text())
status = plan.get("status")
changes = plan.get("changeset") or []
counts = collections.Counter(c.get("type") for c in changes)
summary = ", ".join(f"{k}: {v}" for k, v in sorted(counts.items())) or "no changes"
print(f"Plan status: {status} | {summary}")
if status != "SUCCESSFUL":
    sys.exit(1)
risky = [c["object_id"].get("fqn") for c in changes
         if c.get("type") == "DROP"
         and c.get("object_id", {}).get("domain") in {"DATABASE", "SCHEMA", "TABLE", "STAGE"}]
other_drops = counts.get("DROP", 0) - len(risky)
if other_drops:
    print(f"NOTE: {other_drops} other DROP(s) (views, roles, policies ...). Review above.")
if risky:
    print("DROP of data-holding objects:", *risky, sep="\n  ")
    if os.environ.get("BLOCK_DROPS") == "true" and os.environ.get("ALLOW_DROPS") != "true":
        print("BLOCKED: re-run with ALLOW_DROPS=true after review to proceed.")
        sys.exit(1)
    print("WARNING: review before triggering the deploy job.")
EOF

if [[ "${DCM_ACTION}" == "plan" ]]; then
  echo "--- Plan only. Review the changes above, then trigger the deploy job."
  exit 0
fi

# Alias: release tag with dots replaced (v1.0.3 -> v1_0_3), else short SHA.
if [[ "${GIT_REF}" == v* ]]; then ALIAS="${GIT_REF//./_}"; else ALIAS="${GIT_SHA:0:12}"; fi
echo "--- DCM deploy (${TARGET}) alias ${ALIAS}"
(cd dcm && snow dcm deploy --target "${TARGET}" --alias "${ALIAS}" -x)

echo "--- post_deploy.sql (seed data)"
snow sql -x -f dcm/post_deploy.sql -D "db=${DB}" -D "schema=APP_DCM"

echo "--- Smoke tests"
snow sql -x -f tests/smoke_tests.sql -D "db=${DB}" -D "schema=APP_DCM"

echo "--- Record deployment"
snow sql -x -f deploy/record_deployment.sql -D "db=${DB}" -D "schema=APP_DCM" \
  -D "env=${DEPLOY_ENV}" -D "sha=${GIT_SHA}" -D "ref=${GIT_REF}" -D "run_url=concourse:dcm-${DEPLOY_ENV}"
