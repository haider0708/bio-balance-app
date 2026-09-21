import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../workspace/workspace_view_model.dart';
import '../workspace/operation_helpers.dart';
import '../stores/stores_screen.dart';
import '../replenishment/order_screens.dart';
import '../authentication/session_view_model.dart';

class AdminDashboard extends StatefulWidget {
  final WorkspaceViewModel vm;
  const AdminDashboard({super.key, required this.vm});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  Json? data;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.vm.request('GET', '/v1/admin/overview');
      if (mounted) {
        setState(() {
          data = Map<String, dynamic>.from(result);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    }
  }

  @override
  Widget build(BuildContext context) => Content(
    children: [
      SectionTitle(
        'Tout votre réseau',
        subtitle: 'Les magasins, les demandes et les actions prioritaires de BioBalance.',
        action: OutlinedButton.icon(
          onPressed: load,
          icon: const Icon(Icons.refresh),
          label: const Text('Actualiser'),
        ),
      ),
      if (error != null) Notice(error!, retry: load),
      if (data == null && error == null)
        const Center(child: CircularProgressIndicator()),
      if (data != null) ...[
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final value in [
              ('Magasins', '${data!['storeCount']}', Icons.storefront_outlined),
              (
                'Comptes actifs',
                '${data!['staffCount']}',
                Icons.groups_outlined,
              ),
            ])
              SizedBox(
                width: 220,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(value.$3, color: darkGreen),
                        const SizedBox(height: 12),
                        Text(
                          value.$2,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(value.$1),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => inviteManager(context, widget.vm),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Inviter un responsable'),
        ),
        const SizedBox(height: 24),
        const SectionTitle('Commandes à traiter'),
        if (objects(data!['orders']).isEmpty)
          const EmptyState(
            title: 'Aucune commande en attente',
            description: 'Les demandes des responsables apparaîtront ici.',
          ),
        ...objects(data!['orders']).map(
          (o) => Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const Icon(Icons.local_shipping_outlined),
              title: Text(o['storeName'] ?? 'Magasin'),
              subtitle: Text(statusLabel(o['status'])),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final store = widget.vm.state.stores.firstWhere(
                  (s) => s.id == o['storeId'],
                );
                await widget.vm.select(store);
                if (context.mounted) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(store.name)),
                        body: OrdersPage(vm: widget.vm),
                      ),
                    ),
                  );
                }
                await load();
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        const SectionTitle('Alertes du réseau'),
        ...objects(data!['alerts']).map(
          (a) => ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: const Icon(
              Icons.warning_amber_outlined,
              color: Color(0xFF815B12),
            ),
            title: Text(a['message']),
            subtitle: Text(a['storeName'] ?? 'Magasin'),
          ),
        ),
      ],
    ],
  );
}
