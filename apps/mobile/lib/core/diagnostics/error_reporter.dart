import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/api_exception.dart';
import '../config.dart';

/// Tells the server about errors the app meets in use, so they can be fixed before anyone has
/// to report them. A report holds the platform, the app version and the error: nothing that says
/// who met it (it is sent without signing in). Only release builds report, each kind of error
/// once per run, at most a few per run, and a report that fails is simply dropped.
class ErrorReporter {
  const ErrorReporter._();

  static const _limit = 20;
  static const _sha = String.fromEnvironment('BUILD_SHA');
  static final _sent = <String>{};
  static Dio? _dio;
  static String? _version;

  /// Wires the reporter to everything the app does not catch itself.
  static void install() {
    if (kDebugMode) return;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      unawaited(report(details.exception, details.stack));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(report(error, stack));
      return false;
    };
  }

  /// A request that failed or timed out is a fact of mobile networks, shown to the person by the screen
  /// that asked (and the server counts what it answered): it is not a bug of the app.
  static bool _expected(Object error) =>
      error is ApiException || error is DioException;

  static Future<void> report(Object error, StackTrace? stack) async {
    try {
      if (_expected(error)) return;
      final message = error.toString();
      final lines = (stack ?? StackTrace.empty).toString();
      final kind = '${error.runtimeType}:$message:${lines.split('\n').first}';
      if (_sent.length >= _limit || !_sent.add(kind)) return;
      // The commit of a web build is added: its stack is minified and is read with that build's map.
      _version ??= await PackageInfo.fromPlatform().then(
        (i) =>
            '${i.version} (${i.buildNumber})'
            '${_sha.isEmpty ? '' : ' ${_sha.substring(0, _sha.length < 8 ? _sha.length : 8)}'}',
      );
      _dio ??= Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      await _dio!.post<void>(
        '/v1/client-errors',
        data: {
          'platform': kIsWeb
              ? 'web'
              : defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
          'appVersion': _version,
          'message': _cut(message, 500),
          'stack': _cut(lines, 4000),
        },
      );
    } on Object {
      // Reporting must never be a problem of its own.
    }
  }

  static String _cut(String text, int max) =>
      text.length <= max ? text : text.substring(0, max);
}
