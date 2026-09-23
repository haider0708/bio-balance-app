import 'package:dio/dio.dart';

import '../../domain/models/dashboard.dart';
import '../../domain/models/models.dart';
import 'offline_repository.dart';
import 'repository_context.dart';

class DashboardRepository {
  final RepositoryContext context;
  final OfflineRepository local;
  final String accountId;
  DashboardRepository(this.context, this.local, this.accountId);
  Future<Json> attention(
    String scope,
    String kind, {
    String? organizationId,
    String? storeId,
    String? after,
  }) => context.run(
    () async => (await context.api.dashboardAttention(
      scope: scope,
      kind: kind,
      from: DashboardPeriod.today().from,
      to: DashboardPeriod.today().to,
      organizationId: organizationId,
      storeId: storeId,
      after: after,
    )).toJson(),
  );
  Future<Json> sales(
    String scope,
    DashboardPeriod period, {
    String? organizationId,
    String? storeId,
    String? after,
  }) => context.run(
    () async => (await context.api.dashboardSales(
      scope: scope,
      from: period.from,
      to: period.to,
      organizationId: organizationId,
      storeId: storeId,
      after: after,
    )).toJson(),
  );
  Future<DashboardData> load(
    String scope,
    DashboardPeriod period, {
    String? organizationId,
    String? storeId,
  }) => context.run(() async {
    final key =
        'dashboard:$scope:${organizationId ?? ''}:${storeId ?? ''}:${period.key}';
    try {
      final result = (await context.api.dashboardGet(
        scope: scope,
        from: period.from,
        to: period.to,
        organizationId: organizationId,
        storeId: storeId,
      )).toJson();
      await context.run(() => local.saveDashboard(accountId, key, result));
      return DashboardData(result);
    } on DioException catch (e) {
      if (e.response != null) rethrow;
      final cached = await local.draft(accountId, '', key);
      if (cached == null) rethrow;
      return DashboardData(cached, cached: true);
    }
  });
  Future<Json> orders(
    String scope,
    DashboardPeriod period, {
    String? organizationId,
    String? storeId,
    String? after,
    String? phase,
  }) => context.run(
    () async => (await context.api.dashboardOrders(
      scope: scope,
      from: period.from,
      to: period.to,
      organizationId: organizationId,
      storeId: storeId,
      after: after,
      phase: phase,
    )).toJson(),
  );
  Future<Json> order(Store store, String id) => context.run(
    () async => (await context.api.dashboardOrder(
      groupId: store.organizationId,
      storeId: store.id,
      id: id,
    )).toJson(),
  );
}
