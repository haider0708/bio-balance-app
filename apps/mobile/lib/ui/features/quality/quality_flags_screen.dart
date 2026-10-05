import 'package:flutter/material.dart';

import '../../../data/repositories/quality_repository.dart';
import '../../../domain/models/models.dart';
import '../../../domain/models/money.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

String flagStatusLabel(Json flag) => switch (flag['status']) {
  'confirmed' => 'Retiré du stock',
  'rejected' => 'Remis en vente',
  _ => 'À inspecter',
};

enum _Filter { open, decided }

/// Damaged or expired goods. A store or depot flags them; BioBalance decides.
/// Nothing here is ever edited: a decision is added, and stays.
class QualityFlagsScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  // A store, or a group/depot; BioBalance may omit both for the whole network.
  final Store? store;
  final String? organizationId;
  final String title;
  const QualityFlagsScreen({
    super.key,
    required this.vm,
    this.store,
    this.organizationId,
    this.title = 'Produits non conformes',
  });
  @override
  State<QualityFlagsScreen> createState() => _QualityFlagsScreenState();
}

class _QualityFlagsScreenState extends State<QualityFlagsScreen> {
  late final repository = QualityRepository(widget.vm.repositoryContext);
  List<Json> items = const [];
  String? error;
  bool loading = true, busy = false;
  _Filter filter = _Filter.open;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final result = await repository.list(
        organizationId: widget.store?.organizationId ?? widget.organizationId,
        storeId: widget.store?.id,
        status: filter == _Filter.open ? 'open' : 'all',
      );
      if (mounted) {
        setState(() {
          items = filter == _Filter.open
              ? result
              : result.where((f) => f['status'] != 'open').toList();
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> decide(Json flag, String decision) async {
    if (busy) return;
    final confirm = decision == 'confirm';
    final done = await openEditor(
      context,
      title: confirm ? 'Retirer du stock' : 'Remettre en vente',
      description: confirm
          ? '${flag['quantity']} unité(s) de ${flag['productName']} seront retirées du stock pour de bon. La perte est enregistrée au prix de la livraison.'
          : '${flag['quantity']} unité(s) de ${flag['productName']} redeviendront vendables. Le signalement était injustifié.',
      fields: [
        if (confirm) ...[
          FieldSpec(
            'quantity',
            'Unités retenues (le reste est remis en vente)',
            initial: '${flag['quantity']}',
            numeric: true,
          ),
          FieldSpec(
            'responsibility',
            'Qui est responsable ?',
            choice: true,
            initial: 'none',
            options: {
              if (flag['sourceTicket'] != null)
                'shipper': flag['supplierName'] == null
                    ? 'L’expéditeur'
                    : 'L’expéditeur (${flag['supplierName']})',
              'store': 'Le magasin',
              'carrier': 'Le transport',
              'none': 'Personne',
            },
          ),
        ],
        const FieldSpec('note', 'Décision et explication'),
      ],
      submit: (values) => widget.vm.online(
        {
          'type': 'quality.resolve',
          'flagId': flag['id'],
          'decision': decision,
          if (confirm) ...{
            'quantity': () {
              final q = int.tryParse(values['quantity']!.trim());
              if (q == null || q < 1 || q > integer(flag['quantity'])) {
                throw FormatException(
                  'Retenez entre 1 et ${flag['quantity']} unité(s).',
                );
              }
              return q;
            }(),
            'responsibility': values['responsibility'],
          },
          'note': values['note'],
        },
        expectedVersion: integer(flag['version']),
        targetStore: Store.fromJson({
          'id': flag['storeId'],
          'organizationId': flag['organizationId'],
          'name': flag['storeName'],
          'organizationName': flag['groupName'],
          'permissions': ['manage'],
        }),
      ),
      submitLabel: confirm ? 'Retirer du stock' : 'Remettre en vente',
    );
    if (done && mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final admin = widget.vm.user.admin;
    final loss = items
        .where((f) => f['status'] == 'confirmed' && f['valueMillimes'] != null)
        .fold<int>(0, (sum, f) => sum + integer(f['valueMillimes']));
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Content(
        children: [
          SectionTitle(
            widget.title,
            subtitle: admin
                ? 'Vous décidez : retirer du stock, ou remettre en vente si le signalement était injustifié.'
                : 'Les unités signalées sont hors vente ; BioBalance décide de la suite.',
            action: IconButton(
              tooltip: 'Actualiser',
              onPressed: loading ? null : load,
              icon: const Icon(AppIcons.refresh),
            ),
          ),
          FilterBar<_Filter>(
            options: const {
              _Filter.open: 'À inspecter',
              _Filter.decided: 'Décidés',
            },
            selected: filter,
            onChanged: (value) {
              setState(() => filter = value);
              load();
            },
          ),
          const SizedBox(height: 12),
          if (filter == _Filter.decided && loss > 0)
            CompactRow(
              title: 'Pertes enregistrées',
              subtitle: 'Produits retirés du stock, au prix de leur livraison',
              value: Money(loss).formatted,
              icon: AppIcons.receiptLongOutlined,
            ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Notice(error!, retry: load),
          if (!loading && items.isEmpty && error == null)
            EmptyState(
              title: filter == _Filter.open
                  ? 'Rien à inspecter'
                  : 'Aucune décision pour le moment',
              description:
                  'Les produits abîmés ou périmés signalés apparaissent ici.',
              icon: AppIcons.checkCircleOutline,
            ),
          for (final flag in items)
            CompactRow(
              title:
                  '${flag['quantity']} × ${flag['productName']} · ${flag['kind'] == 'expired' ? 'périmé' : 'abîmé'}',
              subtitle: [
                '${flag['groupName']} · ${flag['storeName']}',
                'Lot ${flag['batch']} · exp. ${TunisDates.dateOnlyLabel(flag['expiry'])}',
                'Signalé par ${flag['flaggerName'] ?? '—'} le ${TunisDates.timestampLabel(flag['flaggedAt'])}',
                if (flag['note'] != null) '« ${flag['note']} »',
                if (flag['sourceTicket'] != null)
                  'Livré avec le bon ${flag['sourceTicket']}${flag['supplierName'] == null ? '' : ' · ${flag['supplierName']}'}',
                if (flag['status'] != 'open')
                  '${flagStatusLabel(flag)} par ${flag['deciderName'] ?? '—'}${flag['decisionNote'] == null ? '' : ' : ${flag['decisionNote']}'}',
                if (flag['confirmedQuantity'] != null &&
                    flag['confirmedQuantity'] != flag['quantity'])
                  '${flag['confirmedQuantity']} retenue(s) sur ${flag['quantity']}, le reste remis en vente',
                if (flag['responsibility'] != null &&
                    flag['responsibility'] != 'none')
                  'Responsable : ${const {'shipper': 'l’expéditeur', 'store': 'le magasin', 'carrier': 'le transport'}[flag['responsibility']]}',
                if (flag['valueMillimes'] != null)
                  'Perte : ${Money(integer(flag['valueMillimes'])).formatted}',
              ].join('\n'),
              icon: AppIcons.infoOutline,
              tone: flag['status'] == 'open'
                  ? AppTone.warning
                  : flag['status'] == 'confirmed'
                  ? AppTone.info
                  : AppTone.success,
              footer: admin && flag['status'] == 'open'
                  ? Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: busy
                              ? null
                              : () => decide(flag, 'confirm'),
                          child: const Text('Retirer du stock'),
                        ),
                        // An expired product is never put back on sale.
                        if (flag['kind'] == 'damaged')
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => decide(flag, 'reject'),
                            child: const Text('Remettre en vente'),
                          ),
                      ],
                    )
                  : StatusChip(flagStatusLabel(flag)),
            ),
        ],
      ),
    );
  }
}
