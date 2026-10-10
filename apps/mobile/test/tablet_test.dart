// Every role on tablet sizes (iPad portrait and landscape): side rail, readable widths, no overflow.
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import 'analytics_test.dart' as analytics show analyticsServer;
import 'screenshots_test.dart' as base show loadFonts, server;
import 'support/harness.dart';

void main() {
  setUpAll(base.loadFonts);

  for (final (name, size) in [
    ('portrait', const Size(1024, 1366)),
    ('landscape', const Size(1366, 1024)),
  ]) {
    testWidgets('admin on an iPad ($name)', (tester) async {
      await launch(
        tester,
        analytics.analyticsServer(),
        language: 'en',
        size: size,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Approvals'), findsWidgets);
      await screenshot(tester, '70-tablet-admin-$name');
      await tester.tap(find.text('Today').first);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await screenshot(tester, '71-tablet-analytics-$name');
    });

    testWidgets('team member on an iPad ($name)', (tester) async {
      await launch(tester, base.server('VENDEUR'), language: 'en', size: size);
      expect(tester.takeException(), isNull);
      await screenshot(tester, '72-tablet-vendeur-$name');
      await tester.tap(find.text('Wallet').last);
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('responsable on an iPad ($name)', (tester) async {
      await launch(
        tester,
        analytics.analyticsServer(role: 'RESPONSABLE'),
        language: 'en',
        size: size,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Stores').last);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await screenshot(tester, '73-tablet-responsable-$name');
    });
  }
}
