import 'package:dio/dio.dart';

/// Real-network test clients use TLS, except explicitly local/emulator fixtures.
BaseOptions testOptions(String origin, {Map<String, dynamic>? headers}) {
  final uri = Uri.tryParse(origin);
  const local = {'localhost', '127.0.0.1', '::1', '10.0.2.2'};
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !{'', '/'}.contains(uri.path) ||
      !(uri.scheme == 'https' ||
          (uri.scheme == 'http' && local.contains(uri.host)))) {
    throw const FormatException(
      'Use a TLS test origin or a local emulator fixture.',
    );
  }
  return BaseOptions(
    baseUrl: origin,
    headers: headers,
    followRedirects: false,
    maxRedirects: 0,
  );
}
