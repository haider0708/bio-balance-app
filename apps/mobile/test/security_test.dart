import 'dart:io';

import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/api/transport_security.dart';
import 'package:biobalance/data/services/notifications/push_notifications.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'release refuses plaintext, credentials, paths and ambiguous origins',
    () {
      for (final value in [
        'http://api.biobalance.tn',
        'https://user:pass@api.biobalance.tn',
        'https://api.biobalance.tn/v1',
        'https://api.biobalance.tn?token=x',
        'https://api.biobalance.tn#x',
        '',
      ]) {
        expect(
          () => TransportSecurity.validateOrigin(value, release: true),
          throwsFormatException,
        );
      }
      expect(
        TransportSecurity.validateOrigin(
          'https://api.biobalance.tn',
          release: true,
        ).scheme,
        'https',
      );
      expect(
        TransportSecurity.validateOrigin(
          'http://127.0.0.1:3000',
          release: false,
        ).port,
        3000,
      );
    },
  );
  test(
    'a forged destination never reaches the network or a supplied interceptor',
    () async {
      var sent = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              sent++;
              handler.resolve(
                Response(requestOptions: request, statusCode: 200),
              );
            },
          ),
        );
      final api = ApiClient(baseUrl: 'https://api.biobalance.tn', dio: dio)
        ..authenticate('private-token', accountId: 'user');
      for (final url in [
        'https://attacker.invalid/v1/sales',
        'http://api.biobalance.tn/v1/sales',
        'https://api.biobalance.tn:8443/v1/sales',
        'https://user@api.biobalance.tn/v1/sales',
      ]) {
        await expectLater(
          api.request('POST', url),
          throwsA(isA<DioException>()),
        );
      }
      expect(sent, 0);
      api.http.options.baseUrl = 'https://attacker.invalid';
      expect(api.mediaUri('id', api.binding).host, 'api.biobalance.tn');
      await expectLater(
        api.transfer('GET', '/v1/media/id'),
        throwsA(isA<DioException>()),
      );
      expect(sent, 0);
    },
  );
  test('real HTTP redirects never forward credentials and 429 does not expire the account', () async {
    final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final destination = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await source.close(force: true);
      await destination.close(force: true);
    });
    var leaked = false;
    destination.listen((request) {
      leaked = true;
      request.response.close();
    });
    source.listen((request) {
      if (request.uri.path == '/limited') {
        request.response.statusCode = 429;
        request.response.headers.set('retry-after', '20');
        request.response.write('{"code":"RATE_LIMITED"}');
      } else {
        request.response.statusCode = 307;
        request.response.headers.set(
          'location',
          'http://127.0.0.1:${destination.port}/sink',
        );
      }
      request.response.close();
    });
    final api = ApiClient(baseUrl: 'http://127.0.0.1:${source.port}')
      ..authenticate('private-token', accountId: 'user');
    await expectLater(
      api.request('POST', '/redirect'),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      api.request('GET', '/limited'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.headers.value('retry-after'),
          'retry after',
          '20',
        ),
      ),
    );
    expect(leaked, false);
    expect(api.accessBlocked, false);
    expect(api.accountId, 'user');
  });
  test('VPS inbox needs no push registration or external SDK', () async {
    var requests = 0;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests++;
            h.resolve(Response(requestOptions: r));
          },
        ),
      );
    final api = ApiClient(baseUrl: 'https://test.invalid', dio: dio)
      ..authenticate('token', accountId: 'user');
    final service = PushNotifications(api);
    expect(service.configured, false);
    await service.resume();
    await service.dispose();
    expect(requests, 0);
  });
}
