import 'dart:io';
import 'dart:ui' as ui;

import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/features/workspace/workspace_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in [
    const Size(360, 800),
    const Size(800, 360),
    const Size(1024, 768),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'manager navigation is usable at $size with text scale $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final db = AppDatabase(NativeDatabase.memory()),
              api = ApiClient(baseUrl: 'http://test');
          final vm = WorkspaceViewModel(
            const UserAccount(
              id: 'user',
              name: 'Amira',
              email: 'demo@example.test',
              admin: false,
            ),
            OfflineRepository(db, api),
            api,
          );
          final store = Store.fromJson({
            'id': 'store',
            'organizationId': 'org',
            'name': 'BioBalance · Tunis',
            'city': 'Tunis',
            'permissions': ['manage', 'sell', 'receive'],
          });
          vm.state = WorkspaceState(
            stores: [store],
            store: store,
            data: StoreData({
              'store': {'onboardingStep': 5},
              'points': {'balance': '240', 'reserved': '40'},
              'sales': [],
              'products': [],
              'lots': [],
              'alerts': [],
            }),
            syncedAt: DateTime.now(),
          );
          final boundary = GlobalKey();
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: vm,
              child: MaterialApp(
                theme: appTheme(),
                locale: const Locale('fr', 'TN'),
                supportedLocales: const [Locale('fr', 'TN')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: RepaintBoundary(
                  key: boundary,
                  child: const WorkspaceScreen(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.text('Nouvelle vente'),
            120,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Nouvelle vente'), findsOneWidget);
          if (size == const Size(360, 800) && scale == 1) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 2);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('../../docs/screenshots/manager-home.png')
                  .writeAsBytes(data!.buffer.asUint8List());
            });
          }
          await tester.tap(find.text('Stock').last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          vm.dispose();
          await db.close();
        },
      );
    }
  }
}
