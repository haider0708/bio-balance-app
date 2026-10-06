import 'package:biobalance/app/app.dart';
import 'package:biobalance/core/auth/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

/// Starts the whole app against a fake server, already signed in (or not).
Future<ProviderContainer> launch(WidgetTester tester, FakeServer server, {bool signedIn = true, Size size = const Size(412, 892), String? language}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: server.overrides(token: signedIn ? 'a-valid-token-of-sufficient-length-123456' : null), retry: (_, _) => null);
  addTearDown(container.dispose);
  if (language != null) await container.read(localeProvider.notifier).choose(language);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const BioBalanceApp()));
  await settle(tester);
  return container;
}

/// Let animations and futures finish without waiting on endless animations (spinners).
Future<void> settle(WidgetTester tester, {int frames = 30}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
