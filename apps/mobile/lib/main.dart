import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Failed requests are shown to the person, not silently retried behind their back.
  runApp(ProviderScope(retry: (_, _) => null, child: const BioBalanceApp()));
}
