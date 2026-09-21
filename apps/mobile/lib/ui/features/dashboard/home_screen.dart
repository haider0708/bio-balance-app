import 'package:flutter/material.dart';

import '../replenishment/order_screens.dart';

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
  @override
  Widget build(BuildContext context) {
    final data = vm.state.data!;
    final summary = data.raw['summary'] as Map? ?? {};
    final saleCount = integer(summary['saleCount']);
    final total = integer(summary['totalMillimes']);
    final alerts = data.list('alerts');
    return Content(
      children: [
        SectionTitle(
          'Bonjour ${vm.user.name.split(' ').first}',
          subtitle: 'Voici l’essentiel pour votre magasin aujourd’hui.',
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: darkGreen,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chaque conseil compte.',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Des ventes bien suivies, une équipe qui avance.',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: darkGreen,
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SaleScreen(workspace: vm),
                      ),
                    ),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Nouvelle vente'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Livraisons')),
                          body: OrdersPage(vm: vm),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('Réceptionner'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final stat in [
                (
                  'Ventes synchronisées du jour',
                  '$saleCount',
                  Icons.receipt_long_outlined,
                ),
                (
                  'Montant enregistré',
                  Money(total).formatted,
                  Icons.trending_up,
                ),
                (
                  'Points disponibles',
                  '${data.available}',
                  Icons.stars_outlined,
                ),
              ])
                SizedBox(
                  width: constraints.maxWidth < 600
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 24) / 3,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(stat.$3, color: darkGreen),
                          const SizedBox(height: 16),
                          Text(
                            stat.$2,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            stat.$1,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (vm.state.store!.canManage &&
            integer((data.raw['store'] as Map?)?['onboardingStep']) < 5) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Préparez votre magasin',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Invitez votre équipe, ajoutez vos lots, puis configurez vos prix et vos points.',
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OnboardingScreen(vm: vm),
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Continuer le guide'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        const SectionTitle('À suivre aujourd’hui'),
        if (alerts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: darkGreen),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aucune alerte de stock. Votre activité est à jour.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ...alerts.map(
          (a) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: const Icon(
                  Icons.warning_amber_outlined,
                  color: Color(0xFF815B12),
                ),
                title: Text(a['message']),
                subtitle: Text(vm.productName(a['productId'] ?? '')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ['low', 'zero'].contains(a['kind']) &&
                            a['productId'] != null
                        ? OrderEditor(vm: vm, initialProductId: a['productId'])
                        : Scaffold(
                            appBar: AppBar(title: const Text('Stock')),
                            body: StockPage(vm: vm),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
