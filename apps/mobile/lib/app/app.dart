import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../core/auth/session.dart';
import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';

class BioBalanceApp extends ConsumerStatefulWidget {
  const BioBalanceApp({super.key});

  @override
  ConsumerState<BioBalanceApp> createState() => _BioBalanceAppState();
}

class _BioBalanceAppState extends ConsumerState<BioBalanceApp> {
  late final Future<void> _ready = Future.wait([
    initializeDateFormatting('fr'),
    initializeDateFormatting('en'),
  ]);

  @override
  Widget build(BuildContext context) {
    final choice = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) => MaterialApp.router(
        onGenerateTitle: (context) {
          final t = AppLocalizations.of(context);
          return kIsWeb ? t.adminConsoleTitle : t.appName;
        },
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ref.watch(themeModeProvider),
        locale: choice == null ? null : Locale(choice),
        supportedLocales: AppLocalizations.supportedLocales,
        // French is the default unless the phone itself is set to English.
        localeResolutionCallback: (device, supported) => supported.firstWhere(
          (l) => l.languageCode == device?.languageCode,
          orElse: () => const Locale('fr'),
        ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
        // On the web the administrator can select and copy any text (an email, a code, a total).
        builder: kIsWeb
            ? (context, child) =>
                  SelectionArea(child: child ?? const SizedBox())
            : null,
      ),
    );
  }
}
