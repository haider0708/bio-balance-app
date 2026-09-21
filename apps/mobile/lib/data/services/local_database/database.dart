import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
part 'database.g.dart';

class CacheEntries extends Table {
  TextColumn get accountId => text()();
  TextColumn get storeId => text()();
  TextColumn get resource => text()();
  TextColumn get entityId => text()();
  TextColumn get payload => text()();
  @override
  Set<Column> get primaryKey => {accountId, storeId, resource, entityId};
}

class OutboxRows extends Table {
  IntColumn get sequence => integer().autoIncrement()();
  TextColumn get operationId => text().unique()();
  TextColumn get accountId => text()();
  TextColumn get storeId => text()();
  TextColumn get payload => text()();
  TextColumn get effect => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get error => text().nullable()();
  TextColumn get resolution => text().nullable()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class DraftRows extends Table {
  TextColumn get accountId => text()();
  TextColumn get storeId => text()();
  TextColumn get key => text()();
  TextColumn get payload => text()();
  @override
  Set<Column> get primaryKey => {accountId, storeId, key};
}

@DriftDatabase(tables: [CacheEntries, OutboxRows, DraftRows])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);
  factory AppDatabase.open() => AppDatabase(
    LazyDatabase(() async {
      final directory = await getApplicationSupportDirectory();
      return NativeDatabase.createInBackground(
        File(p.join(directory.path, 'biobalance.sqlite')),
        setup: (database) {
          database.execute('PRAGMA journal_mode=WAL;');
          database.execute('PRAGMA foreign_keys=ON;');
          database.execute('PRAGMA busy_timeout=5000;');
        },
      );
    }),
  );
  @override
  int get schemaVersion => 2;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(outboxRows, outboxRows.resolution);
        await m.addColumn(outboxRows, outboxRows.resolvedAt);
      }
    },
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX outbox_owner_store_sequence ON outbox_rows(account_id, store_id, sequence)',
      );
    },
  );
}
