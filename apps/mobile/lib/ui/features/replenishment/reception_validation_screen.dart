import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/receipt_plan.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../../core/navigation.dart';
import '../authentication/session_view_model.dart';
import '../catalog/product_information.dart';
import '../workspace/operation_helpers.dart';
import '../workspace/workspace_view_model.dart';

/// A parcel received without the QR is only a claim. BioBalance compares what
/// was shipped with what the store says it got, corrects it, and submits: the
/// store's stock then rises by what is validated, and the depot's moves with it.
class ReceptionValidationScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  final Json delivery;
  const ReceptionValidationScreen({
    super.key,
    required this.vm,
    required this.delivery,
  });
  @override
  State<ReceptionValidationScreen> createState() =>
      _ReceptionValidationScreenState();
}

class _ReceptionValidationScreenState extends State<ReceptionValidationScreen> {
  late List<Json> lines;
  final note = TextEditingController();
  String shortfall = 'returned';
  String? error;
  bool busy = false;

  Json? get claim => widget.delivery['claim'] as Json?;
  List<Json> get shipped => objects(widget.delivery['lines']);
  bool get fromDepot => widget.delivery['sourceStoreId'] != null;
  ReceiptPlan get plan => ReceiptPlan(shipped, lines);

  @override
  void initState() {
    super.initState();
    // The store's claim is the starting point; without one, the shipment itself
    // is, and BioBalance corrects it.
    lines = claim != null
        ? [
            for (final l in objects(claim?['lines']))
              Map<String, dynamic>.from(l),
          ]
        : [
            for (final l in shipped)
              for (final a in objects(l['allocations']))
                {
                  'productId': l['productId'],
                  'batch': a['batch'],
                  'expiry': a['expiry'],
                  'quantity': integer(a['quantity']),
                  'condition': 'sellable',
                },
          ];
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  /// Units shipped but not counted, and units counted beyond the shipment.
  int missing(String productId) {
    final got = plan.enteredUnits(productId);
    return (plan.expectedUnits(productId) - got).clamp(0, 1000000);
  }

  int surplus(String productId) {
    final got = plan.enteredUnits(productId);
    return (got - plan.expectedUnits(productId)).clamp(0, 1000000);
  }

  bool get anyMissing => shipped.any((l) => missing(l['productId']) > 0);

  Future<void> editLot(String productId, {int? index}) async {
    final target = index ?? lines.length;
    final original = index == null ? null : lines[index];
    await openEditor(
      context,
      title: widget.vm.productName(productId),
      fields: [
        FieldSpec(
          'quantity',
          'Quantité validée pour ce lot',
          initial: original == null
              ? '${plan.remaining(productId).clamp(1, 1000000)}'
              : '${original['quantity']}',
          numeric: true,
        ),
        FieldSpec('batch', 'Numéro de lot', initial: original?['batch'] ?? ''),
        FieldSpec(
          'expiry',
          'Péremption : JJ/MM/AAAA ou MM/AAAA',
          initial: original == null
              ? ''
              : TunisDates.dateOnlyLabel(original['expiry']),
        ),
        FieldSpec(
          'condition',
          'État des unités',
          initial: original?['condition'] ?? 'sellable',
          options: const {
            'sellable': 'Acceptées — stock vendable',
            'damaged': 'Abîmées — stock non vendable',
            'refused': 'Refusées — pas ajoutées au stock',
          },
        ),
      ],
      submit: (values) async {
        final value = <String, dynamic>{
          'productId': productId,
          'quantity': whole(values['quantity']!),
          'batch': values['batch']!.trim(),
          'expiry': TunisDates.expiry(values['expiry']!),
          'condition': values['condition'],
        };
        setState(() {
          if (target < lines.length) {
            lines[target] = value;
          } else {
            lines.add(value);
          }
        });
      },
    );
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (lines.isEmpty) {
        throw const FormatException(
          'Ajoutez au moins un lot reçu. Si rien n’est arrivé, signalez la livraison comme non reçue.',
        );
      }
      if (note.text.trim().length < 3) {
        throw const FormatException(
          'Indiquez la décision et ce que vous avez vérifié.',
        );
      }
      if (!mounted ||
          !await confirmAction(
            context,
            'Valider cette réception',
            'Le stock du magasin augmentera de ${plan.sellable + plan.damaged} unité(s)${anyMissing && fromDepot
                ? shortfall == 'returned'
                      ? ' et les unités manquantes retourneront au dépôt'
                      : ' ; les unités manquantes seront passées en perte'
                : ''}. Cette décision est définitive.',
            label: 'Valider',
          )) {
        return;
      }
      await widget.vm.online({
        'type': 'delivery.validate',
        'deliveryId': widget.delivery['id'],
        'lines': lines,
        'shortfall': shortfall,
        'note': note.text.trim(),
      }, expectedVersion: integer(widget.delivery['version']));
      if (mounted) {
        completeRoute(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Réception validée.')));
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String lotsOf(Json line) => objects(line['allocations'])
      .map(
        (a) =>
            '${a['quantity']} × lot ${a['batch']} (exp. ${TunisDates.dateOnlyLabel(a['expiry'])})',
      )
      .join('\n');

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Valider la réception',
    maxWidth: 760,
    action: FilledButton(
      onPressed: busy ? null : submit,
      child: Text(busy ? 'Validation…' : 'Valider la réception'),
    ),
    children: [
      StatusChip(
        'Bon ${widget.delivery['ticketNumber']}',
        icon: AppIcons.localShippingOutlined,
      ),
      const SizedBox(height: 12),
      if (error != null) Notice(error!, error: true),
      if (claim != null)
        CompactRow(
          title: 'Réception sans scan',
          subtitle:
              'Raison : ${claim!['manualReason']}${(claim!['note'] as String?)?.isNotEmpty == true ? '\n« ${claim!['note']} »' : ''}',
          icon: AppIcons.infoOutline,
          tone: AppTone.warning,
        )
      else
        const CompactRow(
          title: 'Réception au nom du magasin',
          subtitle: 'Aucune déclaration du magasin : vous saisissez ce qui a été reçu.',
          icon: AppIcons.infoOutline,
          tone: AppTone.info,
        ),
      const SizedBox(height: 16),
      const SectionTitle(
        'Expédié et validé',
        subtitle: 'Pour chaque produit : ce que l’expéditeur a déclaré, puis, en dessous, ce que vous validez.',
      ),
      for (final expected in shipped) ...[
        CompactRow(
          title: widget.vm.productName(expected['productId']),
          leading: ProductPhoto(
            vm: widget.vm,
            productId: expected['productId'],
          ),
          subtitle:
              'Expédié : ${expected['quantity']}${lotsOf(expected).isEmpty ? '' : '\n${lotsOf(expected)}'}\nValidé : ${plan.enteredUnits(expected['productId'])}${missing(expected['productId']) > 0 ? ' · manque ${missing(expected['productId'])}' : ''}${surplus(expected['productId']) > 0 ? ' · ${surplus(expected['productId'])} en plus' : ''}',
          tone:
              missing(expected['productId']) > 0 ||
                  surplus(expected['productId']) > 0
              ? AppTone.warning
              : AppTone.success,
          footer: TextButton.icon(
            onPressed: busy ? null : () => editLot(expected['productId']),
            icon: const Icon(AppIcons.add, size: 18),
            label: const Text('Ajouter un lot validé'),
          ),
        ),
        for (final entry in lines.asMap().entries)
          if (entry.value['productId'] == expected['productId'])
            CompactRow(
              title:
                  '${entry.value['quantity']} unités · ${receiptCondition(entry.value)}',
              subtitle:
                  'Lot ${entry.value['batch']} · ${TunisDates.dateOnlyLabel(entry.value['expiry'])}',
              onTap: busy
                  ? null
                  : () => editLot(expected['productId'], index: entry.key),
              trailing: IconButton(
                tooltip: 'Retirer ce lot',
                onPressed: busy
                    ? null
                    : () => setState(() => lines.removeAt(entry.key)),
                icon: const Icon(AppIcons.close),
              ),
            ),
      ],
      const SizedBox(height: 12),
      if (anyMissing && fromDepot) ...[
        const SectionTitle(
          'Unités manquantes',
          subtitle:
              'Elles ont déjà quitté le stock du grossiste. Que décidez-vous ?',
        ),
        RadioGroup<String>(
          groupValue: shortfall,
          onChanged: (value) => setState(() => shortfall = value ?? shortfall),
          child: const Column(
            children: [
              RadioListTile<String>(
                value: 'returned',
                title: Text('Le grossiste a menti : elles retournent au dépôt'),
              ),
              RadioListTile<String>(
                value: 'lost',
                title: Text('Perdues : elles sont passées en perte'),
              ),
            ],
          ),
        ),
        const Text(
          'Si le magasin a menti, ajoutez simplement les quantités manquantes ci-dessus : le magasin les reçoit, rien ne retourne au dépôt.',
          style: TextStyle(fontSize: 14, color: muted),
        ),
      ],
      if (fromDepot && shipped.any((l) => surplus(l['productId']) > 0))
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Les unités en plus sont retirées du stock du grossiste.',
            style: TextStyle(fontSize: 14, color: muted),
          ),
        ),
      const SizedBox(height: 12),
      TextField(
        controller: note,
        enabled: !busy,
        maxLength: 500,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Votre décision et ce que vous avez vérifié (obligatoire)',
        ),
      ),
      const SizedBox(height: 24),
    ],
  );
}
