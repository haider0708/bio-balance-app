import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'product.dart';

const _cacheKey = 'catalog.products';

class CatalogRepository {
  CatalogRepository(this._ref);

  final Ref _ref;

  /// The active catalog. Cached on the phone so selling works without a connection.
  Future<List<Product>> products({bool includeInactive = false}) async {
    final prefs = await _ref.read(preferencesProvider.future);
    try {
      final data = await _ref
          .read(apiClientProvider)
          .get(
            '/v1/products',
            query: {'includeInactive': includeInactive ? 'true' : null},
          );
      if (!includeInactive) await prefs.setString(_cacheKey, jsonEncode(data));
      return jsonList(data).map(Product.fromJson).toList();
    } on ApiException catch (error) {
      final cached = prefs.getString(_cacheKey);
      if (cached != null && (error.isOffline || error.code == 'TIMEOUT')) {
        return jsonList(jsonDecode(cached)).map(Product.fromJson).toList();
      }
      rethrow;
    }
  }

  Future<Product> create(Json body) async => Product.fromJson(
    await _ref.read(apiClientProvider).post('/v1/products', body) as Json,
  );

  Future<Product> update(String id, Json body) async => Product.fromJson(
    await _ref.read(apiClientProvider).patch('/v1/products/$id', body) as Json,
  );
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  CatalogRepository.new,
);

final productsProvider = FutureProvider.autoDispose<List<Product>>(
  (ref) => ref.watch(catalogRepositoryProvider).products(),
);

final allProductsProvider = FutureProvider<List<Product>>(
  (ref) => ref.watch(catalogRepositoryProvider).products(includeInactive: true),
);
