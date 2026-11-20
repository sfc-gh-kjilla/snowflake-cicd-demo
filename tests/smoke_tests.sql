-- Each check raises an error on failure, so `snow sql` exits non-zero and the
-- CI job fails, blocking promotion to the next environment.
EXECUTE IMMEDIATE $$
DECLARE
  n INTEGER;
  bad INTEGER;
  no_orders EXCEPTION (-20001, 'Smoke test failed: ORDERS is empty');
  bad_amounts EXCEPTION (-20002, 'Smoke test failed: negative or NULL AMOUNT in ORDERS');
  bad_summary EXCEPTION (-20003, 'Smoke test failed: CUSTOMER_SUMMARY returned no rows');
BEGIN
  SELECT COUNT(*) INTO :n FROM <% db %>.<% schema %>.ORDERS;
  IF (n = 0) THEN RAISE no_orders; END IF;

  SELECT COUNT(*) INTO :bad FROM <% db %>.<% schema %>.ORDERS
  WHERE AMOUNT IS NULL OR AMOUNT < 0;
  IF (bad > 0) THEN RAISE bad_amounts; END IF;

  SELECT COUNT(*) INTO :n FROM <% db %>.<% schema %>.CUSTOMER_SUMMARY;
  IF (n = 0) THEN RAISE bad_summary; END IF;

  RETURN 'All smoke tests passed';
END;
$$;
