/** Every test run talks to the isolated test database, never to a real one. */
export default function setup() {
  const app =
    process.env.TEST_DATABASE_URL ??
    "postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_test";
  if (!/\/[A-Za-z0-9_-]+_test$/.test(new URL(app).pathname))
    throw new Error(
      "TEST_DATABASE_URL must point to a database whose name ends in _test",
    );
}
