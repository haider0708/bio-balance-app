import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/features/catalog/catalog_screen.dart';
import 'package:biobalance/ui/features/inventory/inventory_screens.dart';
import 'package:biobalance/ui/features/replenishment/order_screens.dart';
import 'package:biobalance/ui/features/rewards/rewards_screen.dart';
import 'package:biobalance/ui/features/sales/sales_history_screen.dart';
import 'package:biobalance/ui/features/team/team_screen.dart';
import 'package:biobalance/ui/features/training/training_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  for (final name in [
    'stock',
    'sales',
    'orders',
    'rewards',
    'team',
    'training',
    'catalog',
  ]) {
    for (final size in [const Size(360, 800), const Size(800, 360)]) {
      testWidgets(
        '$name supports 200 percent text, landscape/keyboard and labeled controls at $size',
        (t) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final db = AppDatabase(NativeDatabase.memory());
          final dio = Dio(BaseOptions(baseUrl: 'http://test'));
          dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) => h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: o.path.endsWith('/ranking')
                      ? {'month': '2026-09', 'scores': []}
                      : [],
                ),
              ),
            ),
          );
          final api = ApiClient(baseUrl: 'http://test', dio: dio)
            ..authenticate('token', accountId: 'user');
          final vm = WorkspaceViewModel(
            UserAccount(
              id: 'user',
              name: 'Amira',
              email: 'test@example.test',
              admin: name == 'catalog',
            ),
            OfflineRepository(db, api),
            api,
          );
          final store = Store.fromJson({
            'id': 'store',
            'organizationId': 'org',
            'name': 'Parapharmacie de démonstration',
            'permissions': ['manage', 'sell', 'receive'],
          });
          vm.state = WorkspaceState(
            store: store,
            stores: [store],
            data: StoreData({
              'products': [
                {
                  'id': 'product',
                  'name': 'Sérum BioBalance PDRN',
                  'reference': 'PDRN',
                  'active': true,
                },
              ],
              'lots': [
                {
                  'id': 'lot',
                  'productId': 'product',
                  'batch': 'BATCH',
                  'expiry': '2030-12-31',
                  'sellable': 5,
                  'damaged': 1,
                  'version': 3,
                },
              ],
              'config': [
                {
                  'productId': 'product',
                  'priceMillimes': '49900',
                  'threshold': 5,
                  'pointsPerUnit': 10,
                  'pointsConfigured': true,
                },
              ],
              'points': {'balance': '30', 'reserved': '10'},
              'sales': [],
              'team': [],
              'orders': [],
              'deliveries': [],
              'rewards': [
                {
                  'id': 'gift',
                  'title': 'Cadeau PDRN',
                  'description': 'Produit offert',
                  'cost': 10,
                  'active': true,
                },
              ],
            }),
          );
          final Widget page = switch (name) {
            'stock' => StockPage(vm: vm),
            'sales' => SalesPage(vm: vm),
            'orders' => OrdersPage(vm: vm),
            'rewards' => RewardsPage(vm: vm),
            'team' => TeamPage(vm: vm),
            'training' => TrainingPage(vm: vm),
            _ => CatalogPage(vm: vm),
          };
          final semantics = t.ensureSemantics();
          await t.pumpWidget(
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
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: const TextScaler.linear(2),
                    viewInsets: EdgeInsets.only(
                      bottom: size.width > size.height ? 100 : 0,
                    ),
                  ),
                  child: Scaffold(body: SafeArea(child: page)),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
          for (var i = 0; i < 5; i++) {
            await t.drag(find.byType(Scrollable).first, const Offset(0, -180));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          }
          semantics.dispose();
          await t.pumpWidget(const SizedBox());
          vm.dispose();
          await db.close();
          api.http.close();
        },
      );
    }
  }
}
