import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color, VoidCallback;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../api/api_client.dart';
import '../auth/secure_storage.dart';
import '../config.dart';
import '../l10n/server_text.dart';
import 'fcm.dart';
import 'push.dart';

const _taskName = 'biobalance.alerts';
const _channelId = 'biobalance_alerts';
const _seenKey = 'alerts.seen';

/// Set when the server sends this iPhone push alerts: the background check then stays quiet.
const _pushedKey = 'alerts.pushed';

const _settings = InitializationSettings(
  android: AndroidInitializationSettings('@drawable/ic_stat_biobalance'),
  // Permission is asked in the app (Push.token), never from the background.
  iOS: DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  ),
);

final _notifications = FlutterLocalNotificationsPlugin();

/// Phone alerts, two ways. **Push** (Apple on iPhone, Firebase on Android): the server sends each
/// new notification at once, the phone's system shows it even with the app closed, and no code runs
/// on the phone. **Background check** (the fallback, used while the server has no push key for this
/// phone, or the phone has no Google services): every fifteen minutes or so the phone asks the
/// server for new notifications and shows them. Once push is registered the check stays quiet, so
/// nothing is announced twice.
class BackgroundAlerts {
  const BackgroundAlerts._();

  static String? _enabledFor;
  static ApiClient? _api;
  static VoidCallback? _opened;
  static bool _initialized = false;
  static bool _listening = false;

  /// Prepares the phone's alerts once in the app, with what a tap on one does.
  static Future<void> _initialize() async {
    if (_initialized) return;
    await _notifications.initialize(
      _settings,
      onDidReceiveNotificationResponse: (_) => _opened?.call(),
    );
    // Push alerts name this channel; it exists before the first one arrives.
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            'BioBalance',
            description: 'Sales, deliveries and messages',
            importance: Importance.high,
          ),
        );
    _initialized = true;
  }

  static bool get _phone =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> start() async {
    if (!_phone) return;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    try {
      await Workmanager().initialize(alertsDispatcher);
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(minutes: 15),
        initialDelay: ios ? const Duration(minutes: 15) : null,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: ios
            ? null
            : Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {
      // Background work refused by this phone: alerts still show in the app.
    }
  }

  /// Runs [opened] when the person taps an alert (push or background), including the one that
  /// started the app.
  static Future<void> onOpened(VoidCallback opened) async {
    if (!_phone) return;
    _opened = opened;
    await Push.onOpened(opened);
    await Fcm.watchOpened(opened);
    try {
      await _initialize();
      final launch = await _notifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) opened();
    } catch (_) {
      // No notification support here (a test): taps simply open the app.
    }
  }

  /// Once per account on this phone: asks whether alerts may be shown (Android 13+, iPhone) and
  /// registers the phone for push alerts.
  static Future<void> enable(String account, ApiClient api) async {
    if (!_phone || _enabledFor == account) return;
    _enabledFor = account;
    _api = api;
    try {
      final android = defaultTargetPlatform == TargetPlatform.android;
      if (android) {
        await _initialize();
        await _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }
      final token = android ? await Fcm.token() : await Push.token();
      final prefs = await SharedPreferences.getInstance();
      if (token == null) {
        // Alerts refused, or no Google services here: the background check does the work.
        await prefs.setBool(_pushedKey, false);
        return;
      }
      await prefs.setBool(_pushedKey, await _register(api, token, android));
      if (android && !_listening) {
        _listening = true;
        // Firebase may replace the token later: the server must always have the current one.
        await Fcm.watchToken((fresh) => unawaited(_refreshed(fresh)));
        // An alert that arrives while the app is open is shown by the app itself.
        Fcm.foreground.listen((m) {
          final body = m.body;
          if (body != null && body.isNotEmpty) {
            unawaited(
              _show(body.hashCode & 0x7fffffff, m.title ?? 'BioBalance', body),
            );
          }
        });
      }
    } catch (_) {
      // No notification support here (a test, an old phone, offline): try at the next start.
      _enabledFor = null;
    }
  }

  /// Tells the server about this phone; true when the server really sends push alerts to it.
  static Future<bool> _register(
    ApiClient api,
    String token,
    bool android,
  ) async {
    final answer = await api.post('/v1/me/push-device', {
      'token': token,
      'platform': android ? 'ANDROID' : 'IOS',
      // iPhone builds run from Xcode talk to Apple's test servers.
      if (!android) 'sandbox': !kReleaseMode,
    });
    return answer is Map && answer['push'] == true;
  }

  static Future<void> _refreshed(String token) async {
    final api = _api;
    if (api == null || _enabledFor == null) return;
    try {
      await _register(api, token, true);
    } catch (_) {
      // Offline: the next start registers it.
      _enabledFor = null;
    }
  }

  /// Signed out: the next account asks again.
  static void reset() => _enabledFor = null;
}

/// Runs in the background, without the app. Returns true when done (it runs again at the next turn).
@pragma('vm:entry-point')
void alertsDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await checkForAlerts();
    } catch (_) {
      // Offline or signed out: try again at the next turn.
    }
    return true;
  });
}

/// Fetch what is new and show it. The first run only remembers what already exists.
Future<void> checkForAlerts({
  Dio? client,
  Future<void> Function(int id, String title, String body)? show,
}) async {
  final token = await secureStorage.read(key: 'session.token');
  if (token == null) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_pushedKey) ?? false) return;
  final locale = prefs.getString('app.locale') ?? 'fr';
  final dio =
      client ??
      Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
  final response = await dio.get<Object?>(
    '/v1/notifications',
    queryParameters: {'limit': 30},
    options: Options(
      headers: {'Authorization': 'Bearer $token'},
      responseType: ResponseType.plain,
    ),
  );
  final body = response.data is String
      ? jsonDecode(response.data! as String) as Map<String, dynamic>
      : response.data! as Map<String, dynamic>;
  final items = (body['items'] as List<dynamic>).cast<Map<String, dynamic>>();
  final unread = items.where((n) => n['readAt'] == null).toList();
  final seen = prefs.getStringList(_seenKey);
  final ids = unread.map((n) => n['id'] as String).toSet();
  if (seen == null) {
    // First run on this phone: nothing is announced for what was already waiting.
    await prefs.setStringList(_seenKey, ids.toList());
    return;
  }
  final fresh = unread.where((n) => !seen.contains(n['id'])).take(5).toList();
  final show0 = show ?? _show;
  for (final n in fresh.reversed) {
    final message = n['kind'] == 'MESSAGE'
        ? (n['title'] as String? ?? '')
        : ServerText.notification(
            locale,
            n['key'] as String? ?? '',
            (n['params'] as Map<String, dynamic>?) ?? const {},
            fallback: n['title'] as String?,
          );
    await show0(
      (n['id'] as String).hashCode & 0x7fffffff,
      'BioBalance',
      message,
    );
  }
  // Keep the list short: what is still unread, plus what was just shown.
  await prefs.setStringList(_seenKey, {...ids, ...seen}.take(200).toList());
}

Future<void> _show(int id, String title, String body) async {
  await _notifications.initialize(_settings);
  await _notifications.show(
    id,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'BioBalance',
        channelDescription: 'Sales, deliveries and messages',
        importance: Importance.high,
        priority: Priority.high,
        // The white leaf in the status bar, tinted with the brand colour in the shade.
        color: Color(0xFF0C6B45),
      ),
      iOS: DarwinNotificationDetails(threadIdentifier: 'biobalance'),
    ),
  );
}
