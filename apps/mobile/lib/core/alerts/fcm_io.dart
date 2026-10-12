import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// The project's public client identifiers (the same values that sit in `google-services.json`);
/// they only say which Firebase project this app talks to. Given here, in code, so builds need no
/// Gradle plugin and the test copies (other application ids) work as well.
const _options = FirebaseOptions(
  apiKey: 'AIzaSyAW6BBhp1OYMyx-5A9Wwj0uHDyvJaturOE',
  appId: '1:995710356813:android:76cffdffa5d1fc1136bb04',
  messagingSenderId: '995710356813',
  projectId: 'bio-balance-8b7c4',
  storageBucket: 'bio-balance-8b7c4.firebasestorage.app',
);

/// A push alert that arrived while the app was open (Android shows the others by itself).
class FcmMessage {
  const FcmMessage(this.title, this.body);

  final String? title;
  final String? body;
}

/// Firebase Cloud Messaging on Android: the phone's registration token, alerts that arrive while
/// the app is open, and taps on alerts. Alerts that arrive while the app is closed or in the
/// background are shown by Android itself (the server sends them as notifications), so no code
/// runs and no battery is spent. Firebase starts only when first needed.
class Fcm {
  const Fcm._();

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static final _foreground = StreamController<FcmMessage>.broadcast();
  static Stream<FcmMessage> get foreground => _foreground.stream;

  static Future<FirebaseMessaging?>? _starting;

  static Future<FirebaseMessaging?> _messaging() => _starting ??= _start();

  static Future<FirebaseMessaging?> _start() async {
    if (!supported) return null;
    try {
      if (Firebase.apps.isEmpty)
        await Firebase.initializeApp(options: _options);
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        _foreground.add(FcmMessage(n?.title, n?.body));
      });
      return FirebaseMessaging.instance;
    } catch (_) {
      // Google services unavailable on this phone (or a test): try again at the next call.
      _starting = null;
      return null;
    }
  }

  /// This phone's registration token, or null when there is none (no Google services).
  static Future<String?> token() async {
    final messaging = await _messaging();
    if (messaging == null) return null;
    try {
      return await messaging.getToken();
    } catch (_) {
      return null;
    }
  }

  /// Calls [changed] whenever Firebase gives the phone a new token.
  static Future<void> watchToken(void Function(String token) changed) async {
    final messaging = await _messaging();
    messaging?.onTokenRefresh.listen(changed, onError: (_) {});
  }

  /// Calls [opened] when the person taps an alert, including the one that started the app.
  static Future<void> watchOpened(VoidCallback opened) async {
    final messaging = await _messaging();
    if (messaging == null) return;
    FirebaseMessaging.onMessageOpenedApp.listen((_) => opened());
    try {
      if (await messaging.getInitialMessage() != null) opened();
    } catch (_) {
      // Not essential.
    }
  }
}
