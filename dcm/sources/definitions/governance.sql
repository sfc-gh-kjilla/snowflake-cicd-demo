-- Governance as code: access roles, grants, classification tag and masking.
-- Same reviewed path as tables: PLAN shows every GRANT / REVOKE / ATTACH /
-- DETACH before deploy, and removing a line here revokes or detaches it.
--
--   DATA_READER  read the app schema (masked CUSTOMER_ID)
--   PII_READER   DATA_READER + sees raw CUSTOMER_ID
-- At the customer, grant these database roles to functional roles
-- (FR_DATA_ENGINEER, FR_<BU>_*); in the demo PII_READER goes to SYSADMIN.
-- In the policy, database role names are unqualified: they resolve in the
-- policy's own database (a fully qualified name evaluates to FALSE).

DEFINE SCHEMA {{db}}.GOV_DCM{{suffix}}
    COMMENT = 'Governance objects (tags, policies) managed by DCM';

-- Access roles -------------------------------------------------------------
DEFINE DATABASE ROLE {{db}}.DATA_READER{{suffix}}
    COMMENT = 'Read APP_DCM{{suffix}}; CUSTOMER_ID masked';
DEFINE DATABASE ROLE {{db}}.PII_READER{{suffix}}
    COMMENT = 'DATA_READER{{suffix}} plus unmasked CUSTOMER_ID';

GRANT USAGE ON SCHEMA {{db}}.APP_DCM{{suffix}} TO DATABASE ROLE {{db}}.DATA_READER{{suffix}};
GRANT SELECT ON TABLE {{db}}.APP_DCM{{suffix}}.ORDERS TO DATABASE ROLE {{db}}.DATA_READER{{suffix}};
GRANT SELECT ON VIEW {{db}}.APP_DCM{{suffix}}.CUSTOMER_SUMMARY TO DATABASE ROLE {{db}}.DATA_READER{{suffix}};
GRANT DATABASE ROLE {{db}}.DATA_READER{{suffix}} TO DATABASE ROLE {{db}}.PII_READER{{suffix}};
GRANT DATABASE ROLE {{db}}.PII_READER{{suffix}} TO ROLE SYSADMIN;

-- Classification -----------------------------------------------------------
DEFINE TAG {{db}}.GOV_DCM{{suffix}}.SENSITIVITY
    ALLOWED_VALUES 'PII', 'INTERNAL', 'PUBLIC'
    COMMENT = 'Data classification';

ATTACH TAG {{db}}.GOV_DCM{{suffix}}.SENSITIVITY = 'PII'
    TO TABLE {{db}}.APP_DCM{{suffix}}.ORDERS COLUMN CUSTOMER_ID;
ATTACH TAG {{db}}.GOV_DCM{{suffix}}.SENSITIVITY = 'INTERNAL'
    TO SCHEMA {{db}}.APP_DCM{{suffix}};

-- Masking ------------------------------------------------------------------
DEFINE MASKING POLICY {{db}}.GOV_DCM{{suffix}}.MASK_CUSTOMER_ID
    AS (VAL NUMBER) RETURNS NUMBER ->
    CASE WHEN IS_DATABASE_ROLE_IN_SESSION('PII_READER{{suffix}}') THEN VAL ELSE NULL END
    COMMENT = 'Raw CUSTOMER_ID only for PII_READER{{suffix}}';

ATTACH MASKING POLICY {{db}}.GOV_DCM{{suffix}}.MASK_CUSTOMER_ID
    TO TABLE {{db}}.APP_DCM{{suffix}}.ORDERS COLUMN CUSTOMER_ID;
