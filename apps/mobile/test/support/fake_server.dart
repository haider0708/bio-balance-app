import 'dart:convert';
import 'dart:typed_data';

import 'package:biobalance/core/api/api_client.dart';
import 'package:biobalance/core/auth/session.dart';
import 'package:biobalance/core/config.dart';
import 'package:biobalance/features/notifications/notifications_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef Handler = ({int status, Object? body}) Function(RequestOptions request);

/// A pretend BioBalance server: routes are "METHOD /path" → a function returning the response.
class FakeServer implements HttpClientAdapter {
  final Map<String, Handler> routes = {};
  final List<RequestOptions> calls = [];
  bool offline = false;

  void on(String route, Object? body, {int status = 200}) => routes[route] = (_) => (status: status, body: body);
  void handle(String route, Handler handler) => routes[route] = handler;

  int count(String route) => calls.where((c) => '${c.method} ${c.path}' == route).length;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    if (offline) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    }
    final handler = routes['${options.method} ${options.path}'];
    if (handler == null) {
      return ResponseBody.fromString(jsonEncode({'code': 'NOT_FOUND', 'message': 'no route ${options.method} ${options.path}'}), 404, headers: _json);
    }
    final result = handler(options);
    return ResponseBody.fromString(jsonEncode(result.body), result.status, headers: _json);
  }

  static const _json = {
    Headers.contentTypeHeader: ['application/json'],
  };

  @override
  void close({bool force = false}) {}

  /// Provider overrides that make the app talk to this server instead of the network.
  List<Override> overrides({String? token}) {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'session.token': ?token});
    final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl))..httpClientAdapter = this;
    return [
      unreadPollIntervalProvider.overrideWithValue(null),
      apiClientProvider.overrideWith(
        (ref) => ApiClient(
          dio: dio,
          tokenReader: () => ref.read(tokenProvider),
          localeReader: () => ref.read(localeProvider) ?? 'fr',
          onUnauthorized: () => ref.read(sessionProvider.notifier).expire(),
        ),
      ),
    ];
  }
}

Map<String, Object?> meJson({String role = 'VENDEUR', String name = 'Karim Ben Ali', String locale = 'en'}) => {
      'id': 'u1',
      'name': name,
      'email': 'karim@example.test',
      'phone': null,
      'role': role,
      'locale': locale,
      'region': {'id': 'r1', 'code': 'NORD', 'name': 'Nord'},
      'pdv': {'id': 'p1', 'name': 'Para Lac'},
      'depot': null,
    };

Map<String, Object?> productJson(String id, String name, {String family = 'Serums', String? barcode}) => {
      'id': id,
      'reference': 'REF-$id',
      'name': name,
      'family': family,
      'barcode': barcode,
      'active': true,
    };

Map<String, Object?> walletJson({int balance = 0, int todayReward = 0, int todaySales = 0}) => {
      'balanceMillimes': balance,
      'pendingPayoutMillimes': 0,
      'availableMillimes': balance,
      'today': {'sales': todaySales, 'units': todaySales * 3, 'rewardMillimes': todayReward},
      'week': {'sales': todaySales, 'units': todaySales * 3, 'rewardMillimes': todayReward},
      'month': {'sales': todaySales, 'units': todaySales * 3, 'rewardMillimes': todayReward},
    };

/// What the store holds: every product the tests sell is in stock.
Map<String, Object?> stockJson(List<String> productIds, {int quantity = 50, String place = 'p1'}) => {
      'location': {'id': place, 'kind': 'PDV', 'name': 'Para Lac', 'status': 'ACTIVE'},
      'items': [
        for (final id in productIds) {'productId': id, 'name': 'Product $id', 'family': 'Serums', 'imageId': null, 'quantity': quantity, 'level': 'OK'},
      ],
    };
