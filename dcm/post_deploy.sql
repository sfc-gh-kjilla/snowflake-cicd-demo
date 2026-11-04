-- Runs after `snow dcm deploy` (DCM definitions can't contain INSERT).
-- Companion scripts don't support Jinja, so the pipeline supplies <% db %>
-- through `snow sql -D "db=..."`. Safe to re-run: seeds only an empty table.
INSERT INTO <% db %>.APP_DCM.ORDERS
SELECT * FROM VALUES
  (1, 101, '2026-10-01'::DATE, 120.00, 'SHIPPED'),
  (2, 102, '2026-10-02'::DATE,  75.50, 'SHIPPED'),
  (3, 101, '2026-10-05'::DATE, 210.25, 'PENDING'),
  (4, 103, '2026-10-07'::DATE,  42.00, 'CANCELLED')
WHERE (SELECT COUNT(*) FROM <% db %>.APP_DCM.ORDERS) = 0;
