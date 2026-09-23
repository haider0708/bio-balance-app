import 'dart:async';

import 'package:biobalance/data/services/api/generated/models.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/workspace_scope.dart';
import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/features/team/group_member_editor.dart';
import 'package:biobalance/ui/features/workspace/access_setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'group_navigation_test.dart' show ScopeFixture;
import 'ui_test.dart' show screenshot;

GroupListResponseDto directory({required bool manage}) =>
    GroupListResponseDto.fromJson({
      'items': [
        {
          'id': 'g1',
          'name': 'Parahouse',
          'createdAt': '2026-09-23T10:00:00Z',
          'imageId': null,
          'phone': null,
          'version': 1,
          'canManage': manage,
          'storeCount': 1,
        },
      ],
      'creationGrants': [],
      'nextCursor': null,
    });

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });

  testWidgets('responsible setup has a clear primary action and access help', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final f = ScopeFixture(admin: false);
    addTearDown(f.close);
    f.scope.groups = [];
    f.scope.grants = ['grant'];
    f.workspace.state = f.workspace.state.copy(stores: []);
    final capture = GlobalKey();
    await t.pumpWidget(f.app(capture: capture));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('access.create-group')), findsOneWidget);
    expect(find.byKey(const ValueKey('access.refresh')), findsOneWidget);
    expect(find.text('Catalogue'), findsNothing);
    await screenshot(t, capture, 'responsible-access-setup');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  for (final manage in [true, false]) {
    test(
      'refresh opens newly granted ${manage ? 'group' : 'seller store'} instead of network',
      () async {
        final f = ScopeFixture(admin: false);
        addTearDown(f.close);
        addTearDown(f.scope.dispose);
        f.scope.groups = [];
        final assigned = Store.fromJson({
          ...f.workspace.state.stores.first.toJson(),
          'permissions': manage
              ? ['manage', 'sell', 'receive']
              : ['sell', 'receive'],
        });
        f.workspace.state = f.workspace.state.copy(stores: [assigned]);
        final response = Completer<GroupListResponseDto>();
        f.api.groupResponse = response.future;
        final refresh = f.scope.refresh();
        expect(f.scope.refreshing, isTrue);
        expect(identical(refresh, f.scope.refresh()), isTrue);
        response.complete(directory(manage: manage));
        await refresh;
        expect(f.scope.scope.kind, manage ? ScopeKind.group : ScopeKind.store);
        expect(f.scope.scope.group?.id, 'g1');
        expect(f.scope.scope.store?.id, manage ? isNull : 's1');
        expect(f.scope.refreshing, isFalse);
        expect(f.scope.canGoBack, isFalse);
        final key = f.scope.scope.key;
        await f.scope.refresh();
        expect(f.scope.scope.key, key);
      },
    );
  }

  for (final size in [const Size(360, 640), const Size(640, 360)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'setup and refresh are separate actions at $size and scale $scale',
        (t) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          var creates = 0, refreshes = 0;
          await t.pumpWidget(
            MaterialApp(
              theme: appTheme(),
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: AccessSetupPage(
                  email: 'responsable@example.test',
                  canCreateGroup: true,
                  refreshing: false,
                  onCreateGroup: () => creates++,
                  onRefresh: () => refreshes++,
                ),
              ),
            ),
          );
          final create = find.byKey(const ValueKey('access.create-group'));
          final refresh = find.byKey(const ValueKey('access.refresh'));
          expect(find.text('Votre compte est activé'), findsOneWidget);
          await t.scrollUntilVisible(create, 120);
          await t.ensureVisible(create);
          await t.pumpAndSettle();
          final createBottom =
              t.getBottomLeft(create).dy +
              t
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position
                  .pixels;
          await t.tap(create);
          expect(creates, 1);
          expect(refreshes, 0);
          await t.scrollUntilVisible(refresh, 120);
          await t.ensureVisible(refresh);
          await t.pumpAndSettle();
          final refreshTop =
              t.getTopLeft(refresh).dy +
              t
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position
                  .pixels;
          expect(refreshTop - createBottom, greaterThan(48));
          await t.tap(refresh);
          expect(refreshes, 1);
          expect(creates, 1);
          expect(t.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'unassigned seller is not offered group creation or network navigation',
    (t) async {
      final f = ScopeFixture(admin: false);
      addTearDown(f.close);
      f.scope.groups = [];
      f.scope.grants = [];
      f.workspace.state = f.workspace.state.copy(stores: []);
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      expect(find.text('Mon espace'), findsOneWidget);
      expect(find.text('Aucun magasin attribué'), findsOneWidget);
      expect(find.byKey(const ValueKey('access.create-group')), findsNothing);
      expect(find.text('Tous les groupes'), findsNothing);
      expect(find.text('Catalogue'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'invitation confirmation shows the exact address, role and store before submission',
    (t) async {
      final f = ScopeFixture();
      addTearDown(f.close);
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: GroupMemberEditor(
            workspace: f.workspace,
            group: f.scope.groups.first,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('field.email')),
        'hayder.boudhrioua@example.test',
      );
      await t.ensureVisible(find.text('Magasin Tunis'));
      await t.pumpAndSettle();
      await t.tap(find.text('Magasin Tunis'));
      await t.tap(find.byKey(const ValueKey('editor.save')));
      await t.pumpAndSettle();
      expect(find.text('Vérifier l’invitation'), findsOneWidget);
      expect(find.text('hayder.boudhrioua@example.test'), findsWidgets);
      expect(find.text('Vendeur · Magasin Tunis'), findsOneWidget);
      await t.tap(find.text('Revenir'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('field.email')))
            .controller!
            .text,
        'hayder.boudhrioua@example.test',
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
