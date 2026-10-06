import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../config.dart';
import '../l10n/server_text.dart';

const _taskName = 'biobalance.alerts';
const _channelId = 'biobalance_alerts';
const _seenKey = 'alerts.seen';

final _notifications = FlutterLocalNotificationsPlugin();

/// Phone alerts without a push service: every fifteen minutes (the shortest the system
/// allows) the phone asks the server for new notifications and shows them, even when the
/// app is closed. A responsable hears about each sale of their stores this way.
class BackgroundAlerts {
  const BackgroundAlerts._();

  static bool _asked = false;

  static Future<void> start() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await Workmanager().initialize(alertsDispatcher);
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  /// Android 13+ asks the person once whether alerts may be shown.
  static Future<void> askPermission() async {
    if (_asked || defaultTargetPlatform != TargetPlatform.android) return;
    _asked = true;
    try {
      await _notifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {
      // No notification support here (a test, an old phone): the app works without alerts.
    }
  }
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
  const storage = FlutterSecureStorage();
  final token = await storage.read(key: 'session.token');
  if (token == null) return;
  final prefs = await SharedPreferences.getInstance();
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
  await _notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
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
      ),
    ),
  );
}
