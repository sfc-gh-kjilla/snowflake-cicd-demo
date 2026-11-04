-- Schema and tables managed by DCM. DCM computes CREATE/ALTER/DROP from these
-- desired-state definitions; removing a DEFINE drops the object on deploy.

DEFINE SCHEMA {{db}}.APP_DCM
    COMMENT = 'Managed by DCM project {{db}}.DCM.DEMO_PROJECT'
    DATA_RETENTION_TIME_IN_DAYS = {{retention_days}};

DEFINE TABLE {{db}}.APP_DCM.ORDERS (
    ORDER_ID NUMBER,
    CUSTOMER_ID NUMBER,
    ORDER_DATE DATE,
    AMOUNT NUMBER(12, 2),
    STATUS VARCHAR
)
COMMENT = 'Demo orders';

DEFINE TABLE {{db}}.APP_DCM.DEPLOYMENT_LOG (
    DEPLOYED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    ENVIRONMENT VARCHAR,
    GIT_SHA VARCHAR,
    GIT_REF VARCHAR,
    RUN_URL VARCHAR,
    DEPLOYED_BY VARCHAR DEFAULT CURRENT_USER()
)
COMMENT = 'One row per successful pipeline deployment';
