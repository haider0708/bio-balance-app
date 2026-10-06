import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/auth/me.dart';
import '../core/auth/session.dart';
import '../core/widgets/states.dart';
import '../features/auth/activate_screen.dart';
import '../features/auth/forgot_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/vendeur_home.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/sales/celebration_screen.dart';
import '../features/sales/new_sale_screen.dart';
import '../features/sales/sale_detail_screen.dart';
import '../features/sales/sales_history_screen.dart';
import '../features/sales/sales_repository.dart';
import '../features/sales/scanner_screen.dart';
import '../features/sales/sales_models.dart';
import '../features/settings/settings_screen.dart';
import '../features/training/training_screens.dart';
import '../features/wallet/wallet_screen.dart';
import '../l10n/app_localizations.dart';
import 'nav_shell.dart';

const _publicPaths = {'/login', '/activate', '/forgot'};

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
      if (!signedIn) return _publicPaths.contains(path) ? null : '/login';
      if (_publicPaths.contains(path) || path == '/splash') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const Scaffold(body: LoadingState())),
      GoRoute(path: '/login', builder: (_, state) => LoginScreen(email: state.uri.queryParameters['email'])),
      GoRoute(path: '/activate', builder: (_, _) => const ActivateScreen()),
      GoRoute(path: '/forgot', builder: (_, _) => const ForgotScreen()),
      ..._common(),
      if (role != null) ..._roleRoutes(role),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Screens every signed-in role can open.
List<RouteBase> _common() => [
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/training', builder: (_, _) => const CoursesScreen()),
      GoRoute(path: '/training/:id', builder: (_, state) => CourseScreen(courseId: state.pathParameters['id']!)),
      GoRoute(
        path: '/training/:id/lessons/:lesson',
        builder: (_, state) => LessonScreen(courseId: state.pathParameters['id']!, lessonId: state.pathParameters['lesson']!),
      ),
    ];

List<RouteBase> _roleRoutes(Role role) => switch (role) {
      Role.vendeur => _vendeur(),
      _ => [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => NavShell(shell: shell, destinations: [NavDestination(icon: LucideIcons.house, label: AppLocalizations.of(context).tabHome)]),
            branches: [
              StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: EmptyState(icon: LucideIcons.hammer, title: 'Soon')))]),
            ],
          ),
        ],
    };

List<RouteBase> _vendeur() => [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) {
          final t = AppLocalizations.of(context);
          return NavShell(shell: shell, destinations: [
            NavDestination(icon: LucideIcons.house, label: t.tabHome),
            NavDestination(icon: LucideIcons.receipt, label: t.tabSales),
            NavDestination(icon: LucideIcons.wallet, label: t.tabWallet),
            NavDestination(icon: LucideIcons.graduationCap, label: t.tabLearn),
          ]);
        },
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const VendeurHome())]),
          StatefulShellBranch(routes: [GoRoute(path: '/sales', builder: (_, _) => const SalesHistoryScreen(embedded: true))]),
          StatefulShellBranch(routes: [GoRoute(path: '/wallet', builder: (_, _) => const WalletScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/learn', builder: (_, _) => const CoursesScreen())]),
        ],
      ),
      GoRoute(path: '/sell', builder: (_, _) => const NewSaleScreen()),
      GoRoute(path: '/scan', builder: (_, _) => const ScannerScreen()),
      GoRoute(path: '/sale-done', builder: (_, state) => CelebrationScreen(outcome: state.extra! as SaleOutcome)),
      GoRoute(path: '/sales/:id', builder: (_, state) => SaleDetailScreen(saleId: state.pathParameters['id']!)),
      GoRoute(path: '/sales/:id/correct', builder: (_, state) => CorrectSaleScreen(sale: state.extra! as Sale)),
    ];
