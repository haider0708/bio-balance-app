import 'dart:convert';

import 'package:biobalance/core/alerts/background_alerts.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a new sale is announced once, and what was already waiting is not',
    () async {
      SharedPreferences.setMockInitialValues({'app.locale': 'en'});
      FlutterSecureStorage.setMockInitialValues({
        'session.token': 'a-valid-token-of-sufficient-length-123456',
      });
      Map<String, Object?> note(String id, {String? readAt}) => {
        'id': id,
        'kind': 'SYSTEM',
        'key': 'sale.recorded',
        'createdAt': DateTime.now().toIso8601String(),
        'readAt': readAt,
        'params': {
          'seller': 'Amira',
          'place': 'Para Lac',
          'units': 3,
          'amountMillimes': 1500,
        },
      };
      final server = FakeServer()
        ..on('GET /v1/notifications', {
          'items': [note('n1')],
          'pinned': <Object>[],
          'unread': 1,
          'nextCursor': null,
        });
      final dio = Dio(BaseOptions(baseUrl: 'http://fake'))
        ..httpClientAdapter = server;
      final shown = <String>[];
      Future<void> show(int id, String title, String body) async =>
          shown.add(body);

      await checkForAlerts(client: dio, show: show);
      expect(shown, isEmpty); // first run: only remembers

      server.on('GET /v1/notifications', {
        'items': [note('n2'), note('n1')],
        'pinned': <Object>[],
        'unread': 2,
        'nextCursor': null,
      });
      await checkForAlerts(client: dio, show: show);
      expect(shown, ['Amira sold 3 units at Para Lac · 1.500 TND earned.']);

      await checkForAlerts(client: dio, show: show);
      expect(shown, hasLength(1)); // not announced twice
      expect(jsonEncode(shown), isNot(contains('n1')));
    },
  );

  test(
    'an iPhone that receives push alerts never asks in the background',
    () async {
      SharedPreferences.setMockInitialValues({
        'alerts.pushed': true,
        'alerts.seen': <String>[],
      });
      FlutterSecureStorage.setMockInitialValues({
        'session.token': 'a-valid-token-of-sufficient-length-123456',
      });
      final server = FakeServer();
      final dio = Dio(BaseOptions(baseUrl: 'http://fake'))
        ..httpClientAdapter = server;
      final shown = <String>[];
      await checkForAlerts(
        client: dio,
        show: (id, title, body) async => shown.add(body),
      );
      expect(shown, isEmpty);
      expect(server.count('GET /v1/notifications'), 0);
    },
  );
}
