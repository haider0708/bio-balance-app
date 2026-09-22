import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// One trusted API origin. A redirect must never forward an account credential.
class TransportSecurity extends Interceptor {
  final Uri origin;
  TransportSecurity(String baseUrl, {bool release = kReleaseMode})
    : origin = validateOrigin(baseUrl, release: release);

  static Uri validateOrigin(String value, {required bool release}) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['', '/'].contains(uri.path) ||
        (release && uri.scheme != 'https')) {
      throw const FormatException('Une origine API HTTPS valide est requise.');
    }
    return uri;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final target = options.uri;
    if (target.scheme != origin.scheme ||
        target.host != origin.host ||
        target.port != origin.port ||
        target.userInfo.isNotEmpty) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          message: 'La destination de cette requête n’est pas autorisée.',
        ),
      );
      return;
    }
    options.followRedirects = false;
    options.maxRedirects = 0;
    handler.next(options);
  }
}
