import '../team/invitations_screen.dart';
import '../wholesale/wholesalers_screen.dart';
import 'lifecycle_screen.dart';

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
import 'scope_view_model.dart';
import 'group_screens.dart';
import 'operation_helpers.dart';
import 'workspace_help.dart';

class MorePage extends StatelessWidget {
  final WorkspaceViewModel vm;
  final ScopeViewModel? scope;
  final bool showTitle;
  const MorePage({
    super.key,
    required this.vm,
    this.scope,
    this.showTitle = true,
  });
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
                appBar: AppBar(title: Text(title)),
                body: page,
              ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, ?scope]),
    builder: (context, _) => contents(context),
  );

  Widget contents(BuildContext context) {
    final store = vm.state.store;
    final group = scope?.scope.group;
    final wholesale = store?.wholesale == true;
    final manage = store != null && (vm.user.admin || store.canManage);
    final groupManage = group != null && (vm.user.admin || group.canManage);
    return Content(
      children: [
        if (showTitle)
          SectionTitle(
            'Paramètres et gestion',
            subtitle: store != null
                ? '${store.organizationName} · ${store.name}'
                : group?.name ?? 'BioBalance · tous les groupes',
          ),
        if (!showTitle)
          Text(
            store != null
                ? '${store.organizationName} · ${store.name}'
                : group?.name ?? 'BioBalance · tous les groupes',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        const SizedBox(height: 12),
        if (store != null) ...[
          const SectionTitle('Activité du magasin'),
          if (!wholesale)
            link(
              context,
              'Ventes & corrections',
              AppIcons.receiptLongOutlined,
              SalesPage(vm: vm),
            ),
          link(
            context,
            wholesale ? 'Points et récompenses' : 'Récompenses & classement',
            AppIcons.redeemOutlined,
            RewardsPage(vm: vm),
          ),
          if (!vm.user.admin && !wholesale)
            link(
              context,
              'Formation',
              AppIcons.schoolOutlined,
              TrainingPage(vm: vm),
            ),
        ],
        if (manage) ...[
          if (!wholesale)
            link(
              context,
              'Envoyer une annonce',
              AppIcons.campaignOutlined,
              AnnouncementScreen(vm: vm),
              fullScreen: true,
            ),
          const SizedBox(height: 20),
          SectionTitle(
            wholesale ? 'Configuration du dépôt' : 'Configuration du magasin',
          ),
          if (!wholesale)
            link(
              context,
              'Paramètres du magasin',
              AppIcons.storefrontOutlined,
              StoreSettingsPage(vm: vm),
              subtitle: 'Nature, nom, coordonnées et image',
            ),
          link(
            context,
            wholesale ? 'Seuils et points' : 'Prix, points et seuils',
            AppIcons.tuneOutlined,
            ProductSettingsPage(vm: vm),
          ),
          if (!wholesale) ...[
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
          ],
          const SizedBox(height: 20),
          const SectionTitle('Suivi'),
          if (!wholesale)
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
        if (store == null && scope != null && scope!.groups.isNotEmpty) ...[
          const SectionTitle('Configuration des magasins'),
          const Text(
            'Ouvrez un magasin depuis votre groupe pour retrouver ses coordonnées, prix, points, seuils et autres réglages. Le groupe se choisit en haut de l’écran principal.',
          ),
        ],
        if (groupManage && scope != null) ...[
          const SizedBox(height: 20),
          SectionTitle('Paramètres du groupe', subtitle: group.name),
          if (vm.user.admin)
            CompactRow(
              title: 'Accès du groupe · ${statusLabel(group.status)}',
              subtitle:
                  'Suspendre, réactiver ou archiver le groupe et ses magasins',
              icon: AppIcons.lockOutline,
              onTap: () => run(context, () async {
                await manageLifecycle(
                  context,
                  vm,
                  groupId: group.id,
                  name: group.name,
                  version: group.version,
                  status: group.status,
                );
                await scope!.refresh();
              }),
            ),
          CompactRow(
            title: 'Informations du groupe',
            subtitle: 'Nom, téléphone et image',
            icon: AppIcons.settingsOutlined,
            onTap: () => run(context, () => editGroup(context, scope!)),
          ),
          if (!group.wholesale)
            link(
              context,
              'Équipe du groupe et invitations',
              AppIcons.groupsOutlined,
              GroupTeamPage(workspace: vm, group: group),
            ),
        ],
        if (vm.user.admin) ...[
          const SizedBox(height: 20),
          const SectionTitle('Administration BioBalance'),
          if (group != null && scope != null)
            CompactRow(
              title: 'Retour à l’administration',
              subtitle: 'Vue globale de tous les groupes',
              icon: AppIcons.arrowBack,
              onTap: () => run(context, () async {
                await scope!.returnToAdministration();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              }),
            ),
          link(
            context,
            'Invitations et suivi',
            AppIcons.mailOutline,
            InvitationsScreen(workspace: vm),
            fullScreen: true,
            subtitle:
                'Renvoyer, révoquer et suivre les invitations de responsables',
          ),
          link(
            context,
            'Grossistes',
            AppIcons.localShippingOutlined,
            WholesalersScreen(workspace: vm, scope: scope),
            fullScreen: true,
            subtitle: 'Créer un grossiste, son stock initial et son invitation',
          ),
          link(context, 'Catalogue', AppIcons.spaOutlined, CatalogPage(vm: vm)),
          link(
            context,
            'Formation et publications',
            AppIcons.schoolOutlined,
            TrainingPage(vm: vm),
          ),
          CompactRow(
            title: 'Inviter un responsable',
            subtitle: 'Accès pour créer un nouveau groupe',
            icon: AppIcons.personAddAlt,
            onTap: () => inviteManager(context, vm),
          ),
        ],
        const SizedBox(height: 20),
        const SectionTitle('Compte et aide'),
        link(
          context,
          'Aide et premiers pas',
          AppIcons.help,
          const WorkspaceHelp(),
          fullScreen: true,
        ),
        link(
          context,
          'Synchronisation',
          AppIcons.sync,
          SyncScreen(vm: vm),
          fullScreen: true,
        ),
        link(
          context,
          'Mon compte et notifications',
          AppIcons.settingsOutlined,
          AccountScreen(vm: vm),
          fullScreen: true,
        ),
      ],
    );
  }
}
