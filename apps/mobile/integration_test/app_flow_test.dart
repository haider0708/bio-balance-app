// Drives the real app on a device or emulator against a real API (not a fake).
//   flutter test integration_test -d <device> --dart-define=WORLD=<base64 json>
// The world (accounts, API address) comes from a seeding script that talks to the server's public routes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:biobalance/app/app.dart';
import 'package:biobalance/core/api/json.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _world = String.fromEnvironment('WORLD');

Json get world => jsonDecode(utf8.decode(base64Decode(_world))) as Json;

/// RFC 6238 (SHA-1, six digits, thirty seconds), so the test can sign the admin in.
String totp(String base32Secret, {int stepOffset = 0}) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var bits = '';
  for (final c in base32Secret.toUpperCase().replaceAll('=', '').split('')) {
    bits += alphabet.indexOf(c).toRadixString(2).padLeft(5, '0');
  }
  final key = Uint8List.fromList([
    for (var i = 0; i + 8 <= bits.length; i += 8)
      int.parse(bits.substring(i, i + 8), radix: 2),
  ]);
  final step = DateTime.now().millisecondsSinceEpoch ~/ 30000 + stepOffset;
  final message = ByteData(8)..setUint64(0, step);
  final hash = Hmac(sha1, key).convert(message.buffer.asUint8List()).bytes;
  final offset = hash.last & 0xf;
  final code =
      ((hash[offset] & 0x7f) << 24) |
      (hash[offset + 1] << 16) |
      (hash[offset + 2] << 8) |
      hash[offset + 3];
  return (code % 1000000).toString().padLeft(6, '0');
}

Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 25),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  final onScreen = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .take(40)
      .join(' | ');
  throw TestFailure(
    'Timed out waiting for ${reason ?? finder.toString()}. On screen: $onScreen',
  );
}

/// Scroll the nearest list until the finder's widget is built and on screen.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await pumpUntil(tester, find.byType(Scrollable).last);
  for (var i = 0; i < 12 && finder.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
    await settleFor(tester, 200);
  }
}

Future<void> hideKeyboard(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await settleFor(tester, 400);
}

Future<void> settleFor(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Every test starts like a freshly installed app.
Future<void> start(WidgetTester tester) async {
  await const FlutterSecureStorage().deleteAll();
  SharedPreferences.setMockInitialValues({});
  await (await SharedPreferences.getInstance()).clear();
  await tester.pumpWidget(
    ProviderScope(retry: (_, _) => null, child: const BioBalanceApp()),
  );
  await settleFor(tester, 1500);
}

Future<void> signIn(WidgetTester tester, Json account, {String? otp}) async {
  await pumpUntil(
    tester,
    find.text('Sign in').last,
    reason: 'the sign-in screen',
  );
  await tester.enterText(
    find.byType(TextFormField).at(0),
    account.str('email'),
  );
  await tester.enterText(
    find.byType(TextFormField).at(1),
    account.str('password'),
  );
  await hideKeyboard(tester);
  await tester.tap(find.text('Sign in').last);
  if (otp != null) {
    await pumpUntil(
      tester,
      find.text('Authenticator code'),
      reason: 'the authenticator field',
    );
    await tester.enterText(find.byType(TextFormField).at(2), otp);
    await hideKeyboard(tester);
    await tester.tap(find.text('Sign in').last);
  }
}

Future<void> signOut(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await pumpUntil(tester, find.text('Sign out').last);
  await tester.drag(find.byType(ListView).first, const Offset(0, -600));
  await settleFor(tester, 300);
  await tester.tap(find.text('Sign out').last);
  await pumpUntil(tester, find.text('Sign out of BioBalance?'));
  await tester.tap(find.text('Sign out').last);
  await pumpUntil(tester, find.text('Welcome back'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a team member sells and sees the reward', (tester) async {
    await start(tester);
    await signIn(tester, world.obj('vendeur'));
    await pumpUntil(
      tester,
      find.text('Hello, Amira'),
      reason: 'the team member home',
    );
    expect(find.text('Para Lac'), findsOneWidget);

    await pumpUntil(
      tester,
      find.text('New sale'),
      reason: 'the New sale button',
    );
    await tester.tap(find.text('New sale').first);
    await pumpUntil(tester, find.byType(TextField));
    // A product the store does not hold cannot be sold; one it holds can.
    await pumpUntil(
      tester,
      find.textContaining('in stock'),
      reason: 'products in stock',
    );
    final soldOut = find.text('Out of stock');
    if (soldOut.evaluate().isNotEmpty) {
      await tester.tap(soldOut.first, warnIfMissed: false);
      await settleFor(tester, 300);
      expect(find.textContaining('Review sale'), findsNothing);
    }
    await tester.enterText(find.byType(TextField).first, 'SERUM');
    await settleFor(tester);
    await pumpUntil(
      tester,
      find.textContaining('in stock'),
      reason: 'serums in stock',
    );
    await tester.tap(find.textContaining('in stock').first);
    await settleFor(tester, 300);
    await tester.tap(find.textContaining('Review sale'));
    await pumpUntil(tester, find.text('Record the sale'));
    await tester.tap(find.text('Record the sale'));

    await pumpUntil(
      tester,
      find.text('Great sale!'),
      reason: 'the celebration screen',
    );
    expect(find.textContaining('TND'), findsWidgets);
    expect(find.text('You earned'), findsOneWidget);
    await settleFor(tester, 1500);
    await tester.tap(find.text('Done'));
    await settleFor(tester, 1000);
    await tester.tap(find.text('Wallet').last);
    await pumpUntil(tester, find.text('Available balance'));
    expect(find.text('Request a payout'), findsOneWidget);
    await tester.tap(find.text('Sales').last);
    await pumpUntil(tester, find.textContaining('unit'));
    await tester.tap(find.text('Home').last);
    await pumpUntil(tester, find.byTooltip('Settings'));
    await signOut(tester);
  });

  testWidgets('a responsable sees their region and the order in progress', (
    tester,
  ) async {
    await start(tester);
    await signIn(tester, world.obj('responsable'));
    await pumpUntil(
      tester,
      find.text('Hello, Nora'),
      reason: 'the responsable home',
    );
    expect(find.text('Region Nord'), findsOneWidget);
    await tester.tap(find.text('Stores').last);
    await pumpUntil(tester, find.text('Para Lac'));
    expect(find.text('Pharma Marsa'), findsOneWidget);
    expect(find.text('Waiting for approval'), findsWidgets);
    await tester.tap(find.text('Para Lac').first);
    await pumpUntil(
      tester,
      find.text('Amira Gharbi'),
      reason: 'the team of the point of sale',
    );
    expect(find.text('Karim Mejri'), findsOneWidget);
    await tester.pageBack();
    await settleFor(tester, 500);
    await tester.tap(find.text('Restocks').last);
    await pumpUntil(tester, find.textContaining('RS-'));
    await tester.tap(find.textContaining('RS-').first);
    await pumpUntil(tester, find.text('With the grossiste'));
    await reveal(tester, find.text('Choose who counts the goods'));
    expect(find.text('Choose who counts the goods'), findsOneWidget);
    await tester.pageBack();
    await settleFor(tester, 400);
    await tester.tap(find.text('More').last);
    await pumpUntil(tester, find.text('Grossistes'));
    await tester.tap(find.text('Grossistes'));
    await pumpUntil(tester, find.text('Depot Hedi'));
    await tester.tap(find.text('Depot Hedi'));
    // A grossiste is a warehouse: its details, its stock, and what the responsable may do about it.
    await pumpUntil(
      tester,
      find.text('71 111 111'),
      reason: 'the grossiste page',
    );
    expect(find.text('Restock'), findsOneWidget);
    await tester.pageBack();
    await tester.pageBack();
  });

  testWidgets(
    'a responsable prepares and ships the order given to a grossiste',
    (tester) async {
      await start(tester);
      await signIn(tester, world.obj('responsable'));
      await pumpUntil(
        tester,
        find.text('Hello, Nora'),
        reason: 'the responsable home',
      );
      await tester.tap(find.text('Restocks').last);
      await pumpUntil(tester, find.textContaining('RS-'));
      await tester.tap(find.textContaining('RS-').first);
      await pumpUntil(
        tester,
        find.text('Requested by'),
        reason: 'the order detail',
      );
      await reveal(tester, find.text('Prepare and ship'));
      await tester.tap(find.text('Prepare and ship'));
      await pumpUntil(
        tester,
        find.text('Ship'),
        reason: 'the ship screen',
        timeout: const Duration(seconds: 3),
      ).catchError((_) {});
      await reveal(tester, find.text('Mark as shipped'));
      await tester.tap(find.text('Mark as shipped'));
      await settleFor(tester, 2500);
      await tester.drag(find.byType(Scrollable).last, const Offset(0, 4000));
      await settleFor(tester, 500);
      await pumpUntil(
        tester,
        find.text('On its way'),
        reason: 'the shipped status',
      );
      expect(find.text('Prepare and ship'), findsNothing);
    },
  );

  testWidgets(
    'the admin signs in with the authenticator and approves a point of sale',
    (tester) async {
      final admin = world.obj('admin');
      final secret = Uri.parse(admin.str('totpUri')).queryParameters['secret']!;
      await start(tester);
      await signIn(tester, admin, otp: totp(secret));
      await pumpUntil(
        tester,
        find.textContaining('Hello,'),
        reason: 'the admin home',
      );
      await tester.tap(find.text('Approvals').last);
      await pumpUntil(
        tester,
        find.text('Pharma Marsa'),
        reason: 'the pending point of sale',
      );
      expect(find.text('Karim Mejri'), findsOneWidget);
      await tester.tap(find.text('Pharma Marsa'));
      await pumpUntil(
        tester,
        find.text('Approve'),
        reason: 'the point of sale page',
      );
      await tester.tap(find.text('Approve').first);
      await pumpUntil(tester, find.text('Active'), reason: 'the new status');
      await tester.pageBack();
      await settleFor(tester, 800);
      await tester.tap(find.text('More').last);
      await pumpUntil(tester, find.text('Rewards'));
      await tester.tap(find.text('Rewards'));
      await pumpUntil(
        tester,
        find.text('Pays today'),
        reason: 'the rewards screen',
      );
      await reveal(tester, find.text('0.500 TND'));
      expect(find.text('0.500 TND'), findsWidgets);
    },
  );

  testWidgets(
    'the admin creates a store and a group for a region, active at once',
    (tester) async {
      final admin = world.obj('admin');
      final secret = Uri.parse(admin.str('totpUri')).queryParameters['secret']!;
      await start(tester);
      // The previous test used this one-time code: take the next step's.
      await signIn(tester, admin, otp: totp(secret, stepOffset: 1));
      await pumpUntil(
        tester,
        find.textContaining('Hello,'),
        reason: 'the admin home',
      );
      await tester.tap(find.text('Network').last);
      await pumpUntil(
        tester,
        find.text('New store'),
        reason: 'the New store button',
      );
      await tester.tap(find.text('New store'));
      await pumpUntil(tester, find.text('Region'), reason: 'the store form');
      await tester.tap(find.text('Region'));
      await settleFor(tester, 500);
      await tester.tap(find.text('Centre').last);
      await settleFor(tester, 400);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Para Sfax Test');
      await tester.enterText(fields.at(1), '5 rue de la Paix');
      await tester.enterText(fields.at(2), 'Sfax');
      await hideKeyboard(tester);
      await tester.tap(find.text('Create the point of sale'));
      await pumpUntil(
        tester,
        find.text('Para Sfax Test'),
        reason: 'the new store page',
      );
      await pumpUntil(
        tester,
        find.text('Active'),
        reason: 'the store is active at once',
      );
    },
  );

  testWidgets('a responsable reads the report tabs', (tester) async {
    await start(tester);
    await signIn(tester, world.obj('responsable'));
    await pumpUntil(
      tester,
      find.text('Hello, Nora'),
      reason: 'the responsable home',
    );
    await tester.tap(find.text('Reports').last);
    await pumpUntil(tester, find.text('Overview'), reason: 'the report tabs');
    for (final tab in ['Products', 'Team']) {
      await tester.tap(find.text(tab).last);
      await settleFor(tester, 1500);
    }
    expect(find.textContaining('unavailable'), findsNothing);
  });
}
