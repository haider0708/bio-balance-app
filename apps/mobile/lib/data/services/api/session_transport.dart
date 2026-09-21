import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../domain/models/models.dart';

enum AccessCondition {
  authenticated,
  offline,
  expired,
  disabled,
  storeAccessRevoked,
}

class SessionBinding {
  final String? accountId, authorization;
  final int generation, accessEpoch;
  const SessionBinding(
    this.accountId,
    this.authorization,
    this.generation,
    this.accessEpoch,
  );
}

class AccessEvent {
  final SessionBinding binding;
  final AccessCondition condition;
  final String? storeId;
  const AccessEvent(this.binding, this.condition, {this.storeId});
}

/// All transport calls capture credentials and generation before starting I/O.
class SessionTransport {
  final Dio http;
  final _events = StreamController<AccessEvent>.broadcast(sync: true);
  String? _accountId, _authorization;
  int _generation = 0, _accessEpoch = 0;
  bool _accessBlocked = false;
  SessionTransport({required String baseUrl, Dio? dio})
    : http =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );
  String? get accountId => _accountId;
  int get generation => _generation;
  bool get accessBlocked => _accessBlocked;
  Stream<AccessEvent> get accessEvents => _events.stream;
  SessionBinding get binding =>
      SessionBinding(_accountId, _authorization, _generation, _accessEpoch);
  void authenticate(String? token, {String? accountId}) {
    _generation++;
    _accessEpoch++;
    _accountId = accountId;
    _authorization = token == null ? null : 'Bearer $token';
    _accessBlocked = false;
    if (_authorization == null) {
      http.options.headers.remove('Authorization');
    } else {
      http.options.headers['Authorization'] = _authorization;
    }
  }

  void requireBinding(SessionBinding value) {
    if (value.generation != _generation ||
        value.accessEpoch != _accessEpoch ||
        value.accountId != _accountId) {
      throw const AppFailure(
        'ACCOUNT_CHANGED',
        'La session a changé. Les données restent liées au compte d’origine.',
      );
    }
  }

  void markExpired() {
    _accessBlocked = true;
    _accessEpoch++;
  }

  void confirmAccessLoss(AccessCondition condition, {String? storeId}) {
    final current = binding;
    _accessEpoch++;
    if (condition == AccessCondition.expired ||
        condition == AccessCondition.disabled) {
      _accessBlocked = true;
    }
    _events.add(AccessEvent(current, condition, storeId: storeId));
  }

  Future<dynamic> request(
    String method,
    String path, {
    dynamic body,
    Map<String, dynamic>? query,
  }) async {
    final captured = binding;
    final identity = path.startsWith('/v1/identity/');
    if (_accessBlocked && !identity) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 401,
          data: {
            'code': 'SESSION_EXPIRED',
            'message':
                'Veuillez vous reconnecter. Les brouillons sont conservés.',
          },
        ),
      );
    }
    final store =
        RegExp(r'/v1/stores/([^/]+)').firstMatch(path)?.group(1) ??
        (body is Map &&
                body['operations'] is List &&
                (body['operations'] as List).length == 1
            ? body['operations'][0]['storeId'] as String?
            : null);
    try {
      final response = await http.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {'Authorization': captured.authorization},
        ),
      );
      requireBinding(captured);
      if (captured.accountId != null && !identity) {
        _events.add(
          AccessEvent(captured, AccessCondition.authenticated, storeId: store),
        );
      }
      return response.data;
    } on DioException catch (error) {
      requireBinding(captured);
      _reportError(captured, error, identity, store);
      rethrow;
    }
  }

  void _reportError(
    SessionBinding captured,
    DioException error,
    bool identity,
    String? store,
  ) {
    if (captured.accountId != null && !identity) {
      final status = error.response?.statusCode;
      final code = error.response?.data is Map
          ? error.response!.data['code']
          : null;
      AccessCondition? condition;
      if (status == 401) {
        condition = AccessCondition.expired;
        _accessBlocked = true;
      } else if (status == 403 && code == 'ACCESS_DISABLED') {
        condition = AccessCondition.disabled;
        _accessBlocked = true;
      } else if (status == 403 && code == 'STORE_ACCESS_REVOKED') {
        condition = AccessCondition.storeAccessRevoked;
      } else if (error.response == null &&
          error.type != DioExceptionType.cancel) {
        condition = AccessCondition.offline;
      }
      if (condition != null) {
        if (condition != AccessCondition.offline) _accessEpoch++;
        _events.add(AccessEvent(captured, condition, storeId: store));
      }
    }
  }

  Future<Response<T>> transfer<T>(
    String method,
    String path, {
    dynamic body,
    Map<String, dynamic>? headers,
    ResponseType? responseType,
    CancelToken? cancelToken,
    bool Function(int?)? validateStatus,
    String? storeId,
  }) async {
    final captured = binding;
    if (_accessBlocked) {
      throw const AppFailure(
        'SESSION_EXPIRED',
        'Reconnectez-vous pour reprendre ce transfert.',
      );
    }
    try {
      final response = await http.request<T>(
        path,
        data: body,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          responseType: responseType,
          validateStatus: validateStatus,
          headers: {...?headers, 'Authorization': captured.authorization},
        ),
      );
      try {
        requireBinding(captured);
      } catch (_) {
        final body = response.data;
        if (body is ResponseBody) await body.stream.listen((_) {}).cancel();
        rethrow;
      }
      return response;
    } on DioException catch (error) {
      final body = error.response?.data;
      if (body is ResponseBody) {
        final bytes = <int>[];
        await for (final chunk in body.stream) {
          bytes.addAll(chunk);
          if (bytes.length > 65536) break;
        }
        try {
          error.response?.data = jsonDecode(utf8.decode(bytes));
        } catch (_) {}
      } else if (body is List<int>) {
        try {
          error.response?.data = jsonDecode(utf8.decode(body));
        } catch (_) {}
      }
      requireBinding(captured);
      _reportError(captured, error, false, storeId);
      rethrow;
    }
  }

  Uri mediaUri(String id, SessionBinding captured) {
    requireBinding(captured);
    return Uri.parse(http.options.baseUrl)
        .resolve('/v1/media/${Uri.encodeComponent(id)}')
        .replace(queryParameters: {'session': '${captured.generation}'});
  }

  /// Logout cleanup uses only the captured old credential and never feeds a cache.
  Future<void> revoke(SessionBinding previous) async {
    if (previous.authorization == null) return;
    await http.request<void>(
      '/v1/identity/logout',
      options: Options(
        method: 'POST',
        headers: {'Authorization': previous.authorization},
      ),
    );
  }
}
