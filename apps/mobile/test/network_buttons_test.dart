import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show server;
import 'support/harness.dart';

void main() {
  testWidgets('the admin can create a store, a group and a member, the button follows the tab', (tester) async {
    await launch(tester, base.server('ADMIN'), language: 'en');
    await tester.tap(find.text('Network').last);
    await settle(tester);
    expect(find.text('New store'), findsOneWidget);
    await tester.tap(find.text('Groups').last);
    await settle(tester);
    expect(find.text('New group'), findsOneWidget);
    await tester.tap(find.text('People').last);
    await settle(tester);
    expect(find.text('New member'), findsOneWidget);
  });
}
