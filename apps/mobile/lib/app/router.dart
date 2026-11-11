import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/auth/me.dart';
import '../core/auth/session.dart';
import '../core/widgets/components.dart';
import '../core/widgets/states.dart';
import '../features/analytics/explorer_screen.dart';
import '../features/analytics/ledger_screen.dart';
import '../features/analytics/lens.dart';
import '../features/analytics/stores_board_screen.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/auth/activate_screen.dart';
import '../features/dashboard/region_screen.dart';
import '../features/auth/forgot_screen.dart';
import '../features/auth/set_password_screen.dart';
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
import '../features/network/regions_screen.dart';
import '../features/orders/buyer_home.dart';
import '../features/orders/order_papers_screen.dart';
import '../features/orders/orders_screens.dart';
import '../features/network/people_widgets.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/restock/restock_models.dart';
import '../features/restock/restock_screens.dart';
import '../features/reports/stock_attention_screen.dart';
import '../features/rewards/rewards_screens.dart';
import '../features/sales/celebration_screen.dart';
import '../features/sales/new_sale_screen.dart';
import '../features/sales/sale_detail_screen.dart';
import '../features/sales/sales_history_screen.dart';
import '../features/sales/sales_models.dart';
import '../features/sales/sales_repository.dart';
import '../features/sales/scanner_screen.dart';
import '../features/settings/app_errors_screen.dart';
import '../features/settings/app_settings_screen.dart';
import '../features/planning/planning_models.dart';
import '../features/planning/planning_overview_screen.dart';
import '../features/planning/planning_repository.dart';
import '../features/planning/planning_screen.dart';
import '../features/planning/planning_settings_screen.dart';
import '../features/planning/visit_detail_screen.dart';
import '../features/planning/visit_form_screen.dart';
import '../features/returns/new_return_screen.dart';
import '../features/returns/return_detail_screen.dart';
import '../features/returns/returns_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/transfers/new_transfer_screen.dart';
import '../features/transfers/transfer_detail_screen.dart';
import '../features/transfers/transfers_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/stock/edit_declaration_screen.dart';
import '../features/stock/stock_models.dart';
import '../features/stock/stock_screens.dart';
import '../features/training/training_admin_screens.dart';
import '../features/training/training_models.dart';
import '../features/training/training_screens.dart';
import '../features/wallet/payouts_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../l10n/app_localizations.dart';
import 'console_shell.dart';
import 'nav_shell.dart';

const _publicPaths = {'/login', '/activate', '/forgot', '/code'};

/// The page the app was opened on (a bookmark or a reload in the browser, a code link from an
/// email on the phone): once the saved session is checked and the opening has played, the app
/// goes there, once, instead of always landing on the home tab.
String? _landing;

/// Called once at start, before the first screen replaces the address.
void rememberLanding() {
  final route = PlatformDispatcher.instance.defaultRouteName;
  if (route != '/' && route.isNotEmpty) _landing = route;
}

/// The app's routes. They depend on who is signed in, so a new router is built at sign-in and sign-out.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  // The pages are checked again when signing in or out, or when a password must be chosen: not each time the
  // app asks the server who is signed in (it does, whenever it comes back to the foreground, e.g. from the
  // camera), which would throw away the page the person is on and the order it was handed.
  ref.listen(
    sessionProvider.select(
      (s) => (s.isLoading, s.value != null, s.value?.me.mustChangePassword),
    ),
    (_, _) => refresh.value++,
  );
  ref.listen(splashDoneProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);
  final role = ref.watch(sessionProvider.select((s) => s.value?.me.role));
  // A seller who is allowed to order gets another tab: the routes change with it.
  final buys =
      ref.watch(sessionProvider.select((s) => s.value?.me.canOrder)) ?? false;

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final path = state.uri.path;
      // The opening plays to its end, even when the session is known sooner.
      if (session.isLoading || !ref.read(splashDoneProvider)) {
        return path == '/splash' ? null : '/splash';
      }
      final signedIn = session.value != null;
      // A code link that opened the app while it was closed.
      if (path == '/splash' && _landing != null && !signedIn) {
        final uri = Uri.tryParse(_landing!);
        if (uri != null && _publicPaths.contains(uri.path)) {
          _landing = null;
          return uri.toString();
        }
      }
      // A code opened from the email: straight to the screen that uses it.
      if (path == '/code') {
        final code = state.uri.queryParameters['c'] ?? '';
        if (signedIn) return '/home';
        return state.uri.queryParameters['k'] == 'r'
            ? '/forgot?code=$code'
            : '/activate?code=$code';
      }
      if (!signedIn) return _publicPaths.contains(path) ? null : '/login';
      // Signed in with the generated password: nothing but choosing their own is open to them.
      final mustChange = session.value?.me.mustChangePassword ?? false;
      if (mustChange) return path == '/set-password' ? null : '/set-password';
      if (path == '/set-password') return '/home';
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
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
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
      GoRoute(
        path: '/set-password',
        builder: (_, _) => const SetPasswordScreen(),
      ),
      if (role != null) ..._roleRoutes(role, buys: buys),
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

List<RouteBase> _roleRoutes(Role role, {required bool buys}) => switch (role) {
  Role.vendeur => [..._vendeur(buys: buys), ..._shared()],
  Role.acheteur => [..._buyerTabs(), ..._shared()],
  // The order manager: the paras' stock and the orders, on the phone and in the browser.
  Role.orders =>
    kIsWeb
        ? [
            ShellRoute(
              builder: (_, _, child) => ConsoleShell(child: child),
              routes: [
                GoRoute(path: '/home', builder: (_, _) => const OrdersHome()),
                GoRoute(path: '/paras', builder: (_, _) => const ParasScreen()),
                GoRoute(
                  path: '/restocks',
                  builder: (_, _) => const RestocksScreen(),
                ),
                ..._shared(),
              ],
            ),
          ]
        : [..._ordersTabs(), ..._shared()],
  Role.responsable =>
    kIsWeb
        ? [
            ShellRoute(
              builder: (_, _, child) => ConsoleShell(child: child),
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (_, _) => const ManagementHome(),
                ),
                GoRoute(
                  path: '/pdvs',
                  builder: (_, _) => const NetworkScreen(),
                ),
                GoRoute(
                  path: '/restocks',
                  builder: (_, _) => const RestocksScreen(),
                ),
                GoRoute(
                  path: '/reports',
                  builder: (_, _) => ExplorerScreen.root(),
                ),
                ..._analytics(),
                ..._planning(Role.responsable),
                ..._shared(),
              ],
            ),
          ]
        : [
            ..._responsable(),
            ..._analytics(),
            ..._planning(Role.responsable),
            ..._shared(),
          ],
  // On the phone the admin and the responsable have bottom tabs; in a browser, a sidebar around every page.
  Role.admin =>
    kIsWeb
        ? [
            ShellRoute(
              builder: (_, _, child) => ConsoleShell(child: child),
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
                ..._analytics(),
                ..._planning(Role.admin),
                ..._shared(),
              ],
            ),
          ]
        : [
            ..._adminTabs(),
            ..._admin(),
            ..._analytics(),
            ..._planning(Role.admin),
            ..._shared(),
          ],
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
  builder: (_, state) =>
      pageNeeding<T>(state, fallback, (extra) => builder(state, extra)),
);

/// The page for the object the previous screen handed over. The router can rebuild a page that is
/// already on screen without it (after the system restores the app, or when the router refreshes); that
/// goes back to [fallback] instead of failing with a cast error (seen in build 47: SaleOutcome, Product).
@visibleForTesting
Widget pageNeeding<T>(
  GoRouterState state,
  String fallback,
  Widget Function(T extra) build,
) {
  final extra = state.extra;
  return extra is T ? build(extra) : _GoTo(fallback);
}

/// The optional object handed over, or null when there is none or it is not the expected kind.
T? _extra<T>(GoRouterState state) {
  final extra = state.extra;
  return extra is T ? extra : null;
}

/// An empty page that moves on to [location] as soon as it is shown.
class _GoTo extends StatefulWidget {
  const _GoTo(this.location);

  final String location;

  @override
  State<_GoTo> createState() => _GoToState();
}

class _GoToState extends State<_GoTo> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(widget.location);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}

List<RouteBase> _vendeur({required bool buys}) => [
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
    // A seller the responsable allowed to order has the para's orders in a tab of its own.
    if (buys)
      TabSpec(
        LucideIcons.truck,
        (t) => t.tabRestocks,
        '/restocks',
        () => const RestocksScreen(),
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
];

/// The responsable's calendar and visits; the admin only reads them (an overview and each visit).
List<RouteBase> _planning(Role role) => [
  GoRoute(
    path: '/planning/visits/:id',
    builder: (_, state) =>
        VisitDetailScreen(visitId: state.pathParameters['id']!),
  ),
  if (role == Role.responsable) ...[
    GoRoute(path: '/planning', builder: (_, _) => const PlanningScreen()),
    GoRoute(
      path: '/planning/new',
      builder: (_, state) => VisitFormScreen(day: _extra<DateTime>(state)),
    ),
    GoRoute(
      path: '/planning/settings',
      builder: (_, _) => const PlanningSettingsScreen(),
    ),
    _withExtra<Visit>(
      '/planning/:id/edit',
      '/planning',
      (_, visit) => VisitFormScreen(visit: visit),
    ),
  ] else ...[
    GoRoute(
      path: '/planning/overview',
      builder: (_, _) => const PlanningOverviewScreen(),
    ),
    _withExtra<(String, OverviewQuery)>(
      '/planning/overview/:id',
      '/planning/overview',
      (state, extra) => ResponsableVisitsScreen(
        responsableId: state.pathParameters['id']!,
        name: extra.$1,
        query: extra.$2,
      ),
    ),
  ],
];

/// The analytics behind every number, for the admin and the responsables. The question
/// travels in the address, so a page can be reloaded, bookmarked or shared on the web.
List<RouteBase> _analytics() => [
  GoRoute(
    path: '/explore',
    builder: (_, state) =>
        ExplorerScreen(lens: Lens.fromQuery(state.uri.queryParameters)),
  ),
  GoRoute(
    path: '/explore/stores',
    builder: (_, state) =>
        StoresBoardScreen.fromQuery(state.uri.queryParameters),
  ),
  GoRoute(
    path: '/explore/sales',
    builder: (_, state) => LedgerScreen(
      lens: Lens.fromQuery(state.uri.queryParameters),
      voidedOnly: state.uri.queryParameters['show'] == 'voided',
    ),
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
      ExplorerScreen.root,
    ),
    TabSpec(
      LucideIcons.menu,
      (t) => t.moreTitle,
      '/more',
      () => _more(Role.responsable),
    ),
  ]),
];

/// The buyer's bottom tabs: the para's stock and orders, and nothing about sales.
List<RouteBase> _buyerTabs() => [
  _shell([
    TabSpec(
      LucideIcons.house,
      (t) => t.tabHome,
      '/home',
      () => const BuyerHome(),
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
      () => _more(Role.acheteur),
    ),
  ]),
];

/// The order manager's bottom tabs on the phone.
List<RouteBase> _ordersTabs() => [
  _shell([
    TabSpec(
      LucideIcons.house,
      (t) => t.tabHome,
      '/home',
      () => const OrdersHome(),
    ),
    TabSpec(
      LucideIcons.store,
      (t) => t.parasTitle,
      '/paras',
      () => const ParasScreen(),
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
      () => _more(Role.orders),
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
  GoRoute(path: '/reports', builder: (_, _) => ExplorerScreen.root()),
  GoRoute(path: '/depots/new', builder: (_, _) => const DepotFormScreen()),
  GoRoute(path: '/regions', builder: (_, _) => const RegionsScreen()),
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
      locationName: _extra<String>(state),
    ),
  ),
  GoRoute(
    path: '/regions/:id',
    builder: (_, state) => RegionScreen(
      regionId: state.pathParameters['id']!,
      name: _extra<String>(state),
    ),
  ),
  GoRoute(path: '/rewards', builder: (_, _) => const RewardsScreen()),
  GoRoute(
    path: '/rewards/new',
    builder: (_, state) =>
        RewardFormScreen(preset: _extra<RewardPreset>(state)),
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
  GoRoute(
    path: '/people/new',
    builder: (_, state) => CreateAccountScreen(regionId: _extra<String>(state)),
  ),
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
      lesson: _extra<Lesson>(state),
    ),
  ),
  GoRoute(path: '/catalog/new', builder: (_, _) => const ProductFormScreen()),
  GoRoute(
    path: '/catalog/:id/edit',
    builder: (_, state) => ProductFormScreen(existing: _extra<Product>(state)),
  ),
];

/// Screens that several roles can open.
List<RouteBase> _shared() => [
  GoRoute(
    path: '/paras/:id',
    builder: (_, state) =>
        ParaDetailScreen(paraId: state.pathParameters['id']!),
  ),
  // Returns: a responsable asks, the admin decides (a team member has no returns).
  GoRoute(path: '/returns', builder: (_, _) => const ReturnsScreen()),
  GoRoute(path: '/returns/new', builder: (_, _) => const NewReturnScreen()),
  GoRoute(
    path: '/returns/:id',
    builder: (_, state) =>
        ReturnDetailScreen(returnId: state.pathParameters['id']!),
  ),
  // Transfers between paras of a group: a team member records them, the admin decides.
  GoRoute(path: '/transfers', builder: (_, _) => const TransfersScreen()),
  GoRoute(path: '/transfers/new', builder: (_, _) => const NewTransferScreen()),
  GoRoute(
    path: '/transfers/:id',
    builder: (_, state) =>
        TransferDetailScreen(transferId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: '/notifications',
    builder: (_, _) => const NotificationsScreen(),
  ),
  // A sale opened from any list: the seller's history, a store's sales, the analytics.
  GoRoute(
    path: '/sales/:id',
    builder: (_, state) =>
        SaleDetailScreen(saleId: state.pathParameters['id']!),
  ),
  _withExtra<Sale>(
    '/sales/:id/correct',
    '/home',
    (_, sale) => CorrectSaleScreen(sale: sale),
  ),
  GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  GoRoute(path: '/app-errors', builder: (_, _) => const AppErrorsScreen()),
  GoRoute(path: '/app-settings', builder: (_, _) => const AppSettingsScreen()),
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
    builder: (_, state) => PdvFormScreen(existing: _extra<Pdv>(state)),
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
    path: '/stock/declarations/:id/edit',
    redirect: (_, state) => state.extra is StockDeclaration
        ? null
        : '/stock/declarations/${state.pathParameters['id']}',
    builder: (_, state) => pageNeeding<StockDeclaration>(
      state,
      '/stock/declarations/${state.pathParameters['id']}',
      (declaration) => EditDeclarationScreen(declaration: declaration),
    ),
  ),
  GoRoute(
    path: '/stock/:id',
    builder: (_, state) => StockScreen(
      locationId: state.pathParameters['id']!,
      title: _extra<String>(state),
    ),
  ),
  GoRoute(
    path: '/stock/:id/declare',
    builder: (_, state) => DeclareStockScreen(
      locationId: state.pathParameters['id']!,
      locationName: _extra<String>(state),
    ),
  ),
  GoRoute(
    path: '/restocks/new',
    builder: (_, state) => RequestRestockScreen(destId: _extra<String>(state)),
  ),
  GoRoute(
    path: '/restocks/:id',
    builder: (_, state) =>
        RestockDetailScreen(orderId: state.pathParameters['id']!),
  ),
  _restockStep('ship', (order) => ShipScreen(order: order)),
  _restockStep('papers', (order) => OrderPapersScreen(order: order)),
  _restockStep('receive', (order) => ReceiveScreen(order: order)),
];

/// A step of a restock order (ship, papers, receive): opened without the order it goes back to the order.
GoRoute _restockStep(String step, Widget Function(RestockOrder order) build) =>
    GoRoute(
      path: '/restocks/:id/$step',
      redirect: (_, state) => state.extra is RestockOrder
          ? null
          : '/restocks/${state.pathParameters['id']}',
      builder: (_, state) => pageNeeding<RestockOrder>(
        state,
        '/restocks/${state.pathParameters['id']}',
        build,
      ),
    );

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
        MoreEntry(LucideIcons.map, t.regions, '/regions'),
        MoreEntry(LucideIcons.warehouse, t.grossistesTitle, '/depots'),
        MoreEntry(
          LucideIcons.mapPinCheck,
          t.planningOverviewTitle,
          '/planning/overview',
        ),
        MoreEntry(LucideIcons.arrowLeftRight, t.transfersTitle, '/transfers'),
        MoreEntry(LucideIcons.undo2, t.returnsTitle, '/returns'),
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
      Role.acheteur => [
        MoreEntry(LucideIcons.arrowLeftRight, t.transfersTitle, '/transfers'),
        MoreEntry(LucideIcons.undo2, t.returnsTitle, '/returns'),
        MoreEntry(LucideIcons.package, t.catalogTitle, '/catalog'),
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
      Role.orders => [
        MoreEntry(LucideIcons.arrowLeftRight, t.transfersTitle, '/transfers'),
        MoreEntry(LucideIcons.undo2, t.returnsTitle, '/returns'),
        MoreEntry(LucideIcons.warehouse, t.grossistesTitle, '/depots'),
        MoreEntry(LucideIcons.package, t.catalogTitle, '/catalog'),
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
        MoreEntry(LucideIcons.calendarDays, t.planningTitle, '/planning'),
        MoreEntry(LucideIcons.arrowLeftRight, t.transfersTitle, '/transfers'),
        MoreEntry(LucideIcons.undo2, t.returnsTitle, '/returns'),
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
