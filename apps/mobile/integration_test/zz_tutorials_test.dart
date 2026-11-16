// Scratch (never committed): plays the three tutorials in the real app, in French, against the
// local tutorial world, printing markers a watcher turns into screenshots and videos.
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:biobalance/app/app.dart';
import 'package:biobalance/core/api/json.dart';
import 'package:biobalance/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_flow_test.dart' show totp;

const _world = String.fromEnvironment('WORLD');
const _only = String.fromEnvironment('ONLY');
Json get world => jsonDecode(utf8.decode(base64Decode(_world))) as Json;
final t = lookupAppLocalizations(const Locale('fr'));

/// The page's vertical scrollables (a photo strip scrolls sideways and must not be the one dragged).
final vertical = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axis == Axis.vertical,
);

Future<void> wait(WidgetTester tester, [int ms = 1200]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> until(
  WidgetTester tester,
  Finder finder, {
  int seconds = 25,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    try {
      if (finder.evaluate().isNotEmpty) return;
    } on RangeError {
      // `.at(n)` of a list that has not grown that far yet.
    }
  }
  final onScreen = tester
      .widgetList<Text>(find.byType(Text))
      .map((x) => x.data)
      .whereType<String>()
      .take(60)
      .join(' | ');
  throw TestFailure('Timed out waiting for $finder. On screen: $onScreen');
}

/// A screenshot by the watcher: the screen is left still for a moment.
Future<void> shot(WidgetTester tester, String name) async {
  await wait(tester, 700);
  print('@@SHOT $name');
  await wait(tester, 1500);
}

bool canHit(Finder f) {
  try {
    return f.hitTestable().evaluate().isNotEmpty;
  } on Object {
    return false;
  }
}

Future<void> scrollDown(WidgetTester tester) async {
  try {
    final pages = vertical.evaluate().toList();
    if (pages.isEmpty) return;
    final last = pages.last.widget;
    await tester.drag(find.byWidget(last), const Offset(0, -260));
  } on Object {
    // A page changing under the finger: the next turn tries again.
  }
}

Future<void> tap(WidgetTester tester, Finder finder, {int after = 1300}) async {
  // Scroll until it is built and on screen (a long list builds only what is near the screen).
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (!canHit(finder)) {
    if (DateTime.now().isAfter(end)) {
      await until(tester, finder, seconds: 1);
      throw TestFailure('Could not bring $finder on screen');
    }
    await scrollDown(tester);
    await wait(tester, 300);
  }
  await tester.tap(finder.hitTestable().first);
  await wait(tester, after);
}

Future<void> back(WidgetTester tester) async {
  final finder = find.byTooltip('Retour');
  await until(tester, finder);
  await tester.tap(finder.first);
  await wait(tester, 1200);
}

Future<void> tapText(WidgetTester tester, String text, {int after = 1300}) =>
    tap(tester, find.text(text), after: after);

Future<void> start(WidgetTester tester) async {
  await const FlutterSecureStorage().deleteAll();
  SharedPreferences.setMockInitialValues({});
  await (await SharedPreferences.getInstance()).clear();
  await tester.pumpWidget(
    ProviderScope(retry: (_, _) => null, child: const BioBalanceApp()),
  );
  await wait(tester, 2000);
}

Json account(String role, [String? name]) => world
    .list('people')
    .firstWhere(
      (p) => p.str('role') == role && (name == null || p.str('name') == name),
    );

Future<void> signIn(WidgetTester tester, String role, [String? name]) async {
  await until(tester, find.text(t.signIn));
  await tester.enterText(
    find.byType(TextFormField).at(0),
    account(role, name).str('email'),
  );
  await tester.enterText(
    find.byType(TextFormField).at(1),
    world.str('password'),
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await wait(tester, 500);
  await tester.tap(find.text(t.signIn).last);
  if (role == 'ADMIN') {
    await until(tester, find.byType(TextFormField).at(2));
    await tester.enterText(
      find.byType(TextFormField).at(2),
      totp(world.str('adminSecret')),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await wait(tester, 500);
    await tester.tap(find.text(t.signIn).last);
  }
  await until(tester, find.byTooltip(t.settingsTitle));
  await wait(tester, 2500);
}

Future<void> signOut(WidgetTester tester) async {
  for (
    var i = 0;
    i < 3 && find.byTooltip(t.settingsTitle).evaluate().isEmpty;
    i++
  ) {
    if (find.byTooltip('Retour').evaluate().isNotEmpty) {
      await back(tester);
    } else {
      final home = find.bySemanticsLabel(RegExp('^${t.tabHome}'));
      await tester.tap(home.first);
      await wait(tester, 1500);
    }
  }
  await tester.tap(find.byTooltip(t.settingsTitle).first);
  await until(tester, vertical);
  for (var i = 0; i < 12 && !canHit(find.text(t.signOut)); i++) {
    await scrollDown(tester);
    await wait(tester, 400);
  }
  await tester.tap(find.text(t.signOut).last);
  await wait(tester, 1200);
  await until(tester, find.text(t.signOutTitle));
  await tester.tap(find.text(t.signOut).last);
  await until(tester, find.text(t.signIn));
  await wait(tester, 800);
}

void tutorial(String name, Future<void> Function(WidgetTester) body) {
  if (_only.isNotEmpty && _only != name) return;
  testWidgets(name, (tester) async {
    await start(tester);
    print('@@REC start $name');
    await wait(tester, 1500);
    try {
      await body(tester);
    } finally {
      await wait(tester, 1500);
      print('@@REC stop');
      await wait(tester, 2500);
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}

/// A take for the guides: signs in first (off the video), leaves time to answer the phone's own
/// questions, grants the position, then records only the guide itself.
void clean(String name, String role, String who, Future<void> Function(WidgetTester) body) {
  if (_only != name) return;
  testWidgets(name, (tester) async {
    await start(tester);
    await signIn(tester, role, who);
    print('@@PROMPTS');
    await wait(tester, 20000);
    print('@@GRANT');
    await wait(tester, 4000);
    print('@@REC start $name');
    await wait(tester, 2500);
    try {
      await body(tester);
    } finally {
      await wait(tester, 2500);
      print('@@REC stop');
      await wait(tester, 2500);
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();


  clean('planning2', 'RESPONSABLE', 'Nora Ben Salah', (tester) async {
    await shot(tester, 'p-01-accueil');
    await tapText(tester, t.moreTitle, after: 1800);
    await shot(tester, 'p-02-plus');
    await tapText(tester, t.planningTitle, after: 2000);
    await shot(tester, 'p-03-planning');
    await tapText(tester, t.planningPlanVisit, after: 1800);
    await shot(tester, 'p-04-formulaire');
    await tapText(tester, t.visitChoosePlace, after: 1800);
    await shot(tester, 'p-05-choisir-lieu');
    await tap(tester, find.textContaining('Para Lac'), after: 1800);
    await tapText(tester, t.visitKindCount, after: 1800);
    await shot(tester, 'p-06-formulaire-rempli');
    await tapText(tester, t.save, after: 2800);
    await shot(tester, 'p-07-visite-planifiee');
    await tap(tester, find.textContaining('Para Lac').first, after: 2000);
    await shot(tester, 'p-08-visite');
    await tapText(tester, t.visitCheckIn, after: 500);
    await until(tester, find.textContaining('Arrivé à'), seconds: 40);
    await wait(tester, 4000);
    await shot(tester, 'p-09-position-enregistree');
    await tester.drag(vertical.last, const Offset(0, -420));
    await wait(tester, 3500);
    await shot(tester, 'p-10-carte');
    await tester.drag(vertical.last, const Offset(0, 420));
    await wait(tester, 1500);
    await tapText(tester, t.visitCheckOut, after: 500);
    await until(tester, find.textContaining('Parti à'), seconds: 40);
    await wait(tester, 3500);
    await tester.drag(vertical.last, const Offset(0, -700));
    await wait(tester, 2500);
    await shot(tester, 'p-11-depart');
    await back(tester);
    await wait(tester, 2500);
    await shot(tester, 'p-12-planning-fin');
  });

  tutorial('planning', (tester) async {
    await signIn(tester, 'RESPONSABLE', 'Nora Ben Salah');
    await shot(tester, 'planning-01-accueil');
    await tapText(tester, t.moreTitle);
    await shot(tester, 'planning-02-plus');
    await tapText(tester, t.planningTitle);
    await shot(tester, 'planning-03-planning-vide');
    await tapText(tester, t.planningPlanVisit);
    await shot(tester, 'planning-04-formulaire');
    await tapText(tester, t.visitChoosePlace);
    await shot(tester, 'planning-05-choisir-lieu');
    await tap(tester, find.textContaining('Para Lac'));
    await tapText(tester, t.visitKindCount);
    await shot(tester, 'planning-06-formulaire-rempli');
    await tapText(tester, t.save, after: 2500);
    await shot(tester, 'planning-07-visite-planifiee');
    await tap(tester, find.textContaining('Para Lac').first);
    await shot(tester, 'planning-08-visite');
    await tapText(tester, t.visitCheckIn, after: 500);
    await until(tester, find.textContaining('Arrivé à'), seconds: 40);
    // The simulator's position counts as a faked one: the watcher takes that mark off (test data).
    print('@@SQL');
    await wait(tester, 2500);
    await back(tester);
    await wait(tester, 1500);
    await tap(tester, find.textContaining('Para Lac').first, after: 4500);
    await shot(tester, 'planning-09-position-enregistree');
    await tester.drag(vertical.last, const Offset(0, -420));
    await wait(tester, 3000);
    await shot(tester, 'planning-10-carte');
    await back(tester);
    await wait(tester);
    await back(tester);
    await wait(tester);
    await tapText(tester, t.tabHome);
    await signOut(tester);

    // The admin reads it.
    await signIn(tester, 'ADMIN');
    await tapText(tester, t.moreTitle);
    await shot(tester, 'planning-11-admin-plus');
    await tapText(tester, t.planningOverviewTitle, after: 2500);
    await shot(tester, 'planning-12-admin-vue');
    await tap(tester, find.textContaining('Nora Ben Salah').first, after: 2500);
    await shot(tester, 'planning-13-admin-visites');
    await tap(tester, find.textContaining('Para Lac').first, after: 4500);
    await shot(tester, 'planning-14-admin-visite');
    await tapText(tester, t.placePositionUse);
    await shot(tester, 'planning-15-admin-confirmer');
    await tester.tap(find.text(t.placePositionUse).last);
    await wait(tester, 4500);
    await shot(tester, 'planning-16-admin-position-du-lieu');
  });

  tutorial('reassort', (tester) async {
    await signIn(tester, 'RESPONSABLE', 'Nora Ben Salah');
    await shot(tester, 'reassort-01-accueil-responsable');
    await tapText(tester, t.tabRestocks);
    await shot(tester, 'reassort-02-liste');
    await tapText(tester, t.requestRestock);
    await shot(tester, 'reassort-03-formulaire');
    // The place: the only one in the list is Para Lac.
    if (find.textContaining('Para Lac').evaluate().isEmpty) {
      await tapText(tester, t.deliverTo);
      await shot(tester, 'reassort-03b-choisir-para');
      await tap(tester, find.textContaining('Para Lac').last);
    }
    await tapText(tester, t.addProduct);
    await shot(tester, 'reassort-04-choisir-produits');
    for (final name in [
      'Sérum Vitamine C',
      'Sérum Niacinamide',
      'Shampoing Argan',
    ]) {
      await tap(tester, find.textContaining(name).first, after: 600);
    }
    await shot(tester, 'reassort-05-produits-choisis');
    await tap(tester, find.textContaining('Ajouter 3'));
    await shot(tester, 'reassort-06-quantites-par-defaut');
    // 12, 8 and 6 units, from the top of the list down.
    for (final (i, q) in [(0, '12'), (1, '8'), (2, '6')]) {
      final ones = find.text('1');
      await tester.tap(ones.at(0));
      await wait(tester, 700);
      await tester.enterText(find.byType(TextField).last, q);
      await tester.tap(find.text(t.confirm).last);
      await wait(tester, 900);
      print('quantity row $i set to $q');
    }
    await shot(tester, 'reassort-07-quantites-saisies');
    await tapText(tester, t.sendRequest, after: 2500);
    await shot(tester, 'reassort-08-demande-envoyee');
    await signOut(tester);

    await signIn(tester, 'ADMIN');
    await tapText(tester, t.tabRestocks);
    await shot(tester, 'reassort-09-admin-liste');
    await tap(tester, find.textContaining('Para Lac').first, after: 2500);
    await shot(tester, 'reassort-10-admin-demande');
    await tapText(tester, t.changeQuantities);
    await shot(tester, 'reassort-11-admin-modifier');
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.bySemanticsLabel(t.decrease).first);
      await wait(tester, 500);
    }
    await shot(tester, 'reassort-12-admin-quantite-changee');
    await tester.tap(find.text(t.confirm).last);
    await wait(tester, 1200);
    await tester.enterText(
      find.byType(TextField).last,
      'Stock limité chez le grossiste',
    );
    await wait(tester, 600);
    await shot(tester, 'reassort-13-admin-motif');
    await tapText(tester, t.save, after: 2500);
    await shot(tester, 'reassort-14-admin-historique');
    await tapText(tester, t.sendFromBiobalance, after: 2500);
    await shot(tester, 'reassort-15-admin-en-route');
    await signOut(tester);

    await signIn(tester, 'RESPONSABLE', 'Nora Ben Salah');
    await tapText(tester, t.tabRestocks);
    await tap(tester, find.textContaining('Para Lac').first, after: 2500);
    await shot(tester, 'reassort-16-en-route');
    await tapText(tester, t.confirmDelivery);
    await shot(tester, 'reassort-17-envoyer-le-bon');
    await tap(tester, find.textContaining('photo ou PDF').first);
    await shot(tester, 'reassort-18-choisir-la-photo');
    await tapText(tester, t.photoChoose, after: 500);
    // The iOS photo picker is native: the bon de livraison is chosen by hand in the simulator.
    print('@@PICKER');
    await until(tester, find.textContaining('1 sur 5'), seconds: 180);
    await wait(tester, 1500);
    await shot(tester, 'reassort-19-bon-ajoute');
    await tapText(tester, t.sendToAdmin, after: 3000);
    await shot(tester, 'reassort-20-bon-envoye');
    await signOut(tester);

    await signIn(tester, 'ADMIN');
    await tapText(tester, t.tabRestocks);
    await tap(tester, find.textContaining('Para Lac').first, after: 2500);
    await shot(tester, 'reassort-21-admin-bon-a-verifier');
    await tapText(tester, t.completeDelivery);
    await shot(tester, 'reassort-22-admin-quantites-recues');
    await tester.tap(find.text(t.confirm).last);
    await wait(tester, 3000);
    await shot(tester, 'reassort-23-admin-livre');
    await tapText(tester, t.tabRestocks);
    await shot(tester, 'reassort-24-admin-liste-finale');
  });

  tutorial('reassort_fin', (tester) async {
    await signIn(tester, 'ADMIN');
    await tapText(tester, t.tabRestocks);
    await tapText(tester, 'Terminés');
    await shot(tester, 'reassort-24-admin-termines');
    await tap(tester, find.textContaining('Para Lac').first, after: 2500);
    await shot(tester, 'reassort-25-admin-livre');
  });

  tutorial('transfert', (tester) async {
    await signIn(tester, 'VENDEUR', 'Amira Trabelsi');
    await shot(tester, 'transfert-01-accueil-vendeuse');
    await tapText(tester, t.transferExchange);
    await shot(tester, 'transfert-02-liste-vide');
    await tapText(tester, t.transferNew);
    await shot(tester, 'transfert-03-formulaire');
    await tapText(tester, t.transferChoosePara);
    await shot(tester, 'transfert-04-choisir-para');
    await tap(tester, find.textContaining('Para Carthage').first);
    await tapText(tester, t.addProduct);
    for (final name in ['Sérum Vitamine C', 'Sérum Niacinamide']) {
      await tap(tester, find.textContaining(name).first, after: 600);
    }
    await tap(tester, find.textContaining('Ajouter 2'));
    for (final q in ['3', '2']) {
      await tester.tap(find.text('1').at(0));
      await wait(tester, 700);
      await tester.enterText(find.byType(TextField).last, q);
      await tester.tap(find.text(t.confirm).last);
      await wait(tester, 900);
    }
    await shot(tester, 'transfert-05-produits');
    await tap(tester, find.textContaining('preuve').first);
    await shot(tester, 'transfert-06-photo');
    await tapText(tester, t.photoChoose, after: 500);
    print('@@PICKER');
    await until(tester, find.text('Photo prête'), seconds: 180);
    await wait(tester, 1500);
    await shot(tester, 'transfert-07-photo-ajoutee');
    await tapText(tester, t.transferSubmit, after: 3000);
    await shot(tester, 'transfert-08-envoye');
    await signOut(tester);

    await signIn(tester, 'ADMIN');
    await tapText(tester, t.tabApprovals);
    await tester.enterText(find.byType(TextField).first, 'Carthage');
    FocusManager.instance.primaryFocus?.unfocus();
    await wait(tester, 1500);
    await shot(tester, 'transfert-09-admin-validations');
    await tap(tester, find.textContaining('→').first, after: 2500);
    await shot(tester, 'transfert-10-admin-demande');
    await tapText(tester, t.transferApprove, after: 3000);
    await shot(tester, 'transfert-11-admin-approuve');
    await back(tester);
    await tapText(tester, 'Historique', after: 2000);
    await shot(tester, 'transfert-12-admin-historique');
  });
}
