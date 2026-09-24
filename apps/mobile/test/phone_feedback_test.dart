import 'dart:async';

import 'package:biobalance/data/repositories/dashboard_repository.dart';
import 'package:biobalance/domain/models/dashboard.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/workspace_scope.dart';
import 'package:biobalance/ui/features/replenishment/scoped_order_screen.dart';
import 'package:biobalance/ui/features/replenishment/order_sections.dart';
import 'package:biobalance/ui/features/team/group_member_editor.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/api/generated/models.dart';
import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/features/authentication/login_screen.dart';
import 'package:biobalance/ui/features/authentication/session_view_model.dart';
import 'package:biobalance/ui/features/workspace/scope_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_navigator.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'group_navigation_test.dart' show ScopeFixture;

class RecoveryApi extends ApiClient {
  String? received;
  bool fail = false;
  RecoveryApi() : super(baseUrl: 'http://test');
  @override
  Future<IdentityResetResponseDto> identityReset({
    required IdentityResetRequestDto body,
  }) async {
    received = body.token;
    if (fail) throw const FormatException('Code invalide ou expiré.');
    return IdentityResetResponseDto.fromJson({'ok': true});
  }

  @override
  Future<IdentityForgotResponseDto> identityForgot({
    required IdentityForgotRequestDto body,
  }) async => IdentityForgotResponseDto.fromJson({'message': 'Code envoyé'});
}

class DelayedOrders extends DashboardRepository {
  final calls = <String, Completer<Json>>{};
  DelayedOrders(ScopeFixture f)
    : super(f.workspace.repositoryContext, f.local, f.workspace.user.id);
  @override
  Future<Json> orders(
    String scope,
    DashboardPeriod period, {
    String? organizationId,
    String? storeId,
    String? after,
    String? phase,
  }) {
    final call = Completer<Json>();
    calls[phase!] = call;
    return call.future;
  }
}

void main() {
  test('slow responses cannot repopulate the previous order section', () async {
    final f = ScopeFixture();
    addTearDown(f.close);
    final repository = DelayedOrders(f);
    final vm = ScopedOrdersViewModel(repository, 'network', null, null);
    addTearDown(vm.dispose);
    final old = vm.load();
    vm.select(OrderSection.complete);
    repository.calls['complete']!.complete({
      'items': [
        {'id': 'completed'},
      ],
      'nextCursor': null,
    });
    await Future<void>.delayed(Duration.zero);
    repository.calls['preparation']!.complete({
      'items': [
        {'id': 'old-order'},
      ],
      'nextCursor': 'old-cursor',
    });
    await old;
    expect(vm.items.single['id'], 'completed');
    expect(vm.after, isNull);
    expect(vm.loading, false);
  });
  testWidgets(
    'group invitation separates group-wide responsibility from one-store selling',
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
      expect(find.byType(RadioListTile<String>), findsNWidgets(3));
      expect(find.text('Magasin Bizerte'), findsNothing);
      await t.ensureVisible(find.text('Magasin Tunis'));
      await t.pumpAndSettle();
      await t.tap(find.text('Magasin Tunis'));
      await t.ensureVisible(find.text('Magasin Sousse'));
      await t.pumpAndSettle();
      await t.tap(find.text('Magasin Sousse'));
      await t.pumpAndSettle();
      expect(
        t
            .widgetList<RadioListTile<String>>(
              find.byType(RadioListTile<String>),
            )
            .where(
              (w) =>
                  w.value ==
                  t
                      .widget<RadioGroup<String>>(
                        find.byType(RadioGroup<String>),
                      )
                      .groupValue,
            )
            .length,
        1,
      );
      await t.ensureVisible(find.text('Responsable'));
      await t.pumpAndSettle();
      await t.tap(find.text('Responsable'));
      await t.pumpAndSettle();
      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(find.textContaining('actuels et futurs'), findsOneWidget);
      await t.ensureVisible(find.text('Vendeur'));
      await t.pumpAndSettle();
      await t.tap(find.text('Vendeur'));
      await t.pumpAndSettle();
      expect(
        t
            .widgetList<RadioListTile<String>>(
              find.byType(RadioListTile<String>),
            )
            .where(
              (w) =>
                  w.value ==
                  t
                      .widget<RadioGroup<String>>(
                        find.byType(RadioGroup<String>),
                      )
                      .groupValue,
            )
            .length,
        1,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'seller reaches assigned stores through the single group selector',
    (t) async {
      final f = ScopeFixture(admin: false);
      addTearDown(f.close);
      f.scope.groups = const [
        PartnerGroup(id: 'g1', name: 'Parahouse', storeCount: 3),
      ];
      f.workspace.state = f.workspace.state.copy(
        stores: f.workspace.state.stores
            .map(
              (s) => Store.fromJson({
                ...s.toJson(),
                'permissions': ['sell', 'receive'],
              }),
            )
            .toList(),
      );
      await f.scope.selectAssignedStore(
        f.scope.groups.first,
        f.scope.storesFor('g1').first,
      );
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('scope.group')));
      await t.pumpAndSettle();
      await t.tap(find.text('Parahouse').last);
      await t.pumpAndSettle();
      expect(find.text('Vos magasins'), findsOneWidget);
      expect(find.text('Magasin Bizerte'), findsNothing);
      await t.tap(find.text('Magasin Sousse'));
      await t.pumpAndSettle();
      expect(f.scope.scope.store!.id, 's2');
      expect(find.byKey(const ValueKey('scope.store')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'the redesigned invitation restores the original store-bound draft',
    (t) async {
      final f = ScopeFixture();
      addTearDown(f.close);
      await f.scope.selectAssignedStore(
        f.scope.groups.first,
        f.scope.storesFor('g1').first,
      );
      await f.local.saveDraft('preview', 's1', 'group-member:g1:new', {
        'values': {
          'email': 'pending@example.test',
          'role': 'salesperson',
          'store:s2': 'yes',
          'active': 'yes',
        },
      });
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
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('field.email')))
            .controller!
            .text,
        'pending@example.test',
      );
      expect(
        t
            .widgetList<RadioListTile<String>>(
              find.byType(RadioListTile<String>),
            )
            .where(
              (w) =>
                  w.value ==
                  t
                      .widget<RadioGroup<String>>(
                        find.byType(RadioGroup<String>),
                      )
                      .groupValue,
            )
            .single
            .title,
        isA<Text>().having((w) => w.data, 'store', 'Magasin Sousse'),
      );
      final copied = await f.local.draft('preview', '', 'group-member:g1:new');
      expect(copied!['values']['storeIds'], '["s2"]');
      expect(
        await f.local.draft('preview', 's1', 'group-member:g1:new'),
        isEmpty,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets('pasted recovery code returns to login at text scale $scale', (
      t,
    ) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = RecoveryApi();
      final vm = SessionViewModel(api, const FlutterSecureStorage());
      addTearDown(vm.dispose);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            theme: appTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const LoginScreen(),
          ),
        ),
      );
      await t.ensureVisible(find.text('Mot de passe oublié ?'));
      await t.pumpAndSettle();
      await t.tap(find.text('Mot de passe oublié ?'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('auth.email')),
        'test@example.test',
      );
      await t.tap(find.text('Recevoir un code'));
      await t.pumpAndSettle();
      expect(find.text('Code de récupération'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('auth.token')), 'ab12-cd34');
      await t.enterText(
        find.byKey(const ValueKey('auth.password')),
        'a-new-password-2026',
      );
      await t.tap(find.text('Confirmer'));
      await t.pumpAndSettle();
      expect(api.received, 'AB12CD34');
      expect(find.byType(AccountActionScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('failed reset retains input for correction', (t) async {
    final api = RecoveryApi()..fail = true;
    final vm = SessionViewModel(api, const FlutterSecureStorage());
    addTearDown(vm.dispose);
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: vm,
        child: MaterialApp(
          theme: appTheme(),
          home: const AccountActionScreen(mode: 'reset'),
        ),
      ),
    );
    await t.enterText(find.byKey(const ValueKey('auth.token')), 'AB12CD34');
    await t.enterText(
      find.byKey(const ValueKey('auth.password')),
      'a-new-password-2026',
    );
    await t.tap(find.text('Confirmer'));
    await t.pumpAndSettle();
    expect(find.byType(AccountActionScreen), findsOneWidget);
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('auth.password')))
          .controller!
          .text,
      'a-new-password-2026',
    );
    expect(find.text('Code invalide ou expiré.'), findsOneWidget);
  });
  testWidgets('Android Back closes the inner route without exiting', (t) async {
    final f = ScopeFixture();
    addTearDown(f.close);
    await t.pumpWidget(
      ChangeNotifierProvider<WorkspaceViewModel>.value(
        value: f.workspace,
        child: MaterialApp(theme: appTheme(), home: const WorkspaceNavigator()),
      ),
    );
    await t.pumpAndSettle();
    Navigator.of(t.element(find.byType(ScopeScreen))).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Détail protégé')),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Détail protégé'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Détail protégé'), findsNothing);
    expect(find.byType(ScopeScreen), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  test(
    'administrator returns directly without replaying tab history',
    () async {
      final f = ScopeFixture();
      addTearDown(f.close);
      await f.scope.selectGroup(f.scope.groups.first);
      f.scope.setTab(1);
      await f.scope.selectStore(f.scope.stores.first);
      f.scope.setTab(1);
      f.scope.setTab(2);
      await f.scope.returnToAdministration();
      expect(f.scope.scope.group, isNull);
      expect(f.scope.scope.store, isNull);
      expect(f.scope.canGoBack, false);
      f.scope.dispose();
    },
  );
  test(
    'direct administration return preserves scope when draft saving fails',
    () async {
      final f = ScopeFixture();
      addTearDown(f.close);
      await f.scope.selectGroup(f.scope.groups.first);
      final release = f.workspace.registerDraft(() async {
        throw const AppFailure('STORAGE_FULL', 'Stockage plein');
      });
      await expectLater(
        f.scope.returnToAdministration(),
        throwsA(isA<AppFailure>()),
      );
      expect(f.scope.scope.group!.id, 'g1');
      expect(f.scope.canGoBack, true);
      release();
      await f.scope.returnToAdministration();
      expect(f.scope.scope.group, isNull);
      f.scope.dispose();
    },
  );
  testWidgets(
    'order filters stay on one horizontal row and all remain reachable',
    (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      OrderSection? chosen;
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: OrderSections(
              selected: OrderSection.all,
              admin: true,
              onChanged: (v) => chosen = v,
            ),
          ),
        ),
      );
      final y = t.getCenter(find.byKey(const ValueKey('orders.all'))).dy;
      for (final section in OrderSection.values) {
        expect(
          t.getCenter(find.byKey(ValueKey('orders.${section.name}'))).dy,
          y,
        );
      }
      await t.ensureVisible(find.byKey(const ValueKey('orders.complete')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('orders.complete')));
      expect(chosen, OrderSection.complete);
      expect(t.takeException(), isNull);
    },
  );
  test('Back restores the preceding tab and scope', () async {
    final f = ScopeFixture();
    addTearDown(f.close);
    await f.scope.selectGroup(f.scope.groups.first);
    f.scope.setTab(1);
    await f.scope.selectStore(f.scope.stores.first);
    f.scope.setTab(2);
    await f.scope.back();
    expect(f.scope.scope.store!.id, 's1');
    expect(f.scope.tab, 0);
    await f.scope.back();
    expect(f.scope.scope.store, isNull);
    expect(f.scope.scope.group!.id, 'g1');
    expect(f.scope.tab, 1);
    await f.scope.back();
    expect(f.scope.tab, 0);
    await f.scope.back();
    expect(f.scope.scope.group, isNull);
    expect(f.scope.canGoBack, false);
    f.scope.dispose();
  });
}
