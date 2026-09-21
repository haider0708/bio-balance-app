import '../dashboard/admin_dashboard.dart';
import '../../../data/services/notifications/push_notifications.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../announcements/announcement_screen.dart';

import '../stores/store_settings_screen.dart';

import 'package:provider/provider.dart';

import '../../core/design.dart';
import '../training/training_screen.dart';
import 'workspace_view_model.dart';
import 'operations_screens.dart';
import 'team_rewards_orders.dart';

import '../dashboard/home_screen.dart';
import '../stores/stores_screen.dart';
import '../catalog/catalog_screen.dart';
import '../notifications/notifications_screen.dart';
import '../synchronization/sync_screen.dart';
import '../settings/account_screen.dart';
import '../reporting/history_screen.dart';
import '../authentication/session_view_model.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen>
    with WidgetsBindingObserver {
  int selected = 0;
  StreamSubscription<PushSignal>? pushEvents;
  PushSignal? pendingPush;
  bool openingPush = false;
  PushNotifications? push;
  Future<void> receivePush(PushSignal signal) async {
    if (!mounted) return;
    if (signal.tapped) {
      pendingPush = signal;
      setState(() {});
      return;
    }
    try {
      final vm = context.read<WorkspaceViewModel>();
      final message = await vm.inbox.get(signal.notificationId);
      if (!mounted || message['readAt'] != null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message['title']),
          action: SnackBarAction(
            label: 'Voir',
            onPressed: () {
              pendingPush = signal;
              setState(() {});
            },
          ),
        ),
      );
    } catch (_) {
      /* Never reveal data before current server authorization. */
    }
  }

  Future<void> openPush() async {
    if (openingPush || pendingPush == null || !mounted) return;
    final vm = context.read<WorkspaceViewModel>();
    if (vm.state.loading) return;
    openingPush = true;
    final signal = pendingPush!;
    pendingPush = null;
    push?.pendingTap = null;
    try {
      final message = await vm.openNotification(signal.notificationId);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(message['title']),
          content: SingleChildScrollView(
            child: Text(
              '${vm.state.store?.name ?? 'BioBalance'}\n\n${message['body']}',
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
      if (mounted) setState(() => selected = 0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(SessionViewModel.message(e))));
      }
    } finally {
      openingPush = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    push = context.read<SessionViewModel?>()?.notifications;
    pendingPush = push?.pendingTap;
    pushEvents = push?.events.listen(
      (signal) => unawaited(receivePush(signal)),
    );
  }

  @override
  void dispose() {
    pushEvents?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<WorkspaceViewModel>().synchronize(silent: true);
      unawaited(push?.resume());
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WorkspaceViewModel>();
    final state = vm.state;
    if (pendingPush != null && !state.loading && !openingPush) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(openPush());
      });
    }
    final admin = vm.user.admin, manager = state.store?.canManage ?? false;
    final destinations = admin
        ? ['Vue d’ensemble', 'Magasins', 'Commandes', 'Catalogue', 'Plus']
        : manager
        ? ['Accueil', 'Stock', 'Commandes', 'Équipe', 'Plus']
        : ['Accueil', 'Mes ventes', 'Récompenses', 'Formation'];
    final icons = admin
        ? [
            Icons.space_dashboard_outlined,
            Icons.storefront_outlined,
            Icons.local_shipping_outlined,
            Icons.spa_outlined,
            Icons.more_horiz,
          ]
        : manager
        ? [
            Icons.space_dashboard_outlined,
            Icons.inventory_2_outlined,
            Icons.local_shipping_outlined,
            Icons.groups_outlined,
            Icons.more_horiz,
          ]
        : [
            Icons.space_dashboard_outlined,
            Icons.receipt_long_outlined,
            Icons.redeem_outlined,
            Icons.school_outlined,
          ];
    if (selected >= destinations.length) selected = 0;
    Widget page;
    if (state.loading && state.data == null) {
      page = const Center(child: CircularProgressIndicator());
    } else if (state.accessBlocked) {
      page = Content(
        children: [
          const EmptyState(
            title: 'Votre accès doit être vérifié',
            description: 'Reconnectez-vous ou contactez votre responsable. Les opérations en attente restent conservées pour votre compte.',
            icon: Icons.lock_outline,
          ),
          FilledButton(
            onPressed: () => context.read<SessionViewModel>().logout(),
            child: const Text('Se reconnecter'),
          ),
          OutlinedButton(
            onPressed: vm.initialize,
            child: const Text('Vérifier mes accès'),
          ),
        ],
      );
    } else if (state.store == null) {
      page = Content(
        children: [
          const SectionTitle('Bienvenue sur votre espace BioBalance'),
          const EmptyState(
            title: 'Créons votre premier magasin',
            description: 'Ajoutez votre magasin, invitez l’équipe et renseignez le stock initial.',
            icon: Icons.storefront_outlined,
          ),
          FilledButton(
            onPressed: () => createStore(context, vm),
            child: const Text('Créer un magasin'),
          ),
          if (admin)
            OutlinedButton(
              onPressed: () => inviteManager(context, vm),
              child: const Text('Accorder un accès responsable'),
            ),
        ],
      );
    } else if (state.data == null) {
      page = Content(
        children: [
          EmptyState(
            title: 'Ce magasin n’est pas encore téléchargé',
            description:
                'Connectez-vous pour préparer son utilisation hors ligne.',
            action: FilledButton(
              onPressed: vm.synchronize,
              child: const Text('Télécharger les données'),
            ),
          ),
        ],
      );
    } else {
      page = switch ((admin, manager, selected)) {
        (true, _, 0) => AdminDashboard(vm: vm),
        (true, _, 1) => StoresPage(vm: vm),
        (true, _, 2) => OrdersPage(vm: vm),
        (true, _, 3) => CatalogPage(vm: vm),
        (true, _, 4) => MorePage(vm: vm),
        (false, true, 1) => StockPage(vm: vm),
        (false, true, 2) => OrdersPage(vm: vm),
        (false, true, 3) => TeamPage(vm: vm),
        (false, true, 4) => MorePage(vm: vm),
        (false, false, 1) => SalesPage(vm: vm),
        (false, false, 2) => RewardsPage(vm: vm),
        (false, false, 3) => TrainingPage(vm: vm),
        _ => HomePage(vm: vm),
      };
    }
    final wide = MediaQuery.sizeOf(context).width >= 840;
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          key: const ValueKey('workspace.storeSelector'),
          onTap: () => switchStore(context, vm),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  admin ? 'BIOBALANCE · ADMIN' : 'BIOBALANCE',
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                    color: darkGreen,
                  ),
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        state.store?.name ?? 'Votre espace',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => NotificationsScreen(vm: vm)),
            ),
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none),
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AccountScreen(vm: vm)),
            ),
            tooltip: 'Compte et aide',
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Notice(
                  state.error!,
                  error: !state.offline,
                  retry: vm.synchronize,
                ),
              ),
            Material(
              color: state.offline
                  ? const Color(0xFFFFF3DE)
                  : const Color(0xFFF0F5ED),
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SyncScreen(vm: vm)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        state.offline
                            ? Icons.cloud_off
                            : state.syncing
                            ? Icons.sync
                            : Icons.cloud_done_outlined,
                        size: 18,
                        color: darkGreen,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.accessBlocked
                              ? 'Accès à vérifier · données locales conservées'
                              : state.syncing
                              ? 'Synchronisation en cours…'
                              : state.offline
                              ? 'Hors connexion · travail enregistré sur ce téléphone'
                              : state.pending > 0
                              ? '${state.pending} opération(s) à synchroniser'
                              : 'Vos données sont synchronisées',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  if (wide)
                    NavigationRail(
                      extended: true,
                      selectedIndex: selected,
                      onDestinationSelected: (i) =>
                          setState(() => selected = i),
                      destinations: [
                        for (var i = 0; i < destinations.length; i++)
                          NavigationRailDestination(
                            icon: Icon(icons[i]),
                            label: Text(destinations[i]),
                          ),
                      ],
                    ),
                  Expanded(child: page),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              height: MediaQuery.textScalerOf(context).scale(14) > 20
                  ? 100
                  : 80,
              selectedIndex: selected,
              onDestinationSelected: (i) => setState(() => selected = i),
              destinations: [
                for (var i = 0; i < destinations.length; i++)
                  NavigationDestination(
                    icon: Icon(icons[i]),
                    label: destinations[i],
                  ),
              ],
            ),
    );
  }
}

class MorePage extends StatelessWidget {
  final WorkspaceViewModel vm;
  const MorePage({super.key, required this.vm});
  @override
  Widget build(BuildContext context) => Content(
    children: [
      const SectionTitle('Tout votre espace'),
      if (vm.state.store?.canManage == true)
        Card(
          child: ListTile(
            leading: const Icon(Icons.checklist_outlined),
            title: const Text('Guide de configuration'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => OnboardingScreen(vm: vm)),
            ),
          ),
        ),
      for (final item in [
        (
          'Ventes & corrections',
          Icons.receipt_long_outlined,
          SalesPage(vm: vm),
        ),
        (
          'Récompenses & classement',
          Icons.redeem_outlined,
          RewardsPage(vm: vm),
        ),
        ('Formation', Icons.school_outlined, TrainingPage(vm: vm)),
        ('Magasins', Icons.storefront_outlined, StoresPage(vm: vm)),
        if (vm.state.store?.canManage == true)
          (
            'Paramètres du magasin',
            Icons.settings_outlined,
            StoreSettingsPage(vm: vm),
          ),
        (
          'Historique et exports',
          Icons.assessment_outlined,
          HistoryScreen(
            vm: vm,
            resource: 'sales',
            title: 'Historique des ventes',
          ),
        ),
        (
          'Journal d’audit',
          Icons.manage_search,
          HistoryScreen(vm: vm, resource: 'audit', title: 'Journal d’audit'),
        ),
      ])
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Icon(item.$2, color: darkGreen),
            title: Text(item.$1),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text(item.$1)),
                  body: item.$3,
                ),
              ),
            ),
          ),
        ),
      const SizedBox(height: 16),
      if (vm.state.store?.canManage == true || vm.user.admin)
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const Icon(Icons.campaign_outlined, color: darkGreen),
            title: const Text('Envoyer une annonce'),
            subtitle: const Text(
              'Choisissez le message à transmettre à votre équipe.',
            ),
            onTap: () => announce(context),
          ),
        ),
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Compte, aide et synchronisation'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AccountScreen(vm: vm)),
          ),
        ),
      ),
    ],
  );
  Future<void> announce(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AnnouncementScreen(vm: vm)),
    );
  }
}
