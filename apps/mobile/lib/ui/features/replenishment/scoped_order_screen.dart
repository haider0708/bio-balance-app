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
import '../catalog/product_information.dart';
import '../../../domain/models/order_workflow.dart';
import 'order_screens.dart';
import 'order_sections.dart';
import 'order_actions.dart';
import 'order_creation_screen.dart';
import '../../core/forms.dart';
import '../inventory/inventory_screens.dart';
import '../../../domain/models/tunis_dates.dart';

class ScopedOrdersViewModel extends ChangeNotifier {
  final DashboardRepository repository;
  final String scope;
  final String? groupId, storeId;
  List<Json> items = [];
  String? after, error;
  bool loading = false, closed = false;
  OrderSection section = OrderSection.preparation;
  Store? filterStore;
  int revision = 0;
  void filter(Store? store) {
    filterStore = store;
    revision++;
    loading = false;
    items = [];
    after = null;
    unawaited(load());
  }

  void select(OrderSection value) {
    if (value == section) return;
    section = value;
    revision++;
    loading = false;
    items = [];
    after = null;
    unawaited(load());
  }

  ScopedOrdersViewModel(
    this.repository,
    this.scope,
    this.groupId,
    this.storeId,
  );
  Future<void> load({bool more = false}) async {
    if (loading) return;
    final captured = ++revision;
    loading = true;
    notifyListeners();
    try {
      final page = await repository.orders(
        filterStore == null ? scope : 'store',
        DashboardPeriod.month(),
        organizationId: filterStore?.organizationId ?? groupId,
        storeId: filterStore?.id ?? storeId,
        after: more ? after : null,
        phase: section.name,
      );
      if (closed || captured != revision) return;
      items = [if (more) ...items, ...objects(page['items'])];
      after = page['nextCursor'];
      error = null;
    } catch (e) {
      if (!closed && captured == revision) error = SessionViewModel.message(e);
    } finally {
      if (!closed && captured == revision) {
        loading = false;
        notifyListeners();
      }
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
  bool opening = false, restored = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!restored) {
      final name = PageStorage.maybeOf(
        context,
      )?.readState(context, identifier: 'orders-section') as String?;
      final selected = OrderSection.values
          .where((s) => s.name == name)
          .firstOrNull;
      if (selected != null) vm.select(selected);
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
      final items = vm.items;
      return Content.builder(
        key: PageStorageKey('orders:${widget.scope.scope.key}'),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final o = items[i];
          return OrderRow(
            order: o,
            storeName: o['storeName'],
            groupName: o['groupName'],
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
          FilledButton.icon(
            onPressed: opening ? null : create,
            icon: const Icon(AppIcons.add),
            label: const Text('Nouvelle commande'),
          ),
          const SizedBox(height: 16),
          if (widget.scope.scope.store == null)
            DropdownButtonFormField<String>(
              initialValue: vm.filterStore?.id ?? '',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Filtrer par magasin',
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Tous les magasins de cet espace'),
                ),
                for (final store in workspace.state.stores.where(
                  (s) => vm.groupId == null || s.organizationId == vm.groupId,
                ))
                  DropdownMenuItem(
                    value: store.id,
                    child: Text(
                      '${store.organizationName} · ${store.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) => vm.filter(
                workspace.state.stores.where((s) => s.id == id).firstOrNull,
              ),
            ),
          const SizedBox(height: 16),
          OrderSections(
            selected: vm.section,
            admin: workspace.user.admin,
            onChanged: (value) {
              PageStorage.maybeOf(
                context,
              )?.writeState(context, value.name, identifier: 'orders-section');
              vm.select(value);
            },
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
  Future<void> create() async {
    if (opening) return;
    setState(() => opening = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderCreationScreen(
            parent: workspace,
            groupId: vm.groupId,
            initialStore: vm.filterStore,
          ),
        ),
      );
      if (mounted) await vm.load();
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

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
      await vm.select(widget.store, rememberSelection: false);
      final cached = vm.state.data
          ?.list('orders')
          .where((o) => o['id'] == widget.orderId)
          .firstOrNull;
      if (mounted && cached != null) {
        setState(
          () => data = {
            'order': {
              ...cached,
              'groupName': widget.store.organizationName,
              'storeName': widget.store.name,
            },
            'deliveries':
                vm.state.data
                    ?.list('deliveries')
                    .where((d) => d['orderId'] == widget.orderId)
                    .toList() ??
                [],
            'fulfillment': cached['fulfillment'] ?? [],
          },
        );
      }
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
    final order = data?['order'] as Json?;
    final workflow = order == null
        ? null
        : OrderWorkflow(
            order,
            objects(data?['fulfillment']),
            admin: vm.user.admin,
            manager: widget.store.canManage,
          );
    final disabled = busy || loading || vm.state.offline;
    final problem = data?['problem'] as Json?;
    return ChangeNotifierProvider.value(
      value: vm,
      child: Scaffold(
        appBar: AppBar(title: const Text('Détail de la commande')),
        body: Content(
          children: [
            SectionTitle(
              widget.store.name,
              subtitle:
                  '${widget.store.organizationName} · ${widget.orderId.substring(0, 8).toUpperCase()}',
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) Notice(error!, retry: load),
            if (order != null && workflow != null) ...[
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusChip(
                    statusLabel(order['status']),
                    icon: order['status'] == 'received'
                        ? AppIcons.checkCircleOutline
                        : AppIcons.package,
                    tone: order['status'] == 'received'
                        ? AppTone.success
                        : AppTone.info,
                  ),
                  Text(
                    TunisDates.timestampLabel(order['createdAt']),
                    style: const TextStyle(fontSize: 14, color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(workflow.nextStep),
              const SizedBox(height: 16),
              if (workflow.canPrepare)
                FilledButton.icon(
                  onPressed: disabled
                      ? null
                      : () => action(
                          () => vm.online({
                            'type': 'order.prepare',
                            'orderId': widget.orderId,
                          }, expectedVersion: integer(order['version'])),
                        ),
                  icon: const Icon(AppIcons.package),
                  label: const Text('Mettre en préparation'),
                ),
              if (workflow.canDispatch)
                FilledButton.icon(
                  onPressed: disabled
                      ? null
                      : () => action(
                          () => OrdersPage(vm: vm).dispatch(context, order),
                        ),
                  icon: const Icon(AppIcons.localShippingOutlined),
                  label: const Text('Expédier une livraison'),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (workflow.canAmend)
                    TextButton(
                      onPressed: disabled
                          ? null
                          : () => action(() => editOrder(order)),
                      child: const Text('Modifier les quantités'),
                    ),
                  if (workflow.canCancel)
                    TextButton(
                      onPressed: disabled
                          ? null
                          : () => action(() => cancelOrder(order)),
                      child: Text(
                        order['status'] == 'requested'
                            ? 'Annuler la commande'
                            : 'Annuler le reliquat',
                      ),
                    ),
                  if (problem?['active'] != true)
                    TextButton.icon(
                      onPressed: disabled
                          ? null
                          : () => action(() => orderProblem(order)),
                      icon: const Icon(AppIcons.infoOutline, size: 18),
                      label: const Text('Signaler un problème'),
                    ),
                ],
              ),
              if (problem != null) ...[
                const SizedBox(height: 12),
                CompactRow(
                  title: problem['active'] == true
                      ? 'Signalement à traiter'
                      : 'Signalement traité',
                  subtitle: problem['message'],
                  icon: AppIcons.infoOutline,
                  tone: problem['active'] == true
                      ? AppTone.warning
                      : AppTone.success,
                  footer: problem['active'] == true && vm.user.admin
                      ? TextButton(
                          onPressed: disabled
                              ? null
                              : () => action(
                                  () => orderProblem(order, resolve: true),
                                ),
                          child: const Text('Répondre et résoudre'),
                        )
                      : null,
                ),
              ],
              const SizedBox(height: 20),
              Text('Produits', style: Theme.of(context).textTheme.titleMedium),
              for (final line in objects(order['lines']))
                CompactRow(
                  title: vm.productName(line['productId']),
                  value: '${line['quantity']} u.',
                  subtitle: fulfillmentLabel(line['productId']),
                  leading: ProductPhoto(vm: vm, productId: line['productId']),
                ),
              const SizedBox(height: 20),
              Text(
                'Livraisons et réception',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (objects(data?['deliveries']).isEmpty)
                const Text(
                  'Aucune expédition pour le moment.',
                  style: TextStyle(color: muted),
                ),
              for (final delivery in objects(data?['deliveries']))
                deliveryRow(delivery, disabled),
              if (objects(data?['issues']).isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Écarts et incidents de livraison',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final issue in objects(data?['issues']))
                  issueRow(issue, disabled),
              ],
              if (objects(data?['history']).isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Historique'),
                  children: [
                    for (final event in objects(data?['history']))
                      CompactRow(
                        title: historyLabel(event['action']),
                        subtitle:
                            '${TunisDates.timestampLabel(event['createdAt'])}${event['details']?['reason'] == null ? '' : ' · ${event['details']['reason']}'}',
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget deliveryRow(Json delivery, bool disabled) {
    final canReceive =
        delivery['status'] == 'dispatched' &&
        (widget.store.canManage || vm.user.admin);
    final hasIssue = objects(data?['issues'])
        .any((issue) => issue['deliveryId'] == delivery['id']);
    return CompactRow(
      title:
          'Livraison ${delivery['id'].toString().substring(0, 8).toUpperCase()}',
      subtitle:
          '${statusLabel(delivery['status'])} · ${TunisDates.timestampLabel(delivery['dispatchedAt'])}\n${objects(delivery['lines']).fold<int>(0, (sum, line) => sum + integer(line['quantity']))} unités expédiées',
      icon: AppIcons.localShippingOutlined,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?receiptSummary(delivery),
          if (canReceive) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.tonal(
                  onPressed: busy || loading
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReceiptScreen(vm: vm, delivery: delivery),
                            ),
                          );
                          if (mounted) await load();
                        },
                  child: const Text('Confirmer la réception'),
                ),
                if (!hasIssue)
                  TextButton(
                    onPressed: disabled
                        ? null
                        : () => action(() => reportDelivery(delivery)),
                    child: const Text('Non reçue'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget issueRow(Json issue, bool disabled) => CompactRow(
    title: issue['reason'],
    subtitle:
        '${statusLabel(issue['status'])} · ${TunisDates.timestampLabel(issue['createdAt'])}${objects(issue['heldLines']).map((line) => '\n${vm.productName(line['productId'])} : ${line['quantity']} unités à régler').join()}${issue['resolutionNote'] == null ? '' : '\n${issue['resolutionNote']}'}',
    icon: AppIcons.infoOutline,
    tone: issue['status'] == 'resolved' ? AppTone.success : AppTone.warning,
    footer: vm.user.admin && issue['status'] != 'resolved'
        ? TextButton(
            onPressed: disabled ? null : () => action(() => manageIssue(issue)),
            child: const Text('Traiter cet incident'),
          )
        : null,
  );

  Future<void> orderProblem(Json order, {bool resolve = false}) => openEditor(
    context,
    title: resolve ? 'Résoudre le signalement' : 'Signaler un problème',
    fields: [
      FieldSpec(
        'reason',
        resolve
            ? 'Votre réponse et la solution apportée'
            : 'Expliquez le problème ou le changement souhaité',
      ),
    ],
    submit: (values) =>
        OrderActions(vm).problem(order, values['reason']!, resolve: resolve),
  ).then((_) {});

  Future<void> manageIssue(Json issue) async {
    final delivery = objects(data?['deliveries'])
        .where((d) => d['id'] == issue['deliveryId'])
        .firstOrNull;
    if (delivery == null) {
      throw const AppFailure(
        'NOT_FOUND',
        'Actualisez la commande pour retrouver la livraison.',
      );
    }
    await openEditor(
      context,
      title: 'Traiter l’incident',
      fields: [
        FieldSpec(
          'decision',
          'Suite à donner',
          initial: delivery['status'] == 'received' ? 'settled' : 'tracing',
          options: delivery['status'] == 'received'
              ? const {'settled': 'Écarts vérifiés et réglés'}
              : const {
                  'tracing': 'Recherche en cours',
                  'lost': 'Livraison perdue — libérer le remplacement',
                  'returned': 'Livraison retournée — libérer le remplacement',
                },
        ),
        const FieldSpec('reason', 'Décision et explication'),
      ],
      submit: (values) =>
          OrderActions(vm)
              .resolve(delivery, values['decision']!, values['reason']!),
    );
  }

  Future<void> editOrder(Json order) async {
    await openEditor(
      context,
      title: 'Modifier les quantités prévues',
      fields: [
        for (final line in objects(order['lines']))
          FieldSpec(
            line['productId'],
            vm.productName(line['productId']),
            initial: '${line['quantity']}',
            numeric: true,
          ),
        FieldSpec('reason', 'Motif de la modification'),
      ],
      submit: (values) => OrderActions(vm).amend(order, values),
    );
  }

  Future<void> cancelOrder(Json order) async {
    await openEditor(
      context,
      title: order['status'] == 'requested'
          ? 'Annuler la commande'
          : 'Annuler le reliquat non expédié',
      fields: [
        FieldSpec(
          'reason',
          order['status'] == 'requested'
              ? 'Motif de l’annulation'
              : 'Motif — les livraisons engagées restent à traiter',
        ),
      ],
      submit: (v) => OrderActions(vm).cancel(order, v['reason']!),
    );
  }

  Future<void> reportDelivery(Json delivery) async {
    await openEditor(
      context,
      title: 'Signaler une livraison non reçue',
      fields: [FieldSpec('reason', 'Précisez le problème constaté')],
      submit: (v) => OrderActions(vm).report(delivery, v['reason']!),
    );
  }

  String historyLabel(String action) =>
      {
        'order.create': 'Commande demandée',
        'order.report': 'Problème signalé',
        'order.resolve': 'Signalement résolu',
        'order.amend': 'Quantités modifiées',
        'order.cancel': 'Reliquat annulé',
        'order.prepare': 'Mise en préparation',
        'delivery.dispatch': 'Livraison expédiée',
        'delivery.receive': 'Réception enregistrée',
        'delivery.report': 'Livraison signalée',
        'delivery.resolve': 'Incident traité',
      }[action] ??
      action;

  String? fulfillmentLabel(String productId) {
    final line = objects(data?['fulfillment'])
        .where((l) => l['productId'] == productId)
        .firstOrNull;
    if (line == null) return null;
    final requested = objects(data?['order']?['requestedLines'])
        .where((value) => value['productId'] == productId)
        .firstOrNull;
    final current = objects(data?['order']?['lines'])
        .where((value) => value['productId'] == productId)
        .firstOrNull;
    final initial =
        requested != null && requested['quantity'] != current?['quantity']
        ? '${requested['quantity']} demandées initialement\n'
        : '';
    return '$initial${line['received']} reçues · ${line['inTransit']} engagées\n${line['remainingToDispatch']} restant à expédier · ${line['cancelled'] ?? 0} annulées';
  }

  Widget? receiptSummary(Json delivery) {
    final receipt = objects(data?['receipts'])
        .where((r) => r['deliveryId'] == delivery['id'])
        .firstOrNull;
    if (receipt == null) {
      return null;
    }
    final lines = objects(receipt['lines']);
    int units(String condition) => lines
        .where((line) => (line['condition'] ?? 'sellable') == condition)
        .fold<int>(0, (sum, line) => sum + integer(line['quantity']));
    final details = [
      '${units('sellable')} unités vendables',
      if (units('damaged') > 0) '${units('damaged')} non vendables',
      if (units('refused') > 0) '${units('refused')} refusées',
    ].join(' · ');
    final note = receipt['differences']?['note']?.toString() ?? '';
    final differences = objects(receipt['differences']?['lines'])
        .where(
          (l) =>
              integer(l['expected']) != integer(l['actual']) ||
              integer(l['damaged']) > 0 ||
              integer(l['refused']) > 0 ||
              integer(l['surplus']) > 0,
        )
        .map(
          (l) =>
              '${vm.productName(l['productId'])} : ${l['expected']} attendues, ${l['actual']} acceptées'
              '${integer(l['damaged']) > 0 ? ', ${l['damaged']} abîmées' : ''}'
              '${integer(l['refused']) > 0 ? ', ${l['refused']} refusées' : ''}'
              '${integer(l['surplus']) > 0 ? ', ${l['surplus']} supplémentaires' : ''}',
        )
        .join('\n');
    return Text(
      '$details · ${TunisDates.timestampLabel(receipt['createdAt'])}${differences.isEmpty ? '' : '\n$differences'}${note.isEmpty ? '' : '\n$note'}',
      style: const TextStyle(fontSize: 14, color: muted),
    );
  }
}
