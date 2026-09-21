import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../domain/models/models.dart';
import '../api/generated/api_client.dart';
import '../api/generated/models.dart';

class PushSignal {
  final String notificationId, userId;
  final bool tapped;
  const PushSignal(this.notificationId, this.userId, {this.tapped = false});
}

abstract interface class PushPlatform {
  bool get configured;
  String get platform;
  Future<void> initialize();
  Future<bool> permission({required bool request});
  Future<String?> token();
  Future<void> deleteToken();
  Stream<String> get tokens;
  Stream<PushSignal> get messages;
  Future<PushSignal?> initialMessage();
}

class FirebasePushPlatform implements PushPlatform {
  @override
  bool get configured =>
      const String.fromEnvironment('FIREBASE_APP_ID').isNotEmpty;
  @override
  String get platform => Platform.isIOS ? 'ios' : 'android';
  @override
  Future<void> initialize() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
          appId: String.fromEnvironment('FIREBASE_APP_ID'),
          messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
          projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
          iosBundleId: 'tn.biobalance.app',
        ),
      );
    }
  }

  @override
  Future<bool> permission({required bool request}) async {
    final settings = request
        ? await FirebaseMessaging.instance.requestPermission()
        : await FirebaseMessaging.instance.getNotificationSettings();
    return [
      AuthorizationStatus.authorized,
      AuthorizationStatus.provisional,
    ].contains(settings.authorizationStatus);
  }

  @override
  Future<String?> token() => FirebaseMessaging.instance.getToken();
  @override
  Future<void> deleteToken() => FirebaseMessaging.instance.deleteToken();
  @override
  Stream<String> get tokens => FirebaseMessaging.instance.onTokenRefresh;
  PushSignal signal(RemoteMessage m, bool tapped) => PushSignal(
    '${m.data['notificationId'] ?? ''}',
    '${m.data['userId'] ?? ''}',
    tapped: tapped,
  );
  @override
  Stream<PushSignal> get messages => Stream.multi((controller) {
    final foreground = FirebaseMessaging.onMessage.listen(
      (m) => controller.add(signal(m, false)),
    );
    final opened = FirebaseMessaging.onMessageOpenedApp.listen(
      (m) => controller.add(signal(m, true)),
    );
    controller.onCancel = () async {
      await foreground.cancel();
      await opened.cancel();
    };
  });
  @override
  Future<PushSignal?> initialMessage() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    return message == null ? null : signal(message, true);
  }
}

/// Serializes platform token mutation; account generation guards every callback.
class PushNotifications {
  final ApiClient api;
  final PushPlatform platform;
  StreamSubscription<String>? _tokens;
  StreamSubscription<PushSignal>? _messages;
  final _events = StreamController<PushSignal>.broadcast();
  final _seen = <String>{};
  Future<void> _tail = Future.value();
  int _epoch = 0;
  PushSignal? pendingTap;
  PushNotifications(this.api, {PushPlatform? platform})
    : platform = platform ?? FirebasePushPlatform();
  bool get configured => platform.configured;
  Stream<PushSignal> get events => _events.stream;
  Future<void> _serialize(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<void> enable() => _bind(request: true);
  Future<void> resume() async {
    try {
      await _bind(request: false);
    } catch (_) {
      /* Inbox remains available. */
    }
  }

  Future<void> _bind({required bool request}) {
    final epoch = ++_epoch, binding = api.binding;
    bool current() =>
        epoch == _epoch &&
        binding.generation == api.generation &&
        binding.accountId == api.accountId &&
        !api.accessBlocked;
    return _serialize(() async {
      await _tokens?.cancel();
      await _messages?.cancel();
      _tokens = null;
      _messages = null;
      if (!current() || binding.accountId == null) return;
      if (!configured) {
        if (request) {
          throw const AppFailure(
            'PUSH_UNAVAILABLE',
            'Les notifications sur ce téléphone ne sont pas encore disponibles. Consultez les messages dans l’application.',
          );
        }
        return;
      }
      await platform.initialize();
      if (!current()) return;
      final allowed = await platform.permission(request: request);
      if (!current()) return;
      if (!allowed) {
        if (request) {
          throw const AppFailure(
            'PUSH_DENIED',
            'Les notifications sont désactivées dans les réglages du téléphone. Les messages restent consultables ici.',
          );
        }
        return;
      }
      String? previousToken;
      Future<void> tokenTail = Future.value();
      Future<void> save(String token) async {
        if (!current()) return;
        await api.notificationsDevice(
          body: NotificationsDeviceRequestDto(
            token: token,
            platform: platform.platform,
          ),
        );
        if (!current()) return;
        final previous = previousToken;
        previousToken = token;
        if (previous != null && previous != token) {
          await api.notificationsRemoveDevice(
            body: NotificationsRemoveDeviceRequestDto(token: previous),
          );
        }
      }

      final token = await platform.token();
      if (!current()) return;
      if (token != null) await save(token);
      if (!current()) return;
      _tokens = platform.tokens.listen((t) {
        tokenTail = tokenTail.then((_) => save(t)).catchError((Object _) {});
      });
      void receive(PushSignal message) {
        if (!current() ||
            message.userId != binding.accountId ||
            message.notificationId.isEmpty) {
          return;
        }
        final key =
            '${binding.generation}:${message.notificationId}:${message.tapped}';
        if (!_seen.add(key)) return;
        if (_seen.length > 256) _seen.remove(_seen.first);
        if (message.tapped) pendingTap = message;
        _events.add(message);
      }

      _messages = platform.messages.listen(receive, onError: (Object _) {});
      final initial = await platform.initialMessage();
      if (initial != null) receive(initial);
    });
  }

  Future<void> unbind() {
    ++_epoch;
    pendingTap = null;
    _seen.clear();
    return _serialize(() async {
      await _tokens?.cancel();
      await _messages?.cancel();
      _tokens = null;
      _messages = null;
      // A later account reuses/registers the installation only after this action.
      if (configured && api.accountId == null) {
        try {
          await platform.deleteToken();
        } catch (_) {}
      }
    });
  }

  Future<void> dispose() async {
    await unbind();
    await _events.close();
  }
}
