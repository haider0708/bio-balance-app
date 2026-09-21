import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../repositories/workspace_repository.dart';

class RecordReturn {
  final WorkspaceRepository repository;
  RecordReturn(this.repository);
  Future<void> execute(
    UserAccount user,
    Store store,
    Json sale, {
    required String lineId,
    required String lotId,
    required int quantity,
    required bool sellable,
    required String reason,
  }) async {
    if (quantity < 1 || quantity > 1000000) {
      throw const AppFailure(
        'INVALID_QUANTITY',
        'Indiquez une quantité entière positive.',
      );
    }
    final line = objects(sale['lines'])
        .where((l) => l['id'] == lineId)
        .firstOrNull;
    final allocation = objects(line?['allocations'])
        .where((a) => a['lotId'] == lotId)
        .firstOrNull;
    final returned = Map<String, dynamic>.from(sale['returned'] ?? {});
    final key = '$lineId:$lotId';
    if (allocation == null ||
        integer(returned[key]) + quantity > integer(allocation['quantity'])) {
      throw const AppFailure(
        'RETURN_EXCEEDS_SALE',
        'Cette quantité dépasse le nombre d’unités encore retournables.',
      );
    }
    returned[key] = integer(returned[key]) + quantity;
    await repository.enqueue(
      user,
      store,
      {
        'operationId': const Uuid().v4(),
        'storeId': store.id,
        'organizationId': store.organizationId,
        'payloadVersion': 1,
        'expectedVersion': integer(sale['version']),
        'command': {
          'type': 'sale.return',
          'saleId': sale['id'],
          'reason': reason,
          'lines': [
            {
              'lineId': lineId,
              'lotId': lotId,
              'quantity': quantity,
              'sellable': sellable,
            },
          ],
        },
      },
      {
        'sale': {
          ...sale,
          'returned': returned,
          'version': integer(sale['version']) + 1,
          'local': true,
        },
        'lots': [
          {'id': lotId, 'delta': sellable ? quantity : 0},
        ],
      },
    );
  }
}
