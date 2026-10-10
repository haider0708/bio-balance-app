import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Apple push alerts, through the small native part in ios/Runner/AppDelegate.swift. Only the
/// iPhone uses it: Android phones check for alerts in the background by themselves.
class Push {
  const Push._();

  static const _channel = MethodChannel('biobalance/push');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Asks the person (once; iOS remembers) and returns this phone's device token, or null when
  /// alerts are refused or unavailable.
  static Future<String?> token() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('register');
    } on Object {
      return null;
    }
  }

  /// The number on the app icon.
  static Future<void> badge(int count) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('badge', count);
    } on Object {
      // Not essential.
    }
  }

  /// Runs [opened] when the person taps an alert, including the one that started the app.
  static Future<void> onOpened(VoidCallback opened) async {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'opened') opened();
    });
    try {
      if (await _channel.invokeMethod<bool>('takeOpened') ?? false) opened();
    } on Object {
      // Not essential.
    }
  }
}
