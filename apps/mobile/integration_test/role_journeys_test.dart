import '../test/support/test_origin.dart';

import 'package:biobalance/main.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/ui/features/inventory/inventory_screens.dart';
import 'package:biobalance/ui/features/workspace/workspace_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

const base = String.fromEnvironment('API_BASE_URL');
const product = String.fromEnvironment('PRODUCT_NAME'),
    reference = String.fromEnvironment('PRODUCT_REF'),
    store = String.fromEnvironment('STORE_NAME');
const password = String.fromEnvironment('TEST_PASSWORD'),
    manager = String.fromEnvironment('MANAGER_EMAIL'),
    seller = String.fromEnvironment('SELLER_EMAIL'),
    admin = String.fromEnvironment('ADMIN_EMAIL');
final fixture = Dio(
  testOptions(
    base,
    headers: {'x-test-key': const String.fromEnvironment('TEST_KEY')},
  ),
);
Future<Map<String, dynamic>> state() async =>
    Map<String, dynamic>.from((await fixture.get('/__test/state')).data);

class Journey {
  final WidgetTester t;
  Journey(this.t);
  Finder key(String key) => find.byKey(ValueKey(key));
  Finder label(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> until(
    bool Function() condition, {
    String reason = 'UI condition',
    int seconds = 30,
  }) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!condition() && DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(condition(), isTrue, reason: reason);
  }

  Future<void> seek(Finder f) async {
    final scroll = find.byWidgetPredicate(
      (w) =>
          w is Scrollable &&
          w.restorationId != 'editable' &&
          (w.axisDirection == AxisDirection.down ||
              w.axisDirection == AxisDirection.up),
    );
    // Returning from details retains the previous scroll offset. Locate controls
    // above that offset as well as controls further down the form.
    if (f.evaluate().isEmpty && scroll.evaluate().isNotEmpty) {
      for (var i = 0; i < 12; i++) {
        final position = t.state<ScrollableState>(scroll.last).position;
        if (position.pixels <= position.minScrollExtent) break;
        await t.drag(scroll.last, const Offset(0, 600));
        await t.pumpAndSettle();
      }
    }
    for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
      if (scroll.evaluate().isEmpty) break;
      await t.drag(scroll.last, const Offset(0, -240));
      await t.pumpAndSettle();
    }
    await until(() => f.evaluate().isNotEmpty, reason: 'find $f');
    await t.ensureVisible(f.first);
    await t.pumpAndSettle();
  }

  Future<void> tap(String text) async {
    final f = find.text(text);
    await seek(f);
    await until(
      () =>
          f.evaluate().isNotEmpty && f.last.hitTestable().evaluate().isNotEmpty,
      reason: 'tap target available: $text',
    );
    await t.tap(f.last);
    await t.pumpAndSettle();
  }

  Future<void> tapKey(String id) async {
    final f = key(id);
    await seek(f);
    await until(
      () => f.hitTestable().evaluate().isNotEmpty,
      reason: 'tap target available: $id',
    );
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> dismissKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    // Native IME completion can arrive after Flutter has settled its frames.
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await until(
      () => t.view.viewInsets.bottom == 0,
      reason: 'native keyboard dismissed',
    );
    await t.pumpAndSettle();
  }

  Future<void> fill(String id, String value) async {
    final f = key(id);
    await seek(f);
    await t.enterText(f, value);
    await dismissKeyboard();
  }

  Future<void> fillLabel(String name, String value) async {
    final f = label(name);
    await seek(f);
    await t.enterText(f, value);
    await dismissKeyboard();
  }

  Future<void> chooseSaleProduct(String name) async {
    final search = find.byWidgetPredicate(
      (w) =>
          w is TextField && w.decoration?.hintText == 'Rechercher un produit',
    );
    await seek(search);
    await t.enterText(search, name);
    await dismissKeyboard();
    await tap(name);
  }

  Future<void> back() async {
    await t.pumpAndSettle();
    await until(
      () => find.byType(BackButton).evaluate().isNotEmpty,
      reason: "back button",
    );
    await t.tap(find.byType(BackButton).last);
    await t.pumpAndSettle();
  }

  Future<void> ready() async {
    await until(
      () => find
          .byType(WorkspaceScreen, skipOffstage: false)
          .evaluate()
          .isNotEmpty,
      reason: 'workspace visible',
    );
    await until(
      () {
        final c = t.element(find.byType(WorkspaceScreen, skipOffstage: false));
        final s = c.read<WorkspaceViewModel>().state;
        return !s.loading && !s.syncing;
      },
      reason: 'workspace loaded',
      seconds: 45,
    );
  }

  Future<void> login(String email) async {
    await fill('auth.email', email);
    await fill('auth.password', password);
    if (email == admin) {
      await tap('Code administrateur (MFA)');
      var info = await state();
      while (info['otp'] == null) {
        await t.pump(const Duration(seconds: 1));
        info = await state();
      }
      await fill('auth.otp', '${info['otp']}');
    }
    await tapKey('auth.login');
    await ready();
    if (email == admin && (await state())['store'] != null) {
      await tapKey('workspace.storeSelector');
      final sheet = find.byType(BottomSheet);
      await t.enterText(
        find.descendant(of: sheet, matching: find.byType(TextField)),
        store,
      );
      await dismissKeyboard();
      final choice = find.descendant(of: sheet, matching: find.text(store));
      await seek(choice);
      await t.tap(choice.last);
      await t.pumpAndSettle();
      await ready();
    }
  }

  Future<void> logout() async {
    while (find.byTooltip('Compte et aide').evaluate().isEmpty) {
      await back();
    }
    await t.tap(find.byTooltip('Compte et aide'));
    await t.pumpAndSettle();
    await tap('Se déconnecter');
    await tap('Confirmer');
    await until(
      () => key('auth.login').evaluate().isNotEmpty,
      reason: 'local logout',
    );
  }

  Future<void> activate(String code, String name) async {
    await tap('Activer mon invitation');
    await fill('auth.token', code);
    await fill('auth.name', name);
    await fill('auth.password', password);
    await tap('Confirmer');
    await until(
      () => find
          .text('Votre compte est prêt. Vous pouvez vous connecter.')
          .evaluate()
          .isNotEmpty,
      reason: 'invitation activation',
    );
    await back();
  }

  Future<void> nav(String text) async {
    // A narrow phone groups team/catalogue under Plus; large text uses Menu.
    final menu = find.byKey(const ValueKey('workspace.navigationMenu'));
    for (
      var i = 0;
      i < 5 &&
          menu.evaluate().isEmpty &&
          find.byType(NavigationBar).evaluate().isEmpty &&
          find.byType(NavigationRail).evaluate().isEmpty;
      i++
    ) {
      await back();
    }
    if (menu.evaluate().isNotEmpty) {
      await t.tap(menu);
      await t.pumpAndSettle();
      await tap(text);
      return;
    }
    final label = switch (text) {
      'Mes ventes' => 'Ventes',
      'Récompenses' => 'Cadeaux',
      'Vue d’ensemble' => 'Accueil',
      _ => text,
    };
    final f = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is NavigationBar || w is NavigationRail,
      ),
      matching: find.text(
        find.byType(NavigationRail).evaluate().isNotEmpty ? text : label,
      ),
    );
    if (f.evaluate().isEmpty && ['Équipe', 'Catalogue'].contains(text)) {
      await nav('Plus');
      await tap(text == 'Équipe' ? 'Équipe et accès' : 'Catalogue');
      return;
    }
    await t.tap(f.last);
    await t.pumpAndSettle();
  }

  Future<void> editorSave() async {
    await tapKey('editor.save');
    await until(
      () => key('editor.save').evaluate().isEmpty,
      reason: 'editor saved',
    );
    await t.pumpAndSettle();
    await ready();
  }

  Future<void> receipt(String batch, String quantity) async {
    await tap('Ajouter un produit et un lot');
    await tap(product);
    await fill('field.quantity', quantity);
    await fill('field.batch', batch);
    await fill('field.expiry', '12/2030');
    await tapKey('editor.save');
    await until(() => key('editor.save').evaluate().isEmpty);
    await tap('Confirmer la réception');
    // The receipt commits SQLite before it closes. The underlying workspace can
    // still report idle during that I/O; waiting only for ready() races the pop
    // and makes nav() look for a Back button that has just disappeared.
    await until(
      () => find.byType(ReceiptScreen).evaluate().isEmpty,
      reason: 'receipt committed and editor closed',
    );
    await t.pumpAndSettle();
    await ready();
  }

  Future<void> dropdown(String field, String value) async {
    await tapKey('field.$field');
    await tap(value);
  }

  Future<void> verifyState(
    bool Function(Map<String, dynamic>) check,
    String reason,
  ) async {
    var success = false;
    for (var i = 0; i < 50; i++) {
      if (check(await state())) {
        success = true;
        break;
      }
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(success, isTrue, reason: reason);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('admin, manager and seller complete the BioBalance workflows', (
    tester,
  ) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    if (base.isEmpty) {
      fail('Run npm run test:journeys with the isolated test harness.');
    }
    await const FlutterSecureStorage().deleteAll();
    final db = AppDatabase.open(), api = ApiClient(baseUrl: base);
    await tester.pumpWidget(BioBalanceApp(api: api, database: db));
    final j = Journey(tester);
    await j.until(
      () => find.byKey(const ValueKey('auth.login')).evaluate().isNotEmpty,
    );
    debugPrint('JOURNEY: administrator invitation');
    await j.login(admin);
    // With a new database the administrator starts by granting partner access.
    if (find.text('Accorder un accès responsable').evaluate().isNotEmpty) {
      await j.tap('Accorder un accès responsable');
    } else {
      await j.nav('Magasins');
      await j.tap('Inviter un responsable');
    }
    await j.fill('field.email', manager);
    await j.fill('field.organizationName', 'Partenaire parcours');
    await j.editorSave();
    await j.logout();
    debugPrint('JOURNEY: manager activation and store setup');
    await j.activate(
      '${(await state())['managerCode']}',
      'Responsable parcours',
    );
    await j.login(manager);
    await j.tap('Créer un magasin');
    await j.fill('field.name', store);
    await j.fill('field.address', '10 avenue de test');
    await j.fill('field.city', 'Tunis');
    await j.tapKey('editor.save');
    await j.until(
      () => find.text('Préparer votre magasin').evaluate().isNotEmpty,
      reason: 'resumable onboarding',
    );
    await j.tap('Continuer plus tard');
    await j.ready();
    await j.logout();
    debugPrint('JOURNEY: admin catalog and training');
    await j.login(admin);
    await j.nav('Catalogue');
    await j.tap('Ajouter un produit');
    await j.fill('field.reference', reference);
    await j.fill('field.name', product);
    await j.editorSave();
    await j.nav('Plus');
    await j.tap('Formation');
    await j.tap('Créer un contenu');
    await j.fillLabel('Titre', 'Conseils $reference');
    await j.fillLabel(
      'Article ou description',
      'Appliquer le sérum sur une peau propre.',
    );
    await j.tap('Associer des produits');
    await j.tap(product);
    await j.tap('Associer 1 produit(s)');
    await j.tap('Brouillon');
    await j.tap('Publié');
    await j.tap('Aperçu du contenu');
    await j.back();
    await j.tap('Enregistrer le contenu');
    await j.until(() => find.text('Éditer une formation').evaluate().isEmpty);
    await j.back();
    await j.logout();
    debugPrint('JOURNEY: manager stock, pricing, team, reward and order');
    await j.login(manager);
    await j.nav('Stock');
    await j.tap(product);
    await j.tap('Prix, seuil et points');
    await j.fill('field.price', '49,900');
    await j.fill('field.threshold', '5');
    await j.fill('field.points', '10');
    await j.editorSave();
    await j.back();
    await j.tap('Entrée de stock');
    await j.receipt('OPENING', '20');
    await j.nav('Équipe');
    await j.tap('Inviter');
    await j.fill('field.email', seller);
    await j.editorSave();
    await j.nav('Plus');
    await j.tap('Guide de configuration');
    await j.until(
      () => find.text('4 étapes sur 4 terminées').evaluate().isNotEmpty,
    );
    await j.tap('Terminer le guide');
    await j.tap('Récompenses & classement');
    await j.tap('Créer une récompense');
    await j.fill('field.title', 'Cadeau PDRN');
    await j.fill('field.cost', '10');
    await j.dropdown('product', product);
    await j.editorSave();
    await j.back();
    await j.nav('Commandes');
    await j.tap('Commander');
    await j.tap('Ajouter un produit');
    await j.tap(product);
    await j.fillLabel('Unités à commander', '5');
    await j.tap('Envoyer la commande');
    await j.until(
      () => find.text('Commander des produits').evaluate().isEmpty,
      reason: 'order editor closed',
    );
    await j.ready();
    await j.logout();
    debugPrint('JOURNEY: admin dispatch');
    await j.login(admin);
    await j.nav('Commandes');
    await j.tap('En préparation');
    await j.ready();
    await j.tap('Expédier une livraison');
    await j.tapKey('editor.save');
    await j.until(() => find.text('Préparer une livraison').evaluate().isEmpty);
    await j.ready();
    await j.logout();
    debugPrint(
      'JOURNEY: seller activation, delivery, sale, correction and return',
    );
    await j.activate('${(await state())['sellerCode']}', 'Vendeur parcours');
    await j.login(seller);
    await j.tap('Recevoir');
    final deliveryText = find.textContaining('Livraison ');
    await j.seek(deliveryText);
    await tester.tap(deliveryText.first);
    await tester.pumpAndSettle();
    await j.receipt('DELIVERY', '5');
    await j.back();
    await j.tap('Nouvelle vente');
    await j.tap('Rechercher');
    await j.chooseSaleProduct(product);
    await j.fillLabel('Lot DELIVERY · 31/12/2030', '0');
    await j.fillLabel('Lot OPENING · 31/12/2030', '3');
    await j.tap('Ajouter à la vente');
    await j.tap('Enregistrer la vente');
    await j.ready();
    await j.verifyState(
      (s) => (s['sales'] as List).length == 1,
      'sale committed',
    );
    await j.nav('Mes ventes');
    await j.tap('149,700 TND');
    await j.tap('Corriger');
    await j.tap('Modifier');
    await j.fillLabel('Lot OPENING · 31/12/2030', '4');
    await j.tap('Ajouter à la vente');
    await j.fillLabel('Motif de la correction', 'Quantité réelle');
    await j.tap('Enregistrer la vente');
    await j.verifyState(
      (s) => (s['sales'] as List).first['version'] == 2,
      'correction committed',
    );
    await j.tap('Enregistrer un retour');
    await j.tapKey('field.allocation');
    await j.tap('$product · Lot OPENING · 4 unité(s) retournable(s)');
    await j.tapKey('editor.save');
    await j.verifyState((s) => s['revisions'] == 3, 'return committed');
    await j.back();
    await j.nav('Récompenses');
    await j.tap('Demander cette récompense');
    await j.tap('Confirmer');
    await j.verifyState(
      (s) => (s['claims'] as List).isNotEmpty,
      'points reserved online',
    );
    await j.nav('Formation');
    await j.tap('Conseils $reference');
    await j.until(
      () => find
          .text('Appliquer le sérum sur une peau propre.')
          .evaluate()
          .isNotEmpty,
    );
    await j.back();
    await j.logout();
    debugPrint('JOURNEY: manager handover and deliberate announcement');
    await j.login(manager);
    await j.nav('Plus');
    await j.tap('Récompenses & classement');
    await j.tap('Confirmer la remise');
    await j.tap('Confirmer');
    await j.verifyState(
      (s) => (s['claims'] as List).first['status'] == 'fulfilled',
      'reward handed over',
    );
    await j.back();
    await j.tap('Envoyer une annonce');
    await j.fillLabel('Titre', 'Bravo équipe');
    await j.fillLabel('Message', 'La formation PDRN est disponible.');
    await j.tap('Vérifier avant d’envoyer');
    expect(find.textContaining('Magasin : $store'), findsOneWidget);
    await j.tap('Envoyer à cette équipe');
    await j.until(() => find.text('Annonce à votre équipe').evaluate().isEmpty);
    await j.logout();
    debugPrint('JOURNEY: seller inbox and access revoked with an editor open');
    await j.login(seller);
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    await j.tap('Bravo équipe');
    await j.tap('Fermer');
    await j.back();
    await j.tap('Nouvelle vente');
    await j.tap('Rechercher');
    await j.chooseSaleProduct(product);
    await fixture.post('/__test/revoke');
    // A protected server read confirms revocation; the production listener saves
    // the draft and replaces the route. The pending operation owner never changes.
    await api
        .request(
          'GET',
          '/v1/stores/${(await state())['store']['id']}/snapshot',
          query: {'organizationId': (await state())['store']['organizationId']},
        )
        .catchError((Object _) => null);
    await j.until(
      () => find.text('Votre accès doit être vérifié').evaluate().isNotEmpty,
      reason: 'safe access screen',
    );
    expect(tester.takeException(), isNull);
    binding.reportData = {
      'roleJourneys': 'passed',
      'platform': defaultTargetPlatform.name,
      'environment': 'emulator-or-simulator',
      'physicalDevice': false,
    };
    await tester.pumpWidget(const SizedBox());
    await db.close();
    fixture.close();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
