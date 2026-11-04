#!/usr/bin/env bash
# CI-agnostic deploy: apply migrations in order, run smoke tests, record the
# deployment. Called by Concourse (ci/tasks/deploy.sh) and GitHub Actions.
# Required env: TARGET_DB, TARGET_SCHEMA, DEPLOY_ENV
# Optional env: GIT_SHA, GIT_REF, RUN_URL (falls back to GitHub's vars), SKIP_RECORD=1
set -euo pipefail

cd "$(dirname "$0")/.."

vars=(-D "db=${TARGET_DB}" -D "schema=${TARGET_SCHEMA}")

for f in migrations/V*.sql; do
  echo "--- Migration ${f}"
  snow sql -x -f "$f" "${vars[@]}"
done

echo "--- Smoke tests"
snow sql -x -f tests/smoke_tests.sql "${vars[@]}"

if [[ "${SKIP_RECORD:-0}" != "1" ]]; then
  echo "--- Record deployment"
  snow sql -x -f deploy/record_deployment.sql "${vars[@]}" \
    -D "env=${DEPLOY_ENV}" \
    -D "sha=${GIT_SHA:-${GITHUB_SHA:-local}}" \
    -D "ref=${GIT_REF:-${GITHUB_REF_NAME:-local}}" \
    -D "run_url=${RUN_URL:-local}"
fi
