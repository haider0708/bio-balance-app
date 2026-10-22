// Starting the app: a known account opens at once (the server confirms in the background), a session
// the server ended signs out, and a read that fails for lack of a connection is tried once more.
import 'dart:convert';

import 'package:biobalance/core/api/api_client.dart';
import 'package:biobalance/core/api/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

void main() {
  String known(String role) =>
      jsonEncode({...meJson(role: role), 'region': null, 'pdv': null});

  testWidgets('a known account opens although the server cannot be reached', (
    tester,
  ) async {
    final s = FakeServer()..offline = true;
    await launch(tester, s, language: 'en', cachedMe: known('ADMIN'));
    // Without the saved account the app would be stuck on the opening screen or the sign-in.
    expect(find.text('Approvals'), findsWidgets);
    expect(find.text('Welcome back'), findsNothing);
  });

  testWidgets('the server ending the session signs the person out', (
    tester,
  ) async {
    final s = FakeServer()
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/me', {
        'code': 'SESSION_EXPIRED',
        'message': 'Please sign in again.',
      }, status: 401);
    await launch(tester, s, language: 'en', cachedMe: known('ADMIN'));
    await settle(tester);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  test(
    'a read is tried once more after a failed connection, a write never',
    () async {
      var gets = 0;
      var posts = 0;
      final dio = Dio(BaseOptions(baseUrl: 'http://x'))
        ..httpClientAdapter = _Flaky(
          onGet: () {
            gets++;
            return gets == 1;
          },
          onPost: () {
            posts++;
            return true;
          },
        );
      final client = ApiClient(
        dio: dio,
        retryDelay: Duration.zero,
        tokenReader: () => null,
        localeReader: () => 'en',
        onUnauthorized: () {},
      );
      expect(await client.get('/ok'), {'ok': true});
      expect(gets, 2);
      await expectLater(client.post('/write'), throwsA(isA<ApiException>()));
      expect(posts, 1);
    },
  );
}

/// An adapter whose connection fails when told to (the second attempt of a read works).
class _Flaky implements HttpClientAdapter {
  _Flaky({required this.onGet, required this.onPost});

  final bool Function() onGet;
  final bool Function() onPost;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final fail = options.method == 'GET' ? onGet() : onPost();
    if (fail) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no connection',
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'ok': true}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}
