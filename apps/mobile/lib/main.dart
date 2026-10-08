import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/router.dart' show rememberLanding;
import 'core/alerts/background_alerts.dart';

Future<void> main() async {
  usePathUrlStrategy();
  rememberLanding();
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(BackgroundAlerts.start());
  // Failed requests are shown to the person, not silently retried behind their back.
  runApp(ProviderScope(retry: (_, _) => null, child: const BioBalanceApp()));
}
