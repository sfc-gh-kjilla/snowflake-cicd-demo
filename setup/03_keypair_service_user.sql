-- Fallback path: key-pair service user, for when the CI issuer can't be made
-- publicly reachable (for example a laptop Concourse without a tunnel).
-- The private key lives in the CI secret store (Concourse: Vault / CredHub /
-- --load-vars-from a local file never committed to Git) and must be rotated.
--
-- Generate a key pair (unencrypted PKCS#8 keeps the demo simple):
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out snowflake_key.p8
--   openssl rsa -in snowflake_key.p8 -pubout | grep -v -- '-----' | tr -d '\n'
--
--   snow sql -f setup/03_keypair_service_user.sql -D "env=dev" -D "ENV=DEV" \
--     -D "public_key=<base64 body from the command above>"

USE ROLE ACCOUNTADMIN;

CREATE USER IF NOT EXISTS SVC_CICD_<% ENV %>_KP
  TYPE = SERVICE
  DEFAULT_ROLE = CICD_DEPLOY_<% ENV %>
  DEFAULT_WAREHOUSE = CICD_DEMO_WH
  COMMENT = 'CI/CD key-pair service user for <% env %> (fallback)';
ALTER USER SVC_CICD_<% ENV %>_KP SET RSA_PUBLIC_KEY = '<% public_key %>';
GRANT ROLE CICD_DEPLOY_<% ENV %> TO USER SVC_CICD_<% ENV %>_KP;
