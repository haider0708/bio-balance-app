import '../test/support/test_origin.dart';

import 'dart:async';
import 'dart:convert';

import 'package:biobalance/main.dart';
import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/features/sales/sale_screen.dart';
import 'package:dio/dio.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'role_journeys_test.dart' show Journey;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('durable sale survives a real Android process termination', (
    t,
  ) async {
    const base = String.fromEnvironment('API_BASE_URL'),
        phase = String.fromEnvironment('TEST_PHASE'),
        product = String.fromEnvironment('PRODUCT_NAME');
    final account = jsonDecode(
      const String.fromEnvironment('TEST_ACCOUNT'),
    ) as Map<String, dynamic>;
    final user = UserAccount.fromJson(account['user']);
    final api = ApiClient(baseUrl: base),
        db = AppDatabase.open(),
        repo = OfflineRepository(db, api);
    if (phase == 'save') {
      api.authenticate(account['token'], accountId: user.id);
      final stores = await repo.stores(user, refresh: true);
      final store = stores.singleWhere(
        (s) => s.id == const String.fromEnvironment('TEST_STORE'),
      );
      await repo.refresh(user, store);
      await const FlutterSecureStorage().write(
        key: 'session',
        value: jsonEncode(account),
      );
      api.http.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) => h.reject(
            DioException(
              requestOptions: o,
              type: DioExceptionType.connectionError,
            ),
          ),
        ),
      );
    } else {
      final rows = await db.select(db.outboxRows).get();
      final pending = rows.where((r) => r.accountId == user.id).single;
      final saved = await repo.draft(
        user.id,
        const String.fromEnvironment('TEST_STORE'),
        'restart-evidence',
      );
      expect(pending.operationId, saved!['operationId']);
      expect(pending.payload, saved['payload']);
    }
    await t.pumpWidget(BioBalanceApp(api: api, database: db));
    final j = Journey(t);
    await j.ready();
    if (phase == 'save') {
      await j.tap('Nouvelle vente');
      await j.tap('Rechercher');
      await j.chooseSaleProduct(product);
      await j.fillLabel('Lot OPENING · 31/12/2030', '3');
      await j.tap('Ajouter à la vente');
      await j.tap('Enregistrer la vente');
      await j.until(
        () => find.byType(SaleScreen).evaluate().isEmpty,
        reason: 'sale committed and editor closed before process termination',
      );
      await j.ready();
      final pending = (await db.select(db.outboxRows).get()).singleWhere(
        (r) => r.accountId == user.id,
      );
      await repo.saveDraft(
        user.id,
        const String.fromEnvironment('TEST_STORE'),
        'restart-evidence',
        {'operationId': pending.operationId, 'payload': pending.payload},
      );
      await Dio(
        testOptions(
          base,
          headers: {'x-test-key': const String.fromEnvironment('TEST_KEY')},
        ),
      ).post(
        '/__test/checkpoint',
        data: {'operationId': pending.operationId, 'accountId': user.id},
      );
      await Completer<void>().future; // The host force-stops this process at the acknowledged checkpoint.
    } else {
      for (var i = 0; i < 100 && await repo.pendingCount(user.id) > 0; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(
        await repo.pendingCount(user.id),
        0,
        reason:
            (await repo.operations(
                  user.id,
                  const String.fromEnvironment('TEST_STORE'),
                ))
                .map((r) => '${r.status}: ${r.error}; retry ${r.nextAttemptAt}')
                .join('\n'),
      );
      expect(api.accountId, user.id);
      await j.until(
        () =>
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
        reason: 'native camera probe requires an awake, foreground Android app',
      );
      await Dio(
        testOptions(
          base,
          headers: {'x-test-key': const String.fromEnvironment('TEST_KEY')},
        ),
      ).post('/__test/deny-camera');
      await j.tap('Nouvelle vente');
      await j.tap('Scanner un produit');
      await j.until(
        () => find.text('Caméra indisponible').evaluate().isNotEmpty,
        reason: 'native camera denial is recoverable',
      );
      await j.tap('Utiliser la recherche manuelle');
      await j.tap('Rechercher');
      await j.chooseSaleProduct(product);
      expect(find.text('Ajouter à la vente'), findsOneWidget);
      await j.back();
      await j.back();
      await j.nav('Plus');
      await j.tap('Formation');
      await j.tap(const String.fromEnvironment('TEST_VIDEO_TITLE'));
      await j.until(
        () => find.byType(VideoPlayer).evaluate().isNotEmpty,
        reason: 'native video initialized',
      );
      await t.tap(find.byTooltip('Lire'));
      await t.pump(const Duration(seconds: 1));
      var player = t.widget<VideoPlayer>(find.byType(VideoPlayer)).controller;
      expect(player.value.position, greaterThan(Duration.zero));
      await t.tap(find.byTooltip('Pause'));
      await t.pumpAndSettle();
      await j.tap('Télécharger ou reprendre hors ligne');
      await j.until(
        () => find.text('Vidéo disponible hors ligne').evaluate().isNotEmpty,
        reason: 'verified video downloaded',
      );
      await j.back();
      api.http.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) => h.reject(
            DioException(
              requestOptions: o,
              type: DioExceptionType.connectionError,
            ),
          ),
        ),
      );
      await j.tap(const String.fromEnvironment('TEST_VIDEO_TITLE'));
      await j.until(
        () => find.byType(VideoPlayer).evaluate().isNotEmpty,
        reason: 'offline video initialized',
      );
      player = t.widget<VideoPlayer>(find.byType(VideoPlayer)).controller;
      expect(player.dataSourceType, DataSourceType.file);
      await t.tap(find.byTooltip('Lire'));
      await t.pump(const Duration(seconds: 1));
      expect(player.value.position, greaterThan(Duration.zero));
      await j.back();
      await t.pumpWidget(const SizedBox());
      await db.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
