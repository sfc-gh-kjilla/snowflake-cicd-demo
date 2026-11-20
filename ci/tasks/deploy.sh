#!/usr/bin/env bash
# Concourse task entrypoint: install Snowflake CLI, configure auth, deploy.
set -euo pipefail

pip install --quiet --disable-pip-version-check uv
uv tool install --quiet snowflake-cli
export PATH="$HOME/.local/bin:$PATH"
snow --version

case "${AUTH_MODE}" in
  oidc)
    # snow -x reads these to build a workload-identity connection.
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

# Release tag (UAT/PROD) or branch (DEV), recorded in DEPLOYMENT_LOG.
export GIT_REF="$(cat release/tag 2>/dev/null || echo main)"

cd repo
export GIT_SHA="$(cat .git/ref 2>/dev/null || git rev-parse HEAD)"
export RUN_URL="concourse:${DEPLOY_ENV}"

snow connection test -x
bash scripts/deploy.sh
