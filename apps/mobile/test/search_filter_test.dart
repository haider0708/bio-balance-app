// Search, filters and sorts above the lists: the same toolkit everywhere.
import 'dart:async';

import 'package:biobalance/app/router.dart';
import 'package:biobalance/core/theme/app_theme.dart';
import 'package:biobalance/core/widgets/list_tools.dart';
import 'package:biobalance/core/widgets/paged_list.dart';
import 'package:biobalance/l10n/app_localizations.dart';
import 'package:flutter/material.dart'
    show Locale, Material, MaterialApp, Scaffold, Size, Text, TextField, Widget;
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

void main() {
  group('matching', () {
    test('ignores case and accents, and every word has to be found', () {
      expect(foldText('Sérum Éclat Œuf'), 'serum eclat oeuf');
      expect(matchesSearch('serum', ['SÉRUM vitamine C']), isTrue);
      expect(matchesSearch('vitamine serum', ['Sérum vitamine C']), isTrue);
      expect(matchesSearch('serum niacine', ['Sérum vitamine C']), isFalse);
      expect(matchesSearch('  ', ['anything']), isTrue);
      expect(matchesSearch('lac', [null, 'Para Lac']), isTrue);
      expect(matchesSearch('x', [null]), isFalse);
    });
  });

  group('SearchableList', () {
    Widget app(List<(String, int)> items) => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SearchableList<(String, int)>(
          items: items,
          hint: 'Search',
          emptyTitle: 'Nothing found',
          fields: (i) => [i.$1],
          filters: [
            ListFilter('All', (_) => true),
            ListFilter('Big', (i) => i.$2 >= 10),
          ],
          sorts: [
            ListSort('Name', (a, b) => a.$1.compareTo(b.$1)),
            ListSort('Most', (a, b) => b.$2.compareTo(a.$2)),
          ],
          itemBuilder: (context, i) => Text('${i.$1}:${i.$2}'),
        ),
      ),
    );

    testWidgets(
      'searches, filters by chip, sorts, and says when nothing is left',
      (tester) async {
        await tester.pumpWidget(
          app([('Sérum', 4), ('Crème', 12), ('Savon', 30)]),
        );
        expect(find.text('Sérum:4'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'serum');
        await tester.pump();
        expect(find.text('Sérum:4'), findsOneWidget);
        expect(find.text('Crème:12'), findsNothing);

        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        await tester.tap(find.text('Big'));
        await tester.pump();
        expect(find.text('Sérum:4'), findsNothing);
        expect(find.text('Savon:30'), findsOneWidget);

        await tester.tap(find.byTooltip('Sort'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Most').last);
        await tester.pumpAndSettle();
        final first = tester.getTopLeft(find.text('Savon:30')).dy;
        final second = tester.getTopLeft(find.text('Crème:12')).dy;
        expect(first, lessThan(second));

        await tester.enterText(find.byType(TextField), 'zzz');
        await tester.pump();
        expect(find.text('Nothing found'), findsOneWidget);
      },
    );
  });

  group('PagedList filter', () {
    testWidgets('keeps loading pages while a search has few matches', (
      tester,
    ) async {
      var pages = 0;
      final controller = PagedController<int>((cursor) async {
        pages++;
        final start = int.parse(cursor ?? '0');
        // Page after page of numbers: only multiples of 40 match.
        return PageResult([
          for (var i = start; i < start + 20; i++) i,
        ], start + 20 >= 200 ? null : '${start + 20}');
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: PagedList<int>(
              controller: controller,
              empty: const Text('empty'),
              noMatch: const Text('no match'),
              test: (i) => i % 40 == 0,
              itemBuilder: (context, i, _) => Text('n$i'),
            ),
          ),
        ),
      );
      for (var k = 0; k < 12; k++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Pages were pulled in until the screen could be filled with matches (or all were read).
      expect(pages, greaterThan(1));
      expect(find.text('n0'), findsOneWidget);
      expect(find.text('n1'), findsNothing);
      controller.dispose();
    });

    testWidgets('says nothing matched once everything was read', (
      tester,
    ) async {
      final controller = PagedController<int>(
        (cursor) async => const PageResult([1, 2, 3], null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: PagedList<int>(
              controller: controller,
              empty: const Text('empty'),
              noMatch: const Text('no match'),
              test: (i) => i > 10,
              itemBuilder: (context, i, _) => Text('n$i'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('no match'), findsOneWidget);
      controller.dispose();
    });
  });

  group('screens', () {
    FakeServer admin() => FakeServer()
      ..on('GET /v1/me', meJson(role: 'ADMIN'))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/pdvs', <Object?>[])
      ..on('GET /v1/groups', <Object?>[])
      ..on('GET /v1/regions', <Object?>[])
      ..on('GET /v1/users', [
        _person('u1', 'Amira Gharbi', 'VENDEUR', 'amira@x.tn'),
        _person('u2', 'Nora Ben Salah', 'RESPONSABLE', 'nora@x.tn'),
        _person('u3', 'Karim Orders', 'ORDERS', 'karim@x.tn'),
      ])
      ..on('GET /v1/depots', [
        _depot('d1', 'Grossiste Tunis', 120, 6),
        _depot('d2', 'Grossiste Sfax', 900, 12),
        _depot('d3', 'Dépôt Sousse', 40, 3),
      ])
      ..on('GET /v1/approvals', {
        'counts': <String, Object?>{},
        'items': <Object?>[],
      });

    testWidgets(
      'the admin finds a person by part of their name or their role',
      (tester) async {
        final s = admin();
        final container = await launch(
          tester,
          s,
          language: 'en',
          size: const Size(412, 900),
        );
        unawaited(container.read(routerProvider).push('/network'));
        await settle(tester);
        await tester.tap(find.text('People'));
        await settle(tester);
        expect(find.text('Amira Gharbi'), findsOneWidget);
        expect(find.text('Karim Orders'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'nora');
        await tester.pump();
        await settle(tester);
        expect(find.text('Nora Ben Salah'), findsOneWidget);
        expect(find.text('Amira Gharbi'), findsNothing);
        // The admin can pick every kind of account, the new ones too.
        expect(find.text('Order manager'), findsOneWidget);
        expect(find.text('Buyer'), findsOneWidget);
      },
    );

    testWidgets('warehouses sort by pieces in stock and search by name', (
      tester,
    ) async {
      final s = admin();
      final container = await launch(
        tester,
        s,
        language: 'en',
        size: const Size(412, 900),
      );
      unawaited(container.read(routerProvider).push('/depots'));
      await settle(tester);
      expect(find.text('Grossiste Tunis'), findsOneWidget);
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pieces in stock').last);
      await tester.pumpAndSettle();
      final sfax = tester.getTopLeft(find.text('Grossiste Sfax')).dy;
      final tunis = tester.getTopLeft(find.text('Grossiste Tunis')).dy;
      expect(sfax, lessThan(tunis));
      await tester.enterText(find.byType(TextField).first, 'sousse');
      await tester.pump();
      await settle(tester);
      expect(find.text('Dépôt Sousse'), findsOneWidget);
      expect(find.text('Grossiste Sfax'), findsNothing);
    });
  });
}

Map<String, Object?> _person(
  String id,
  String name,
  String role,
  String email,
) => {
  'id': id,
  'name': name,
  'email': email,
  'phone': null,
  'role': role,
  'status': 'ACTIVE',
  'regionId': role == 'ORDERS' ? null : 'r1',
  'pdvId': null,
  'activated': true,
};

Map<String, Object?> _depot(String id, String name, int units, int products) =>
    {
      'id': id,
      'name': name,
      'address': '1 rue',
      'city': 'Tunis',
      'status': 'ACTIVE',
      'region': {'id': 'r1', 'name': 'Nord'},
      'photoIds': <Object?>[],
      'units': units,
      'products': products,
      'counted': true,
      'countPending': false,
    };
