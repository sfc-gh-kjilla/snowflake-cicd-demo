-- Runs last, after migrations and smoke tests succeed.
INSERT INTO <% db %>.<% schema %>.DEPLOYMENT_LOG (ENVIRONMENT, GIT_SHA, GIT_REF, RUN_URL)
VALUES ('<% env %>', '<% sha %>', '<% ref %>', '<% run_url %>');

SELECT ENVIRONMENT, GIT_SHA, DEPLOYED_AT, DEPLOYED_BY
FROM <% db %>.<% schema %>.DEPLOYMENT_LOG
ORDER BY DEPLOYED_AT DESC
LIMIT 5;
