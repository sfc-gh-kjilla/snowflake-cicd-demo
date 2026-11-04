#!/usr/bin/env bash
# Concourse task entrypoint for the DCM path.
#   DCM_ACTION=plan   -> create project if missing, run plan, print the changes
#   DCM_ACTION=deploy -> plan, deploy (alias = commit SHA), seed, smoke test, record
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

cd repo
GIT_SHA="$(cat .git/ref 2>/dev/null || git rev-parse HEAD)"
TARGET="${DCM_TARGET}"            # DEV | QA | PROD (manifest target)
DB="${TARGET_DB}"

snow connection test -x

echo "--- Ensure DCM project exists for target ${TARGET}"
snow dcm create --target "${TARGET}" --from dcm --if-not-exists -x

echo "--- DCM plan (${TARGET})"
(cd dcm && snow dcm plan --target "${TARGET}" --save-output -x)
# The CLI prints the CREATE/ALTER/DROP tree above; fail loudly if the saved
# plan isn't SUCCESSFUL, and call out drops for the approver.
python3 - <<'EOF'
import json, pathlib, sys
plan = json.loads(pathlib.Path("dcm/out/plan_result.json").read_text())
status = plan.get("status")
drops = json.dumps(plan.get("changeset", "")).upper().count('"DROP"')
print(f"Plan status: {status} | DROP operations: {drops}")
if drops:
    print("WARNING: this plan DROPS objects. Review before triggering the deploy job.")
if status != "SUCCESSFUL":
    sys.exit(1)
EOF

if [[ "${DCM_ACTION}" == "plan" ]]; then
  echo "--- Plan only. Review the changes above, then trigger the deploy job."
  exit 0
fi

echo "--- DCM deploy (${TARGET}) alias ${GIT_SHA:0:12}"
(cd dcm && snow dcm deploy --target "${TARGET}" --alias "${GIT_SHA:0:12}" -x)

echo "--- post_deploy.sql (seed data)"
snow sql -x -f dcm/post_deploy.sql -D "db=${DB}"

echo "--- Smoke tests"
snow sql -x -f tests/smoke_tests.sql -D "db=${DB}" -D "schema=APP_DCM"

echo "--- Record deployment"
snow sql -x -f deploy/record_deployment.sql -D "db=${DB}" -D "schema=APP_DCM" \
  -D "env=${DEPLOY_ENV}" -D "sha=${GIT_SHA}" -D "ref=main" -D "run_url=concourse:dcm-${DEPLOY_ENV}"
