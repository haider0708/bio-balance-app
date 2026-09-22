import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'CSV neutralizes formulas and preserves signs, whitespace, and quotes',
    () {
      for (final text in ['=1+1', ' +SUM(1,2)', '\t=1', '-10', '@x']) {
        expect(csvCell(text), '"\'$text"');
      }
      expect(csvCell('Name "A"'), '"Name ""A"""');
    },
  );
  test(
    'paged collections prioritize pending work and stable date ordering',
    () {
      final data = StoreData({
        'claims': [
          {
            'id': 'b',
            'status': 'fulfilled',
            'createdAt': '2026-09-22T10:00:00Z',
          },
          {
            'id': 'a',
            'status': 'requested',
            'createdAt': '2026-09-01T10:00:00Z',
          },
          {
            'id': 'c',
            'status': 'requested',
            'createdAt': '2026-09-21T10:00:00Z',
          },
        ],
      });
      expect(data.list('claims').map((r) => r['id']), ['c', 'a', 'b']);
    },
  );
}
