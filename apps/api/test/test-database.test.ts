import { expect, it } from 'vitest';
import { assertTestDatabases } from './test-database.cjs';
const app = 'postgresql://app:secret@localhost:54329/bio_test';
it('permits distinct restricted and owner credentials on the same test database', () => {
  expect(() => assertTestDatabases(app, app.replace('app:secret', 'owner:other'))).not.toThrow();
});
it.each([
  'postgresql://owner:private@localhost:54329/production',
  'postgresql://owner:private@localhost:54329/another_test',
  'postgresql://owner:private@elsewhere:54329/bio_test',
  'postgresql://owner:private@localhost:5432/bio_test',
  'postgresql://owner:private@localhost:54329/bio_test?host=production',
  'postgresql://owner:private@localhost:54329/bio_test?dbname=production',
  'https://owner:private@localhost:54329/bio_test',
  'malformed-private-url',
])('rejects unsafe or mismatched target without exposing credentials', (owner) => {
  expect(() => assertTestDatabases(app, owner)).toThrow('MATCHING_ISOLATED_TEST_DATABASES_REQUIRED');
});
