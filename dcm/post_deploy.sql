-- Runs after `snow dcm deploy` (DCM definitions can't contain INSERT).
-- Companion scripts don't support Jinja, so the caller supplies <% db %> and
-- <% schema %> through `snow sql -D ...` (APP_DCM, or APP_DCM_<NAME> for a
-- developer sandbox). Safe to re-run: seeds only an empty table.
INSERT INTO <% db %>.<% schema %>.ORDERS
SELECT * FROM VALUES
  (1, 101, '2026-10-01'::DATE, 120.00, 'SHIPPED'),
  (2, 102, '2026-10-02'::DATE,  75.50, 'SHIPPED'),
  (3, 101, '2026-10-05'::DATE, 210.25, 'PENDING'),
  (4, 103, '2026-10-07'::DATE,  42.00, 'CANCELLED')
WHERE (SELECT COUNT(*) FROM <% db %>.<% schema %>.ORDERS) = 0;
