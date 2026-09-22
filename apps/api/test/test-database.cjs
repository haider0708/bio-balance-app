/* Mutating test harnesses must agree on one isolated target before connecting. */
function assertTestDatabases(app, owner = app) {
  try {
    const targets = [app, owner].map((value) => {
      const url = new URL(value);
      const database = decodeURIComponent(url.pathname);
      if (!['postgres:', 'postgresql:'].includes(url.protocol) ||
          !/^\/[A-Za-z0-9_-]+_test$/.test(database) ||
          !url.hostname || url.hash || url.searchParams.has('host') ||
          url.searchParams.has('hostaddr') || url.searchParams.has('dbname') ||
          url.searchParams.has('port') || url.searchParams.has('service')) {
        throw Error();
      }
      return `${url.hostname}:${url.port || '5432'}${database}`;
    });
    if (targets[0] !== targets[1]) throw Error();
  } catch {
    // Never echo connection strings or credentials in validation failures.
    throw Error('MATCHING_ISOLATED_TEST_DATABASES_REQUIRED');
  }
}
module.exports = { assertTestDatabases };
