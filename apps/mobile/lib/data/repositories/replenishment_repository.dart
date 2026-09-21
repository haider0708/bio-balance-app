import '../../domain/models/models.dart';
import '../../domain/models/order_fulfillment.dart';
import '../services/api/generated/api_client.dart';

class ReplenishmentRepository {
  final ApiClient api;
  const ReplenishmentRepository(this.api);
  Future<OrderFulfillment> fulfillment(Store store, String orderId) async =>
      OrderFulfillment.fromJson(
        (await api.workspaceFulfillment(
          store: store.id,
          organizationId: store.organizationId,
          order: orderId,
        )).toJson(),
      );
}
