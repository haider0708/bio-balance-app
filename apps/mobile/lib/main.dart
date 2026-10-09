import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/router.dart' show rememberLanding;
import 'core/alerts/background_alerts.dart';

Future<void> main() async {
  usePathUrlStrategy();
  rememberLanding();
  WidgetsFlutterBinding.ensureInitialized();
  // In a browser the page is described to screen readers, and its text can be found and read.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  unawaited(BackgroundAlerts.start());
  // Failed requests are shown to the person, not silently retried behind their back.
  runApp(ProviderScope(retry: (_, _) => null, child: const BioBalanceApp()));
}
