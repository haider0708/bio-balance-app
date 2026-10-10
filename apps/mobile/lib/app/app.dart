import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../core/alerts/background_alerts.dart';
import '../core/auth/session.dart';
import '../core/theme/app_theme.dart';
import '../features/splash/splash_screen.dart';
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

  /// An alert was tapped while the opening still played.
  bool _inboxAfterOpening = false;

  @override
  void initState() {
    super.initState();
    unawaited(BackgroundAlerts.onOpened(_openInbox));
  }

  /// A tapped alert opens the notifications, once the opening is over.
  void _openInbox() {
    if (!ref.read(splashDoneProvider)) {
      _inboxAfterOpening = true;
      return;
    }
    if (ref.read(accountProvider) == null) return;
    unawaited(ref.read(routerProvider).push('/notifications'));
  }

  @override
  Widget build(BuildContext context) {
    final choice = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);
    ref.listen(splashDoneProvider, (_, done) {
      if (!done || !_inboxAfterOpening) return;
      _inboxAfterOpening = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInbox());
    });
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
