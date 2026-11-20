#!/usr/bin/env bash
# Isolated developer sandbox inside the shared DEV environment, following the
# DCM Projects "independent development" pattern: each developer (or branch)
# gets its own DCM project object plus a name suffix, so parallel work never
# overwrites DEV or another developer's objects.
#
#   scripts/dev-sandbox.sh kiran           plan + deploy APP_DCM_KIRAN, GOV_DCM_KIRAN, ...
#   scripts/dev-sandbox.sh kiran --plan    plan only
#   scripts/dev-sandbox.sh kiran --purge   drop everything the sandbox created
#
# Connection: SNOW_CONN=<name> uses `snow -c <name>`; otherwise the SNOWFLAKE_*
# environment variables (`snow -x`), as in the CI tasks.
set -euo pipefail

name="$(printf '%s' "${1:?usage: dev-sandbox.sh <name> [--plan|--purge]}" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9_' '_')"
action="${2:-deploy}"
db="${DB:-CICD_DEMO_DEV}"
project="${db}.DCM.DEMO_PROJECT_${name}"
suffix="_${name}"
if [[ -n "${SNOW_CONN:-}" ]]; then conn=(-c "${SNOW_CONN}"); else conn=(-x); fi

cd "$(dirname "$0")/.."

if [[ "${action}" == "--purge" ]]; then
  echo "--- Purge sandbox ${project} (drops all objects it manages)"
  (cd dcm && snow dcm purge "${project}" --target DEV --force "${conn[@]}")
  snow dcm drop "${project}" "${conn[@]}"
  exit 0
fi

echo "--- Sandbox ${project} (suffix ${suffix})"
snow dcm create "${project}" --target DEV --from dcm --if-not-exists "${conn[@]}"
(cd dcm && snow dcm plan "${project}" --target DEV -D "suffix='${suffix}'" "${conn[@]}")
[[ "${action}" == "--plan" ]] && exit 0

(cd dcm && snow dcm deploy "${project}" --target DEV -D "suffix='${suffix}'" --alias "sandbox_${name}" "${conn[@]}")
snow sql "${conn[@]}" -f dcm/post_deploy.sql -D "db=${db}" -D "schema=APP_DCM${suffix}"
snow sql "${conn[@]}" -f tests/smoke_tests.sql -D "db=${db}" -D "schema=APP_DCM${suffix}"
