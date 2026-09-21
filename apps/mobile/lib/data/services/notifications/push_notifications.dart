import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../domain/models/models.dart';
import '../api/generated/api_client.dart';

/// Platform configuration is supplied per environment; no service-account
/// credentials belong in a mobile build.
class PushNotifications {
  final ApiClient api;
  StreamSubscription<String>? _tokens;
  PushNotifications(this.api);
  bool get configured =>
      const String.fromEnvironment('FIREBASE_APP_ID').isNotEmpty;
  Future<void> _initialize() async {
    if (!configured) {
      throw const AppFailure(
        'PUSH_UNAVAILABLE',
        'Les notifications sur ce téléphone ne sont pas encore disponibles. Consultez les notifications dans l’application.',
      );
    }
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

  Future<void> enable() async {
    await _initialize();
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      throw const AppFailure(
        'PUSH_DENIED',
        'Les notifications sont désactivées dans les réglages de votre téléphone. Les messages restent consultables ici.',
      );
    }
    await _register();
  }

  Future<void> resume() async {
    if (!configured) return;
    try {
      await _initialize();
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if ([
        AuthorizationStatus.authorized,
        AuthorizationStatus.provisional,
      ].contains(settings.authorizationStatus)) {
        await _register();
      }
    } catch (_) {
      /* Foreground notification history remains available. */
    }
  }

  Future<void> _register() async {
    final account = api.accountId;
    if (account == null) return;
    Future<void> save(String token) async {
      if (api.accountId != account) return;
      await api.request(
        'POST',
        '/v1/devices',
        body: {'token': token, 'platform': Platform.isIOS ? 'ios' : 'android'},
      );
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await save(token);
    await _tokens?.cancel();
    _tokens = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(save(token).catchError((Object _) {}));
    });
  }

  Future<void> unbind() async {
    await _tokens?.cancel();
    _tokens = null;
    if (Firebase.apps.isEmpty) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await api.request('DELETE', '/v1/devices', body: {'token': token});
      }
    } catch (_) {
    } finally {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
  }
}
