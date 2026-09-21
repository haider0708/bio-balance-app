import 'dart:io';

import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/money.dart';
import 'package:biobalance/domain/use_cases/record_sale.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SQLite full rolls back the complete sale and retains the draft and older outbox bytes', () async {
    final directory = await Directory.systemTemp.createTemp('biobalance-full-');
    final db = AppDatabase(
      NativeDatabase(File('${directory.path}/full.sqlite')),
    );
    final api = ApiClient(baseUrl: 'http://unused')
      ..authenticate('token', accountId: 'owner');
    final repo = OfflineRepository(db, api);
    const user = UserAccount(
      id: 'owner',
      name: 'Test',
      email: 'test@example.test',
      admin: false,
    );
    final store = Store.fromJson({
      'id': 'store',
      'organizationId': 'org',
      'name': 'Store',
      'permissions': ['sell'],
    });
    SaleLine line(int i) => SaleLine(
      id: 'line-$i',
      productId: 'product',
      quantity: 1,
      price: Money(49900),
      allocations: [
        {'lotId': 'lot', 'quantity': 1},
      ],
    );
    await RecordSale(repo).execute(user, store, [line(0)]);
    final old = (await db.select(db.outboxRows).get()).single;
    await repo.saveDraft(user.id, store.id, 'sale', {
      'note': 'Retenir ce brouillon',
    });
    final pages =
        (await db.customSelect('PRAGMA page_count').getSingle())
                .data
                .values
                .single
            as int;
    await db.customStatement('PRAGMA max_page_count=$pages');
    Object? failure;
    try {
      await RecordSale(repo).execute(user, store, List.generate(1000, line));
    } catch (error) {
      failure = error;
    }
    expect('$failure', contains('database or disk is full'));
    final remaining = await db.select(db.outboxRows).get();
    expect(remaining.length, 1);
    expect(remaining.single.payload, old.payload);
    expect(remaining.single.operationId, old.operationId);
    expect(
      (await repo.draft(user.id, store.id, 'sale'))?['note'],
      'Retenir ce brouillon',
    );
    await db.customStatement('PRAGMA max_page_count=100000');
    await RecordSale(repo).execute(user, store, [line(1)]);
    expect(await repo.pendingCount(user.id), 2);
    expect(await repo.draft(user.id, store.id, 'sale'), isNull);
    await db.close();
    await directory.delete(recursive: true);
  });
}
