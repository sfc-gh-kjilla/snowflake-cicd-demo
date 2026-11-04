-- Idempotent: safe to re-run on every deploy.
-- <% db %> and <% schema %> are supplied by the pipeline (snow sql -D ...).

CREATE OR ALTER TABLE <% db %>.<% schema %>.DEPLOYMENT_LOG (
  DEPLOYED_AT  TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
  ENVIRONMENT  VARCHAR,
  GIT_SHA      VARCHAR,
  GIT_REF      VARCHAR,
  RUN_URL      VARCHAR,
  DEPLOYED_BY  VARCHAR DEFAULT CURRENT_USER()
);

CREATE OR ALTER TABLE <% db %>.<% schema %>.ORDERS (
  ORDER_ID     NUMBER,
  CUSTOMER_ID  NUMBER,
  ORDER_DATE   DATE,
  AMOUNT       NUMBER(12, 2),
  STATUS       VARCHAR
);

-- Seed reference rows only when the table is empty
INSERT INTO <% db %>.<% schema %>.ORDERS
SELECT * FROM VALUES
  (1, 101, '2026-10-01'::DATE, 120.00, 'SHIPPED'),
  (2, 102, '2026-10-02'::DATE,  75.50, 'SHIPPED'),
  (3, 101, '2026-10-05'::DATE, 210.25, 'PENDING'),
  (4, 103, '2026-10-07'::DATE,  42.00, 'CANCELLED')
WHERE (SELECT COUNT(*) FROM <% db %>.<% schema %>.ORDERS) = 0;
