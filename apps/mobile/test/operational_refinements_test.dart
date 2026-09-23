import 'package:biobalance/data/repositories/group_repository.dart';
import 'package:biobalance/data/repositories/notifications_repository.dart';
import 'package:biobalance/data/repositories/repository_context.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/features/notifications/notifications_view_model.dart';
import 'package:biobalance/ui/features/workspace/lifecycle_view_model.dart';
import 'package:biobalance/ui/features/workspace/lifecycle_screen.dart';
import 'package:flutter/material.dart';
import 'package:biobalance/ui/features/inventory/inventory_screens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test.dart';

class LifecycleRepository extends GroupRepository {
  LifecycleRepository(super.context, super.local, super.accountId);
  Json? submitted;
  @override
  Future<Json> lifecycleImpact(String id, {String? storeId}) async => {
    'orders': 2,
    'deliveries': 1,
    'issues': 1,
    'rewards': 1,
    'stockLots': 5,
  };
  @override
  Future<void> lifecycle(String id, Json body, {String? storeId}) async {
    submitted = body;
  }
}

class FeedRepository extends NotificationsRepository {
  FeedRepository(super.context);
  int calls = 0;
  String key = 'first';
  bool more = false;
  @override
  Future<Json> page({String? cursor}) async {
    calls++;
    return {
      'items': key == 'revoked'
          ? []
          : [
              {'id': cursor == null ? 'a' : 'b', 'readAt': null},
            ],
      'unreadCount': key == 'revoked' ? 0 : 120,
      'accessKey': key,
      'nextCursor': cursor == null ? 'next' : null,
    };
  }
}

void main() {
  testWidgets(
    'shared feed counts all unread, deduplicates pages and removes revoked cached entries',
    (t) async {
      final api = PreviewApi(),
          repository = FeedRepository(RepositoryContext(PreviewApi()));
      final vm = NotificationsViewModel(repository)..setActive(true);
      await t.pump();
      expect(vm.unreadCount, 120);
      await vm.load(more: true);
      expect(vm.items.map((n) => n['id']), ['a', 'b']);
      await vm.load();
      expect(vm.items.map((n) => n['id']), ['a', 'b']);
      repository.key = 'revoked';
      await vm.load();
      expect(vm.items, isEmpty);
      expect(vm.unreadCount, 0);
      vm.setActive(false);
      final calls = repository.calls;
      await t.pump(const Duration(minutes: 1));
      expect(repository.calls, calls);
      vm.dispose();
      api.http.close();
      repository.context.api.http.close();
    },
  );
  testWidgets(
    'receipt conditions and lifecycle screens have readable phone layouts',
    (t) async {
      viewport(t, const Size(360, 800));
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
      await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
            rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
          ))
          .load();
      final f = RoleFixture('admin');
      final key = GlobalKey();
      final repository = LifecycleRepository(
        f.vm.repositoryContext,
        f.vm.repository,
        f.vm.user.id,
      );
      await t.pumpWidget(
        f.app(
          LifecycleScreen(
            model: LifecycleViewModel(
              repository,
              groupId: 'org',
              version: 1,
              initialStatus: 'active',
            ),
            name: 'Parahouse',
          ),
          capture: key,
        ),
      );
      await t.pumpAndSettle();
      await screenshot(t, key, 'refinement-lifecycle');
      await t.pumpWidget(const SizedBox());
      await f.vm.repository.saveDraft(
        f.vm.user.id,
        f.vm.state.store!.id,
        'receipt:delivery',
        {
          'lines': [
            {
              'productId': 'p',
              'batch': 'BB-2026',
              'expiry': '2028-12-31',
              'quantity': 6,
              'condition': 'sellable',
            },
            {
              'productId': 'p',
              'batch': 'BB-2026',
              'expiry': '2028-12-31',
              'quantity': 2,
              'condition': 'damaged',
            },
          ],
          'note': 'Deux emballages abîmés à la réception',
        },
      );
      await t.pumpWidget(
        f.app(
          ReceiptScreen(
            vm: f.vm,
            delivery: {
              'id': 'delivery',
              'version': 1,
              'lines': [
                {'productId': 'p', 'quantity': 10},
              ],
            },
          ),
          capture: key,
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Confirmer la réception'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await screenshot(t, key, 'refinement-receipt');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await f.close();
    },
  );
  for (final dimensions in [const Size(360, 800), const Size(800, 360)]) {
    testWidgets(
      'lifecycle impact and required reason remain usable at 200 percent $dimensions',
      (t) async {
        viewport(t, dimensions);
        final f = RoleFixture('admin');
        final repository = LifecycleRepository(
          f.vm.repositoryContext,
          f.vm.repository,
          f.vm.user.id,
        );
        final model = LifecycleViewModel(
          repository,
          groupId: 'org',
          version: 1,
          initialStatus: 'active',
        );
        await t.pumpWidget(
          f.app(
            LifecycleScreen(
              model: model,
              name: 'Groupe de test et ses trois magasins',
            ),
            scale: 2,
          ),
        );
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.text('Commandes ouvertes'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Commandes ouvertes'), findsOneWidget);
        await t.scrollUntilVisible(
          find.byType(TextField),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.enterText(
          find.byType(TextField),
          'Suspension demandée pour vérification',
        );
        await t.scrollUntilVisible(
          find.text('Suspendre les accès'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await f.close();
      },
    );
  }
}
