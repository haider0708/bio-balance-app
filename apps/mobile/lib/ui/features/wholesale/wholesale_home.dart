import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/repositories/wholesale_repository.dart';
import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../inventory/inventory_screens.dart';
import '../replenishment/order_screens.dart';
import '../workspace/scope_view_model.dart';
import '../workspace/workspace_view_model.dart';
import 'supplier_orders_screen.dart';

/// Home of a grossiste: what is low, what to deliver and its points.
class WholesaleHome extends StatefulWidget {
  final WorkspaceViewModel vm;
  final ScopeViewModel scope;
  const WholesaleHome({super.key, required this.vm, required this.scope});
  @override
  State<WholesaleHome> createState() => _WholesaleHomeState();
}

class _WholesaleHomeState extends State<WholesaleHome> {
  int? toDeliver;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    unawaited(loadOrders());
  }

  Future<void> loadOrders() async {
    final depot = widget.vm.state.store;
    if (depot == null) return;
    try {
      final page = await WholesaleRepository(widget.vm.repositoryContext)
          .orders(depot);
      if (!mounted) return;
      setState(() {
        toDeliver =
            objects(page['items']).length +
            (page['nextCursor'] == null ? 0 : 1);
        failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.vm,
    builder: (context, _) {
      final vm = widget.vm, data = vm.state.data, store = vm.state.store!;
      final alerts = objects(data?.raw['alerts']).where(
        (a) => ['low', 'zero', 'expired', 'expiring'].contains(a['kind']),
      );
      final inStock = data == null
          ? 0
          : data.lotsByProduct.values
                .where((lots) => lots.any((l) => l.sellable > 0))
                .length;
      return Content(
        children: [
          SectionTitle(store.name, subtitle: 'Dépôt grossiste'),
          MetricStrip(
            metrics: [
              (label: 'Produits en stock', value: '$inStock'),
              (label: 'Alertes', value: '${alerts.length}'),
              (label: 'Points', value: '${data?.available ?? 0}'),
            ],
          ),
          const SizedBox(height: 12),
          CompactRow(
            title: toDeliver == null
                ? 'Commandes à livrer'
                : toDeliver == 0
                ? 'Aucune commande à livrer'
                : '$toDeliver commande(s) à livrer',
            subtitle: failed
                ? 'Actualisation impossible. Touchez pour réessayer.'
                : 'Attribuées par BioBalance à votre dépôt',
            icon: AppIcons.localShippingOutlined,
            tone: (toDeliver ?? 0) > 0 ? AppTone.warning : AppTone.info,
            onTap: () {
              if (failed) {
                unawaited(loadOrders());
              } else {
                widget.scope.setTab(2);
              }
            },
          ),
          const SizedBox(height: 12),
          OpeningStockCard(vm: vm),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => OrdersPage(vm: vm).create(context),
                icon: const Icon(AppIcons.package),
                label: const Text('Commander à BioBalance'),
              ),
            ],
          ),
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionTitle('À surveiller'),
            for (final alert in alerts.take(20))
              CompactRow(
                title: alert['message'],
                subtitle: alert['productId'] == null
                    ? null
                    : vm.productName(alert['productId']),
                icon: AppIcons.infoOutline,
                tone: AppTone.warning,
                onTap: () => widget.scope.setTab(1),
              ),
          ],
        ],
      );
    },
  );
}

/// A grossiste's orders: store orders to deliver, and its own orders to BioBalance.
class WholesaleOrdersPage extends StatefulWidget {
  final WorkspaceViewModel vm;
  const WholesaleOrdersPage({super.key, required this.vm});
  @override
  State<WholesaleOrdersPage> createState() => _WholesaleOrdersPageState();
}

class _WholesaleOrdersPageState extends State<WholesaleOrdersPage> {
  bool mine = false;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('À livrer')),
            ButtonSegment(value: true, label: Text('Mes commandes')),
          ],
          selected: {mine},
          onSelectionChanged: (value) => setState(() => mine = value.first),
        ),
      ),
      Expanded(
        child: mine
            ? OrdersPage(vm: widget.vm)
            : SupplierOrdersPage(vm: widget.vm),
      ),
    ],
  );
}
