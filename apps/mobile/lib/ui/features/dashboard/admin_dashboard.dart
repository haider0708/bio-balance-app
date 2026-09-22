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

  bool fetching = false;
  Future<void> load() async {
    if (fetching) return;
    fetching = true;
    try {
      final result = await widget.vm.reporting.overview();
      if (mounted) {
        setState(() {
          data = Map<String, dynamic>.from(result);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      fetching = false;
    }
  }

  @override
  Widget build(BuildContext context) => Content(
    children: [
      SectionTitle(
        'Vue d’ensemble',
        subtitle: 'L’essentiel de votre réseau',
        action: IconButton(
          onPressed: load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Actualiser',
        ),
      ),
      if (error != null) Notice(error!, retry: load),
      if (data == null && error == null)
        const Center(child: CircularProgressIndicator()),
      if (data != null) ...[
        MetricStrip(
          metrics: [
            (label: 'Magasins', value: '${data!['storeCount']}'),
            (label: 'Comptes', value: '${data!['staffCount']}'),
            (label: 'Commandes', value: '${objects(data!['orders']).length}'),
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
          const CompactRow(
            title: 'Aucune commande en attente',
            subtitle: 'Les demandes des responsables apparaîtront ici.',
            icon: Icons.check_circle_outline,
          ),
        ...objects(data!['orders']).map(
          (o) => CompactRow(
            title: o['storeName'] ?? 'Magasin',
            subtitle: statusLabel(o['status']),
            icon: Icons.local_shipping_outlined,
            onTap: () => run(context, () async {
              final stores = await widget.vm.repository.stores(
                widget.vm.user,
                refresh: true,
              );
              final store = stores
                  .where((s) => s.id == o['storeId'])
                  .firstOrNull;
              if (store == null) {
                throw const AppFailure(
                  'STORE_ACCESS_REVOKED',
                  'Ce magasin n’est plus accessible.',
                );
              }
              await widget.vm.flushDrafts();
              await widget.vm.select(store);
              if (!context.mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(store.name)),
                    body: OrdersPage(vm: widget.vm),
                  ),
                ),
              );
              if (mounted) await load();
            }),
          ),
        ),
        const SizedBox(height: 24),
        const SectionTitle('Alertes du réseau'),
        if (objects(data!['alerts']).isEmpty)
          const CompactRow(
            title: 'Aucune alerte de stock',
            icon: Icons.check_circle_outline,
          ),
        ...objects(data!['alerts']).map(
          (a) => CompactRow(
            icon: Icons.warning_amber_outlined,
            title: a['message'],
            subtitle: a['storeName'] ?? 'Magasin',
          ),
        ),
      ],
    ],
  );
}
