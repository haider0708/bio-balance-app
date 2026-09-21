import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/features/stores/stores_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_test.dart' show MemoryDraftRepository;

void main() {
  testWidgets(
    'setup remains accessible and resumes from saved completion instead of a step counter',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory()),
          api = ApiClient(baseUrl: 'http://test')
            ..authenticate('token', accountId: 'u');
      const user = UserAccount(
        id: 'u',
        name: 'Manager',
        email: 'test@example.test',
        admin: false,
      );
      final store = Store.fromJson({
        'id': 's',
        'organizationId': 'o',
        'name': 'Tunis',
        'permissions': ['manage'],
        'onboardingStep': 5,
      });
      final vm = WorkspaceViewModel(user, MemoryDraftRepository(db, api), api);
      vm.state = WorkspaceState(
        store: store,
        stores: [store],
        data: StoreData({
          'store': {'version': 1},
          'onboarding': {
            'profile': true,
            'team': false,
            'stock': false,
            'products': false,
            'completedCount': 1,
            'complete': false,
            'workingAlone': false,
            'noOpeningStock': false,
            'incompleteProducts': ['p'],
          },
        }),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => OnboardingScreen(vm: vm)),
                  ),
                  child: const Text('Guide'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Guide'));
      await tester.pumpAndSettle();
      expect(find.text('1 étapes sur 4 terminées'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Terminer le guide'), 250);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Terminer le guide'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('1 produit(s) restent'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Continuer plus tard'), 150);
      await tester.tap(find.text('Continuer plus tard'));
      await tester.pumpAndSettle();
      vm.state = vm.state.copy(
        data: StoreData({
          'store': {'version': 3},
          'onboarding': {
            'profile': true,
            'team': true,
            'stock': true,
            'products': true,
            'completedCount': 4,
            'complete': true,
            'workingAlone': true,
            'noOpeningStock': true,
            'incompleteProducts': [],
          },
        }),
      );
      await tester.tap(find.text('Guide'));
      await tester.pumpAndSettle();
      expect(find.text('4 étapes sur 4 terminées'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Je travaille seul pour le moment'),
        150,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(
                CheckboxListTile,
                'Je travaille seul pour le moment',
              ),
            )
            .value,
        isTrue,
      );
      await tester.scrollUntilVisible(find.text('Terminer le guide'), 250);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Terminer le guide'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      await db.close();
    },
  );
}
