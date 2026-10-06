// Renders the main screens of every role to build/screenshots for a visual review.
import 'dart:io';

import 'package:flutter/material.dart' show BackButton, TextFormField;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, Object?> pdv(String id, String name, String status, {String stock = 'APPROVED', int members = 2, String? group}) => {
      'id': id, 'name': name, 'address': '12 rue du Lac', 'city': 'Tunis', 'phone': '71 000 000', 'status': status,
      'regionId': 'r1', 'groupId': group == null ? null : 'g1', 'groupName': group, 'memberCount': members, 'initialStock': stock,
    };

Map<String, Object?> line(String name, int requested, {int? shipped, int? received, int? approved}) =>
    {'productId': name, 'name': name, 'family': 'Sérums', 'requested': requested, 'shipped': shipped, 'received': received, 'approved': approved};

FakeServer server(String role) {
  final s = FakeServer()
    ..on('GET /v1/me', meJson(role: role, name: switch (role) { 'ADMIN' => 'Admin BioBalance', 'RESPONSABLE' => 'Nora Ben Salah', 'GROSSISTE' => 'Hedi Trabelsi', _ => 'Amira Gharbi' }, locale: 'fr'))
    ..on('GET /v1/notifications/unread-count', {'unread': 3})
    ..on('GET /v1/regions', [
      {'id': 'r1', 'code': 'NORD', 'name': 'Nord'}, {'id': 'r2', 'code': 'CENTRE', 'name': 'Centre'}, {'id': 'r3', 'code': 'SUD', 'name': 'Sud'},
    ])
    ..on('GET /v1/products', [
      productJson('a', 'BIOBALANCE SÉRUM VITAMINE C 30ML'), productJson('b', 'BIOBALANCE SÉRUM NIACINAMIDE 10%'),
      productJson('c', 'BIOBALANCE SHAMPOING HUILE D’ARGAN 330ML', family: 'Soins capillaires'), productJson('d', 'BIOBALANCE CRÈME HYDRATANTE ACIDE HYALURONIQUE', family: 'Crèmes visage'),
    ]);
  final trend = [for (var i = 0; i < 14; i++) {'day': '2026-09-${23 + i % 8}'.padRight(10, '0').substring(0, 10), 'sales': i % 5, 'units': [4, 7, 5, 9, 12, 6, 3, 8, 11, 14, 9, 10, 13, 17][i], 'rewardMillimes': 0}];
  switch (role) {
    case 'VENDEUR':
      s.on('GET /v1/stock/locations/p1', stockJson(['a', 'b', 'c', 'd']));
      s.on('GET /v1/dashboard', {
        'role': 'VENDEUR', 'pdv': {'id': 'p1', 'name': 'Para Lac', 'status': 'ACTIVE'},
        'wallet': walletJson(balance: 48500, todayReward: 5200, todaySales: 3),
        'week': {'sales': 14, 'units': 41, 'rewardMillimes': 21300},
        'latest': [
          {'id': 's1', 'occurredAt': DateTime.now().toIso8601String(), 'units': 3, 'rewardMillimes': 2100},
          {'id': 's2', 'occurredAt': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(), 'units': 1, 'rewardMillimes': 800},
        ],
      });
      s.on('GET /v1/wallet', walletJson(balance: 48500, todayReward: 5200, todaySales: 3));
      s.on('GET /v1/wallet/entries', {'items': [
        {'id': 'e1', 'kind': 'SALE', 'amountMillimes': 2100, 'createdAt': DateTime.now().toIso8601String()},
        {'id': 'e2', 'kind': 'CORRECTION', 'amountMillimes': -800, 'createdAt': DateTime.now().subtract(const Duration(hours: 5)).toIso8601String()},
        {'id': 'e3', 'kind': 'PAYOUT', 'amountMillimes': -20000, 'createdAt': DateTime.now().subtract(const Duration(days: 4)).toIso8601String()},
      ], 'nextCursor': null});
      s.on('GET /v1/payouts', [
        {'id': 'p1', 'amountMillimes': 15000, 'status': 'PENDING', 'createdAt': DateTime.now().toIso8601String()},
      ]);
      s.on('GET /v1/sales', {'items': [
        for (var i = 0; i < 4; i++) {
          'id': 's$i', 'status': 'ACTIVE', 'version': i == 1 ? 2 : 1, 'day': '2026-10-06', 'occurredAt': DateTime.now().subtract(Duration(hours: i * 3)).toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(), 'units': 3 - i % 3, 'rewardMillimes': 2100 - i * 500,
          'seller': {'id': 'u1', 'name': 'Amira'}, 'pdv': {'id': 'p1', 'name': 'Para Lac'}, 'lines': <Object>[],
        },
      ], 'nextCursor': null});
    case 'RESPONSABLE' || 'ADMIN':
      s.on('GET /v1/dashboard', {
        'role': role, 'approvals': {'GROUP': 0, 'PDV': 2, 'MEMBER': 3, 'STOCK': 1, 'RECEIPT': 1, 'RESTOCK_REQUEST': 2, 'PAYOUT': 1, 'total': 10},
        'sales': {'today': {'sales': 12, 'units': 31, 'rewardMillimes': 15300}, 'week': {'sales': 88, 'units': 240, 'rewardMillimes': 120400}, 'month': {'sales': 340, 'units': 905, 'rewardMillimes': 452000}},
        'trend': trend,
        'topProducts': [{'name': 'BIOBALANCE SÉRUM VITAMINE C 30ML', 'family': 'Sérums', 'units': 64}, {'name': 'BIOBALANCE SÉRUM NIACINAMIDE 10%', 'family': 'Sérums', 'units': 51}],
        'topPdvs': [{'name': 'Para Lac', 'units': 120}, {'name': 'Pharma Marsa', 'units': 84}],
        'attention': {'negativeStock': 1, 'lowStock': 4}, 'restocks': {'REQUESTED': 2, 'ASSIGNED': 1, 'SHIPPED': 1, 'RECEIVED': 1},
        'pdvs': {'active': 9, 'pending': 2},
        'regions': role == 'ADMIN' ? [
          {'id': 'r1', 'code': 'NORD', 'name': 'Nord', 'pdvs': 4, 'members': 11, 'units': 120, 'pending': 3},
          {'id': 'r2', 'code': 'CENTRE', 'name': 'Centre', 'pdvs': 3, 'members': 8, 'units': 74, 'pending': 0},
          {'id': 'r3', 'code': 'SUD', 'name': 'Sud', 'pdvs': 2, 'members': 5, 'units': 46, 'pending': 7},
        ] : <Object>[],
        'payouts': role == 'ADMIN' ? {'pending': 1, 'amountMillimes': 15000} : null,
      });
      s.on('GET /v1/approvals', {
        'counts': {'GROUP': 0, 'PDV': 2, 'MEMBER': 3, 'STOCK': 1, 'RECEIPT': 1, 'RESTOCK_REQUEST': 2, 'PAYOUT': 1, 'total': 10},
        'items': [
          {'type': 'PDV', 'id': 'p9', 'name': 'Para Marsa', 'by': 'Nora Ben Salah', 'region': 'Nord', 'regionId': 'r1', 'createdAt': DateTime.now().toIso8601String(), 'meta': {'city': 'La Marsa'}},
          {'type': 'STOCK', 'id': 'd1', 'name': 'Para Lac', 'by': 'Nora Ben Salah', 'region': 'Nord', 'regionId': 'r1', 'createdAt': DateTime.now().toIso8601String(), 'meta': {'kind': 'INITIAL', 'units': 120, 'lines': 14}},
          {'type': 'MEMBER', 'id': 'u9', 'name': 'Karim Mejri', 'by': 'Nora Ben Salah', 'region': 'Nord', 'regionId': 'r1', 'createdAt': DateTime.now().toIso8601String(), 'meta': {'pdv': 'Para Lac'}},
          {'type': 'RECEIPT', 'id': 'o1', 'name': 'Para Lac', 'by': 'Nora Ben Salah', 'region': 'Nord', 'regionId': 'r1', 'createdAt': DateTime.now().toIso8601String(), 'meta': {'number': 'RS-2026-000012', 'units': 40}},
          {'type': 'PAYOUT', 'id': 'q1', 'name': 'Amira Gharbi', 'region': 'Nord', 'regionId': 'r1', 'createdAt': DateTime.now().toIso8601String(), 'meta': {'amountMillimes': 15000}},
        ],
      });
      s.on('GET /v1/pdvs', [pdv('p1', 'Para Lac', 'ACTIVE', group: 'Groupe Tunis'), pdv('p2', 'Pharma Marsa', 'ACTIVE', members: 3), pdv('p3', 'Para Sfax Centre', 'PENDING', stock: 'NONE', members: 0)]);
      s.on('GET /v1/groups', [{'id': 'g1', 'name': 'Groupe Tunis', 'status': 'ACTIVE', 'regionId': 'r1', 'pdvCount': 2}]);
      s.on('GET /v1/users', [
        {'id': 'u1', 'name': 'Amira Gharbi', 'email': 'a@x.tn', 'role': 'VENDEUR', 'status': 'ACTIVE', 'activated': true, 'pdvId': 'p1'},
        {'id': 'u2', 'name': 'Karim Mejri', 'email': 'k@x.tn', 'role': 'VENDEUR', 'status': 'PENDING', 'activated': false, 'pdvId': 'p1'},
      ]);
      s.on('GET /v1/restocks', [
        {'id': 'o1', 'number': 'RS-2026-000012', 'status': 'RECEIVED', 'source': 'GROSSISTE', 'destination': {'id': 'p1', 'kind': 'PDV', 'name': 'Para Lac'}, 'supplier': {'id': 'd1', 'name': 'Dépôt Hedi'}, 'requestedBy': {'id': 'x', 'name': 'Nora Ben Salah'}, 'createdAt': DateTime.now().toIso8601String(), 'receiptPhotoId': null, 'lines': [line('SÉRUM VITAMINE C', 20, shipped: 20, received: 18)]},
        {'id': 'o2', 'number': 'RS-2026-000013', 'status': 'REQUESTED', 'destination': {'id': 'p2', 'kind': 'PDV', 'name': 'Pharma Marsa'}, 'requestedBy': {'id': 'x', 'name': 'Nora Ben Salah'}, 'createdAt': DateTime.now().toIso8601String(), 'lines': [line('SÉRUM NIACINAMIDE', 12)]},
      ]);
      s.on('GET /v1/restocks/o1', {'id': 'o1', 'number': 'RS-2026-000012', 'status': 'RECEIVED', 'source': 'GROSSISTE', 'destination': {'id': 'p1', 'kind': 'PDV', 'name': 'Para Lac'}, 'supplier': {'id': 'd1', 'name': 'Dépôt Hedi'}, 'requestedBy': {'id': 'x', 'name': 'Nora Ben Salah'}, 'receiver': {'id': 'u1', 'name': 'Amira Gharbi'}, 'createdAt': DateTime.now().toIso8601String(), 'receiptPhotoId': null, 'lines': [line('SÉRUM VITAMINE C 30ML', 20, shipped: 20, received: 18), line('SÉRUM NIACINAMIDE', 10, shipped: 10, received: 10)]});
      s.on('GET /v1/reports/sales', {'rows': [{'key': 'a', 'label': 'Para Lac', 'sales': 140, 'units': 380, 'rewardMillimes': 190000}, {'key': 'b', 'label': 'Pharma Marsa', 'sales': 90, 'units': 250, 'rewardMillimes': 120000}], 'totals': {'sales': 230, 'units': 630, 'rewardMillimes': 310000}});
    case 'GROSSISTE':
      s.on('GET /v1/dashboard', {'role': 'GROSSISTE', 'toShip': 2, 'myRestocks': {'REQUESTED': 1}, 'stock': {'units': 640, 'products': 38}, 'lastDeclaration': {'id': 'd', 'status': 'APPROVED', 'kind': 'INITIAL'}});
  }
  return s;
}

/// The test environment draws text as blocks unless real fonts are loaded.
Future<void> loadFonts() async {
  Future<void> load(String family, String path) async {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    await loader.load();
  }

  await load('Inter', 'assets/fonts/Inter.ttf');
  await load('MaterialIcons', '${Platform.environment['HOME']}/development/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  const lucide = '/home/haydar/.pub-cache/hosted/pub.dev/lucide_icons_flutter-3.1.20/assets/lucide.ttf';
  await load('Lucide', lucide);
  await load('packages/lucide_icons_flutter/Lucide', lucide);
}

void main() {
  setUpAll(loadFonts);
  testWidgets('screens: sign-in', (tester) async {
    await launch(tester, FakeServer(), signedIn: false, language: 'fr');
    await screenshot(tester, '01-login-fr');
    await tester.enterText(find.byType(TextFormField).at(0), 'x');
    await launch(tester, FakeServer(), signedIn: false, language: 'en');
    await screenshot(tester, '02-login-en');
  });

  testWidgets('screens: team member', (tester) async {
    final s = server('VENDEUR');
    await launch(tester, s, language: 'fr');
    await screenshot(tester, '10-vendeur-home');
    await tester.tap(find.text('Nouvelle vente').first);
    await settle(tester);
    await tester.tap(find.text('BIOBALANCE SÉRUM VITAMINE C 30ML'));
    await settle(tester, frames: 5);
    await tester.tap(find.text('BIOBALANCE SÉRUM VITAMINE C 30ML'));
    await screenshot(tester, '11-vendeur-sell');
  });

  testWidgets('screens: admin', (tester) async {
    final s = server('ADMIN');
    await launch(tester, s, language: 'fr');
    await screenshot(tester, '20-admin-home');
    await tester.tap(find.text('Validations').last);
    await settle(tester);
    await screenshot(tester, '21-admin-approvals');
    await tester.tap(find.text('Réseau').last);
    await settle(tester);
    await screenshot(tester, '22-admin-network');
  });

  testWidgets('screens: responsable', (tester) async {
    final s = server('RESPONSABLE');
    await launch(tester, s, language: 'fr');
    await screenshot(tester, '30-resp-home');
    await tester.tap(find.text('Magasins').last);
    await settle(tester);
    await screenshot(tester, '31-resp-pdvs');
  });

  testWidgets('screens: celebration and wallet', (tester) async {
    final s = server('VENDEUR')
      ..handle('POST /v1/sales', (r) => (
            status: 201,
            body: {
              'id': (r.data as Map<String, dynamic>)['id'], 'status': 'ACTIVE', 'version': 1, 'day': '2026-10-06',
              'occurredAt': DateTime.now().toIso8601String(), 'createdAt': DateTime.now().toIso8601String(),
              'units': 3, 'rewardMillimes': 2100, 'seller': {'id': 'u1', 'name': 'Amira'}, 'pdv': {'id': 'p1', 'name': 'Para Lac'},
              'lines': [{'productId': 'a', 'name': 'SÉRUM VITAMINE C', 'quantity': 3, 'rewardMillimes': 2100}],
              'wallet': walletJson(balance: 50600, todayReward: 7300, todaySales: 4),
            },
          ));
    await launch(tester, s, language: 'fr');
    await tester.tap(find.text('Nouvelle vente').first);
    await settle(tester);
    await tester.tap(find.text('BIOBALANCE SÉRUM VITAMINE C 30ML'));
    await settle(tester, frames: 5);
    await tester.tap(find.textContaining('Vérifier la vente'));
    await settle(tester);
    await screenshot(tester, '12-vendeur-review');
    await tester.tap(find.text('Enregistrer la vente'));
    await settle(tester, frames: 12);
    await screenshot(tester, '13-vendeur-bravo');
    await settle(tester, frames: 30);
    await tester.tap(find.text('Terminé'));
    await settle(tester);
    await tester.tap(find.text('Portefeuille').last);
    await settle(tester);
    await screenshot(tester, '14-vendeur-wallet');
    await tester.tap(find.text('Ventes').last);
    await settle(tester);
    await screenshot(tester, '15-vendeur-sales');
  });

  testWidgets('screens: admin details', (tester) async {
    final s = server('ADMIN')
      ..on('GET /v1/reward-rules/effective', [
        {'productId': 'a', 'name': 'SÉRUM VITAMINE C 30ML', 'family': 'Sérums', 'amountMillimes': 800},
        {'productId': 'b', 'name': 'SÉRUM NIACINAMIDE 10%', 'family': 'Sérums', 'amountMillimes': 500},
        {'productId': 'c', 'name': 'SHAMPOING ARGAN 330ML', 'family': 'Soins capillaires', 'amountMillimes': 0},
      ])
      ..on('GET /v1/messages', [
        {'id': 'm1', 'title': 'Nouveau sérum', 'body': 'Découvrez le nouveau sérum cette semaine.', 'pinned': true, 'status': 'SENT', 'recipientCount': 24, 'readCount': 17, 'createdAt': DateTime.now().toIso8601String(), 'sentAt': DateTime.now().toIso8601String()},
        {'id': 'm2', 'title': 'Réunion vendredi', 'body': 'Réunion à 10h.', 'pinned': false, 'status': 'SCHEDULED', 'recipientCount': 24, 'readCount': 0, 'createdAt': DateTime.now().toIso8601String(), 'scheduledFor': DateTime.now().add(const Duration(days: 2)).toIso8601String()},
      ]);
    await launch(tester, s, language: 'fr');
    await tester.tap(find.text('Réassorts').last);
    await settle(tester);
    await screenshot(tester, '23-admin-restocks');
    await tester.tap(find.text('RS-2026-000012').first);
    await settle(tester);
    await screenshot(tester, '24-admin-restock-review');
    await tester.tap(find.byType(BackButton).first);
    await settle(tester);
    await tester.tap(find.text('Plus').last);
    await settle(tester);
    await screenshot(tester, '25-admin-more');
    await tester.tap(find.text('Récompenses'));
    await settle(tester);
    await screenshot(tester, '26-admin-rewards');
    await tester.tap(find.byType(BackButton).first);
    await settle(tester);
    await tester.tap(find.text('Annonces'));
    await settle(tester);
    await screenshot(tester, '27-admin-announcements');
    await tester.tap(find.text('Nouvelle annonce').last);
    await settle(tester);
    await screenshot(tester, '28-admin-compose');
  });

  testWidgets('screens: grossiste', (tester) async {
    await launch(tester, server('GROSSISTE'), language: 'fr');
    await screenshot(tester, '40-grossiste-home');
  });
}
