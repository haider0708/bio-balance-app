import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/features/training/training_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_test.dart' show MemoryDraftRepository;

void main() {
  testWidgets(
    'training restores the draft and previews associated products and decoded article text',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory()),
          api = ApiClient(baseUrl: 'http://test')
            ..authenticate('token', accountId: 'admin');
      final local = MemoryDraftRepository(db, api);
      await local.saveDraft('admin', '', 'training:new', {
        'values': {
          'id': 'draft-id',
          'version': '0',
          'title': 'Formation PDRN',
          'body': '<p>Conseils &amp; bienfaits</p>',
          'type': 'article',
          'status': 'draft',
          'productIds': '["p"]',
          'mediaId': '',
          'filePath': '',
          'fileName': '',
          'mediaStatus': '',
        },
      });
      const user = UserAccount(
        id: 'admin',
        name: 'Admin',
        email: 'admin@example.test',
        admin: true,
      );
      final vm = WorkspaceViewModel(user, local, api);
      vm.state = WorkspaceState(
        data: StoreData({
          'products': [
            {'id': 'p', 'name': 'Sérum PDRN', 'reference': 'PDRN'},
          ],
        }),
      );
      await tester.pumpWidget(MaterialApp(home: TrainingEditor(vm: vm)));
      await tester.pumpAndSettle();
      expect(find.text('Formation PDRN'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Aperçu du contenu'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Aperçu du contenu'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Conseils & bienfaits'), findsOneWidget);
      expect(find.text('Sérum PDRN'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      await db.close();
    },
  );
  testWidgets(
    'product association remains scrollable in landscape with a keyboard and 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(640, 360),
              textScaler: TextScaler.linear(2),
              viewInsets: EdgeInsets.only(bottom: 120),
            ),
            child: Scaffold(
              body: ProductAssociationSheet(
                products: [
                  Product.fromJson({
                    'id': 'p',
                    'name': 'Sérum PDRN',
                    'reference': 'PDRN',
                  }),
                ],
                selected: const [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Sérum PDRN'),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byType(Checkbox)),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Associer 1 produit(s)'),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
