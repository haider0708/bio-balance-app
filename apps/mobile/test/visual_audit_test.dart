import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:biobalance/data/repositories/photo_repository.dart';
import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/models.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/features/authentication/login_screen.dart';
import 'package:biobalance/ui/features/authentication/session_view_model.dart';
import 'package:biobalance/ui/features/catalog/catalog_screen.dart';
import 'package:biobalance/ui/features/catalog/product_information.dart';
import 'package:biobalance/ui/features/inventory/inventory_screens.dart';
import 'package:biobalance/ui/features/sales/sale_screen.dart';
import 'package:biobalance/ui/features/sales/sales_history_screen.dart';
import 'package:biobalance/ui/features/replenishment/order_screens.dart';
import 'package:biobalance/ui/features/rewards/rewards_screen.dart';
import 'package:biobalance/ui/features/team/team_screen.dart';
import 'package:biobalance/ui/features/training/training_screen.dart';
import 'package:biobalance/ui/features/announcements/announcement_screen.dart';
import 'package:biobalance/ui/features/notifications/notifications_screen.dart';
import 'package:biobalance/ui/features/stores/store_settings_screen.dart';
import 'package:biobalance/ui/features/stores/product_settings_screen.dart';
import 'package:biobalance/ui/features/stores/stores_screen.dart';
import 'package:biobalance/ui/features/settings/account_screen.dart';
import 'package:biobalance/ui/features/synchronization/sync_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_help.dart';

import 'ui_test.dart';

final productPhoto = File('test/fixtures/magic-touch.jpg').absolute;
final photoProduct = <String, dynamic>{
  'id': 'p',
  'name': 'Magic Touch',
  'reference': 'BB-WEB-46',
  'barcode': '8697711601118',
  'description': 'Base de maquillage, fond de teint et anti-cernes. Texture légère et fini mat.',
  'instructions': 'Après votre routine de soin, appliquer avec les doigts ou une éponge sur le visage et le cou.',
  'category': 'Maquillage',
  'range': '',
  'packageSize': '30 ml',
  'ingredients': '',
  'precautions': '',
  'priceStatus': 'verified',
  'referencePriceMillimes': '56000',
  'sourceUrls': ['https://biobalance.tn/maquillage/46-customizable-mug.html'],
  'imageId': 'photo',
  'active': true,
  'version': 1,
  'updatedAt': '2026-09-23T10:00:00Z',
};
final article = <String, dynamic>{
  'id': 'article',
  'title': 'Accompagner une cliente dans sa routine',
  'body': '<p>Écoutez ses besoins et expliquez simplement les conseils d’utilisation du produit.</p>',
  'type': 'article',
  'mediaId': null,
  'productIds': ['p'],
  'status': 'published',
  'version': 1,
  'authorId': 'user',
  'updatedAt': '2026-09-23T10:00:00Z',
};

class AuditApi extends PreviewApi {
  AuditApi() {
    authenticate('test-only', accountId: 'user');
  }
  @override
  Future<CatalogListResponseDto> catalogList({String? after}) async =>
      CatalogListResponseDto.fromJson({
        'items': [photoProduct],
        'nextCursor': null,
      });
  @override
  Future<List<TrainingContentDto>> trainingList({String? after}) async => [
    TrainingContentDto.fromJson(article),
  ];
  @override
  Future<TrainingGetResponseDto> trainingGet({required String id}) async =>
      TrainingGetResponseDto.fromJson(article);
  @override
  Future<WorkspaceRankingResponseDto> workspaceRanking({
    required String store,
    required String organizationId,
  }) async => WorkspaceRankingResponseDto.fromJson({
    'month': '2026-09',
    'scores': [
      {'userId': 'user', 'name': 'Amira', 'score': '240', 'rank': '1'},
    ],
  });
  @override
  Future<List<NotificationDto>> notificationsList({String? before}) async => [
    NotificationDto.fromJson({
      'kind': 'announcement',
      'audience': 'staff',
      'id': 'notice',
      'organizationId': 'org',
      'storeId': 'store',
      'userId': 'user',
      'eventKey': 'test-event',
      'title': 'Bienvenue dans votre magasin',
      'body': 'Votre responsable a partagé les conseils de la semaine.',
      'readAt': null,
      'createdAt': '2026-09-23T10:00:00Z',
    }),
  ];
}

class AuditPhotos extends PhotoRepository {
  AuditPhotos(super.context, super.local, super.account);
  @override
  Future<File> get(String id, {bool thumbnail = true}) async => productPhoto;
}

class AuditWorkspace extends PreviewWorkspace {
  AuditWorkspace(super.user, super.repository, super.api);
  @override
  PhotoRepository get photos => _auditPhotos;
  late final PhotoRepository _auditPhotos = AuditPhotos(
    repositoryContext,
    repository,
    user.id,
  );
}

class VisualFixture extends RoleFixture {
  VisualFixture() : super('manager') {
    final raw = Map<String, dynamic>.from(vm.state.data!.raw);
    raw['products'] = [photoProduct];
    raw['store'] = {
      ...vm.state.store!.toJson(),
      'address': '12 avenue Habib Bourguiba',
      'phone': '+216 71 000 000',
      'version': 1,
    };
    raw['rewards'] = [
      {
        'id': 'reward',
        'title': 'Magic Touch offert',
        'description': 'Un produit à découvrir',
        'cost': '200',
        'productId': 'p',
        'quantity': 1,
        'imageId': 'photo',
        'active': true,
        'version': 1,
      },
    ];
    raw['onboarding'] = {
      'complete': false,
      'completedCount': 2,
      'profile': true,
      'team': false,
      'stock': true,
      'products': false,
      'incompleteProducts': ['p'],
    };
    vm.replace(StoreData(raw));
  }
  @override
  AuditApi get api => _auditApi;
  final _auditApi = AuditApi();
  @override
  AuditWorkspace get vm => _auditVm;
  late final _auditVm = AuditWorkspace(
    const UserAccount(
      id: 'user',
      name: 'Amira Ben Salem',
      email: 'test@example.test',
      admin: true,
    ),
    OfflineRepository(db, api),
    api,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });
  final pages = <String, Widget Function(VisualFixture)>{
    'catalog': (f) => CatalogPage(vm: f.vm),
    'product': (f) => ProductInformation(vm: f.vm, product: photoProduct),
    'stock': (f) => StockPage(vm: f.vm),
    'stock-product': (f) =>
        ProductDetail(vm: f.vm, product: Product.fromJson(photoProduct)),
    'sales-history': (f) => SalesPage(vm: f.vm),
    'sale': (f) => SaleScreen(workspace: f.vm),
    'receipt': (f) => ReceiptScreen(vm: f.vm),
    'orders': (f) => OrdersPage(vm: f.vm),
    'order-editor': (f) => OrderEditor(vm: f.vm, initialProductId: 'p'),
    'rewards': (f) => RewardsPage(vm: f.vm),
    'team': (f) => TeamPage(vm: f.vm),
    'training': (f) => TrainingPage(vm: f.vm),
    'article': (f) => TrainingReader(vm: f.vm, article: article),
    'training-editor': (f) => TrainingEditor(vm: f.vm),
    'announcement': (f) => AnnouncementScreen(vm: f.vm),
    'notifications': (f) => NotificationsScreen(vm: f.vm),
    'store-settings': (f) => StoreSettingsPage(vm: f.vm),
    'product-settings': (f) => ProductSettingsPage(vm: f.vm),
    'onboarding': (f) => OnboardingScreen(vm: f.vm),
    'sync': (f) => SyncScreen(vm: f.vm),
    'account': (f) => AccountScreen(vm: f.vm),
    'help': (f) => const WorkspaceHelp(),
    'login': (f) => const LoginScreen(),
    'activation': (f) => const AccountActionScreen(mode: 'activate'),
    'recovery': (f) => const AccountActionScreen(mode: 'forgot'),
    'reset': (f) => const AccountActionScreen(mode: 'reset'),
  };
  for (final entry in pages.entries) {
    for (final large in [false, true]) {
      testWidgets(
        'visual audit ${entry.key} ${large ? "landscape 200%" : "phone"}',
        (t) async {
          WidgetController.hitTestWarningShouldBeFatal = true;
          viewport(t, large ? const Size(800, 360) : const Size(360, 800));
          final f = VisualFixture(), key = GlobalKey();
          final session = SessionViewModel(f.api, const FlutterSecureStorage());
          await t.pumpWidget(f.app(const SizedBox()));
          final imageContext = t.element(find.byType(SizedBox).first);
          await t.runAsync(() async {
            for (final height in [
              40,
              48,
              52,
              56,
              60,
              72,
              80,
              96,
              120,
              140,
              160,
              220,
            ]) {
              await precacheImage(
                ResizeImage(FileImage(productPhoto), height: height),
                imageContext,
              ).timeout(const Duration(seconds: 5));
            }
          });
          await t.pumpWidget(
            f.app(
              ChangeNotifierProvider.value(
                value: session,
                child: Scaffold(body: entry.value(f)),
              ),
              scale: large ? 2 : 1,
              capture: key,
            ),
          );
          for (var i = 0; i < 4; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await t.pump(const Duration(milliseconds: 200));
          }
          await t.pump();
          expect(t.takeException(), isNull);
          if (!large &&
              ['product', 'catalog', 'stock', 'rewards'].contains(entry.key)) {
            expect(
              find.byWidgetPredicate((w) => w is RawImage && w.image != null),
              findsWidgets,
            );
          }
          if (!large) await screenshot(t, key, 'audit-${entry.key}');
          final scrollables = find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .hitTestable();
          if (scrollables.evaluate().isNotEmpty) {
            await t.drag(scrollables.last, const Offset(0, -480));
            await t.pump(const Duration(milliseconds: 250));
            expect(t.takeException(), isNull);
          }
          await t.pumpWidget(const SizedBox());
          await t.pump();
          session.dispose();
          await f.close();
        },
      );
    }
  }
}
