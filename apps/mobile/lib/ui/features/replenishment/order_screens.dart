import '../../core/navigation.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/repositories/replenishment_repository.dart';
import '../../../domain/models/inventory_rules.dart';
import '../../../domain/models/order_fulfillment.dart';
import '../../core/form_draft.dart';
import '../sales/sale_screen.dart';

import 'package:uuid/uuid.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';
import '../workspace/operations_screens.dart';

import '../workspace/operation_helpers.dart';

class OrdersPage extends StatelessWidget {
  final WorkspaceViewModel vm;
  const OrdersPage({super.key, required this.vm});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) => content(context),
  );

  Widget content(BuildContext context) {
    final orders = vm.state.data?.list('orders') ?? [],
        deliveries = vm.state.data?.list('deliveries') ?? [];
    final manage = vm.user.admin || vm.state.store?.canManage == true;
    final canReceive =
        manage || vm.state.store?.permissions.contains('receive') == true;
    return Content.builder(
      itemCount: deliveries.length + orders.length + 1,
      itemBuilder: (context, index) {
        if (index < deliveries.length) {
          final d = deliveries[index];
          final id = d['id'].toString();
          return CompactRow(
            title:
                'Livraison ${id.substring(0, id.length < 8 ? id.length : 8).toUpperCase()}',
            subtitle: d['syncStatus'] != null
                ? 'Réception enregistrée · ${statusLabel(d['syncStatus'])}'
                : '${objects(d['lines']).fold<int>(0, (sum, l) => sum + integer(l['quantity']))} unités annoncées',
            icon: Icons.local_shipping_outlined,
            onTap: d['syncStatus'] != null || !canReceive
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReceiptScreen(vm: vm, delivery: d),
                    ),
                  ),
          );
        }
        if (index == deliveries.length) {
          return const Padding(
            padding: EdgeInsets.only(top: 20),
            child: SectionTitle('Historique des commandes'),
          );
        }
        final order = orders[index - deliveries.length - 1],
            id = orders[index - deliveries.length - 1]['id'].toString();
        return CompactRow(
          title:
              'Commande ${id.substring(0, id.length < 8 ? id.length : 8).toUpperCase()}',
          subtitle:
              '${statusLabel(order['status'])} · ${objects(order['lines']).length} produit(s)',
          onTap: () => showOrder(context, order),
          footer: vm.user.admin && order['status'] != 'received'
              ? Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => run(
                        context,
                        () => vm.online({
                          'type': 'order.prepare',
                          'orderId': order['id'],
                        }, expectedVersion: integer(order['version'])),
                      ),
                      child: const Text('En préparation'),
                    ),
                    FilledButton.tonal(
                      onPressed: () =>
                          run(context, () => dispatch(context, order)),
                      child: const Text('Expédier une livraison'),
                    ),
                  ],
                )
              : null,
        );
      },
      children: [
        SectionTitle(
          manage ? 'Commandes & livraisons' : 'Livraisons',
          subtitle: manage
              ? 'Approvisionnement du magasin'
              : 'Confirmez les quantités reçues',
          action: manage
              ? FilledButton.icon(
                  onPressed: () => create(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Commander'),
                )
              : null,
        ),
        if (deliveries.isNotEmpty) const SectionTitle('À réceptionner'),
        if (orders.isEmpty && deliveries.isEmpty)
          const EmptyState(
            title: 'Aucune commande pour le moment',
            description: 'Les commandes et livraisons apparaîtront ici.',
          ),
      ],
    );
  }

  Future<void> showOrder(BuildContext context, Json order) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Détail de la commande'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(statusLabel(order['status'])),
            const SizedBox(height: 12),
            for (final line in objects(order['lines']))
              CompactRow(
                title: vm.productName(line['productId']),
                value: '${line['quantity']} u.',
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );

  Future<void> create(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OrderEditor(vm: vm)),
    );
  }

  Future<void> dispatch(BuildContext context, Json order) async {
    final store = vm.state.store!;
    vm.requireAccess(store, 'manage');
    final remaining = await ReplenishmentRepository(vm.api)
        .fulfillment(store, order['id']);
    if (!context.mounted) return;
    final lines = remaining.lines
        .where((line) => line.remainingToDispatch > 0)
        .toList();
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toutes les unités sont reçues ou déjà en route.'),
        ),
      );
      return;
    }
    final deliveryId = const Uuid().v4();
    await openEditor(
      context,
      title: 'Préparer une livraison',
      description:
          '${store.name}\n${remaining.lines.map((l) => '${vm.productName(l.productId)} : ${l.received} reçues, ${l.inTransit} en route, ${l.remainingToDispatch} à expédier').join('\n')}',
      fields: lines
          .map(
            (l) => FieldSpec(
              l.productId,
              vm.productName(l.productId),
              initial: '${l.remainingToDispatch}',
              numeric: true,
            ),
          )
          .toList(),
      submit: (values) async {
        final selected = <Json>[];
        for (final line in lines) {
          final quantity = whole(values[line.productId]!, allowZero: true);
          if (quantity > line.remainingToDispatch) {
            throw const FormatException(
              'La quantité dépasse le reste à expédier.',
            );
          }
          if (quantity > 0) {
            selected.add({'productId': line.productId, 'quantity': quantity});
          }
        }
        if (selected.isEmpty) {
          throw const FormatException('Ajoutez au moins une unité à expédier.');
        }
        await vm.online(
          {
            'type': 'delivery.dispatch',
            'orderId': remaining.orderId,
            'deliveryId': deliveryId,
            'lines': selected,
          },
          expectedVersion: remaining.version,
          targetStore: store,
        );
      },
      submitLabel: 'Confirmer l’expédition',
    );
  }
}

class OrderEditor extends StatefulWidget {
  final WorkspaceViewModel vm;
  final String? initialProductId;
  const OrderEditor({super.key, required this.vm, this.initialProductId});
  @override
  State<OrderEditor> createState() => _OrderEditorState();
}

class _OrderEditorState extends State<OrderEditor> {
  final quantities = <String, TextEditingController>{};
  late final Store store = widget.vm.state.store!;
  late final StoreData data = widget.vm.state.data!;
  late final FormDraftController draft;
  String orderId = const Uuid().v4();
  bool busy = false, loading = true, uncertain = false;
  String? error;
  @override
  void initState() {
    super.initState();
    draft = FormDraftController(widget.vm, store, 'order', {});
    unawaited(restore());
  }

  Future<void> restore() async {
    try {
      final values = await draft.restore() ?? {};
      final submission = await widget.vm.repository.draft(
        widget.vm.user.id,
        store.id,
        'online:order.create:new',
      );
      if (!mounted) return;
      orderId = values['_orderId'] ?? orderId;
      for (final entry in values.entries) {
        if (entry.key != '_orderId' &&
            (values.containsKey('_orderId') ||
                (int.tryParse(entry.value) ?? 0) > 0)) {
          quantities[entry.key] = TextEditingController(text: entry.value);
        }
      }
      final command = submission?['operation']?['command'];
      if (command is Map) {
        uncertain = true;
        orderId = command['orderId'];
        for (final controller in quantities.values) {
          controller.dispose();
        }
        quantities.clear();
        for (final line in objects(command['lines'])) {
          quantities[line['productId']] = TextEditingController(
            text: '${line['quantity']}',
          );
        }
      }
      final initial = widget.initialProductId;
      if (!uncertain && initial != null) {
        quantities.putIfAbsent(initial, () => TextEditingController());
      }
      await persist();
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> persist() => draft.change({
    '_orderId': orderId,
    for (final e in quantities.entries) e.key: e.value.text,
  });
  void changed() => unawaited(
    persist().catchError((Object e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    }),
  );
  @override
  void dispose() {
    draft.dispose();
    for (final controller in quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Commander des produits')),
    body: Content(
      maxWidth: 640,
      children: [
        StatusChip(store.name, icon: Icons.storefront_outlined),
        const SizedBox(height: 16),
        const Notice(
          'Brouillon conservé sur ce téléphone. Les quantités en attente comprennent les commandes à préparer et les livraisons en route. Une connexion est nécessaire pour envoyer.',
        ),
        if (uncertain)
          const Notice(
            'Une transmission reste à vérifier. Réessayez cette commande avec ses quantités enregistrées.',
          ),
        const SizedBox(height: 16),
        if (error != null) Notice(error!, error: true),
        if (loading) const LinearProgressIndicator(),
        for (final entry in quantities.entries) product(entry),
        if (quantities.isEmpty && !loading)
          const EmptyState(
            title: 'Choisissez vos produits',
            description: 'Saisissez les quantités nécessaires pour ce magasin.',
          ),
        OutlinedButton.icon(
          onPressed: loading || busy || uncertain ? null : add,
          icon: const Icon(Icons.add),
          label: const Text('Ajouter un produit'),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: loading || busy ? null : save,
          child: Text(busy ? 'Transmission…' : 'Envoyer la commande'),
        ),
      ],
    ),
  );
  Widget product(MapEntry<String, TextEditingController> entry) {
    final stock = StockSummary.forProduct(data, entry.key);
    return CompactRow(
      title:
          data.products.where((p) => p.id == entry.key).firstOrNull?.name ??
          'Produit',
      subtitle:
          'Stock : ${stock.available} · Seuil : ${stock.threshold}\nEn attente : ${FulfillmentLine.outstanding(data, entry.key)} unités',
      footer: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          children: [
            TextField(
              controller: entry.value,
              enabled: !busy && !loading && !uncertain,
              onChanged: (_) => changed(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Unités à commander',
              ),
            ),
            if (!uncertain)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          setState(
                            () => quantities.remove(entry.key)?.dispose(),
                          );
                          changed();
                        },
                  child: const Text('Retirer'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> add() async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductPicker(
        products: data.products
            .where((p) => p.active && !quantities.containsKey(p.id))
            .toList(),
      ),
    );
    if (product == null || !mounted) return;
    setState(() => quantities[product.id] = TextEditingController());
    changed();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      widget.vm.requireAccess(store, 'manage');
      await persist();
      final lines = quantities.entries
          .map(
            (entry) => <String, dynamic>{
              'productId': entry.key,
              'quantity': whole(entry.value.text),
            },
          )
          .toList();
      if (lines.isEmpty) {
        throw const FormatException('Ajoutez une quantité à commander.');
      }
      await widget.vm.online({
        'type': 'order.create',
        'orderId': orderId,
        'lines': lines,
      }, targetStore: store);
      await draft.complete();
      if (mounted) completeRoute(context);
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
