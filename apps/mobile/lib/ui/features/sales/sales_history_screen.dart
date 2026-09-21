import 'dart:async';

import '../../../domain/use_cases/record_return.dart';

import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/money.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../sales/sale_screen.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class SalesPage extends StatelessWidget {
  final WorkspaceViewModel vm;
  const SalesPage({super.key, required this.vm});
  @override
  Widget build(BuildContext context) {
    final sales = vm.state.data?.list('sales') ?? [];
    return Content(
      children: [
        SectionTitle(
          vm.state.store!.canManage ? 'Ventes du magasin' : 'Mes ventes',
          subtitle: 'Les ventes et leur historique de correction.',
          action: FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SaleScreen(workspace: vm)),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Nouvelle vente'),
          ),
        ),
        if (sales.isEmpty)
          const EmptyState(
            title: 'Votre première vente vous attend',
            description: 'Enregistrez une vente pour suivre le stock et gagner des points.',
            icon: Icons.receipt_long_outlined,
          ),
        ...sales.map(
          (sale) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                title: Text(Money(integer(sale['totalMillimes'])).formatted),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${dateLabel(sale['occurredAt'])} · ${objects(sale['lines']).length} produit(s)',
                    ),
                    StatusChip(
                      sale['syncStatus'] == 'pending'
                          ? 'En attente de synchronisation'
                          : sale['syncStatus'] == 'conflict' ||
                                sale['syncStatus'] == 'rejected'
                          ? 'À vérifier'
                          : sale['local'] == true
                          ? 'Enregistrée sur ce téléphone'
                          : 'Synchronisée',
                      icon: sale['syncStatus'] != null
                          ? Icons.sync
                          : Icons.check_circle_outline,
                    ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SaleDetailScreen(vm: vm, sale: sale),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SaleDetailScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  final Json sale;
  const SaleDetailScreen({super.key, required this.vm, required this.sale});
  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  Json? details;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await widget.vm.storeRequest(
        'GET',
        'sales/${widget.sale['id']}',
      );
      if (mounted) setState(() => details = Map<String, dynamic>.from(d));
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.vm.state.data
        ?.list('sales')
        .where((s) => s['id'] == widget.sale['id'])
        .firstOrNull;
    final sale = local?['syncStatus'] != null
        ? local!
        : details?['sale'] as Json? ?? local ?? widget.sale;
    return Scaffold(
      appBar: AppBar(title: const Text('Détail de la vente')),
      body: Content(
        maxWidth: 760,
        children: [
          SectionTitle(
            Money(integer(sale['totalMillimes'])).formatted,
            subtitle:
                '${dateLabel(sale['occurredAt'])} · Révision ${sale['version']}',
          ),
          if (error != null) ...[Notice(error!), const SizedBox(height: 16)],
          ...objects(sale['lines']).map(
            (l) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(widget.vm.productName(l['productId'])),
              subtitle: Text(
                '${l['quantity']} unités × ${Money(integer(l['unitPriceMillimes'])).formatted}',
              ),
            ),
          ),
          if (sale['syncStatus'] != 'conflict' &&
              sale['syncStatus'] != 'rejected')
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SaleScreen(workspace: widget.vm, original: sale),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Corriger'),
                ),
                OutlinedButton.icon(
                  onPressed: () => recordReturn(sale),
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Enregistrer un retour'),
                ),
              ],
            ),
          const SizedBox(height: 24),
          const SectionTitle('Historique'),
          ...objects(details?['revisions']).map((r) {
            final person = objects(details?['people'])
                .where((p) => p['id'] == r['editorId'])
                .firstOrNull;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history),
              title: Text(r['reason']),
              subtitle: Text(
                '${person?['name'] ?? r['editorId']} · ${dateLabel(r['createdAt'])}',
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> recordReturn(Json sale) async {
    final choices = <String, String>{};
    for (final l in objects(sale['lines'])) {
      for (final a in objects(l['allocations'])) {
        choices['${l['id']}:${a['lotId']}'] =
            '${widget.vm.productName(l['productId'])} · Lot ${a['lotId'].toString().substring(0, 8)}';
      }
    }
    await openEditor(
      context,
      title: 'Retour client',
      fields: [
        FieldSpec('allocation', 'Produit et lot', options: choices),
        const FieldSpec(
          'quantity',
          'Quantité retournée',
          numeric: true,
          initial: '1',
        ),
        const FieldSpec(
          'sellable',
          'État des produits',
          initial: 'yes',
          options: {'yes': 'Vendables', 'no': 'Endommagés / non vendables'},
        ),
        const FieldSpec('reason', 'Motif', initial: 'Retour client'),
      ],
      submit: (v) async {
        final ids = v['allocation']!.split(':');
        final q = whole(v['quantity']!);
        final current =
            widget.vm.state.data
                ?.list('sales')
                .where((s) => s['id'] == sale['id'])
                .firstOrNull ??
            sale;
        widget.vm.requireAccess(widget.vm.state.store!, 'sell');
        await RecordReturn(widget.vm.repository).execute(
          widget.vm.user,
          widget.vm.state.store!,
          current,
          lineId: ids[0],
          lotId: ids[1],
          quantity: q,
          sellable: v['sellable'] == 'yes',
          reason: v['reason']!,
        );
        await widget.vm.reloadLocal();
        unawaited(widget.vm.synchronize(silent: true));
        if (mounted) setState(() => details = null);
      },
    );
  }
}
