import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/role_journeys_test.dart' show Journey;

void main() {
  testWidgets('journey waits for a transient snackbar covering its target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = previous);
    final messenger = GlobalKey<ScaffoldMessengerState>();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messenger,
        home: Scaffold(
          body: Column(
            children: [
              const Spacer(),
              FilledButton(
                onPressed: () => taps++,
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
    messenger.currentState!.showSnackBar(
      const SnackBar(
        content: Text('Opération enregistrée'),
        duration: Duration(seconds: 2),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Se déconnecter').hitTestable(), findsNothing);
    await Journey(tester).tap('Se déconnecter');
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
