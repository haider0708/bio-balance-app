import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/dashboard_repository.dart';
import '../../../domain/models/dashboard.dart';
import '../../../domain/models/workspace_scope.dart';
import '../../core/design.dart';
import '../../core/workspace_navigation.dart';
import '../authentication/session_view_model.dart';
import '../catalog/catalog_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../dashboard/attention_screen.dart';
import '../dashboard/dashboard_view_model.dart';
import '../inventory/inventory_screens.dart';
import '../notifications/notifications_screen.dart';
import '../notifications/notifications_view_model.dart';
import '../replenishment/scoped_order_screen.dart';
import '../replenishment/order_screens.dart';
import '../rewards/rewards_screen.dart';
import '../sales/sale_screen.dart';
import '../sales/sales_history_screen.dart';
import '../reporting/scoped_sales_screen.dart';
import '../stores/stores_screen.dart';
import '../synchronization/sync_screen.dart';
import '../training/training_screen.dart';
import 'group_screens.dart';
import '../team/team_screen.dart';
import 'operation_helpers.dart';
import 'scope_header.dart';
import 'scope_view_model.dart';
import 'access_setup_page.dart';
import 'more_page.dart';
import 'workspace_view_model.dart';

class ScopeScreen extends StatefulWidget {
  final ScopeViewModel? model;
  const ScopeScreen({super.key, this.model});
  @override
  State<ScopeScreen> createState() => _ScopeScreenState();
}

class _ScopeScreenState extends State<ScopeScreen> with WidgetsBindingObserver {
  late final workspace = context.read<WorkspaceViewModel>();
  late final scope = widget.model ?? (ScopeViewModel(workspace)..initialize());
  late final inbox = NotificationsViewModel(workspace.inbox)
    ..restore()
    ..setActive(true);
  final dashboards = <String, DashboardViewModel>{};
  final periods = <String, DashboardPeriod>{};
  final buckets = <String, PageStorageBucket>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final vm in dashboards.values) {
      vm.dispose();
    }
    inbox.dispose();
    scope.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    workspace.setForeground(state == AppLifecycleState.resumed);
    inbox.setActive(state == AppLifecycleState.resumed);
    if (state != AppLifecycleState.resumed) {
      unawaited(workspace.flushDrafts().catchError((Object _) {}));
    }
  }

  DashboardViewModel dashboard() {
    final key = scope.scope.key;
    if (!dashboards.containsKey(key) && dashboards.length >= 12) {
      final oldest = dashboards.keys.first;
      final previous = dashboards.remove(oldest)!;
      periods[oldest] = previous.period;
      previous.dispose();
    }
    return dashboards.putIfAbsent(
      key,
      () => DashboardViewModel(
        DashboardRepository(
          workspace.repositoryContext,
          workspace.repository,
          workspace.user.id,
        ),
        scope: scope.scope.kind == ScopeKind.store
            ? (workspace.user.admin || scope.scope.store!.canManage
                  ? 'store'
                  : 'personal')
            : scope.scope.kind.name,
        groupId: scope.scope.group?.id,
        storeId: scope.scope.store?.id,
      )..load(periods[key]),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([scope, workspace]),
    builder: (context, _) {
      final s = scope.scope, store = s.store;
      final needsSetup = !workspace.user.admin && scope.groups.isEmpty;
      final seller = store != null && !workspace.user.admin && !store.canManage;
      final labels = s.kind == ScopeKind.network
          ? ['Accueil', 'Groupes', 'Commandes', 'Catalogue']
          : s.kind == ScopeKind.group
          ? ['Résumé', 'Magasins', 'Équipe', 'Commandes']
          : seller
          ? ['Accueil', 'Ventes', 'Récompenses', 'Formation']
          : ['Accueil', 'Stock', 'Commandes', 'Plus'];
      final icons = s.kind == ScopeKind.network
          ? [
              AppIcons.spaceDashboardOutlined,
              AppIcons.groupsOutlined,
              AppIcons.localShippingOutlined,
              AppIcons.spaOutlined,
            ]
          : s.kind == ScopeKind.group
          ? [
              AppIcons.spaceDashboardOutlined,
              AppIcons.storefrontOutlined,
              AppIcons.groupsOutlined,
              AppIcons.localShippingOutlined,
            ]
          : seller
          ? [
              AppIcons.spaceDashboardOutlined,
              AppIcons.receiptLongOutlined,
              AppIcons.redeemOutlined,
              AppIcons.schoolOutlined,
            ]
          : [
              AppIcons.spaceDashboardOutlined,
              AppIcons.inventory2Outlined,
              AppIcons.localShippingOutlined,
              AppIcons.moreHoriz,
            ];
      Widget page;
      if (scope.loading) {
        page = const Center(child: CircularProgressIndicator());
      } else if (workspace.state.accessBlocked) {
        page = Content(
          children: [
            const EmptyState(
              title: 'Votre accès doit être vérifié',
              description: 'Vos brouillons et opérations restent conservés pour votre compte.',
              icon: AppIcons.lockOutline,
            ),
            FilledButton(
              onPressed: () => context.read<SessionViewModel>().logout(),
              child: const Text('Se reconnecter'),
            ),
          ],
        );
      } else if (needsSetup) {
        page = AccessSetupPage(
          email: workspace.user.email,
          canCreateGroup: scope.grants.isNotEmpty,
          refreshing: scope.refreshing,
          onCreateGroup: () => run(context, () => createGroup(context, scope)),
          onRefresh: () => run(context, scope.refresh),
        );
      } else if (scope.switching) {
        page = const Center(child: CircularProgressIndicator());
      } else if (store != null && workspace.state.data == null) {
        page = Content(
          children: [
            EmptyState(
              title: workspace.state.loading
                  ? 'Préparation du magasin…'
                  : 'Ce magasin n’est pas téléchargé',
              description: 'Connectez-vous pour préparer le stock et le catalogue hors connexion.',
            ),
            if (workspace.state.loading)
              const LinearProgressIndicator()
            else
              FilledButton(
                onPressed: workspace.synchronize,
                child: const Text('Télécharger le magasin'),
              ),
          ],
        );
      } else if (scope.tab == 0) {
        final report = dashboard();
        page = DashboardScreen(
          vm: report,
          workspace: workspace,
          title: s.kind == ScopeKind.network
              ? 'Votre réseau'
              : s.kind == ScopeKind.group
              ? 'Résumé du groupe'
              : seller
              ? 'Bonjour ${workspace.user.name.split(' ').first}'
              : store!.name,
          scopeLabel: s.kind == ScopeKind.network
              ? 'BioBalance · tous les groupes'
              : s.kind == ScopeKind.group
              ? 'Résumé de tous les magasins'
              : '${s.group!.name} · ${store!.name}',
          onOpen: (destination, period) => openDashboard(
            destination,
            period,
            source: report,
            sourceTitle: store?.name ?? s.group?.name ?? 'Tous les groupes',
          ),
          onSale: store == null
              ? null
              : (id) => push(
                  'Vente',
                  ScopedSaleScreen(parent: workspace, store: store, id: id),
                  full: true,
                ),
          onComparison: (id) => run(context, () => openComparison(id)),
          onAlert: (alert) =>
              run(context, () => openExactAlert(context, workspace, alert)),
          primaryAction: store != null && store.canSell
              ? FilledButton.icon(
                  onPressed: () => push(
                    'Nouvelle vente',
                    SaleScreen(workspace: workspace),
                    full: true,
                  ),
                  icon: const Icon(AppIcons.scan),
                  label: const Text('Nouvelle vente'),
                )
              : s.kind == ScopeKind.network
              ? FilledButton.icon(
                  onPressed: () => inviteManager(context, workspace),
                  icon: const Icon(AppIcons.personAddAlt),
                  label: const Text('Inviter un responsable'),
                )
              : null,
          setup: s.kind == ScopeKind.group
              ? GroupOverviewLinks(scope: scope)
              : store != null &&
                    store.canManage &&
                    workspace.state.data?.raw['onboarding']?['complete'] != true
              ? CompactRow(
                  title: 'Terminer la préparation du magasin',
                  subtitle: 'Un guide simple pour votre équipe, le stock et les produits.',
                  icon: AppIcons.checklistOutlined,
                  onTap: () => push(
                    'Guide',
                    OnboardingScreen(vm: workspace),
                    full: true,
                  ),
                )
              : null,
        );
      } else {
        page = switch ((s.kind, seller, scope.tab)) {
          (ScopeKind.network, _, 1) => GroupsPage(vm: scope),
          (ScopeKind.network, _, 2) => ScopedOrdersPage(scope: scope),
          (ScopeKind.network, _, 3) => CatalogPage(vm: workspace),
          (ScopeKind.group, _, 1) => GroupsPage(vm: scope, stores: true),
          (ScopeKind.group, _, 2) => GroupTeamPage(
            key: ValueKey(s.group!.id),
            workspace: workspace,
            group: s.group!,
          ),
          (ScopeKind.group, _, 3) => ScopedOrdersPage(scope: scope),
          (ScopeKind.store, false, 1) => StockPage(vm: workspace),
          (ScopeKind.store, false, 2) => OrdersPage(vm: workspace),
          (ScopeKind.store, false, 3) => MorePage(vm: workspace, scope: scope),
          (ScopeKind.store, true, 1) => SalesPage(vm: workspace),
          (ScopeKind.store, true, 2) => RewardsPage(vm: workspace),
          _ => TrainingPage(vm: workspace),
        };
      }
      final wide = MediaQuery.sizeOf(context).width >= 840;
      return PopScope(
        canPop: !scope.canGoBack,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) run(context, scope.back);
        },
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: MediaQuery.textScalerOf(context).scale(17) > 24
                ? 88
                : 64,
            automaticallyImplyLeading: false,
            leading: scope.canGoBack
                ? IconButton(
                    tooltip: 'Retour',
                    icon: const Icon(AppIcons.arrowBack),
                    onPressed: scope.switching
                        ? null
                        : () => run(context, scope.back),
                  )
                : null,
            titleSpacing: scope.canGoBack ? 0 : 16,
            title: ScopeHeader(vm: scope),
            actions: [
              IconButton(
                onPressed: () => push(
                  'Notifications',
                  NotificationsScreen(vm: workspace, model: inbox),
                  full: true,
                ),
                tooltip: 'Notifications',
                icon: ListenableBuilder(
                  listenable: inbox,
                  builder: (_, _) => Badge(
                    isLabelVisible: inbox.unreadCount > 0,
                    label: Text(
                      inbox.unreadCount > 99 ? '99+' : '${inbox.unreadCount}',
                    ),
                    child: Semantics(
                      label: '${inbox.unreadCount} notification(s) non lue(s)',
                      child: const Icon(AppIcons.notificationsNone),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: menu,
                tooltip: 'Paramètres et gestion',
                icon: const Icon(AppIcons.settingsOutlined),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, bounds) => Column(
                children: [
                  if (scope.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Notice(
                        scope.error!,
                        retry: () => run(context, scope.refresh),
                      ),
                    ),
                  if (workspace.state.pending > 0 ||
                      workspace.state.offline ||
                      workspace.state.syncError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextButton.icon(
                        onPressed: () => push(
                          'Synchronisation',
                          SyncScreen(vm: workspace),
                          full: true,
                        ),
                        icon: Icon(
                          workspace.state.offline
                              ? AppIcons.cloudOff
                              : AppIcons.sync,
                          size: 18,
                        ),
                        label: Text(
                          workspace.state.offline
                              ? (workspace.state.pending == 0
                                    ? 'Hors connexion'
                                    : 'Hors connexion · ${workspace.state.pending} à synchroniser')
                              : workspace.state.syncError != null
                              ? 'Synchronisation à vérifier · ce téléphone'
                              : '${workspace.state.syncSummary.label} · ce téléphone',
                        ),
                      ),
                    ),
                  Expanded(
                    child: Row(
                      children: [
                        if (wide && !needsSetup)
                          NavigationRail(
                            extended: true,
                            selectedIndex: scope.tab,
                            onDestinationSelected: scope.setTab,
                            destinations: [
                              for (var i = 0; i < labels.length; i++)
                                NavigationRailDestination(
                                  icon: Icon(icons[i]),
                                  label: Text(labels[i]),
                                ),
                            ],
                          ),
                        Expanded(
                          child: PageStorage(
                            bucket: buckets.putIfAbsent(
                              s.key,
                              PageStorageBucket.new,
                            ),
                            child: KeyedSubtree(
                              key: ValueKey('${s.key}:${scope.tab}'),
                              child: PageEntrance(
                                key: ValueKey('entrance:${s.key}:${scope.tab}'),
                                child: page,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: wide || needsSetup
              ? null
              : WorkspaceNavigation(
                  labels: labels,
                  icons: icons,
                  selected: scope.tab,
                  onSelected: scope.setTab,
                ),
        ),
      );
    },
  );
  Future<void> push(String title, Widget page, {bool full = false}) =>
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => full
              ? page
              : Scaffold(
                  appBar: AppBar(title: Text(title)),
                  body: page,
                ),
        ),
      );
  Future<void> menu() => push(
    'Paramètres et gestion',
    MorePage(vm: workspace, scope: scope, showTitle: false),
  );
  Future<void> openComparison(String id) async {
    final group = scope.groups.where((g) => g.id == id).firstOrNull;
    if (group != null) {
      await scope.selectGroup(group);
      return;
    }
    final store = workspace.state.stores.where((s) => s.id == id).firstOrNull;
    if (store == null) return;
    if (scope.scope.group?.id != store.organizationId) {
      await scope.selectGroup(
        scope.groups.firstWhere((g) => g.id == store.organizationId),
      );
    }
    await scope.selectStore(store);
  }

  void openDashboard(
    DashboardDestination destination,
    DashboardPeriod period, {
    DashboardViewModel? source,
    String? sourceTitle,
  }) {
    final store = scope.scope.store;
    if (destination == DashboardDestination.sales) {
      final report = source ?? dashboard();
      push(
        'Ventes',
        ScopedSalesScreen(
          workspace: workspace,
          scope: report.scope,
          period: period,
          groupId: report.groupId,
          storeId: report.storeId,
          title:
              sourceTitle ??
              scope.scope.store?.name ??
              scope.scope.group?.name ??
              'Tous les groupes',
        ),
        full: true,
      );
      return;
    }
    if ([
      DashboardDestination.stock,
      DashboardDestination.expired,
      DashboardDestination.deliveries,
      DashboardDestination.rewards,
    ].contains(destination)) {
      final report = dashboard();
      final kind = switch (destination) {
        DashboardDestination.stock => 'low_stock',
        DashboardDestination.expired => 'expired',
        DashboardDestination.deliveries => 'deliveries',
        _ => 'rewards',
      };
      final title = switch (kind) {
        'low_stock' => 'Stocks faibles',
        'expired' => 'Lots expirés',
        'deliveries' => 'Livraisons à réceptionner',
        _ => 'Demandes de récompense',
      };
      push(
        title,
        AttentionScreen(
          workspace: workspace,
          scope: report.scope,
          kind: kind,
          title: title,
          scopeLabel:
              store?.name ?? scope.scope.group?.name ?? 'Tous les groupes',
          groupId: report.groupId,
          storeId: report.storeId,
        ),
        full: true,
      );
      return;
    }
    if (destination == DashboardDestination.stores &&
        scope.scope.kind == ScopeKind.network) {
      push(
        'Magasins du réseau',
        GroupsPage(vm: scope, stores: true, allStores: true),
      );
      return;
    }
    if (destination == DashboardDestination.groups ||
        destination == DashboardDestination.stores) {
      scope.setTab(1);
      return;
    }
    if (destination == DashboardDestination.orders ||
        destination == DashboardDestination.deliveries) {
      scope.setTab(scope.scope.kind == ScopeKind.group ? 3 : 2);
      return;
    }
    if (store == null) {
      scope.setTab(1);
      return;
    }
    switch (destination) {
      case DashboardDestination.stock:
        push('Stock · ${store.name}', StockPage(vm: workspace));
      case DashboardDestination.rewards ||
          DashboardDestination.ranking ||
          DashboardDestination.points:
        push('Récompenses · ${store.name}', RewardsPage(vm: workspace));
      default:
        push('Ventes · ${store.name}', SalesPage(vm: workspace));
    }
  }
}
