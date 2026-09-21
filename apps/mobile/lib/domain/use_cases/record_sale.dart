import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../models/money.dart';
import '../repositories/workspace_repository.dart';

class RecordSale {
  final WorkspaceRepository repository;
  RecordSale(this.repository);
  Future<void> execute(
    UserAccount user,
    Store store,
    List<SaleLine> lines, {
    Json? original,
    String? reason,
    String? recoveredSaleId,
    String? recoveredDate,
    List<String> supersedes = const [],
  }) async {
    if (lines.isEmpty) {
      throw const AppFailure('EMPTY_SALE', 'Ajoutez au moins un produit.');
    }
    final id = original?['id'] ?? recoveredSaleId ?? const Uuid().v4();
    var total = 0;
    for (final line in lines) {
      if (line.quantity < 1 ||
          line.quantity > 1000000 ||
          line.allocations.fold<int>(0, (s, a) => s + integer(a['quantity'])) !=
              line.quantity) {
        throw const AppFailure(
          'INVALID_ALLOCATION',
          'Vérifiez les quantités et les lots.',
        );
      }
      total += line.price.times(line.quantity).millimes;
    }
    Money(total);
    final returned = Map<String, dynamic>.from(original?['returned'] ?? {});
    for (final entry in returned.entries) {
      final key = entry.key.split(':');
      final line = lines.where((l) => l.id == key.first).firstOrNull;
      final allocation = line?.allocations
          .where((a) => a['lotId'] == key.last)
          .firstOrNull;
      if (integer(allocation?['quantity']) < integer(entry.value)) {
        throw const AppFailure(
          'ALREADY_RETURNED',
          'La correction ne peut pas supprimer des unités déjà retournées.',
        );
      }
    }
    final declarations = {
      for (final line in lines)
        for (final batch in line.batchDeclarations) batch.lotId: batch,
    };
    final date =
        original?['occurredAt'] ??
        recoveredDate ??
        DateTime.now().toUtc().toIso8601String();
    final command = <String, dynamic>{
      'type': original == null ? 'sale.create' : 'sale.correct',
      'saleId': id,
      'occurredAt': date,
      'lines': lines.map((l) => l.toJson(transport: true)).toList(),
      if (declarations.isNotEmpty)
        'batchDeclarations': declarations.values
            .map((b) => b.toJson())
            .toList(),
      if (original != null) 'reason': reason ?? 'Correction de saisie',
    };
    final operation = {
      'operationId': const Uuid().v4(),
      'storeId': store.id,
      'organizationId': store.organizationId,
      'payloadVersion': 2,
      if (original != null) 'expectedVersion': integer(original['version']),
      'command': command,
    };
    final sale = {
      'id': id,
      'sellerId': original?['sellerId'] ?? user.id,
      'occurredAt': date,
      'totalMillimes': '$total',
      'earnedPoints': '0',
      'version': integer(original?['version']) + 1,
      'lines': command['lines'],
      'returned': original?['returned'] ?? {},
      'local': true,
    };
    await repository.enqueue(
      user,
      store,
      operation,
      {'sale': sale},
      draftKey: supersedes.isNotEmpty
          ? 'recovery:$id'
          : original == null
          ? 'sale'
          : 'sale:$id',
      supersedes: supersedes,
    );
  }
}
