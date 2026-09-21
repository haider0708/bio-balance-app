import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'data/services/api/generated/api_client.dart';
import 'data/services/notifications/push_notifications.dart';
import 'data/services/local_database/database.dart';
import 'data/repositories/offline_repository.dart';
import 'ui/core/design.dart';
import 'ui/features/authentication/session_view_model.dart';
import 'ui/features/authentication/login_screen.dart';
import 'ui/features/workspace/workspace_view_model.dart';
import 'ui/features/workspace/workspace_navigator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient(
    baseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:3000',
    ),
  );
  final database = AppDatabase.open();
  runApp(BioBalanceApp(api: api, database: database));
}

class BioBalanceApp extends StatelessWidget {
  final ApiClient api;
  final AppDatabase database;
  const BioBalanceApp({super.key, required this.api, required this.database});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => SessionViewModel(
      api,
      const FlutterSecureStorage(),
      notifications: PushNotifications(api),
    )..restore(),
    child: MaterialApp(
      title: 'BioBalance',
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
            key: ValueKey(user.id),
            create: (_) {
              final workspace = WorkspaceViewModel(
                user,
                OfflineRepository(database, api),
                api,
              );
              workspace.detachSessionGuard = session.registerExitGuard(
                workspace.flushDrafts,
              );
              workspace.initialize();
              return workspace;
            },
            child: const WorkspaceNavigator(),
          );
        },
      ),
    ),
  );
}
