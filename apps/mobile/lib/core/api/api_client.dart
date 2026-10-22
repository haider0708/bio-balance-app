import 'package:dio/dio.dart';

import '../config.dart';
import 'api_exception.dart';

typedef TokenReader = String? Function();

/// The one place that talks HTTP: adds the sign-in token and language, and turns every
/// failure into an [ApiException] the screens can show.
class ApiClient {
  ApiClient({
    required this.tokenReader,
    required this.localeReader,
    required this.onUnauthorized,
    this.onClosed,
    this.retryDelay = const Duration(milliseconds: 700),
    this.headers = const {},
    Dio? dio,
  }) : _dio = dio ?? _build();

  final TokenReader tokenReader;
  final String Function() localeReader;
  final void Function() onUnauthorized;

  /// Called when the server is closed for now (outside the working hours), with its details.
  final void Function(Object? details)? onClosed;

  /// Sent with every request (the admin's "Show the test region" choice).
  final Map<String, String> headers;

  /// A read that fails for lack of a connection is tried once more after this pause: a flaky network
  /// often answers the second time, and a read does no harm twice.
  final Duration retryDelay;
  final Dio _dio;

  static Dio _build() => Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
    ),
  );

  Options _options({Map<String, Object?>? headers, ResponseType? type}) {
    final token = tokenReader();
    return Options(
      responseType: type,
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept-Language': localeReader(),
        ...this.headers,
        ...?headers,
      },
    );
  }

  Future<dynamic> get(String path, {Map<String, Object?>? query}) => _read(
    () => _dio.get<dynamic>(
      path,
      queryParameters: _clean(query),
      options: _options(),
    ),
  );

  Future<dynamic> post(String path, [Object? body]) => _send(
    () => _dio.post<dynamic>(
      path,
      data: body ?? <String, Object?>{},
      options: _options(),
    ),
  );

  Future<dynamic> put(String path, [Object? body]) => _send(
    () => _dio.put<dynamic>(
      path,
      data: body ?? <String, Object?>{},
      options: _options(),
    ),
  );

  Future<dynamic> patch(String path, [Object? body]) => _send(
    () => _dio.patch<dynamic>(
      path,
      data: body ?? <String, Object?>{},
      options: _options(),
    ),
  );

  Future<dynamic> delete(String path) =>
      _send(() => _dio.delete<dynamic>(path, options: _options()));

  /// A file upload: the raw bytes go in the body, the purpose in the query.
  Future<dynamic> upload(
    String path,
    List<int> bytes, {
    required Map<String, Object?> query,
  }) => _send(
    () => _dio.post<dynamic>(
      path,
      queryParameters: _clean(query),
      data: Stream.fromIterable([bytes]),
      options: _options(
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Length': bytes.length,
        },
      ),
    ),
  );

  /// Raw bytes, e.g. a proof photo.
  Future<List<int>> bytes(String path, {Map<String, Object?>? query}) async {
    final response = await _read(
      () => _dio.get<List<int>>(
        path,
        queryParameters: _clean(query),
        options: _options(type: ResponseType.bytes),
      ),
    );
    return response as List<int>;
  }

  Map<String, Object?>? _clean(Map<String, Object?>? query) => query == null
      ? null
      : (Map.of(query)..removeWhere((_, v) => v == null || v == ''));

  Future<dynamic> _read(Future<Response<dynamic>> Function() request) async {
    try {
      return await _send(request);
    } on ApiException catch (error) {
      if (error.code != 'OFFLINE' && error.code != 'TIMEOUT') rethrow;
      await Future<void>.delayed(retryDelay);
      return _send(request);
    }
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (error) {
      throw _translate(error);
    }
  }

  ApiException _translate(DioException error) {
    final response = error.response;
    if (response == null) {
      final timedOut =
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout;
      return ApiException(
        code: timedOut ? 'TIMEOUT' : 'OFFLINE',
        message: 'No connection.',
      );
    }
    final status = response.statusCode ?? 0;
    final data = response.data;
    final body = data is Map<String, dynamic>
        ? data
        : const <String, dynamic>{};
    final code = (body['code'] as String?) ?? 'HTTP_$status';
    if (status == 401 && code == 'SESSION_EXPIRED') onUnauthorized();
    if (status == 423 && code == 'SERVER_CLOSED')
      onClosed?.call(body['details']);
    final fields = <String, String>{
      for (final f
          in (body['fields'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>())
        (f['path'] as String? ?? ''): (f['message'] as String? ?? ''),
    };
    return ApiException(
      code: code,
      message: (body['message'] as String?) ?? 'Request failed.',
      status: status,
      fields: fields,
      details: body['details'],
    );
  }
}
