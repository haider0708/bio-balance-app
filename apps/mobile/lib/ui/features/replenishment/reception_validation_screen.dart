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
  String? responsibility;

  /// A grossiste's shipment is settled lot by lot: one retained quantity per
  /// shipped lot, the truth for both the depot and the store.
  final retained = <String, TextEditingController>{};
  String lotKey(Json line, Json a) =>
      '${line['productId']}|${a['batch']}|${a['expiry']}';
  List<Json> claimFor(Json line, Json a) => objects(claim?['lines'])
      .where(
        (c) =>
            c['productId'] == line['productId'] &&
            c['batch'] == a['batch'] &&
            c['expiry'] == a['expiry'],
      )
      .toList();
  int claimed(List<Json> rows, [String? condition]) => rows
      .where(
        (c) => condition == null || (c['condition'] ?? 'sellable') == condition,
      )
      .fold(0, (n, c) => n + integer(c['quantity']));
  TextEditingController field(Json line, Json a, String kind) =>
      retained.putIfAbsent('${lotKey(line, a)}|$kind', () {
        final rows = claimFor(line, a);
        final start = switch (kind) {
          'total' =>
            claim == null || rows.isEmpty
                ? integer(a['quantity'])
                : claimed(rows),
          'damaged' => claimed(rows, 'damaged'),
          _ => claimed(rows, 'refused'),
        };
        return TextEditingController(text: '$start')
          ..addListener(() => setState(() {}));
      });
  int read(Json line, Json a, String kind) =>
      int.tryParse(field(line, a, kind).text.trim()) ?? -1;

  /// Claimed lots that are not on the ticket: shown so BioBalance can decide.
  List<Json> get claimedElsewhere => objects(claim?['lines'])
      .where(
        (c) => !shipped.any(
          (l) =>
              l['productId'] == c['productId'] &&
              objects(l['allocations']).any(
                (a) => a['batch'] == c['batch'] && a['expiry'] == c['expiry'],
              ),
        ),
      )
      .toList();
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
    for (final c in retained.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The validated lines of a grossiste shipment, built from the lot fields.
  List<Json> depotLines() {
    final out = <Json>[];
    for (final line in shipped) {
      for (final a in objects(line['allocations'])) {
        final total = read(line, a, 'total'),
            damaged = read(line, a, 'damaged'),
            refused = read(line, a, 'refused');
        if (total < 0 || damaged < 0 || refused < 0) {
          throw FormatException(
            'Lot ${a['batch']} : saisissez des nombres entiers.',
          );
        }
        if (damaged + refused > total) {
          throw FormatException(
            'Lot ${a['batch']} : abîmées et refusées dépassent la quantité retenue.',
          );
        }
        final base = {
          'productId': line['productId'],
          'batch': a['batch'],
          'expiry': a['expiry'],
        };
        if (total - damaged - refused > 0) {
          out.add({
            ...base,
            'quantity': total - damaged - refused,
            'condition': 'sellable',
          });
        }
        if (damaged > 0) {
          out.add({...base, 'quantity': damaged, 'condition': 'damaged'});
        }
        if (refused > 0) {
          out.add({...base, 'quantity': refused, 'condition': 'refused'});
        }
      }
    }
    return out;
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
          'Date de péremption',
          date: true,
          hint: 'Si seul le mois est imprimé, choisissez le dernier jour du mois.',
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
      if (fromDepot) lines = depotLines();
      if (fromDepot && responsibility == null) {
        throw const FormatException(
          'Indiquez qui est à l’origine de l’écart (ou « Aucun écart »).',
        );
      }
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
            fromDepot
                ? 'Les quantités retenues s’appliquent aux deux : le magasin reçoit ${plan.sellable + plan.damaged} unité(s) et le stock du grossiste est ajusté lot par lot. Cette décision est définitive.'
                : 'Le stock du magasin augmentera de ${plan.sellable + plan.damaged} unité(s). Cette décision est définitive.',
            label: 'Valider',
          )) {
        return;
      }
      await widget.vm.online({
        'type': 'delivery.validate',
        'deliveryId': widget.delivery['id'],
        'lines': lines,
        'shortfall': shortfall,
        'responsibility': ?responsibility,
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
      if (fromDepot) ...[
        const SectionTitle(
          'Lot par lot',
          subtitle: 'La quantité retenue s’applique au grossiste et au magasin : ce qui n’est pas retenu retourne dans son lot, ce qui est retenu en plus en sort.',
        ),
        for (final line in shipped)
          for (final a in objects(line['allocations']))
            CompactRow(
              title: widget.vm.productName(line['productId']),
              leading: ProductPhoto(
                vm: widget.vm,
                productId: line['productId'],
              ),
              subtitle:
                  'Lot ${a['batch']} · exp. ${TunisDates.dateOnlyLabel(a['expiry'])}\nExpédié par le grossiste : ${a['quantity']}\nDéclaré par le magasin : ${claim == null ? '—' : '${claimed(claimFor(line, a))}${claimed(claimFor(line, a), 'damaged') > 0 ? ' (dont ${claimed(claimFor(line, a), 'damaged')} abîmées)' : ''}${claimed(claimFor(line, a), 'refused') > 0 ? ' (dont ${claimed(claimFor(line, a), 'refused')} refusées)' : ''}'}',
              tone: read(line, a, 'total') == integer(a['quantity'])
                  ? AppTone.success
                  : AppTone.warning,
              footer: Row(
                children: [
                  for (final kind in const ['total', 'damaged', 'refused']) ...[
                    Expanded(
                      child: TextField(
                        key: ValueKey(
                          'validate.$kind.${line['productId']}.${a['batch']}',
                        ),
                        controller: field(line, a, kind),
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: switch (kind) {
                            'total' => 'Retenu',
                            'damaged' => 'dont abîmées',
                            _ => 'dont refusées',
                          },
                        ),
                      ),
                    ),
                    if (kind != 'refused') const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
        if (claimedElsewhere.isNotEmpty)
          Notice(
            'Le magasin a déclaré des lots absents du bon : ${claimedElsewhere.map((c) => '${widget.vm.productName(c['productId'])} lot ${c['batch']} × ${c['quantity']}').join(', ')}. Retenez les quantités sur les lots expédiés.',
          ),
        const SizedBox(height: 12),
        const SectionTitle('Qui est à l’origine de l’écart ?'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in const {
              'shipper': 'Le grossiste',
              'store': 'Le magasin',
              'carrier': 'Le transport',
              'none': 'Aucun écart',
            }.entries)
              ChoiceChip(
                key: ValueKey('validate.responsibility.${e.key}'),
                label: Text(e.value),
                selected: responsibility == e.key,
                onSelected: busy
                    ? null
                    : (_) => setState(() => responsibility = e.key),
              ),
          ],
        ),
      ] else ...[
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
      ],
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
