import '../../../domain/models/models.dart';
import '../workspace/workspace_view_model.dart';

/// Converts validated editor values into versioned commands. The repository
/// persists command identity before sending; retries never invent a new write.
class OrderActions {
  final WorkspaceViewModel workspace;
  const OrderActions(this.workspace);
  Future<void> amend(Json order, Map<String, String> values) {
    final lines = <Json>[];
    for (final line in objects(order['lines'])) {
      final quantity = int.tryParse(values[line['productId']] ?? '');
      if (quantity == null || quantity < 0 || quantity > 1000000) {
        throw const AppFailure(
          'INVALID_QUANTITY',
          'Saisissez un nombre entier entre 0 et 1 000 000.',
        );
      }
      if (quantity > 0) {
        lines.add({'productId': line['productId'], 'quantity': quantity});
      }
    }
    if (lines.isEmpty) {
      throw const AppFailure(
        'EMPTY_ORDER',
        'Pour supprimer toute la demande restante, utilisez « Annuler le reliquat ».',
      );
    }
    return workspace.online({
      'type': 'order.amend',
      'orderId': order['id'],
      'lines': lines,
      'reason': values['reason'],
    }, expectedVersion: integer(order['version']));
  }

  Future<void> cancel(Json order, String reason) => workspace.online({
    'type': 'order.cancel',
    'orderId': order['id'],
    'reason': reason,
  }, expectedVersion: integer(order['version']));
  Future<void> report(Json delivery, String reason) => workspace.online({
    'type': 'delivery.report',
    'deliveryId': delivery['id'],
    'reason': reason,
  }, expectedVersion: integer(delivery['version']));
  Future<void> resolve(Json delivery, String decision, String reason) =>
      workspace.online({
        'type': 'delivery.resolve',
        'deliveryId': delivery['id'],
        'decision': decision,
        'reason': reason,
      }, expectedVersion: integer(delivery['version']));
}
