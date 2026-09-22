import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/money.dart';
import '../../core/design.dart';
import '../sales/sale_screen.dart';
import '../workspace/workspace_view_model.dart';
import '../workspace/operations_screens.dart';
import '../workspace/team_rewards_orders.dart';
import '../stores/stores_screen.dart';

class HomePage extends StatelessWidget {
  final WorkspaceViewModel vm;
  const HomePage({super.key, required this.vm});
  void open(BuildContext context, String title, Widget page) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(vm.state.store?.name ?? title)),
        body: page,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final data = vm.state.data!, store = vm.state.store!;
    final summary = data.raw['summary'] as Map? ?? {};
    final manager = store.canManage || vm.user.admin;
    final alerts = manager ? data.list('alerts') : <Json>[];
    final pendingClaims = data
        .list('claims')
        .where((c) => c['status'] == 'requested')
        .length;
    final deliveries = data
        .list('deliveries')
        .where((d) => d['syncStatus'] == null)
        .length;
    return Content.builder(
      itemCount: alerts.length,
      itemBuilder: (context, index) {
        final alert = alerts[index];
        return CompactRow(
          title: vm.productName(alert['productId'] ?? ''),
          subtitle: alert['message'],
          icon: Icons.warning_amber_outlined,
          onTap: () {
            if (['low', 'zero'].contains(alert['kind']) &&
                alert['productId'] != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      OrderEditor(vm: vm, initialProductId: alert['productId']),
                ),
              );
            } else {
              open(context, 'Stock', StockPage(vm: vm));
            }
          },
        );
      },
      children: [
        SectionTitle(
          'Bonjour ${vm.user.name.split(' ').first}',
          subtitle: 'Votre activité du jour',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (store.canSell)
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SaleScreen(workspace: vm)),
                ),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Nouvelle vente'),
              ),
            if (manager || store.permissions.contains('receive'))
              OutlinedButton.icon(
                onPressed: () =>
                    open(context, 'Livraisons', OrdersPage(vm: vm)),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Recevoir'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        MetricStrip(
          metrics: [
            (label: 'Ventes', value: '${integer(summary['saleCount'])}'),
            (
              label: 'Montant TND',
              value: Money(integer(summary['totalMillimes'])).input,
            ),
            (label: 'Points', value: '${data.available}'),
          ],
        ),
        if (manager && (data.raw['onboarding'] as Map?)?['complete'] != true)
          CompactRow(
            title: 'Continuer le guide',
            subtitle: 'Équipe, stock et paramètres du magasin',
            icon: Icons.checklist_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => OnboardingScreen(vm: vm)),
            ),
          ),
        const SizedBox(height: 20),
        SectionTitle(manager ? 'À traiter' : 'Mes raccourcis'),
        if (deliveries > 0 &&
            (manager || store.permissions.contains('receive')))
          CompactRow(
            title: 'Livraisons à réceptionner',
            value: '$deliveries',
            icon: Icons.local_shipping_outlined,
            onTap: () => open(context, 'Livraisons', OrdersPage(vm: vm)),
          ),
        CompactRow(
          title: manager ? 'Demandes de récompenses' : 'Mes récompenses',
          subtitle: manager
              ? 'Valider les remises à l’équipe'
              : 'Consulter les cadeaux et mes demandes',
          value: pendingClaims > 0 ? '$pendingClaims en attente' : null,
          icon: Icons.redeem_outlined,
          onTap: () => open(context, 'Récompenses', RewardsPage(vm: vm)),
        ),
        if (manager) ...[
          const SizedBox(height: 20),
          const SectionTitle('Alertes de stock'),
          if (alerts.isEmpty)
            const CompactRow(
              title: 'Aucune alerte de stock',
              subtitle: 'Votre stock est à jour.',
              icon: Icons.check_circle_outline,
            ),
        ] else
          CompactRow(
            title: 'Mes ventes',
            subtitle: 'Consulter, corriger ou enregistrer un retour',
            icon: Icons.receipt_long_outlined,
            onTap: () => open(context, 'Mes ventes', SalesPage(vm: vm)),
          ),
      ],
    );
  }
}
