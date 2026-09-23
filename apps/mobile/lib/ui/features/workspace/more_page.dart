import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../catalog/catalog_screen.dart';
import '../sales/sales_history_screen.dart';
import '../rewards/rewards_screen.dart';
import '../training/training_screen.dart';
import '../announcements/announcement_screen.dart';
import '../stores/store_settings_screen.dart';
import '../stores/product_settings_screen.dart';
import '../stores/stores_screen.dart';
import '../team/team_screen.dart';
import '../reporting/history_screen.dart';
import '../reporting/scoped_sales_screen.dart';
import '../../../domain/models/dashboard.dart';
import '../synchronization/sync_screen.dart';
import '../settings/account_screen.dart';
import 'workspace_view_model.dart';

class MorePage extends StatelessWidget {
  final WorkspaceViewModel vm;
  const MorePage({super.key, required this.vm});
  Widget link(
    BuildContext context,
    String title,
    IconData icon,
    Widget page, {
    bool fullScreen = false,
    String? subtitle,
  }) => CompactRow(
    title: title,
    subtitle: subtitle,
    icon: icon,
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => fullScreen
            ? page
            : Scaffold(
                appBar: AppBar(title: Text(vm.state.store?.name ?? title)),
                body: page,
              ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final manage = vm.user.admin || vm.state.store?.canManage == true;
    return Content(
      children: [
        const SectionTitle('Plus'),
        const SectionTitle('Activité'),
        if (vm.user.admin)
          link(context, 'Catalogue', AppIcons.spaOutlined, CatalogPage(vm: vm)),
        link(
          context,
          'Ventes & corrections',
          AppIcons.receiptLongOutlined,
          SalesPage(vm: vm),
        ),
        link(
          context,
          'Récompenses & classement',
          AppIcons.redeemOutlined,
          RewardsPage(vm: vm),
        ),
        link(
          context,
          'Formation',
          AppIcons.schoolOutlined,
          TrainingPage(vm: vm),
        ),
        if (manage) ...[
          link(
            context,
            'Envoyer une annonce',
            AppIcons.campaignOutlined,
            AnnouncementScreen(vm: vm),
            fullScreen: true,
          ),
          const SizedBox(height: 20),
          const SectionTitle('Configuration du magasin'),
          link(
            context,
            'Paramètres du magasin',
            AppIcons.storefrontOutlined,
            StoreSettingsPage(vm: vm),
            subtitle: 'Nom, coordonnées et image',
          ),
          link(
            context,
            'Prix, points et seuils',
            AppIcons.tuneOutlined,
            ProductSettingsPage(vm: vm),
          ),
          link(
            context,
            'Équipe et accès',
            AppIcons.groupsOutlined,
            TeamPage(vm: vm),
          ),
          link(
            context,
            'Guide de configuration',
            AppIcons.checklistOutlined,
            OnboardingScreen(vm: vm),
            fullScreen: true,
          ),
          const SizedBox(height: 20),
          const SectionTitle('Suivi'),
          link(
            context,
            'Historique et exports',
            AppIcons.assessmentOutlined,
            ScopedSalesScreen(
              workspace: vm,
              scope: 'store',
              period: DashboardPeriod.month(),
              groupId: vm.state.store!.organizationId,
              storeId: vm.state.store!.id,
              title: vm.state.store!.name,
            ),
            fullScreen: true,
          ),
          link(
            context,
            'Journal d’audit',
            AppIcons.manageSearch,
            HistoryScreen(vm: vm, resource: 'audit', title: 'Journal d’audit'),
            fullScreen: true,
          ),
        ],
        const SizedBox(height: 20),
        const SectionTitle('Compte et aide'),
        link(
          context,
          'Synchronisation',
          AppIcons.sync,
          SyncScreen(vm: vm),
          fullScreen: true,
        ),
        link(
          context,
          'Compte, aide et synchronisation',
          AppIcons.settingsOutlined,
          AccountScreen(vm: vm),
          fullScreen: true,
        ),
      ],
    );
  }
}
