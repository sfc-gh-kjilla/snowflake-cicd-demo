-- OPTIONAL: only if the account restricts inbound IPs.
-- A user can have one network policy; a user-level policy overrides the
-- account-level one. Check first:
--   SHOW PARAMETERS LIKE 'NETWORK_POLICY' IN ACCOUNT;
--   SHOW PARAMETERS LIKE 'NETWORK_POLICY' FOR USER SVC_CICD_<% ENV %>;
--
-- Concourse (self-hosted workers): allow the workers' static egress IPs.
--   snow sql -f setup/04_network_policy_optional.sql -D "ENV=DEV" \
--     -D "rule_value=('203.0.113.10/32')"
-- GitHub-hosted runners instead: replace the rule below with the managed rule
--   SNOWFLAKE.NETWORK_SECURITY.GITHUBACTIONS_GLOBAL

USE ROLE ACCOUNTADMIN;

CREATE NETWORK RULE IF NOT EXISTS CICD_DEMO_<% ENV %>.APP.CI_WORKER_EGRESS
  MODE = INGRESS TYPE = IPV4
  VALUE_LIST = <% rule_value %>
  COMMENT = 'Concourse worker egress IPs';

CREATE NETWORK POLICY IF NOT EXISTS CICD_POLICY_<% ENV %>
  ALLOWED_NETWORK_RULE_LIST = ('CICD_DEMO_<% ENV %>.APP.CI_WORKER_EGRESS')
  COMMENT = 'Allow CI workers only';

ALTER USER SVC_CICD_<% ENV %> SET NETWORK_POLICY = CICD_POLICY_<% ENV %>;
