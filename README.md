# Snowflake CI/CD Demo: One Commit, Three Environments

Concourse CI + Snowflake CLI + OIDC workload identity (Concourse `idtoken`).
Release-based promotion:

1. Every commit to `main` deploys to DEV automatically (`deploy-dev`, `dcm-dev`).
2. When DEV passes, `create-release` tags `vX.Y.Z` and publishes a GitHub Release.
3. A new release deploys to UAT automatically (`deploy-uat`, `dcm-deploy-uat`).
4. After UAT sign-off an operator triggers PROD with the same release
   (`passed:` UAT). The release tag and SHA are recorded in every environment.

A GitHub Actions version of the same pipeline is in `alternatives/github-actions/`.

> **Demo vs. production.** The customer runs one Snowflake account per
> environment. This demo uses one account (`SFSENORTHAMERICA-KJILLA`) with three
> databases (`CICD_DEMO_DEV`, `_UAT`, `_PROD`) standing in for the three
> accounts. Each environment still has its own service user, role and OIDC
> trust, so moving to real accounts only changes `snowflake_account` per job.

## Layout

```
ci/pipeline.yml                 Concourse pipeline: dev -> create-release -> uat -> prod
ci/tasks/deploy.yml / .sh       task: install Snowflake CLI, set auth, run scripts/deploy.sh
ci/tasks/create-release.yml / .sh  next vX.Y.Z (patch bump) for the github-release put
ci/vars.example.yml             copy to ci/vars.yml (git-ignored)
ci/docker-compose.yml           local Concourse 8.3.2 for the demo
setup/01_env_objects.sql        warehouse, database, schema, deploy role (per env)
setup/02_oidc_service_user.sql  OIDC service user, any issuer (per env) - primary
setup/03_keypair_service_user.sql  key-pair service user (per env) - fallback
setup/04_network_policy_optional.sql  only if the account restricts inbound IPs
migrations/V*.sql               idempotent DDL
tests/smoke_tests.sql           assertions; failure stops promotion
deploy/record_deployment.sql    writes the commit SHA to DEPLOYMENT_LOG
scripts/deploy.sh               CI-agnostic: migrations -> smoke tests -> record
alternatives/github-actions/    same pipeline as GitHub workflows
```

## Option 2: DCM path (declarative)

The same app is also defined as a DCM project in `dcm/`. Its jobs are on the **dcm**
tab of the pipeline and manage a separate schema, `APP_DCM`, so they never overlap
with the scripted path (`APP`).

```
dcm/manifest.yml                    targets DEV / UAT / PROD (one account each at the customer)
dcm/sources/definitions/tables.sql  DEFINE SCHEMA APP_DCM, ORDERS, DEPLOYMENT_LOG
dcm/sources/definitions/serve.sql   DEFINE VIEW CUSTOMER_SUMMARY
dcm/sources/definitions/governance.sql  database roles, grants, tag, masking policy + ATTACH (governance as code)
dcm/post_deploy.sql                 seed rows (DCM definitions can't contain INSERT)
ci/tasks/dcm.sh                     create-if-missing -> plan -> drop guard -> [deploy -> seed -> smoke tests -> record]
scripts/dev-sandbox.sh              isolated developer sandbox in DEV: own DCM project + name suffix, --plan / --purge
setup/05_dcm_prereqs.sql            DCM schema + CREATE DCM PROJECT / DATABASE ROLE grants per environment
```

Flow: `dcm-dev` (auto: plan + deploy) → `create-release` → `dcm-deploy-uat` (auto on
the new release) → `dcm-plan-prod` (manual, read the plan) → `dcm-deploy-prod` (manual).
UAT/PROD deploys use the release tag as the DCM deployment alias (`v1.0.3` → `v1_0_3`;
DEV uses the short SHA), so `snow dcm list-deployments` ties every deployment to a release.

Demo talking points:
- Add a column to `ORDERS` in `tables.sql`, commit: `dcm-plan-prod` shows `ALTER TABLE ... ADD COLUMN`.
- Delete the `CUSTOMER_SUMMARY` definition: the plan shows a **DROP** and the job lists it for review. Delete the `ORDERS` table definition instead: UAT/PROD jobs **fail** (`BLOCK_DROPS=true` blocks drops of databases, schemas, tables and stages; re-run with `ALLOW_DROPS=true` after review). DCM deletes undefined objects, so the plan gate matters.
- Developer sandbox: `SNOW_CONN=<conn> bash scripts/dev-sandbox.sh <name>` deploys `APP_DCM_<NAME>`, `GOV_DCM_<NAME>`, ... through its own project `DEMO_PROJECT_<NAME>`; `--plan` previews, `--purge` removes everything. Shared targets use an empty `suffix`, so they are unaffected.
- Governance: `SELECT * FROM <db>.APP_DCM.CUSTOMER_SUMMARY` as SYSADMIN (holds PII_READER) shows real CUSTOMER_IDs; as the deploy role it shows NULL. Delete `GRANT DATABASE ROLE ... TO ROLE SYSADMIN` and plan: it shows `removed DATABASE_ROLE PII_READER`. ATTACH TAG / ATTACH MASKING POLICY are Preview.
- In masking policies use `IS_DATABASE_ROLE_IN_SESSION('PII_READER')` unqualified; a fully qualified name evaluates to FALSE.
- DCM needs Snowflake CLI 3.24+ (the task installs the latest).
- With OIDC, each Concourse job has its own subject (`.../dcm-dev`, `.../dcm-deploy-uat`, ...). Add one workload identity per job to the service user with `ALTER USER ... ADD WORKLOAD IDENTITY` (up to 10 per user).

## Why the demo needs a tunnel for OIDC

Snowflake validates the Concourse-signed JWT by fetching
`<issuer>/.well-known/openid-configuration` and its JWKS over the public
internet. A laptop Concourse at `http://localhost:8080` is unreachable, so:

- **OIDC (primary):** expose Concourse through a temporary HTTPS tunnel (e.g.
  `cloudflared tunnel --url http://localhost:8080`) and use the tunnel URL as
  Concourse's external URL, which becomes the token issuer.
- **Key-pair (fallback):** set `auth_mode: keypair` in `ci/vars.yml`. No public
  URL needed.

The customer's production Concourse must meet the same requirement (or publish
discovery on a separate public URL via `--oidc-issuer-url`).

## One-time setup

### 1. Repo
Push this folder to a Git repo Concourse can clone (e.g. GitHub), then
`cp ci/vars.example.yml ci/vars.yml` and set `git_uri`, `github_owner`,
`github_repo` and `github_access_token`. The token is a fine-grained PAT on this
repo with **Contents: Read and write**; `create-release` uses it to push the tag
and publish the release.

### 2. Start Concourse
```bash
cloudflared tunnel --url http://localhost:8080      # note the https://<random>.trycloudflare.com URL
CONCOURSE_EXTERNAL_URL=https://<random>.trycloudflare.com \
  docker compose -f ci/docker-compose.yml up -d
fly -t local login -c http://localhost:8080 -u demo -p demo
curl -s https://<random>.trycloudflare.com/.well-known/openid-configuration   # must return JSON
```

### 3. Snowflake objects (ACCOUNTADMIN, once per env)
```bash
for e in dev uat prod; do
  snow sql -f setup/01_env_objects.sql -D "env=$e" -D "ENV=${e:u}"
done
```
(`${e:u}` is zsh uppercase; in bash use `${e^^}`.)

### 4a. OIDC service users (primary)
Set the pipeline (step 5), then print the real claims:
```bash
fly -t local trigger-job -j snowflake-cicd/print-token-claims -w
```
Check the output:

- header `alg` must be RS/ES 256/384/512 (Snowflake requirement)
- `iss` = `CONCOURSE_EXTERNAL_URL` (the tunnel URL)
- `aud` = `snowflake_oidc_audience` from `ci/vars.yml`
- `sub` for this helper ends in `/print-token-claims`; the deploy jobs use the
  same prefix with `/deploy-<env>`, e.g. `main/snowflake-cicd//deploy-dev`

```bash
for e in dev uat prod; do
  snow sql -f setup/02_oidc_service_user.sql -D "env=$e" -D "ENV=${e:u}" \
    -D "issuer=https://<random>.trycloudflare.com" \
    -D "subject=main/snowflake-cicd//deploy-$e" \
    -D "audience=sfsenorthamerica-kjilla.snowflakecomputing.com"
done
```
The tunnel URL changes every time `cloudflared` restarts (quick tunnels), and
ISSUER can't be altered in place, so recreate the users (or use a named
Cloudflare tunnel) if you restart it.

### 4b. Key-pair service users (fallback)
```bash
for e in dev uat prod; do
  openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out snowflake_key_$e.p8
  pub=$(openssl rsa -in snowflake_key_$e.p8 -pubout 2>/dev/null | grep -v -- '-----' | tr -d '\n')
  snow sql -f setup/03_keypair_service_user.sql -D "env=$e" -D "ENV=${e:u}" -D "public_key=$pub"
done
```
Paste each `.p8` into `ci/vars.yml` (`snowflake_private_key_<env>: |`) and set
`auth_mode: keypair`. The `.p8` files are git-ignored; delete them after the demo.

### 5. Set the pipeline
```bash
fly -t local set-pipeline -p snowflake-cicd -c ci/pipeline.yml -l ci/vars.yml
fly -t local unpause-pipeline -p snowflake-cicd
```

## Run of show (~18 minutes)

| # | Step | What to do | What to say |
|---|---|---|---|
| 1 | Pipeline tour (2 min) | Show the pipeline graph, `ci/pipeline.yml`, `migrations/`, `tests/` | "Same Concourse you run today; Snowflake CLI runs in the task." |
| 2 | Push a change (3 min) | Add `MAX(ORDER_DATE) AS LAST_ORDER_DATE` to `V002`; commit to `main` | "Git is the source of truth; environments differ only by variables." |
| 3 | DEV deploys (3 min) | Watch `deploy-dev` run; open the build log | "Short-lived Concourse token, no password stored anywhere." |
| 4 | Release + UAT (3 min) | Watch `create-release` tag `vX.Y.Z` (show the GitHub Release page), then `deploy-uat` start on its own | "Only a commit that passed DEV becomes a release. UAT always gets an immutable tag, never a branch." |
| 5 | Trigger PROD (3 min) | Click **+** on `deploy-prod` (or `fly -t local trigger-job -j snowflake-cicd/deploy-prod -w`); run the proof query | "PROD only accepts the release that passed UAT. Who can click is a team role." |
| 6 | Break it (2 min, optional) | Commit `migrations/V003__bad_row.sql` with `INSERT INTO <% db %>.<% schema %>.ORDERS VALUES (99, 101, CURRENT_DATE, -1, 'SHIPPED');` | "The smoke test fails at DEV, so no release is created and UAT/PROD never see it." Afterwards `git revert` it and run `DELETE FROM CICD_DEMO_DEV.APP.ORDERS WHERE ORDER_ID = 99;` |

Proof query:
```sql
SELECT 'DEV' env, GIT_REF, GIT_SHA, DEPLOYED_AT FROM CICD_DEMO_DEV.APP.DEPLOYMENT_LOG
UNION ALL SELECT 'UAT', GIT_REF, GIT_SHA, DEPLOYED_AT FROM CICD_DEMO_UAT.APP.DEPLOYMENT_LOG
UNION ALL SELECT 'PROD', GIT_REF, GIT_SHA, DEPLOYED_AT FROM CICD_DEMO_PROD.APP.DEPLOYMENT_LOG
ORDER BY DEPLOYED_AT DESC;
```

**Fallbacks:** (1) if OIDC fails live, `fly set-pipeline` with `auth_mode: keypair`
and re-trigger; (2) screenshot a full rehearsal run into `screenshots/` the day before.

## Troubleshooting
- `create-release` fails with 401/403/404: `github_access_token` is empty, expired, or lacks Contents write on the repo.
- Key-pair `JWT token is invalid` after renaming a user: `ALTER USER ... RENAME` keeps the old `LOGIN_NAME`; set it to the new name.
- Connection test fails with an OIDC error: issuer, subject or audience doesn't match exactly, the issuer isn't publicly reachable, or the token `alg` isn't RS/ES. Check the claims of a real token against `SHOW USER WORKLOAD IDENTITY AUTHENTICATION METHODS FOR USER SVC_CICD_DEV`.
- `Incoming request with IP ... is not allowed`: apply `setup/04_network_policy_optional.sql` with the worker egress IP.
- `Insufficient privileges`: the deploy role only owns `APP` and schemas it creates, by design.

## Cleanup
```sql
DROP DATABASE IF EXISTS CICD_DEMO_DEV; DROP DATABASE IF EXISTS CICD_DEMO_UAT; DROP DATABASE IF EXISTS CICD_DEMO_PROD;
DROP USER IF EXISTS SVC_CICD_DEV; DROP USER IF EXISTS SVC_CICD_UAT; DROP USER IF EXISTS SVC_CICD_PROD;
DROP USER IF EXISTS SVC_CICD_DEV_KP; DROP USER IF EXISTS SVC_CICD_UAT_KP; DROP USER IF EXISTS SVC_CICD_PROD_KP;
DROP ROLE IF EXISTS CICD_DEPLOY_DEV; DROP ROLE IF EXISTS CICD_DEPLOY_UAT; DROP ROLE IF EXISTS CICD_DEPLOY_PROD;
DROP WAREHOUSE IF EXISTS CICD_DEMO_WH;
```
```bash
docker compose -f ci/docker-compose.yml down -v
```
