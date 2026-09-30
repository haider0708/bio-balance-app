import '../../domain/models/models.dart';
import 'repository_context.dart';

/// The shipper's delivery ticket, with its QR. Never available to the receiver.
class TicketRepository {
  final RepositoryContext context;
  const TicketRepository(this.context);
  Future<Json> get(String deliveryId, {Store? depot}) => context.run(
    () async => (await context.api.ticketGet(
      id: deliveryId,
      organizationId: depot?.organizationId,
      supplierStoreId: depot?.id,
    )).toJson(),
  );
}
