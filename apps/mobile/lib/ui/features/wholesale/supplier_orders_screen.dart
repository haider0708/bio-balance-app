import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/wholesale_repository.dart';
import '../../../domain/models/inventory_rules.dart';
import '../../../domain/models/models.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../replenishment/delivery_ticket_screen.dart';
import '../replenishment/order_sections.dart';
import '../workspace/operation_helpers.dart';
import '../workspace/workspace_view_model.dart';

enum _Phase { open, complete }

/// Store orders that BioBalance assigned to this grossiste's depot.
class SupplierOrdersPage extends StatefulWidget {
  final WorkspaceViewModel vm;
  const SupplierOrdersPage({super.key, required this.vm});
  @override
  State<SupplierOrdersPage> createState() => _SupplierOrdersPageState();
}

class _SupplierOrdersPageState extends State<SupplierOrdersPage> {
  late final repository = WholesaleRepository(widget.vm.repositoryContext);
  List<Json> items = const [];
  String? next, error;
  bool loading = false, opening = false;
  _Phase phase = _Phase.open;
  int revision = 0;
  Store get depot => widget.vm.state.store!;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    if (loading) return;
    final captured = ++revision;
    setState(() => loading = true);
    try {
      final page = await repository.orders(
        depot,
        phase: phase.name,
        after: more ? next : null,
      );
      if (!mounted || captured != revision) return;
      setState(() {
        items = [if (more) ...items, ...objects(page['items'])];
        next = page['nextCursor'];
        error = null;
      });
    } catch (e) {
      if (mounted && captured == revision) {
        setState(() => error = SessionViewModel.message(e));
      }
    } finally {
      if (mounted && captured == revision) setState(() => loading = false);
    }
  }

  void select(_Phase value) {
    if (value == phase) return;
    setState(() {
      phase = value;
      items = const [];
      next = null;
      loading = false;
    });
    load();
  }

  Future<void> open(Json order) async {
    if (opening) return;
    setState(() => opening = true);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierOrderScreen(
          parent: widget.vm,
          depot: depot,
          orderId: order['id'],
        ),
      ),
    );
    if (mounted) {
      setState(() => opening = false);
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => Content.builder(
    itemCount: items.length,
    itemBuilder: (_, i) {
      final order = items[i];
      return OrderRow(
        order: order,
        storeName: order['storeName'],
        groupName: order['groupName'],
        onTap: opening ? null : () => open(order),
      );
    },
    children: [
      SectionTitle(
        'Commandes à livrer',
        subtitle: 'Attribuées à votre dépôt par BioBalance',
        action: IconButton(
          onPressed: loading ? null : () => load(),
          tooltip: 'Actualiser',
          icon: const Icon(AppIcons.refresh),
        ),
      ),
      FilterBar<_Phase>(
        options: const {_Phase.open: 'À traiter', _Phase.complete: 'Terminées'},
        selected: phase,
        onChanged: select,
      ),
      const SizedBox(height: 12),
      if (loading) const LinearProgressIndicator(),
      if (error != null) Notice(error!, retry: () => load()),
      if (items.isEmpty && !loading && error == null)
        EmptyState(
          title: phase == _Phase.open
              ? 'Aucune commande à livrer'
              : 'Aucune commande terminée',
          description: phase == _Phase.open
              ? 'Quand BioBalance vous attribue la commande d’un magasin, elle apparaît ici.'
              : 'Les commandes livrées et clôturées apparaîtront ici.',
          icon: AppIcons.localShippingOutlined,
        ),
      if (next != null)
        OutlinedButton(
          onPressed: loading ? null : () => load(more: true),
          child: const Text('Charger la suite'),
        ),
    ],
  );
}

/// Preparation, shipment by lot and settlement of one assigned order. Every
/// change is an online command that keeps its identity through a retry.
class SupplierOrderScreen extends StatefulWidget {
  final WorkspaceViewModel parent;
  final Store depot;
  final String orderId;
  const SupplierOrderScreen({
    super.key,
    required this.parent,
    required this.depot,
    required this.orderId,
  });
  @override
  State<SupplierOrderScreen> createState() => _SupplierOrderScreenState();
}

class _SupplierOrderScreenState extends State<SupplierOrderScreen> {
  late final repository = WholesaleRepository(widget.parent.repositoryContext);
  Json? data;
  String? error;
  bool loading = false, busy = false;
  WorkspaceViewModel get vm => widget.parent;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final result = await repository.order(widget.depot, widget.orderId);
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

  /// The order's store is only a destination: the depot's account acts through
  /// its assignment, never as a member of that store.
  Store get destination {
    final order = data!['order'] as Json;
    return Store.fromJson({
      'id': order['storeId'],
      'organizationId': order['organizationId'],
      'name': order['storeName'],
      'organizationName': order['groupName'],
      'permissions': ['manage'],
    });
  }

  Future<void> command(Json command, int version) async {
    await vm.online(
      command,
      expectedVersion: version,
      targetStore: destination,
      supplierStoreId: widget.depot.id,
    );
    // The depot's own stock changed on the server: pull it into this phone.
    unawaited(vm.synchronize(silent: true));
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

  List<Json> get fulfillment => objects(data?['fulfillment']);
  int get toDispatch => fulfillment.fold(
    0,
    (sum, line) => sum + integer(line['remainingToDispatch']),
  );
  int get inTransit =>
      fulfillment.fold(0, (sum, line) => sum + integer(line['inTransit']));

  @override
  Widget build(BuildContext context) {
    final order = data?['order'] as Json?;
    final status = order?['status'] ?? 'requested';
    final complete = [
      'received',
      'cancelled',
      'closed_partial',
    ].contains(status);
    final canPrepare =
        ['requested', 'partial'].contains(status) &&
        toDispatch > 0 &&
        inTransit == 0;
    final canDispatch =
        !complete && status != 'requested' && !canPrepare && toDispatch > 0;
    final disabled = busy || loading || vm.state.offline;
    return Scaffold(
      appBar: AppBar(title: const Text('Commande à livrer')),
      body: Content(
        children: [
          SectionTitle(
            order?['storeName'] ?? 'Commande',
            subtitle:
                '${order?['groupName'] ?? ''} · ${widget.orderId.substring(0, 8).toUpperCase()}',
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Notice(error!, retry: load),
          if (order != null) ...[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip(
                  statusLabel(status),
                  icon: status == 'received'
                      ? AppIcons.checkCircleOutline
                      : AppIcons.package,
                  tone: status == 'received' ? AppTone.success : AppTone.info,
                ),
                Text(
                  TunisDates.timestampLabel(order['createdAt']),
                  style: const TextStyle(fontSize: 14, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              complete
                  ? 'Cette commande est terminée.'
                  : canPrepare
                  ? 'Commencez la préparation : le magasin ne pourra plus annuler sa demande.'
                  : canDispatch
                  ? 'Choisissez les lots à expédier. Votre stock diminue à l’expédition ; celui du magasin augmente à sa réception.'
                  : 'Les produits sont en route. Le magasin confirme la réception.',
            ),
            const SizedBox(height: 16),
            if (canPrepare)
              FilledButton.icon(
                onPressed: disabled
                    ? null
                    : () => action(
                        () => command({
                          'type': 'order.prepare',
                          'orderId': widget.orderId,
                        }, integer(order['version'])),
                      ),
                icon: const Icon(AppIcons.package),
                label: const Text('Mettre en préparation'),
              ),
            if (canDispatch)
              FilledButton.icon(
                onPressed: disabled ? null : () => dispatch(order),
                icon: const Icon(AppIcons.localShippingOutlined),
                label: const Text('Expédier une livraison'),
              ),
            const SizedBox(height: 20),
            Text('Produits', style: Theme.of(context).textTheme.titleMedium),
            for (final line in objects(order['lines']))
              CompactRow(
                title: vm.productName(line['productId']),
                value: '${line['quantity']} u.',
                subtitle: progress(line['productId']),
              ),
            const SizedBox(height: 20),
            Text('Livraisons', style: Theme.of(context).textTheme.titleMedium),
            if (objects(data?['deliveries']).isEmpty)
              const Text(
                'Aucune expédition pour le moment.',
                style: TextStyle(color: muted),
              ),
            for (final delivery in objects(data?['deliveries']))
              deliveryRow(delivery),
            if (objects(data?['issues']).isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Écarts et incidents',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final issue in objects(data?['issues']))
                issueRow(issue, disabled),
            ],
          ],
        ],
      ),
    );
  }

  String? progress(String productId) {
    final line = fulfillment
        .where((l) => l['productId'] == productId)
        .firstOrNull;
    if (line == null) return null;
    return '${line['received']} reçues · ${line['inTransit']} en route\n${line['remainingToDispatch']} restant à expédier';
  }

  Widget deliveryRow(Json delivery) {
    final receipt = objects(data?['receipts'])
        .where((r) => r['deliveryId'] == delivery['id'])
        .firstOrNull;
    final lots = [
      for (final line in objects(delivery['lines']))
        for (final a in objects(line['allocations']))
          '${vm.productName(line['productId'])} · lot ${a['batch']} × ${a['quantity']}',
    ].join('\n');
    int units(String condition) =>
        objects(receipt?['lines'])
            .where((l) => (l['condition'] ?? 'sellable') == condition)
            .fold<int>(0, (sum, l) => sum + integer(l['quantity']));
    return CompactRow(
      title: 'Bon ${delivery['ticketNumber']}',
      footer: delivery['status'] == 'dispatched'
          ? Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeliveryTicketScreen(
                      vm: vm,
                      deliveryId: delivery['id'],
                      depot: widget.depot,
                    ),
                  ),
                ),
                icon: const Icon(AppIcons.qrCode, size: 18),
                label: const Text('Bon et QR'),
              ),
            )
          : null,
      subtitle:
          '${statusLabel(delivery['status'])} · ${TunisDates.timestampLabel(delivery['dispatchedAt'])}${lots.isEmpty ? '' : '\n$lots'}${receipt == null ? '' : '\nReçue : ${units('sellable')} vendables${units('damaged') > 0 ? ' · ${units('damaged')} non vendables' : ''}${units('refused') > 0 ? ' · ${units('refused')} refusées' : ''}'}',
      icon: AppIcons.localShippingOutlined,
    );
  }

  Widget issueRow(Json issue, bool disabled) => CompactRow(
    title: issue['reason'],
    subtitle:
        '${statusLabel(issue['status'])} · ${TunisDates.timestampLabel(issue['createdAt'])}',
    icon: AppIcons.infoOutline,
    tone: issue['status'] == 'resolved' ? AppTone.success : AppTone.warning,
    footer: issue['status'] != 'resolved'
        ? TextButton(
            onPressed: disabled ? null : () => action(() => settle(issue)),
            child: const Text('Traiter cet incident'),
          )
        : null,
  );

  Future<void> settle(Json issue) async {
    final delivery = objects(data?['deliveries'])
        .where((d) => d['id'] == issue['deliveryId'])
        .firstOrNull;
    if (delivery == null) {
      throw const AppFailure(
        'NOT_FOUND',
        'Actualisez la commande pour retrouver la livraison.',
      );
    }
    final received = delivery['status'] == 'received';
    await openEditor(
      context,
      title: 'Traiter l’incident',
      description: received ? null : 'Une livraison retournée remet ses lots dans votre stock. Une livraison perdue ne le remet pas.',
      fields: [
        FieldSpec(
          'decision',
          'Suite à donner',
          initial: received ? 'settled' : 'tracing',
          options: received
              ? const {'settled': 'Écarts vérifiés et réglés'}
              : const {
                  'tracing': 'Recherche en cours',
                  'lost': 'Livraison perdue',
                  'returned': 'Livraison retournée au dépôt',
                },
        ),
        const FieldSpec('reason', 'Décision et explication'),
      ],
      submit: (values) => command({
        'type': 'delivery.resolve',
        'deliveryId': delivery['id'],
        'decision': values['decision'],
        'reason': values['reason'],
      }, integer(delivery['version'])),
    );
  }

  Future<void> dispatch(Json order) async {
    final lines = fulfillment
        .where((l) => integer(l['remainingToDispatch']) > 0)
        .toList();
    final sent = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierDispatchScreen(
          parent: vm,
          depot: widget.depot,
          destination: destination,
          order: order,
          lines: lines,
          submit: (command, version) => this.command(command, version),
        ),
      ),
    );
    if (sent != null && mounted) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DeliveryTicketScreen(
            vm: vm,
            deliveryId: sent,
            depot: widget.depot,
          ),
        ),
      );
      if (mounted) await load();
    }
  }
}

/// Shipment by lot: earliest-expiry lots are proposed, and each lot's quantity
/// can be changed before confirming.
class SupplierDispatchScreen extends StatefulWidget {
  final WorkspaceViewModel parent;
  final Store depot, destination;
  final Json order;
  final List<Json> lines;
  final Future<void> Function(Json command, int version) submit;
  const SupplierDispatchScreen({
    super.key,
    required this.parent,
    required this.depot,
    required this.destination,
    required this.order,
    required this.lines,
    required this.submit,
  });
  @override
  State<SupplierDispatchScreen> createState() => _SupplierDispatchScreenState();
}

class _SupplierDispatchScreenState extends State<SupplierDispatchScreen> {
  // A retry of this screen's confirmation reuses the same delivery identity.
  final deliveryId = const Uuid().v4();
  final controllers = <String, TextEditingController>{};
  final lotsByProduct = <String, List<InventoryLot>>{};
  String? error;
  bool busy = false;
  WorkspaceViewModel get vm => widget.parent;

  @override
  void initState() {
    super.initState();
    final data = vm.state.data;
    final today = TunisDates.today();
    for (final line in widget.lines) {
      final product = line['productId'] as String;
      final lots = InventorySelection.forSale(
        data?.lotsByProduct[product] ?? const [],
        today,
      ).where((l) => l.sellable > 0).toList();
      lotsByProduct[product] = lots;
      // Earliest expiry first, as far as the stock allows.
      var remaining = integer(line['remainingToDispatch']);
      for (final lot in lots) {
        final take = remaining < lot.sellable ? remaining : lot.sellable;
        controllers[lot.id] = TextEditingController(text: '$take');
        remaining -= take;
      }
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int selected(String product) => (lotsByProduct[product] ?? const []).fold(
    0,
    (sum, lot) => sum + (int.tryParse(controllers[lot.id]!.text) ?? 0),
  );

  Future<void> confirm() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final shipped = <Json>[];
      for (final line in widget.lines) {
        final product = line['productId'] as String;
        final allocations = <Json>[];
        for (final lot in lotsByProduct[product] ?? const <InventoryLot>[]) {
          final quantity = whole(controllers[lot.id]!.text, allowZero: true);
          if (quantity > lot.sellable) {
            throw FormatException(
              'Le lot ${lot.batch} ne contient que ${lot.sellable} unité(s).',
            );
          }
          if (quantity > 0) {
            allocations.add({'lotId': lot.id, 'quantity': quantity});
          }
        }
        final total = selected(product);
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
    title: 'Expédier une livraison',
    maxWidth: 760,
    action: FilledButton(
      onPressed: busy ? null : confirm,
      child: Text(busy ? 'Envoi…' : 'Confirmer l’expédition'),
    ),
    children: [
      StatusChip(widget.destination.name, icon: AppIcons.storefrontOutlined),
      const SizedBox(height: 12),
      const Text(
        'Votre stock diminue dès la confirmation. Les lots partent avec la livraison et le magasin les retrouve à la réception.',
      ),
      const SizedBox(height: 16),
      if (error != null) Notice(error!, error: true),
      for (final line in widget.lines) ...[
        Text(
          vm.productName(line['productId']),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          '${line['remainingToDispatch']} restant à expédier · ${selected(line['productId'])} sélectionnées',
          style: const TextStyle(fontSize: 14, color: muted),
        ),
        if ((lotsByProduct[line['productId']] ?? const []).isEmpty)
          const Notice(
            'Aucun lot valide en stock pour ce produit. Saisissez d’abord votre stock.',
          ),
        for (final lot in lotsByProduct[line['productId']] ?? const [])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Lot ${lot.batch} · exp. ${TunisDates.dateOnlyLabel(lot.expiry)}\n${lot.sellable} disponible(s)',
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: controllers[lot.id],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.end,
                    decoration: const InputDecoration(labelText: 'Quantité'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
      ],
    ],
  );
}
