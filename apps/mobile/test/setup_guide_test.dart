import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/features/workspace/setup_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Store store(String name, {bool closed = false, int step = 1}) =>
    Store.fromJson({
      'id': name,
      'organizationId': 'org',
      'name': name,
      'city': 'Tunis',
      'nature': 'pharmacie',
      'permissions': ['manage'],
      'onboardingStep': step,
      if (closed) 'openingClosedAt': '2026-10-01T10:00:00.000Z',
    });

class Fake {
  bool group = false;
  final stores = <Store>[];
  final calls = <String>[];
  late final actions = SetupGuideActions(
    hasGroup: () => group,
    groupName: () => 'Parahouse',
    stores: () => List.of(stores),
    createGroup: () async {
      calls.add('createGroup');
      group = true;
    },
    addStore: () async {
      calls.add('addStore');
      stores.add(store('Marsa'));
    },
    inviteTeam: () async => calls.add('inviteTeam'),
    enterStock: (s) async => calls.add('enterStock:${s.name}'),
    noStock: (s) async {
      calls.add('noStock:${s.name}');
      stores[0] = store(s.name, closed: true);
    },
    setPrices: (s) async => calls.add('setPrices:${s.name}'),
  );
}

Future<void> pump(
  WidgetTester t,
  Fake fake,
  SetupGuideModel model,
  VoidCallback onFinish,
) => t.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SetupGuidePage(
        model: model,
        actions: fake.actions,
        onFinish: onFinish,
      ),
    ),
  ),
);

Finder next() => find.byKey(const ValueKey('guide.next'));
bool nextEnabled(WidgetTester t) =>
    t.widget<FilledButton>(next()).onPressed != null;

void main() {
  testWidgets('a new responsable is guided from the group to the last step', (
    t,
  ) async {
    final fake = Fake();
    final saved = <String>[];
    var finished = false;
    final model = SetupGuideModel(
      save: (v) async => saved.add('${v['step']}'),
      describe: (e) => '$e',
    );
    await pump(t, fake, model, () => finished = true);

    // Welcome lists what is coming.
    expect(find.text('Étape 1 sur 7'), findsOneWidget);
    expect(find.text('Créer votre groupe'), findsOneWidget);
    await t.tap(next());
    await t.pumpAndSettle();

    // The group is required before going on.
    expect(find.text('Votre groupe'), findsWidgets);
    expect(nextEnabled(t), isFalse);
    await t.tap(find.text('Créer mon groupe'));
    await t.pumpAndSettle();

    // Creating it moves straight to the stores, which are required too.
    expect(fake.calls, ['createGroup']);
    expect(find.text('Vos magasins'), findsWidgets);
    expect(nextEnabled(t), isFalse);
    await t.tap(find.text('Ajouter mon premier magasin'));
    await t.pumpAndSettle();
    expect(find.text('Marsa'), findsOneWidget);
    expect(nextEnabled(t), isTrue);
    await t.tap(next());
    await t.pumpAndSettle();

    // Team: optional, can be skipped.
    expect(find.text('Votre équipe'), findsWidgets);
    expect(nextEnabled(t), isTrue);
    await t.tap(find.text('Inviter quelqu’un'));
    await t.pumpAndSettle();
    expect(fake.calls.last, 'inviteTeam');
    await t.tap(next());
    await t.pumpAndSettle();

    // Starting stock, once per store.
    expect(find.text('Votre stock de départ'), findsWidgets);
    expect(find.text('Avez-vous déjà du stock ?'), findsOneWidget);
    await t.tap(find.text('Non, je commande'));
    await t.pumpAndSettle();
    expect(fake.calls.last, 'noStock:Marsa');
    expect(find.text('Stock de départ déclaré'), findsOneWidget);
    await t.tap(next());
    await t.pumpAndSettle();

    // Prices, then the end.
    expect(find.text('Vos prix de vente'), findsWidgets);
    await t.tap(find.text('Fixer mes prix'));
    await t.pumpAndSettle();
    expect(fake.calls.last, 'setPrices:Marsa');
    await t.tap(next());
    await t.pumpAndSettle();
    expect(find.text('C’est prêt'), findsWidgets);
    expect(find.text('Passer le guide'), findsNothing);
    await t.tap(find.text('Ouvrir mon espace'));
    expect(finished, isTrue);
    // Progress was kept at each step.
    expect(
      saved,
      containsAll(['group', 'stores', 'team', 'stock', 'prices', 'done']),
    );
  });

  testWidgets('the guide can be left at any time, and Retour goes back', (
    t,
  ) async {
    final fake = Fake()..group = true;
    var finished = false;
    final model = SetupGuideModel(
      save: (_) async {},
      describe: (e) => '$e',
      start: GuideStep.stores,
    );
    await pump(t, fake, model, () => finished = true);
    await t.tap(find.text('Retour'));
    await t.pumpAndSettle();
    expect(model.step, GuideStep.group);
    await t.tap(find.text('Passer le guide'));
    expect(finished, isTrue);
  });

  testWidgets('a failed action shows its message and stays on the step', (
    t,
  ) async {
    final fake = Fake();
    final failing = SetupGuideActions(
      hasGroup: () => false,
      groupName: () => null,
      stores: () => const [],
      createGroup: () async => throw StateError('Réseau indisponible'),
      addStore: fake.actions.addStore,
      inviteTeam: fake.actions.inviteTeam,
      enterStock: fake.actions.enterStock,
      noStock: fake.actions.noStock,
      setPrices: fake.actions.setPrices,
    );
    final model = SetupGuideModel(
      save: (_) async {},
      describe: (e) => 'Erreur : ${(e as StateError).message}',
      start: GuideStep.group,
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SetupGuidePage(model: model, actions: failing, onFinish: () {}),
        ),
      ),
    );
    await t.tap(find.text('Créer mon groupe'));
    await t.pumpAndSettle();
    expect(find.text('Erreur : Réseau indisponible'), findsOneWidget);
    expect(model.step, GuideStep.group);
    expect(nextEnabled(t), isFalse);
  });
}
