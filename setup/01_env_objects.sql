-- Step 1 of 2 per environment: warehouse, database, schema, deploy role.
-- Run once per environment as ACCOUNTADMIN. In production each environment is
-- its own Snowflake account; in the single-account demo the databases
-- CICD_DEMO_DEV / _QA / _PROD stand in for the three accounts.
--
--   snow sql -f setup/01_env_objects.sql -D "env=dev" -D "ENV=DEV"

USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS CICD_DEMO_WH
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'CI/CD demo warehouse';

CREATE DATABASE IF NOT EXISTS CICD_DEMO_<% ENV %>
  COMMENT = 'CI/CD demo - <% env %> environment';
CREATE SCHEMA IF NOT EXISTS CICD_DEMO_<% ENV %>.APP;

-- Least-privilege deploy role: DDL inside its own database only
CREATE ROLE IF NOT EXISTS CICD_DEPLOY_<% ENV %>
  COMMENT = 'CI/CD deploy role for <% env %>';
GRANT USAGE ON WAREHOUSE CICD_DEMO_WH TO ROLE CICD_DEPLOY_<% ENV %>;
GRANT USAGE, CREATE SCHEMA ON DATABASE CICD_DEMO_<% ENV %> TO ROLE CICD_DEPLOY_<% ENV %>;
GRANT OWNERSHIP ON SCHEMA CICD_DEMO_<% ENV %>.APP
  TO ROLE CICD_DEPLOY_<% ENV %> COPY CURRENT GRANTS;
GRANT ROLE CICD_DEPLOY_<% ENV %> TO ROLE SYSADMIN;
