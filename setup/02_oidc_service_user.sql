-- Step 2 of 2 per environment (primary path): OIDC service user.
-- Works for any OIDC issuer; the pipeline's CI platform decides the values.
--
-- Concourse (idtoken var source, subject_scope: job):
--   snow sql -f setup/02_oidc_service_user.sql -D "env=dev" -D "ENV=DEV" \
--     -D "issuer=https://<public-concourse-issuer>" \
--     -D "subject=<team>/<pipeline>//deploy-dev" \
--     -D "audience=<org>-<account>.snowflakecomputing.com"
--
-- GitHub Actions (alternative):
--   ... -D "issuer=https://token.actions.githubusercontent.com" \
--       -D "subject=repo:<owner>/<repo>:environment:dev" \
--       -D "audience=snowflakecomputing.com"
--
-- Get the exact iss/sub/aud by decoding one real token (see README). The
-- SUBJECT match is exact and case-sensitive. Use an account-specific audience:
-- the default snowflakecomputing.com audience is shared by all accounts.

USE ROLE ACCOUNTADMIN;

CREATE USER IF NOT EXISTS SVC_CICD_<% ENV %>
  TYPE = SERVICE
  DEFAULT_ROLE = CICD_DEPLOY_<% ENV %>
  DEFAULT_WAREHOUSE = CICD_DEMO_WH
  COMMENT = 'CI/CD OIDC service user for <% env %>'
  WORKLOAD_IDENTITY = (
    TYPE = OIDC
    ISSUER = '<% issuer %>'
    SUBJECT = '<% subject %>'
    OIDC_AUDIENCE_LIST = ('<% audience %>')
  );
GRANT ROLE CICD_DEPLOY_<% ENV %> TO USER SVC_CICD_<% ENV %>;

SHOW USER WORKLOAD IDENTITY AUTHENTICATION METHODS FOR USER SVC_CICD_<% ENV %>;
