import 'package:flutter/material.dart';
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
  Widget build(BuildContext context) {
    final orders = vm.state.data?.list('orders') ?? [],
        deliveries = vm.state.data?.list('deliveries') ?? [];
    return Content(
      children: [
        SectionTitle(
          'Commandes & livraisons',
          subtitle:
              'Demandez vos produits. Confirmez les quantités à leur arrivée.',
          action: FilledButton.icon(
            onPressed: () => create(context),
            icon: const Icon(Icons.add),
            label: const Text('Commander'),
          ),
        ),
        if (deliveries.isNotEmpty) ...[
          const SectionTitle('À réceptionner'),
          ...deliveries.map(
            (d) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(
                    Icons.local_shipping_outlined,
                    color: darkGreen,
                  ),
                  title: Text(
                    'Livraison ${d['id'].toString().substring(0, 8).toUpperCase()}',
                  ),
                  subtitle: Text(
                    '${objects(d['lines']).fold<int>(0, (s, l) => s + integer(l['quantity']))} unités annoncées',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReceiptScreen(vm: vm, delivery: d),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const SectionTitle('Historique des commandes'),
        if (orders.isEmpty)
          const EmptyState(
            title: 'Aucune commande pour le moment',
            description: 'Vous pouvez commander à tout moment, même sans alerte de stock.',
          ),
        ...orders.map(
          (o) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Commande ${o['id'].toString().substring(0, 8).toUpperCase()}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    StatusChip(
                      statusLabel(o['status']),
                      icon: Icons.local_shipping_outlined,
                    ),
                    const SizedBox(height: 12),
                    ...objects(o['lines']).map(
                      (l) => Text(
                        '${vm.productName(l['productId'])} · ${l['quantity']} unités',
                      ),
                    ),
                    if (vm.user.admin) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => run(
                              context,
                              () => vm.online({
                                'type': 'order.prepare',
                                'orderId': o['id'],
                              }, expectedVersion: integer(o['version'])),
                            ),
                            child: const Text('En préparation'),
                          ),
                          FilledButton.tonal(
                            onPressed: () => dispatch(context, o),
                            child: const Text('Expédier une livraison'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> create(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OrderEditor(vm: vm)),
    );
  }

  Future<void> dispatch(BuildContext context, Json order) async {
    await openEditor(
      context,
      title: 'Préparer une livraison',
      description: 'Les quantités expédiées ne seront ajoutées au stock qu’après réception.',
      fields: objects(order['lines'])
          .map(
            (l) => FieldSpec(
              l['productId'],
              vm.productName(l['productId']),
              initial: '${l['quantity']}',
              numeric: true,
            ),
          )
          .toList(),
      submit: (v) => vm.online({
        'type': 'delivery.dispatch',
        'orderId': order['id'],
        'deliveryId': const Uuid().v4(),
        'lines': v.entries
            .where((e) => whole(e.value, allowZero: true) > 0)
            .map((e) => {'productId': e.key, 'quantity': whole(e.value)})
            .toList(),
      }, expectedVersion: integer(order['version'])),
      submitLabel: 'Confirmer l’expédition',
    );
  }
}

class OrderEditor extends StatefulWidget {
  final WorkspaceViewModel vm;
  const OrderEditor({super.key, required this.vm});
  @override
  State<OrderEditor> createState() => _OrderEditorState();
}

class _OrderEditorState extends State<OrderEditor> {
  final quantities = <String, TextEditingController>{};
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    for (final p in widget.vm.state.data!.products) {
      quantities[p.id] = TextEditingController(text: '0');
    }
    restore();
  }

  Future<void> restore() async {
    final draft = await widget.vm.repository.draft(
      widget.vm.user.id,
      widget.vm.state.store!.id,
      'order',
    );
    if (mounted && draft != null) {
      for (final e in draft.entries) {
        quantities[e.key]?.text = '${e.value}';
      }
      setState(() {});
    }
  }

  Future<void> persist() => widget.vm.repository.saveDraft(
    widget.vm.user.id,
    widget.vm.state.store!.id,
    'order',
    {for (final e in quantities.entries) e.key: e.value.text},
  );
  @override
  void dispose() {
    for (final c in quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Commander des produits')),
    body: Content(
      maxWidth: 640,
      children: [
        const Notice(
          'Votre brouillon est conservé sur ce téléphone. Une connexion est nécessaire pour transmettre la commande.',
        ),
        const SizedBox(height: 24),
        if (error != null) Notice(error!, error: true),
        ...widget.vm.state.data!.products.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: quantities[p.id],
              onChanged: (_) => persist(),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: p.name),
            ),
          ),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: const Text('Envoyer la commande'),
        ),
      ],
    ),
  );
  Future<void> save() async {
    setState(() => busy = true);
    try {
      await persist();
      final lines = quantities.entries
          .where((e) => whole(e.value.text, allowZero: true) > 0)
          .map((e) => {'productId': e.key, 'quantity': whole(e.value.text)})
          .toList();
      if (lines.isEmpty) {
        throw const FormatException('Ajoutez une quantité à commander.');
      }
      await widget.vm.online({
        'type': 'order.create',
        'orderId': const Uuid().v4(),
        'lines': lines,
      });
      await widget.vm.repository.saveDraft(
        widget.vm.user.id,
        widget.vm.state.store!.id,
        'order',
        {},
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
