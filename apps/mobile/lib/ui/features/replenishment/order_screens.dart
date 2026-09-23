import '../catalog/product_information.dart';
import '../workspace/operation_helpers.dart';
import 'order_sections.dart';
import 'scoped_order_screen.dart';
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

class OrdersPage extends StatelessWidget {
  final WorkspaceViewModel vm;
  const OrdersPage({super.key, required this.vm});
  @override
  Widget build(BuildContext context) => _StoreOrdersList(vm: vm);

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
          '${store.name}\n${remaining.lines.map((l) => '${vm.productName(l.productId)} : ${l.received} reçues, ${l.inTransit} engagées (en route ou à vérifier), ${l.remainingToDispatch} à expédier').join('\n')}',
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

class _StoreOrdersList extends StatefulWidget {
  final WorkspaceViewModel vm;
  const _StoreOrdersList({required this.vm});
  @override
  State<_StoreOrdersList> createState() => _StoreOrdersListState();
}

class _StoreOrdersListState extends State<_StoreOrdersList> {
  OrderSection section = OrderSection.preparation;
  bool restored = false, opening = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!restored) {
      final saved = PageStorage.maybeOf(
        context,
      )?.readState(context, identifier: 'store-orders-section') as String?;
      section =
          OrderSection.values.where((v) => v.name == saved).firstOrNull ??
          section;
      restored = true;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.vm,
    builder: (context, _) {
      final vm = widget.vm, store = vm.state.store;
      if (store == null) {
        return const Content(children: [Notice('Choisissez un magasin.')]);
      }
      final orders = (vm.state.data?.list('orders') ?? [])
          .where(section.contains)
          .toList();
      return Content.builder(
        itemCount: orders.length,
        itemBuilder: (_, i) => OrderRow(
          order: orders[i],
          storeName: store.name,
          groupName: store.organizationName,
          onTap: opening
              ? null
              : () async {
                  setState(() => opening = true);
                  try {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExactOrderScreen(
                          parent: vm,
                          store: store,
                          orderId: orders[i]['id'],
                        ),
                      ),
                    );
                    if (context.mounted) await run(context, vm.reloadLocal);
                  } finally {
                    if (mounted) setState(() => opening = false);
                  }
                },
        ),
        children: [
          SectionTitle(
            vm.user.admin ? 'Commandes du magasin' : 'Mes commandes',
            subtitle: store.name,
          ),
          if (store.canManage || vm.user.admin) ...[
            FilledButton.icon(
              onPressed: () => OrdersPage(vm: vm).create(context),
              icon: const Icon(AppIcons.add),
              label: const Text('Nouvelle commande'),
            ),
            const SizedBox(height: 20),
          ],
          OrderSections(
            selected: section,
            admin: vm.user.admin,
            onChanged: (value) {
              setState(() => section = value);
              PageStorage.maybeOf(context)?.writeState(
                context,
                value.name,
                identifier: 'store-orders-section',
              );
            },
          ),
          if (orders.isEmpty)
            EmptyState(
              title:
                  'Aucune commande ${section == OrderSection.complete ? 'terminée' : 'dans cette rubrique'}',
              description: section.description(vm.user.admin),
            ),
        ],
      );
    },
  );
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
  bool busy = false, loading = true, uncertain = false, restored = false;
  String? error;
  @override
  void initState() {
    super.initState();
    draft = FormDraftController(widget.vm, store, 'order', {});
    unawaited(restore());
  }

  Future<void> restore() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await draft.restore() ?? {};
      final submission = await widget.vm.repository.draft(
        widget.vm.user.id,
        store.id,
        'online:order.create:new',
      );
      if (!mounted) return;
      for (final controller in quantities.values) {
        controller.dispose();
      }
      quantities.clear();
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
      restored = true;
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
  Widget build(BuildContext context) => FormPage(
    title: 'Nouvelle commande',
    maxWidth: 640,
    action: FilledButton(
      onPressed: !restored || loading || busy ? null : save,
      child: Text(busy ? 'Transmission…' : 'Envoyer la commande'),
    ),
    children: [
      StatusChip(store.name, icon: AppIcons.storefrontOutlined),
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
      if (!loading && !restored)
        TextButton(
          onPressed: restore,
          child: const Text('Réessayer de récupérer le brouillon'),
        ),
      for (final entry in quantities.entries) product(entry),
      if (quantities.isEmpty && !loading)
        const EmptyState(
          title: 'Choisissez vos produits',
          description: 'Saisissez les quantités nécessaires pour ce magasin.',
        ),
      OutlinedButton.icon(
        onPressed: !restored || loading || busy || uncertain ? null : add,
        icon: const Icon(AppIcons.add),
        label: const Text('Ajouter un produit'),
      ),
    ],
  );
  Widget product(MapEntry<String, TextEditingController> entry) {
    final stock = StockSummary.forProduct(data, entry.key);
    return CompactRow(
      leading: ProductPhoto(vm: widget.vm, productId: entry.key),
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
              enabled: restored && !busy && !loading && !uncertain,
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
    if (!restored || loading || busy || uncertain) return;
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductPicker(
        workspace: widget.vm,
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
    if (!restored || loading || busy || draft.completed) return;
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
      try {
        await draft.complete();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Commande envoyée. Le brouillon n’a pas pu être effacé.',
              ),
            ),
          );
        }
      }
      if (mounted) completeRoute(context);
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
