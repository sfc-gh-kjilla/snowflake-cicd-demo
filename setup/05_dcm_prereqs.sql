-- DCM path prerequisites, once per environment (ACCOUNTADMIN).
-- A DCM project can't define its own parent schema, so the DCM schema that
-- holds the project object is created here. The deploy role then creates and
-- owns the project (snow dcm create) and the APP_DCM schema it defines.
--
--   snow sql -f setup/05_dcm_prereqs.sql -D "ENV=DEV"

USE ROLE ACCOUNTADMIN;

CREATE SCHEMA IF NOT EXISTS CICD_DEMO_<% ENV %>.DCM
  COMMENT = 'Holds the DCM project object for this environment';

GRANT USAGE ON SCHEMA CICD_DEMO_<% ENV %>.DCM TO ROLE CICD_DEPLOY_<% ENV %>;
GRANT CREATE DCM PROJECT ON SCHEMA CICD_DEMO_<% ENV %>.DCM TO ROLE CICD_DEPLOY_<% ENV %>;
-- Snowflake CLI uploads project files to a temporary stage during plan/deploy
GRANT CREATE STAGE ON SCHEMA CICD_DEMO_<% ENV %>.DCM TO ROLE CICD_DEPLOY_<% ENV %>;
