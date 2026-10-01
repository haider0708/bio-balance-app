import '../../core/date_field.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class _LotRow {
  final batch = TextEditingController(),
      expiry = TextEditingController(),
      quantity = TextEditingController();
  _LotRow(int initial) {
    quantity.text = '$initial';
  }
  void dispose() {
    batch.dispose();
    expiry.dispose();
    quantity.dispose();
  }
}

/// BioBalance ships without tracking its own stock, but every shipment still
/// states the batch and expiry printed on the ticket, so each lot stays
/// traceable to the store that receives it.
class DeclaredDispatchScreen extends StatefulWidget {
  final WorkspaceViewModel parent;
  final Store destination;
  final Json order;
  // Fulfillment lines that still have units to ship.
  final List<Json> lines;
  final Future<void> Function(Json command, int version) submit;
  const DeclaredDispatchScreen({
    super.key,
    required this.parent,
    required this.destination,
    required this.order,
    required this.lines,
    required this.submit,
  });
  @override
  State<DeclaredDispatchScreen> createState() => _DeclaredDispatchScreenState();
}

class _DeclaredDispatchScreenState extends State<DeclaredDispatchScreen> {
  // A retry of this screen's confirmation reuses the same delivery identity.
  final deliveryId = const Uuid().v4();
  final rows = <String, List<_LotRow>>{};
  String? error;
  bool busy = false;
  WorkspaceViewModel get vm => widget.parent;

  @override
  void initState() {
    super.initState();
    for (final line in widget.lines) {
      rows[line['productId']] = [_LotRow(integer(line['remainingToDispatch']))];
    }
  }

  @override
  void dispose() {
    for (final list in rows.values) {
      for (final row in list) {
        row.dispose();
      }
    }
    super.dispose();
  }

  int selected(String product) => (rows[product] ?? const []).fold(
    0,
    (sum, row) => sum + (int.tryParse(row.quantity.text) ?? 0),
  );

  Future<void> confirm() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final today = TunisDates.today();
      final shipped = <Json>[];
      for (final line in widget.lines) {
        final product = line['productId'] as String;
        final allocations = <Json>[];
        final seen = <String>{};
        for (final row in rows[product]!) {
          final quantity = int.tryParse(row.quantity.text.trim()) ?? 0;
          if (quantity == 0 &&
              row.batch.text.trim().isEmpty &&
              row.expiry.text.trim().isEmpty) {
            continue;
          }
          final batch = row.batch.text.trim();
          if (batch.isEmpty) {
            throw FormatException(
              '${vm.productName(product)} : indiquez le numéro de lot.',
            );
          }
          final expiry = TunisDates.expiry(row.expiry.text);
          if (expiry.compareTo(today) < 0) {
            throw FormatException(
              '${vm.productName(product)} : le lot $batch est périmé.',
            );
          }
          if (!seen.add('$batch|$expiry')) {
            throw FormatException(
              '${vm.productName(product)} : regroupez les quantités du lot $batch.',
            );
          }
          allocations.add({
            'batch': batch,
            'expiry': expiry,
            'quantity': whole(row.quantity.text),
          });
        }
        final total = allocations.fold<int>(
          0,
          (sum, a) => sum + integer(a['quantity']),
        );
        if (total > integer(line['remainingToDispatch'])) {
          throw FormatException(
            '${vm.productName(product)} : la quantité dépasse le reste à expédier.',
          );
        }
        if (total > 0) {
          shipped.add({
            'productId': product,
            'quantity': total,
            'allocations': allocations,
          });
        }
      }
      if (shipped.isEmpty) {
        throw const FormatException('Ajoutez au moins une unité à expédier.');
      }
      await widget.submit({
        'type': 'delivery.dispatch',
        'orderId': widget.order['id'],
        'deliveryId': deliveryId,
        'lines': shipped,
      }, integer(widget.order['version']));
      if (mounted) Navigator.pop(context, deliveryId);
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Préparer une livraison',
    maxWidth: 760,
    action: FilledButton(
      onPressed: busy ? null : confirm,
      child: Text(busy ? 'Envoi…' : 'Confirmer et créer le bon'),
    ),
    children: [
      StatusChip(widget.destination.name, icon: AppIcons.storefrontOutlined),
      const SizedBox(height: 12),
      const Text(
        'Pour chaque produit, indiquez les lots expédiés. Ils figurent sur le bon de livraison ; le magasin les retrouve à la réception.',
      ),
      const SizedBox(height: 16),
      if (error != null) Notice(error!, error: true),
      for (final line in widget.lines) ...[
        Text(
          vm.productName(line['productId']),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          '${line['remainingToDispatch']} restant à expédier · ${selected(line['productId'])} saisies',
          style: const TextStyle(fontSize: 14, color: muted),
        ),
        for (final entry in rows[line['productId']]!.asMap().entries)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: entry.value.batch,
                    decoration: const InputDecoration(labelText: 'Lot'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: ExpiryDateField(
                    controller: entry.value.expiry,
                    label: 'Péremption',
                    required: false,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: entry.value.quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Qté'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  tooltip: 'Retirer ce lot',
                  onPressed: rows[line['productId']]!.length == 1
                      ? null
                      : () => setState(() {
                          rows[line['productId']]!
                              .removeAt(entry.key)
                              .dispose();
                        }),
                  icon: const Icon(AppIcons.close),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: () =>
              setState(() => rows[line['productId']]!.add(_LotRow(0))),
          icon: const Icon(AppIcons.add, size: 18),
          label: const Text('Ajouter un lot'),
        ),
        const SizedBox(height: 12),
      ],
    ],
  );
}
