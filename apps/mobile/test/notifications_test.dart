import 'dart:async';
import 'dart:convert';

import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/api/session_transport.dart';
import 'package:biobalance/data/services/notifications/push_notifications.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePush implements PushPlatform {
  bool allowed = true;
  final refresh = StreamController<String>.broadcast(),
      incoming = StreamController<PushSignal>.broadcast();
  Completer<void>? deletion, permissionWait;
  final deleted = Completer<void>();
  @override
  bool get configured => true;
  @override
  String get platform => 'android';
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> permission({required bool request}) async {
    await permissionWait?.future;
    return allowed;
  }

  @override
  Future<String?> token() async => 'token';
  @override
  Future<void> deleteToken() async {
    if (!deleted.isCompleted) deleted.complete();
    await deletion?.future;
  }

  @override
  Stream<String> get tokens => refresh.stream;
  @override
  Stream<PushSignal> get messages => incoming.stream;
  @override
  Future<PushSignal?> initialMessage() async => null;
  Future<void> close() async {
    await refresh.close();
    await incoming.close();
  }
}

ApiClient client(List<String> registrations) {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) {
        if (o.path == '/v1/devices' && o.method == 'DELETE') {
          h.resolve(
            Response(requestOptions: o, statusCode: 200, data: {'count': 1}),
          );
          return;
        }
        if (o.path == '/v1/devices') {
          registrations.add('${o.headers['Authorization']}:${o.data['token']}');
          h.resolve(
            Response(
              requestOptions: o,
              statusCode: 200,
              data: {
                'id': 'd',
                'userId': 'u',
                'sessionId': 's',
                'token': o.data['token'],
                'platform': 'android',
                'updatedAt': '2026-09-21T00:00:00Z',
              },
            ),
          );
        }
      },
    ),
  );
  return ApiClient(baseUrl: 'https://test.invalid', dio: dio)
    ..authenticate('one', accountId: 'a');
}

Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('denied permission makes no registration; an account change during permission blocks the old request', () async {
    final calls = <String>[],
        platform = FakePush()..allowed = false,
        api = client(calls),
        push = PushNotifications(api, platform: platform);
    await expectLater(push.enable(), throwsA(isA<AppFailure>()));
    expect(calls, isEmpty);
    platform.allowed = true;
    platform.permissionWait = Completer();
    final pending = push.resume();
    await settle();
    api.authenticate('two', accountId: 'b');
    platform.permissionWait!.complete();
    await pending;
    expect(calls, isEmpty);
    await push.dispose();
    await platform.close();
  });
  test('foreground/tap deduplicate by event, reject another account and refresh tokens', () async {
    final calls = <String>[],
        platform = FakePush(),
        api = client(calls),
        push = PushNotifications(api, platform: platform);
    final events = <PushSignal>[];
    final subscription = push.events.listen(events.add);
    await push.resume();
    platform.incoming.add(const PushSignal('notice', 'a'));
    platform.incoming.add(const PushSignal('notice', 'a'));
    platform.incoming.add(const PushSignal('notice', 'a', tapped: true));
    platform.incoming.add(const PushSignal('notice', 'a', tapped: true));
    platform.incoming.add(const PushSignal('foreign', 'b'));
    platform.refresh.add('renewed');
    await settle();
    expect(events.map((e) => e.tapped).toList(), [false, true]);
    expect(calls, ['Bearer one:token', 'Bearer one:renewed']);
    api.authenticate('two', accountId: 'b');
    platform.incoming.add(const PushSignal('late', 'a'));
    platform.refresh.add('late-token');
    await settle();
    expect(calls.length, 2);
    expect(events.length, 2);
    await subscription.cancel();
    await push.dispose();
    await platform.close();
  });
  test(
    'new registration waits for an in-flight logout token deletion',
    () async {
      final calls = <String>[],
          platform = FakePush()..deletion = Completer(),
          api = client(calls),
          push = PushNotifications(api, platform: platform);
      await push.resume();
      api.authenticate(null);
      final logout = push.unbind();
      await platform.deleted.future;
      api.authenticate('two', accountId: 'b');
      final resumed = push.resume();
      await settle();
      expect(calls.length, 1);
      platform.deletion!.complete();
      await logout;
      await resumed;
      expect(calls, ['Bearer one:token', 'Bearer two:token']);
      await push.dispose();
      await platform.close();
    },
  );
  test('permission denial does not revoke a store; streamed expiry triggers session recovery', () async {
    final api = client([]), events = <AccessEvent>[];
    final subscription = api.accessEvents.listen(events.add);
    api.http.interceptors.clear();
    api.http.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) => h.reject(
          DioException(
            requestOptions: o,
            response: Response(
              requestOptions: o,
              statusCode: 403,
              data: {'code': 'FORBIDDEN'},
            ),
          ),
        ),
      ),
    );
    await expectLater(
      api.request('GET', '/v1/stores/store/admin'),
      throwsA(isA<DioException>()),
    );
    expect(events, isEmpty);
    expect(api.accessBlocked, isFalse);
    api.http.interceptors.clear();
    api.http.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) => h.reject(
          DioException(
            requestOptions: o,
            response: Response(
              requestOptions: o,
              statusCode: 403,
              data: ResponseBody.fromString(
                jsonEncode({'code': 'ACCESS_DISABLED'}),
                403,
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      api.transfer<ResponseBody>(
        'GET',
        '/v1/media/video',
        responseType: ResponseType.stream,
      ),
      throwsA(isA<DioException>()),
    );
    expect(events.single.condition, AccessCondition.disabled);
    expect(api.accessBlocked, isTrue);
    await subscription.cancel();
  });
}
