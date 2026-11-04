# Snowflake CI/CD Demo: One Commit, Three Environments

Concourse CI + Snowflake CLI + OIDC workload identity (Concourse `idtoken`).
Every commit to `main` deploys to DEV automatically; QA and PROD run only when
an operator triggers them, and only for a commit that passed the previous
environment. The same Git SHA is recorded in every environment.

A GitHub Actions version of the same pipeline is in `alternatives/github-actions/`.

> **Demo vs. production.** The customer runs one Snowflake account per
> environment. This demo uses one account (`SFSENORTHAMERICA-KJILLA`) with three
> databases (`CICD_DEMO_DEV`, `_QA`, `_PROD`) standing in for the three
> accounts. Each environment still has its own service user, role and OIDC
> trust, so moving to real accounts only changes `snowflake_account` per job.

## Layout

```
ci/pipeline.yml                 Concourse pipeline: deploy-dev -> deploy-qa -> deploy-prod
ci/tasks/deploy.yml / .sh       task: install Snowflake CLI, set auth, run scripts/deploy.sh
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
`cp ci/vars.example.yml ci/vars.yml` and set `git_uri`.

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
for e in dev qa prod; do
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
for e in dev qa prod; do
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
for e in dev qa prod; do
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
| 4 | Trigger QA (3 min) | Click **+** on `deploy-qa` (or `fly -t local trigger-job -j snowflake-cicd/deploy-qa -w`) | "QA only accepts a commit that passed DEV. Who can click is a team role." |
| 5 | Trigger PROD (3 min) | Trigger `deploy-prod`; run the proof query | "Same SHA in all three: provable promotion." |
| 6 | Break it (2 min, optional) | Commit `migrations/V003__bad_row.sql` with `INSERT INTO <% db %>.<% schema %>.ORDERS VALUES (99, 101, CURRENT_DATE, -1, 'SHIPPED');` | "The smoke test fails at DEV, so QA and PROD never see this commit." Afterwards `git revert` it and run `DELETE FROM CICD_DEMO_DEV.APP.ORDERS WHERE ORDER_ID = 99;` |

Proof query:
```sql
SELECT 'DEV' env, GIT_SHA, DEPLOYED_AT FROM CICD_DEMO_DEV.APP.DEPLOYMENT_LOG
UNION ALL SELECT 'QA', GIT_SHA, DEPLOYED_AT FROM CICD_DEMO_QA.APP.DEPLOYMENT_LOG
UNION ALL SELECT 'PROD', GIT_SHA, DEPLOYED_AT FROM CICD_DEMO_PROD.APP.DEPLOYMENT_LOG
ORDER BY DEPLOYED_AT DESC;
```

**Fallbacks:** (1) if OIDC fails live, `fly set-pipeline` with `auth_mode: keypair`
and re-trigger; (2) screenshot a full rehearsal run into `screenshots/` the day before.

## Troubleshooting
- Connection test fails with an OIDC error: issuer, subject or audience doesn't match exactly, the issuer isn't publicly reachable, or the token `alg` isn't RS/ES. Check the claims of a real token against `SHOW USER WORKLOAD IDENTITY AUTHENTICATION METHODS FOR USER SVC_CICD_DEV`.
- `Incoming request with IP ... is not allowed`: apply `setup/04_network_policy_optional.sql` with the worker egress IP.
- `Insufficient privileges`: the deploy role only owns `APP` and schemas it creates, by design.

## Cleanup
```sql
DROP DATABASE IF EXISTS CICD_DEMO_DEV; DROP DATABASE IF EXISTS CICD_DEMO_QA; DROP DATABASE IF EXISTS CICD_DEMO_PROD;
DROP USER IF EXISTS SVC_CICD_DEV; DROP USER IF EXISTS SVC_CICD_QA; DROP USER IF EXISTS SVC_CICD_PROD;
DROP USER IF EXISTS SVC_CICD_DEV_KP; DROP USER IF EXISTS SVC_CICD_QA_KP; DROP USER IF EXISTS SVC_CICD_PROD_KP;
DROP ROLE IF EXISTS CICD_DEPLOY_DEV; DROP ROLE IF EXISTS CICD_DEPLOY_QA; DROP ROLE IF EXISTS CICD_DEPLOY_PROD;
DROP WAREHOUSE IF EXISTS CICD_DEMO_WH;
```
```bash
docker compose -f ci/docker-compose.yml down -v
```
