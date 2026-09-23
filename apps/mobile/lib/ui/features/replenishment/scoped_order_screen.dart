import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/dashboard_repository.dart';
import '../../../domain/models/dashboard.dart';
import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../authentication/session_view_model.dart';
import '../workspace/scope_view_model.dart';
import '../workspace/workspace_view_model.dart';
import '../workspace/operation_helpers.dart';
import '../media/image_input.dart';
import 'order_screens.dart';
import '../inventory/inventory_screens.dart';
import '../../../domain/models/tunis_dates.dart';

class ScopedOrdersViewModel extends ChangeNotifier {
  final DashboardRepository repository;
  final String scope;
  final String? groupId, storeId;
  List<Json> items = [];
  String? after, error;
  bool loading = false, closed = false;
  ScopedOrdersViewModel(
    this.repository,
    this.scope,
    this.groupId,
    this.storeId,
  );
  Future<void> load({bool more = false}) async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      final page = await repository.orders(
        scope,
        DashboardPeriod.month(),
        organizationId: groupId,
        storeId: storeId,
        after: more ? after : null,
      );
      if (closed) return;
      items = [if (more) ...items, ...objects(page['items'])];
      after = page['nextCursor'];
      error = null;
    } catch (e) {
      if (!closed) error = SessionViewModel.message(e);
    } finally {
      loading = false;
      if (!closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }
}

class ScopedOrdersPage extends StatefulWidget {
  final ScopeViewModel scope;
  const ScopedOrdersPage({super.key, required this.scope});
  @override
  State<ScopedOrdersPage> createState() => _ScopedOrdersPageState();
}

class _ScopedOrdersPageState extends State<ScopedOrdersPage> {
  late final workspace = widget.scope.workspace;
  late final vm = ScopedOrdersViewModel(
    DashboardRepository(
      workspace.repositoryContext,
      workspace.repository,
      workspace.user.id,
    ),
    widget.scope.scope.kind.name,
    widget.scope.scope.group?.id,
    widget.scope.scope.store?.id,
  )..load();
  bool opening = false, activeOnly = true, restored = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!restored) {
      activeOnly =
          PageStorage.maybeOf(context)
                  ?.readState(context, identifier: 'orders-active')
              as bool? ??
          true;
      restored = true;
    }
  }

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final items = vm.items
          .where((o) => !activeOnly || o['status'] != 'received')
          .toList();
      return Content.builder(
        key: PageStorageKey('orders:${widget.scope.scope.key}'),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final o = items[i];
          return CompactRow(
            title: o['storeName'],
            subtitle:
                '${o['groupName']} · ${TunisDates.timestampLabel(o['createdAt'])}',
            footer: StatusChip(statusLabel(o['status'])),
            icon: AppIcons.localShippingOutlined,
            onTap: opening ? null : () => open(o),
          );
        },
        children: [
          SectionTitle(
            'Commandes',
            subtitle: widget.scope.scope.group?.name ?? 'Tous les groupes',
            action: IconButton(
              onPressed: vm.loading ? null : () => vm.load(),
              tooltip: 'Actualiser',
              icon: const Icon(AppIcons.refresh),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Commandes en cours'),
            value: activeOnly,
            onChanged: (v) => setState(() {
              activeOnly = v;
              PageStorage.maybeOf(context)
                  ?.writeState(context, v, identifier: 'orders-active');
            }),
          ),
          if (vm.loading) const LinearProgressIndicator(),
          if (vm.error != null) Notice(vm.error!, retry: () => vm.load()),
          if (items.isEmpty && !vm.loading)
            const EmptyState(
              title: 'Aucune commande à afficher',
              description: 'Les demandes des magasins apparaîtront ici.',
            ),
          if (vm.after != null)
            OutlinedButton(
              onPressed: vm.loading ? null : () => vm.load(more: true),
              child: const Text('Charger la suite'),
            ),
        ],
      );
    },
  );
  Future<void> open(Json order) async {
    if (opening) return;
    setState(() => opening = true);
    await run(context, () async {
      final store = workspace.state.stores
          .where(
            (s) =>
                s.id == order['storeId'] &&
                s.organizationId == order['organizationId'],
          )
          .firstOrNull;
      if (store == null) {
        throw const AppFailure(
          'STORE_ACCESS_REVOKED',
          'Ce magasin n’est plus accessible.',
        );
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ExactOrderScreen(
            parent: workspace,
            store: store,
            orderId: order['id'],
          ),
        ),
      );
      if (mounted) await vm.load();
    });
    if (mounted) setState(() => opening = false);
  }
}

/// An order keeps its originating store for its entire route lifetime. It never
/// changes the network/group workspace while loading or synchronizing.
class ExactOrderScreen extends StatefulWidget {
  final WorkspaceViewModel parent;
  final Store store;
  final String orderId;
  const ExactOrderScreen({
    super.key,
    required this.parent,
    required this.store,
    required this.orderId,
  });
  @override
  State<ExactOrderScreen> createState() => _ExactOrderScreenState();
}

class _ExactOrderScreenState extends State<ExactOrderScreen> {
  int accessRevision = 0;
  late final vm = WorkspaceViewModel(
    widget.parent.user,
    widget.parent.repository,
    widget.parent.api,
  );
  late final detach = widget.parent.registerDraft(vm.flushDrafts);
  late final repository = DashboardRepository(
    vm.repositoryContext,
    vm.repository,
    vm.user.id,
  );
  Json? data;
  String? error;
  bool loading = false, busy = false;
  @override
  void initState() {
    super.initState();
    detach;
    vm.addListener(accessChanged);
    load();
  }

  @override
  void dispose() {
    vm.removeListener(accessChanged);
    detach();
    vm.dispose();
    super.dispose();
  }

  void accessChanged() {
    if (vm.accessRevision != accessRevision) {
      accessRevision = vm.accessRevision;
      unawaited(
        widget.parent.closeProtectedRoutes().catchError((Object e) {
          if (mounted) setState(() => error = SessionViewModel.message(e));
        }),
      );
    }
  }

  Future<void> load() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      await vm.select(widget.store);
      final result = await repository.order(widget.store, widget.orderId);
      if (mounted) {
        setState(() {
          data = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() => busy = true);
    await run(context, () async {
      await work();
      await load();
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final order = data?['order'];
    return ChangeNotifierProvider.value(
      value: vm,
      child: Scaffold(
        appBar: AppBar(title: const Text('Détail de la commande')),
        body: Content(
          children: [
            SectionTitle(
              widget.store.name,
              subtitle:
                  '${order?['groupName'] ?? widget.store.organizationName} · ${widget.orderId.substring(0, 8).toUpperCase()}',
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) Notice(error!, retry: load),
            if (order != null) ...[
              StatusChip(statusLabel(order['status'])),
              const SizedBox(height: 16),
              for (final line in objects(order['lines']))
                CompactRow(
                  title: vm.productName(line['productId']),
                  value: '${line['quantity']} unités',
                  leading: SizedBox(
                    width: 48,
                    child: _image(line['productId']),
                  ),
                ),
              if (vm.user.admin && order['status'] != 'received')
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => action(
                              () => vm.online({
                                'type': 'order.prepare',
                                'orderId': widget.orderId,
                              }, expectedVersion: integer(order['version'])),
                            ),
                      child: const Text('Mettre en préparation'),
                    ),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => action(
                              () => OrdersPage(vm: vm).dispatch(
                                context,
                                Map<String, dynamic>.from(order),
                              ),
                            ),
                      child: const Text('Préparer une livraison'),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              const SectionTitle('Livraisons'),
              for (final delivery in objects(data?['deliveries']))
                CompactRow(
                  title:
                      'Livraison ${delivery['id'].toString().substring(0, 8).toUpperCase()}',
                  subtitle: statusLabel(delivery['status']),
                  icon: AppIcons.localShippingOutlined,
                  onTap: delivery['status'] == 'dispatched'
                      ? () =>
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ReceiptScreen(vm: vm, delivery: delivery),
                              ),
                            ).then((_) {
                              if (mounted) load();
                            })
                      : null,
                ),
              if (objects(data?['deliveries']).isEmpty)
                const Text('Aucune livraison expédiée pour cette commande.'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _image(String product) {
    final p = vm.state.data
        ?.list('products')
        .where((p) => p['id'] == product)
        .firstOrNull;
    return p?['imageId'] == null
        ? const Icon(AppIcons.photo, color: muted)
        : ProtectedImage(vm: vm, id: p!['imageId'], height: 56);
  }
}
