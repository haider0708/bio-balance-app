import 'dart:async';

import '../../../domain/use_cases/record_return.dart';

import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/inventory_rules.dart';
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) => content(context),
  );
  Widget content(BuildContext context) {
    if (vm.state.store == null || vm.state.data == null) {
      return const Content(
        children: [Notice('Accès à vérifier. Vos saisies sont conservées.')],
      );
    }
    final sales = vm.state.data!.list('sales');
    return Content.builder(
      itemCount: sales.length,
      itemBuilder: (context, index) {
        final sale = sales[index];
        final status = sale['syncStatus'];
        return CompactRow(
          title: Money(integer(sale['totalMillimes'])).formatted,
          subtitle:
              '${dateLabel(sale['occurredAt'])} · ${objects(sale['lines']).length} produit(s)',
          footer: StatusChip(
            ['conflict', 'rejected', 'blocked'].contains(status)
                ? 'À vérifier'
                : ['pending', 'retryable'].contains(status)
                ? 'En attente de synchronisation'
                : sale['local'] == true
                ? 'Enregistrée sur ce téléphone'
                : 'Synchronisée',
            icon: status != null ? Icons.sync : Icons.check_circle_outline,
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SaleDetailScreen(vm: vm, sale: sale),
            ),
          ),
        );
      },
      children: [
        SectionTitle(
          vm.state.store!.canManage ? 'Ventes du magasin' : 'Mes ventes',
          subtitle: 'Ventes, corrections et retours',
          action: vm.state.store!.canSell || vm.user.admin
              ? FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SaleScreen(workspace: vm),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle vente'),
                )
              : null,
        ),
        if (sales.isEmpty)
          const EmptyState(
            title: 'Votre première vente vous attend',
            description: 'Enregistrez une vente pour suivre le stock et gagner des points.',
            icon: Icons.receipt_long_outlined,
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
  Json? details, cached;
  String? error;
  late final Store store = widget.vm.state.store!;
  @override
  void initState() {
    super.initState();
    widget.vm.addListener(changed);
    load();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.vm.removeListener(changed);
    super.dispose();
  }

  Json get currentSale {
    final local = widget.vm.state.store?.id == store.id
        ? widget.vm.state.data
              ?.list('sales')
              .where((s) => s['id'] == widget.sale['id'])
              .firstOrNull
        : cached;
    return SaleSnapshot.latest(
      widget.sale,
      local ?? cached,
      details?['sale'] as Json?,
    );
  }

  Future<void> load() async {
    try {
      final local = await widget.vm.repository.load(widget.vm.user, store);
      if (mounted) {
        setState(
          () => cached = local
              ?.list('sales')
              .where((s) => s['id'] == widget.sale['id'])
              .firstOrNull,
        );
      }
      final result = await widget.vm.sales.details(store, widget.sale['id']);
      if (mounted) {
        setState(() {
          details = Map<String, dynamic>.from(result);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    }
  }

  Future<void> correct(Json sale) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SaleScreen(workspace: widget.vm, original: sale),
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final sale = currentSale;
    final seller = objects(details?['people'])
        .where((p) => p['id'] == sale['sellerId'])
        .firstOrNull;
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
          Text(
            'Vendeur : ${seller?['name'] ?? (sale['sellerId'] == widget.vm.user.id ? widget.vm.user.name : sale['sellerId'])}',
          ),
          const SizedBox(height: 12),
          if (error != null) ...[Notice(error!), const SizedBox(height: 16)],
          ...objects(sale['lines']).map(
            (l) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(widget.vm.productName(l['productId'])),
              subtitle: Text(
                '${l['quantity']} unités × ${Money(integer(l['unitPriceMillimes'])).formatted}\n${objects(l['allocations']).map((a) => '${a['quantity']} × lot ${widget.vm.state.data?.lots.where((lot) => lot.id == a['lotId']).firstOrNull?.batch ?? a['lotId']}').join(' · ')}',
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
                  onPressed: () => correct(sale),
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
        final key = '${l['id']}:${a['lotId']}';
        final remaining =
            integer(a['quantity']) - integer((sale['returned'] as Map?)?[key]);
        if (remaining <= 0) continue;
        final batch =
            widget.vm.state.data?.lots
                .where((lot) => lot.id == a['lotId'])
                .firstOrNull
                ?.batch ??
            a['lotId'];
        choices[key] =
            '${widget.vm.productName(l['productId'])} · Lot $batch · $remaining unité(s) retournable(s)';
      }
    }
    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toutes les unités ont déjà été retournées.'),
        ),
      );
      return;
    }
    await openEditor(
      context,
      title: 'Retour client',
      draftKey: 'return:${currentSale['id']}',
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
      submitWithDraft: (v, draftKey) async {
        final ids = v['allocation']!.split(':');
        final q = whole(v['quantity']!);
        final current = currentSale;
        widget.vm.requireAccess(store, 'sell');
        await RecordReturn(widget.vm.repository).execute(
          widget.vm.user,
          store,
          current,
          lineId: ids[0],
          lotId: ids[1],
          quantity: q,
          sellable: v['sellable'] == 'yes',
          reason: v['reason']!,
          draftKey: draftKey,
        );
        await widget.vm.afterLocalCommit();
        if (mounted) setState(() => details = null);
      },
    );
  }
}
