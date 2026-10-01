import 'dart:async';

import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/api/generated/models.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/features/stores/stores_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_test.dart' show MemoryDraftRepository;

const user = UserAccount(
  id: 'manager',
  name: 'Responsable',
  email: 'manager@example.test',
  admin: false,
);
final store = Store.fromJson({
  'id': 'store',
  'organizationId': 'org',
  'name': 'Pharmacie Tunis',
  'permissions': ['manage'],
  'version': 1,
});

Map<String, dynamic> progress({bool alone = false, bool noStock = false}) => {
  'profile': true,
  'team': alone,
  'stock': noStock,
  'products': false,
  'workingAlone': alone,
  'noOpeningStock': noStock,
  'carriedCount': 0,
  'incompleteProducts': <String>[],
  'completedCount': 1 + (alone ? 1 : 0) + (noStock ? 1 : 0),
  'complete': false,
};

WorkspaceOnboardingResponseDto answer(
  int version, {
  bool alone = false,
  bool noStock = false,
}) => WorkspaceOnboardingResponseDto.fromJson({
  'store': {
    'id': 'store',
    'organizationId': 'org',
    'name': 'Pharmacie Tunis',
    'nature': 'pharmacie',
    'address': 'Adresse',
    'city': 'Tunis',
    'phone': null,
    'imageId': null,
    'timezone': 'Africa/Tunis',
    'onboardingStep': 3,
    'workingAlone': alone,
    'noOpeningStock': noStock,
    'openingClosedAt': noStock ? '2026-10-01T10:00:00.000Z' : null,
    'version': version,
    'createdAt': '2026-10-01T09:00:00.000Z',
  },
  'onboarding': progress(alone: alone, noStock: noStock),
});

/// A workspace that never goes to the network: only the checkbox logic is tested.
class QuietWorkspace extends WorkspaceViewModel {
  QuietWorkspace(super.user, super.repository, super.api);
  int syncs = 0;
  @override
  Future<void> synchronize({bool silent = false}) async => syncs++;
}

class FakeApi extends ApiClient {
  FakeApi() : super(baseUrl: 'http://test');
  final calls = <Map<String, dynamic>>[];
  final replies = <Completer<WorkspaceOnboardingResponseDto>>[];
  @override
  Future<WorkspaceOnboardingResponseDto> workspaceOnboarding({
    required String store,
    required String organizationId,
    required WorkspaceOnboardingRequestDto body,
  }) {
    calls.add(body.toJson());
    final reply = Completer<WorkspaceOnboardingResponseDto>();
    replies.add(reply);
    return reply.future;
  }
}

Future<(FakeApi, QuietWorkspace)> pump(WidgetTester t) async {
  final db = AppDatabase(NativeDatabase.memory()), api = FakeApi();
  api.authenticate('token', accountId: user.id);
  final vm = QuietWorkspace(user, MemoryDraftRepository(db, api), api);
  vm.state = WorkspaceState(
    store: store,
    stores: [store],
    data: StoreData({
      'onboarding': progress(),
      'store': {'version': 1},
      'products': const [],
    }),
  );
  await t.pumpWidget(
    ChangeNotifierProvider.value(
      value: vm,
      child: MaterialApp(home: OnboardingScreen(vm: vm)),
    ),
  );
  await t.pumpAndSettle();
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    vm.dispose();
    await db.close();
  });
  return (api, vm);
}

Finder box(String label) => find.widgetWithText(CheckboxListTile, label);
bool checked(WidgetTester t, String label) =>
    t.widget<CheckboxListTile>(box(label)).value == true;

void main() {
  testWidgets('a box ticks at once, without waiting for the server', (t) async {
    final (api, _) = await pump(t);
    await t.ensureVisible(box('Je travaille seul pour le moment'));
    await t.tap(box('Je travaille seul pour le moment'));
    await t.pump();
    // Ticked immediately, the request still in flight.
    expect(checked(t, 'Je travaille seul pour le moment'), isTrue);
    expect(api.calls.single['workingAlone'], true);
    expect(api.calls.single['expectedVersion'], 1);
    api.replies[0].complete(answer(2, alone: true));
    await t.pumpAndSettle();
    expect(checked(t, 'Je travaille seul pour le moment'), isTrue);
  });

  testWidgets(
    '"no stock" can be unticked, and a second tick uses the new version',
    (t) async {
      final (api, _) = await pump(t);
      const label = 'Je n’ai pas de stock de départ';
      await t.ensureVisible(box(label));
      await t.tap(box(label));
      await t.pump();
      api.replies[0].complete(answer(2, noStock: true));
      await t.pumpAndSettle();
      expect(checked(t, label), isTrue);
      // Tick it back off.
      await t.tap(box(label));
      await t.pump();
      expect(checked(t, label), isFalse);
      expect(api.calls[1]['noOpeningStock'], false);
      // The version comes from the server's last answer, not from a stale cache.
      expect(api.calls[1]['expectedVersion'], 2);
      api.replies[1].complete(answer(3));
      await t.pumpAndSettle();
      expect(checked(t, label), isFalse);
    },
  );

  testWidgets('two quick ticks are sent in order, one request at a time', (
    t,
  ) async {
    final (api, _) = await pump(t);
    await t.ensureVisible(box('Je travaille seul pour le moment'));
    await t.tap(box('Je travaille seul pour le moment'));
    await t.tap(box('Je n’ai pas de stock de départ'));
    await t.pump();
    expect(checked(t, 'Je travaille seul pour le moment'), isTrue);
    expect(checked(t, 'Je n’ai pas de stock de départ'), isTrue);
    // Only the first is out; the second waits for it, then uses its version.
    expect(api.calls.length, 1);
    api.replies[0].complete(answer(2, alone: true));
    await t.pumpAndSettle();
    expect(api.calls.length, 2);
    expect(api.calls[1]['expectedVersion'], 2);
    api.replies[1].complete(answer(3, alone: true, noStock: true));
    await t.pumpAndSettle();
    expect(checked(t, 'Je travaille seul pour le moment'), isTrue);
    expect(checked(t, 'Je n’ai pas de stock de départ'), isTrue);
  });

  testWidgets('a refused change puts the box back and says why', (t) async {
    final (api, _) = await pump(t);
    const label = 'Je n’ai pas de stock de départ';
    await t.ensureVisible(box(label));
    await t.tap(box(label));
    await t.pump();
    expect(checked(t, label), isTrue);
    api.replies[0].completeError(StateError('Le magasin a été modifié.'));
    await t.pumpAndSettle();
    expect(checked(t, label), isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
