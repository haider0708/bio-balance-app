import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/services/api/generated/api_client.dart';
import 'data/services/api/transport_security.dart';
import 'data/services/api/session_storage.dart';

import 'package:flutter/foundation.dart';

import 'data/services/notifications/push_notifications.dart';
import 'data/services/local_database/database.dart';
import 'data/repositories/offline_repository.dart';
import 'ui/core/design.dart';
import 'ui/core/installation.dart';
import 'ui/features/authentication/session_view_model.dart';
import 'ui/features/authentication/login_screen.dart';
import 'ui/features/authentication/account_links.dart';
import 'ui/features/workspace/workspace_view_model.dart';
import 'ui/features/workspace/workspace_navigator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Lucide Icons',
    ], await rootBundle.loadString('assets/licenses/lucide.txt'));
  });
  const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
  try {
    TransportSecurity.validateOrigin(baseUrl, release: kReleaseMode);
  } on FormatException {
    runApp(
      MaterialApp(
        theme: appTheme(),
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Cette version de BioBalance est mal configurée. Contactez votre administrateur.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  final api = ApiClient(baseUrl: baseUrl);
  final database = AppDatabase.open();
  runApp(BioBalanceApp(api: api, database: database));
}

class BioBalanceApp extends StatelessWidget {
  final ApiClient api;
  final AppDatabase database;
  BioBalanceApp({super.key, required this.api, required this.database});
  final navigator = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => SessionViewModel(
      api,
      SessionStorage.secure,
      prepareStorage: SessionStorage.prepare,
      notifications: PushNotifications(api),
    )..restore(),
    child: MaterialApp(
      title: Installation.label,
      navigatorKey: navigator,
      builder: (context, child) =>
          AccountLinks(navigator: navigator, child: child!),
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      locale: const Locale('fr', 'TN'),
      supportedLocales: const [Locale('fr', 'TN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Consumer<SessionViewModel>(
        builder: (context, session, _) {
          if (session.state.restoring) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final user = session.state.user;
          if (user == null) return const LoginScreen();
          return ChangeNotifierProvider(
            key: ValueKey('${user.id}:${api.generation}'),
            create: (_) {
              final workspace = WorkspaceViewModel(
                user,
                OfflineRepository(database, api),
                api,
              );
              workspace.detachSessionGuard = session.registerExitGuard(
                workspace.flushDrafts,
              );
              return workspace;
            },
            child: const WorkspaceNavigator(),
          );
        },
      ),
    ),
  );
}
