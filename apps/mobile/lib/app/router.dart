import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/auth/me.dart';
import '../core/auth/session.dart';
import '../core/widgets/components.dart';
import '../core/widgets/states.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/auth/activate_screen.dart';
import '../features/dashboard/region_screen.dart';
import '../features/auth/forgot_screen.dart';
import '../features/auth/admin_login_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/catalog/catalog_screens.dart';
import '../features/catalog/product.dart';
import '../features/dashboard/management_home.dart';
import '../features/dashboard/vendeur_home.dart';
import '../features/media/photo_viewer.dart';
import '../features/messages/messages_screens.dart';
import '../features/network/network_models.dart';
import '../features/network/depots_screen.dart';
import '../features/network/network_screen.dart';
import '../features/network/pdv_screens.dart';
import '../features/network/people_widgets.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/restock/restock_models.dart';
import '../features/restock/restock_screens.dart';
import '../features/reports/reports_screens.dart';
import '../features/rewards/rewards_screens.dart';
import '../features/sales/celebration_screen.dart';
import '../features/sales/new_sale_screen.dart';
import '../features/sales/sale_detail_screen.dart';
import '../features/sales/sales_history_screen.dart';
import '../features/sales/sales_models.dart';
import '../features/sales/sales_repository.dart';
import '../features/sales/scanner_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/stock/stock_screens.dart';
import '../features/training/training_admin_screens.dart';
import '../features/training/training_models.dart';
import '../features/training/training_screens.dart';
import '../features/wallet/payouts_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../l10n/app_localizations.dart';
import 'admin_shell.dart';
import 'nav_shell.dart';

const _publicPaths = {'/login', '/activate', '/forgot', '/code'};

/// The page the browser was opened on (a bookmark, a reload): after the saved session is checked the
/// app goes there, once, instead of always landing on the home tab.
String? _landing;

/// Called once at start, before the first screen replaces the browser's address.
void rememberLanding() {
  if (kIsWeb) _landing = PlatformDispatcher.instance.defaultRouteName;
}

/// The app's routes. They depend on who is signed in, so a new router is built at sign-in and sign-out.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);
  final role = ref.watch(sessionProvider.select((s) => s.value?.me.role));

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final path = state.uri.path;
      if (session.isLoading) return path == '/splash' ? null : '/splash';
      final signedIn = session.value != null;
      // A code opened from the email: straight to the screen that uses it.
      if (path == '/code') {
        final code = state.uri.queryParameters['c'] ?? '';
        if (signedIn) return '/home';
        return state.uri.queryParameters['k'] == 'r'
            ? '/forgot?code=$code'
            : '/activate?code=$code';
      }
      if (!signedIn) return _publicPaths.contains(path) ? null : '/login';
      if ((path == '/splash' || _publicPaths.contains(path)) &&
          _landing != null &&
          role != null) {
        final target = _landing!;
        _landing = null;
        final uri = Uri.tryParse(target);
        if (uri != null &&
            uri.path != '/' &&
            uri.path != '/splash' &&
            !_publicPaths.contains(uri.path)) {
          return target;
        }
      }
      if (_publicPaths.contains(path) || path == '/splash') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => const Scaffold(body: LoadingState()),
      ),
      GoRoute(
        path: '/login',
        builder: (_, state) {
          final email = state.uri.queryParameters['email'];
          // Web is the admin console: a dedicated sign-in, not the phone auth screen.
          return kIsWeb
              ? AdminLoginScreen(email: email)
              : LoginScreen(email: email);
        },
      ),
      GoRoute(
        path: '/activate',
        builder: (_, state) =>
            ActivateScreen(code: state.uri.queryParameters['code']),
      ),
      GoRoute(
        path: '/forgot',
        builder: (_, state) =>
            ForgotScreen(code: state.uri.queryParameters['code']),
      ),
      GoRoute(path: '/code', builder: (_, _) => const SizedBox.shrink()),
      if (role != null) ..._roleRoutes(role),
    ],
    errorBuilder: (_, _) => const _NotFound(),
  );
  ref.onDispose(router.dispose);
  return router;
});

/// One bottom-bar tab: its icon, its label (translated when the bar is built), its path and its screen.
class TabSpec {
  const TabSpec(this.icon, this.label, this.path, this.page);

  final IconData icon;
  final String Function(AppLocalizations t) label;
  final String path;
  final Widget Function() page;
}

StatefulShellRoute _shell(List<TabSpec> tabs) =>
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) {
        final t = AppLocalizations.of(context);
        return NavShell(
          shell: shell,
          destinations: [
            for (final tab in tabs)
              NavDestination(icon: tab.icon, label: tab.label(t)),
          ],
        );
      },
      branches: [
        for (final tab in tabs)
          StatefulShellBranch(
            routes: [GoRoute(path: tab.path, builder: (_, _) => tab.page())],
          ),
      ],
    );

List<RouteBase> _roleRoutes(Role role) => switch (role) {
  Role.vendeur => [..._vendeur(), ..._shared()],
  Role.responsable => [..._responsable(), ..._shared()],
  // On the phone the admin has bottom tabs; in a browser, a sidebar around every page.
  Role.admin =>
    kIsWeb
        ? [
            ShellRoute(
              builder: (_, _, child) => AdminShell(child: child),
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (_, _) => const ManagementHome(),
                ),
                GoRoute(
                  path: '/approvals',
                  builder: (_, _) => const ApprovalsScreen(),
                ),
                GoRoute(
                  path: '/network',
                  builder: (_, _) => const NetworkScreen(),
                ),
                GoRoute(
                  path: '/restocks',
                  builder: (_, _) => const RestocksScreen(),
                ),
                ..._admin(),
                ..._shared(),
              ],
            ),
          ]
        : [..._adminTabs(), ..._admin(), ..._shared()],
};

/// A page built from an object handed over by the previous screen. Opened without it
/// (a reload, a bookmark, the browser's back button) it goes to [fallback] instead of failing.
GoRoute _withExtra<T>(
  String path,
  String fallback,
  Widget Function(GoRouterState state, T extra) builder,
) => GoRoute(
  path: path,
  redirect: (_, state) => state.extra is T ? null : fallback,
  builder: (_, state) => builder(state, state.extra as T),
);

List<RouteBase> _vendeur() => [
  _shell([
    TabSpec(
      LucideIcons.house,
      (t) => t.tabHome,
      '/home',
      () => const VendeurHome(),
    ),
    TabSpec(
      LucideIcons.receipt,
      (t) => t.tabSales,
      '/sales',
      () => const SalesHistoryScreen(embedded: true),
    ),
    TabSpec(
      LucideIcons.wallet,
      (t) => t.tabWallet,
      '/wallet',
      () => const WalletScreen(),
    ),
    TabSpec(
      LucideIcons.graduationCap,
      (t) => t.tabLearn,
      '/learn',
      () => const CoursesScreen(),
    ),
  ]),
  GoRoute(path: '/sell', builder: (_, _) => const NewSaleScreen()),
  GoRoute(path: '/scan', builder: (_, _) => const ScannerScreen()),
  _withExtra<SaleOutcome>(
    '/sale-done',
    '/home',
    (_, outcome) => CelebrationScreen(outcome: outcome),
  ),
  GoRoute(
    path: '/sales/:id',
    builder: (_, state) =>
        SaleDetailScreen(saleId: state.pathParameters['id']!),
  ),
  _withExtra<Sale>(
    '/sales/:id/correct',
    '/sales',
    (_, sale) => CorrectSaleScreen(sale: sale),
  ),
];

List<RouteBase> _responsable() => [
  _shell([
    TabSpec(
      LucideIcons.house,
      (t) => t.tabHome,
      '/home',
      () => const ManagementHome(),
    ),
    TabSpec(
      LucideIcons.store,
      (t) => t.tabPdvs,
      '/pdvs',
      () => const NetworkScreen(),
    ),
    TabSpec(
      LucideIcons.truck,
      (t) => t.tabRestocks,
      '/restocks',
      () => const RestocksScreen(),
    ),
    TabSpec(
      LucideIcons.chartNoAxesColumn,
      (t) => t.tabReports,
      '/reports',
      () => const ReportsScreen(),
    ),
    TabSpec(
      LucideIcons.menu,
      (t) => t.moreTitle,
      '/more',
      () => _more(Role.responsable),
    ),
  ]),
];

/// The admin's bottom tabs on the phone.
List<RouteBase> _adminTabs() => [
  _shell([
    TabSpec(
      LucideIcons.house,
      (t) => t.tabHome,
      '/home',
      () => const ManagementHome(),
    ),
    TabSpec(
      LucideIcons.inbox,
      (t) => t.tabApprovals,
      '/approvals',
      () => const ApprovalsScreen(),
    ),
    TabSpec(
      LucideIcons.network,
      (t) => t.tabNetwork,
      '/network',
      () => const NetworkScreen(),
    ),
    TabSpec(
      LucideIcons.truck,
      (t) => t.tabRestocks,
      '/restocks',
      () => const RestocksScreen(),
    ),
    TabSpec(
      LucideIcons.menu,
      (t) => t.moreTitle,
      '/more',
      () => _more(Role.admin),
    ),
  ]),
];

/// Screens only the admin opens, the same on the phone and on the web.
List<RouteBase> _admin() => [
  GoRoute(path: '/payouts', builder: (_, _) => const PayoutsScreen()),
  GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
  GoRoute(path: '/depots/new', builder: (_, _) => const DepotFormScreen()),
  _withExtra<String>(
    '/depots/:id/restock',
    '/depots',
    (state, name) => RecordDeliveryScreen(
      depotId: state.pathParameters['id']!,
      depotName: name,
    ),
  ),
  _withExtra<Depot>(
    '/depots/:id/edit',
    '/depots',
    (_, depot) => DepotFormScreen(existing: depot),
  ),
  GoRoute(
    path: '/stock/:id/adjust',
    builder: (_, state) => AdjustStockScreen(
      locationId: state.pathParameters['id']!,
      locationName: state.extra as String?,
    ),
  ),
  GoRoute(
    path: '/regions/:id',
    builder: (_, state) => RegionScreen(
      regionId: state.pathParameters['id']!,
      name: state.extra as String?,
    ),
  ),
  GoRoute(path: '/rewards', builder: (_, _) => const RewardsScreen()),
  GoRoute(
    path: '/rewards/new',
    builder: (_, state) =>
        RewardFormScreen(preset: state.extra as RewardPreset?),
  ),
  GoRoute(path: '/messages', builder: (_, _) => const MessagesScreen()),
  GoRoute(
    path: '/messages/new',
    builder: (_, _) => const ComposeMessageScreen(),
  ),
  GoRoute(
    path: '/messages/:id',
    builder: (_, state) =>
        MessageDetailScreen(messageId: state.pathParameters['id']!),
  ),
  GoRoute(path: '/people/new', builder: (_, _) => const CreateAccountScreen()),
  _withExtra<Person>(
    '/people/:id',
    '/network',
    (_, person) => PersonDetailScreen(person: person),
  ),
  GoRoute(
    path: '/training/manage',
    builder: (_, _) => const ManageCoursesScreen(),
  ),
  GoRoute(
    path: '/training/manage/:id',
    builder: (_, state) =>
        CourseEditorScreen(courseId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: '/training/manage/:id/progress',
    builder: (_, state) =>
        CourseProgressScreen(courseId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: '/training/manage/:id/lessons/new',
    builder: (_, state) =>
        LessonEditorScreen(courseId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: '/training/manage/:id/lessons/:lesson',
    builder: (_, state) => LessonEditorScreen(
      courseId: state.pathParameters['id']!,
      lesson: state.extra as Lesson?,
    ),
  ),
  GoRoute(path: '/catalog/new', builder: (_, _) => const ProductFormScreen()),
  GoRoute(
    path: '/catalog/:id/edit',
    builder: (_, state) => ProductFormScreen(existing: state.extra as Product?),
  ),
];

/// Screens that several roles can open.
List<RouteBase> _shared() => [
  GoRoute(
    path: '/notifications',
    builder: (_, _) => const NotificationsScreen(),
  ),
  GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  _withExtra<(List<String>, int)>('/photos', '/home', (_, extra) {
    final (ids, index) = extra;
    return PhotoGalleryScreen(ids: ids, initial: index);
  }),
  GoRoute(
    path: '/photo/:id',
    builder: (_, state) =>
        PhotoViewerScreen(mediaId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: '/stock-attention',
    builder: (_, _) => const StockAttentionScreen(),
  ),
  GoRoute(path: '/depots', builder: (_, _) => const DepotsScreen()),
  GoRoute(
    path: '/depots/:id',
    builder: (_, state) => DepotScreen(depotId: state.pathParameters['id']!),
  ),
  GoRoute(path: '/training', builder: (_, _) => const CoursesScreen()),
  GoRoute(
    path: '/training/:id',
    builder: (_, state) => CourseScreen(courseId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: '/training/:id/lessons/:lesson',
    builder: (_, state) => LessonScreen(
      courseId: state.pathParameters['id']!,
      lessonId: state.pathParameters['lesson']!,
    ),
  ),
  GoRoute(path: '/catalog', builder: (_, _) => const _CatalogEntry()),
  _withExtra<Product>(
    '/catalog/:id',
    '/catalog',
    (_, product) => _ProductEntry(product: product),
  ),
  _withExtra<Group>(
    '/groups/:id',
    '/network',
    (_, group) => GroupScreen(group: group),
  ),
  GoRoute(path: '/pdvs/new', builder: (_, _) => const PdvFormScreen()),
  GoRoute(
    path: '/pdvs/:id',
    builder: (_, state) => PdvDetailScreen(pdvId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: '/pdvs/:id/edit',
    builder: (_, state) => PdvFormScreen(existing: state.extra as Pdv?),
  ),
  GoRoute(
    path: '/pdvs/:id/sales',
    builder: (_, state) =>
        SalesHistoryScreen(pdvId: state.pathParameters['id']),
  ),
  GoRoute(
    path: '/pdvs/:id/members/new',
    builder: (_, state) => AddMemberScreen(pdvId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: '/stock/declarations/:id',
    builder: (_, state) =>
        DeclarationScreen(declarationId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: '/stock/:id',
    builder: (_, state) => StockScreen(
      locationId: state.pathParameters['id']!,
      title: state.extra as String?,
    ),
  ),
  GoRoute(
    path: '/stock/:id/declare',
    builder: (_, state) => DeclareStockScreen(
      locationId: state.pathParameters['id']!,
      locationName: state.extra as String?,
    ),
  ),
  GoRoute(
    path: '/restocks/new',
    builder: (_, state) => RequestRestockScreen(destId: state.extra as String?),
  ),
  GoRoute(
    path: '/restocks/:id',
    builder: (_, state) =>
        RestockDetailScreen(orderId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: '/restocks/:id/ship',
    redirect: (_, state) => state.extra is RestockOrder
        ? null
        : '/restocks/${state.pathParameters['id']}',
    builder: (_, state) => ShipScreen(order: state.extra! as RestockOrder),
  ),
  GoRoute(
    path: '/restocks/:id/receive',
    redirect: (_, state) => state.extra is RestockOrder
        ? null
        : '/restocks/${state.pathParameters['id']}',
    builder: (_, state) => ReceiveScreen(order: state.extra! as RestockOrder),
  ),
];

Widget _more(Role role) => Builder(
  builder: (context) {
    final t = AppLocalizations.of(context);
    final entries = switch (role) {
      Role.admin => [
        MoreEntry(
          LucideIcons.banknote,
          t.rewardsTitle,
          '/rewards',
          tone: Tone.success,
        ),
        MoreEntry(LucideIcons.warehouse, t.grossistesTitle, '/depots'),
        MoreEntry(
          LucideIcons.wallet,
          t.payoutsTitle,
          '/payouts',
          tone: Tone.warning,
        ),
        MoreEntry(
          LucideIcons.megaphone,
          t.announcementsTitle,
          '/messages',
          tone: Tone.info,
        ),
        MoreEntry(
          LucideIcons.graduationCap,
          t.trainingTitle,
          '/training/manage',
        ),
        MoreEntry(LucideIcons.package, t.catalogTitle, '/catalog'),
        MoreEntry(
          LucideIcons.chartNoAxesColumn,
          t.reportsTitle,
          '/reports',
          tone: Tone.info,
        ),
        MoreEntry(
          LucideIcons.bell,
          t.notificationsTitle,
          '/notifications',
          tone: Tone.warning,
        ),
        MoreEntry(
          LucideIcons.settings,
          t.settingsTitle,
          '/settings',
          tone: Tone.muted,
        ),
      ],
      Role.responsable => [
        MoreEntry(LucideIcons.warehouse, t.grossistesTitle, '/depots'),
        MoreEntry(LucideIcons.package, t.catalogTitle, '/catalog'),
        MoreEntry(LucideIcons.graduationCap, t.trainingTitle, '/training'),
        MoreEntry(
          LucideIcons.bell,
          t.notificationsTitle,
          '/notifications',
          tone: Tone.warning,
        ),
        MoreEntry(
          LucideIcons.settings,
          t.settingsTitle,
          '/settings',
          tone: Tone.muted,
        ),
      ],
      _ => [
        MoreEntry(LucideIcons.package, t.catalogTitle, '/catalog'),
        MoreEntry(LucideIcons.graduationCap, t.trainingTitle, '/training'),
        MoreEntry(
          LucideIcons.bell,
          t.notificationsTitle,
          '/notifications',
          tone: Tone.warning,
        ),
        MoreEntry(
          LucideIcons.settings,
          t.settingsTitle,
          '/settings',
          tone: Tone.muted,
        ),
      ],
    };
    return MoreScreen(entries: entries);
  },
);

class _CatalogEntry extends ConsumerWidget {
  const _CatalogEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      CatalogScreen(editable: ref.watch(meProvider).role == Role.admin);
}

class _ProductEntry extends ConsumerWidget {
  const _ProductEntry({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ProductScreen(
    product: product,
    editable: ref.watch(meProvider).role == Role.admin,
  );
}

/// An address the app does not know (an old link, a page of another role).
class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: EmptyState(
        icon: LucideIcons.mapPinOff,
        title: t.pageNotFound,
        message: t.pageNotFoundHint,
        action: FilledButton(
          onPressed: () => context.go('/home'),
          child: Text(t.backToHome),
        ),
      ),
    );
  }
}
