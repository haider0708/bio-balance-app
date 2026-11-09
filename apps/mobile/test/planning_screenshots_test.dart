// The planning screens, from the real app with sample data, for a visual review (responsable and admin).
//
//   PLANNING_SHOTS=1 flutter test test/planning_screenshots_test.dart
//
// Written to build/screenshots/planning/.
import 'dart:async';
import 'dart:io';

import 'package:biobalance/app/router.dart';
import 'package:biobalance/features/planning/location_service.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter_test/flutter_test.dart';

import 'planning_test.dart' as p;
import 'screenshots_test.dart' as base show loadFonts;
import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, Object?> visit(
  String id,
  String place,
  String kind,
  String status,
  DateTime start, {
  List<Map<String, Object?>> events = const [],
  String? note,
  bool hasPosition = true,
}) {
  final v = p.visitJson(
    id: id,
    status: status,
    start: start,
    events: events,
    hasPosition: hasPosition,
  );
  return {
    ...v,
    'kind': kind,
    'note': note,
    'target': {...(v['target']! as Map<String, Object?>), 'name': place},
  };
}

Map<String, Object?> ev(
  String kind,
  String verdict,
  DateTime at, {
  int? distance,
  List<String> flags = const [],
  String? reason,
  bool position = true,
}) => {
  'kind': kind,
  'occurredAt': at.toUtc().toIso8601String(),
  'verdict': verdict,
  'distanceM': distance,
  'accuracyM': 12,
  'latitude': position ? 36.8065 : null,
  'longitude': position ? 10.1815 : null,
  'flags': flags,
  'reason': reason,
};

Future<void> go(
  WidgetTester tester,
  FakeServer s,
  String path, {
  Object? extra,
  p.FakeLocation? location,
}) async {
  final container = await launch(
    tester,
    s,
    language: 'fr',
    overrides: [
      locationServiceProvider.overrideWithValue(
        location ?? p.FakeLocation(fix: p.near),
      ),
    ],
  );
  unawaited(container.read(routerProvider).push(path, extra: extra));
  await settle(tester);
}

void main() {
  setUpAll(base.loadFonts);
  final skip = !Platform.environment.containsKey('PLANNING_SHOTS');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  Future<void> shot(WidgetTester tester, String name) =>
      screenshot(tester, 'planning/$name');

  final done = visit(
    'v1',
    'Para Lac',
    'COUNT',
    'DONE',
    today.add(const Duration(hours: 9)),
    note: 'Compter les sérums',
    events: [
      ev(
        'CHECK_IN',
        'VERIFIED',
        today.add(const Duration(hours: 9, minutes: 4)),
        distance: 18,
      ),
      ev(
        'CHECK_OUT',
        'VERIFIED',
        today.add(const Duration(hours: 9, minutes: 52)),
        distance: 12,
      ),
    ],
  );
  final onSite = visit(
    'v2',
    'Para Marsa',
    'TRAINING',
    'ON_SITE',
    today.add(const Duration(hours: 11)),
    note: 'Formation sur les nouveautés',
    events: [
      ev(
        'CHECK_IN',
        'OUT_OF_RANGE',
        today.add(const Duration(hours: 11, minutes: 7)),
        distance: 640,
        flags: ['LATE_SYNC'],
        reason: 'Le magasin est dans le centre commercial, le GPS est décalé',
      ),
    ],
  );
  final planned = visit(
    'v3',
    'Dépôt Ben Arous',
    'DELIVERY',
    'PLANNED',
    now.add(const Duration(hours: 3)),
    note: 'Apporter le bon de livraison',
  );
  final list = [done, onSite, planned];

  FakeServer resp([Object? one]) => p.server(list: list, visit: one)
    ..on('GET /v1/planning/preferences', {
      'leadMinutes': 60,
      'eveningSummary': true,
    })
    ..on('GET /v1/planning/calendar-link', {
      'url': 'https://api.galylio.com/cal/abc.ics',
      'webcal': 'webcal://api.galylio.com/cal/abc.ics',
    });

  testWidgets('planning: calendar', skip: skip, (tester) async {
    await go(tester, resp(), '/planning');
    await shot(tester, '01-calendar');
  });

  testWidgets('planning: new visit', skip: skip, (tester) async {
    await go(tester, resp(), '/planning/new', extra: DateTime.now());
    await tester.tap(find.text('Choisir un magasin ou un grossiste'));
    await settle(tester);
    await tester.tap(find.text('Para Lac'));
    await settle(tester);
    await tester.tap(find.text('Livraison'));
    await tester.pump();
    await tester.enterText(
      find.byType(TextField),
      'Apporter le bon de livraison',
    );
    await settle(tester, frames: 3);
    await shot(tester, '02-new-visit');
  });

  testWidgets('planning: before arriving', skip: skip, (tester) async {
    final v = visit(
      'v1',
      'Para Lac',
      'COUNT',
      'PLANNED',
      now.subtract(const Duration(minutes: 1)),
      note: 'Compter les sérums',
    );
    await go(tester, resp(v), '/planning/visits/v1');
    await shot(tester, '03-visit-before-arriving');
  });

  testWidgets('planning: on site, away, with a reason', skip: skip, (
    tester,
  ) async {
    await go(
      tester,
      resp(onSite)..on('GET /v1/visits/v2', onSite),
      '/planning/visits/v2',
    );
    await shot(tester, '04-visit-on-site-away');
  });

  testWidgets('planning: done', skip: skip, (tester) async {
    await go(tester, resp(done), '/planning/visits/v1');
    await shot(tester, '05-visit-done');
  });

  testWidgets('planning: settings', skip: skip, (tester) async {
    await go(tester, resp(), '/planning/settings');
    await shot(tester, '06-settings');
  });

  FakeServer admin() => p.server(role: 'ADMIN', visit: onSite, list: list)
    ..on('GET /v1/visits/v2', onSite)
    ..on('GET /v1/planning/overview', {
      'from': '2026-11-02',
      'to': '2026-11-08',
      'responsables': [
        {
          'responsableId': 'u9',
          'name': 'Nora Ben Salah',
          'regionId': 'r1',
          'region': 'Nord',
          'planned': 9,
          'done': 6,
          'missed': 1,
          'onSite': 1,
          'cancelled': 1,
          'unplanned': 2,
          'verified': 5,
          'outOfRange': 1,
          'noFix': 1,
          'flagged': 1,
          'avgMinutes': 47,
        },
        {
          'responsableId': 'u10',
          'name': 'Sami Gharbi',
          'regionId': 'r2',
          'region': 'Centre',
          'planned': 5,
          'done': 5,
          'missed': 0,
          'onSite': 0,
          'cancelled': 0,
          'unplanned': 0,
          'verified': 5,
          'outOfRange': 0,
          'noFix': 0,
          'flagged': 0,
          'avgMinutes': 38,
        },
      ],
    });

  testWidgets('planning: admin overview', skip: skip, (tester) async {
    await go(tester, admin(), '/planning/overview');
    await shot(tester, '10-admin-overview');
    await tester.tap(find.text('Nora Ben Salah'));
    await settle(tester);
    await shot(tester, '11-admin-visits-of-one');
    await tester.tap(find.text('Para Marsa'));
    await settle(tester);
    await shot(tester, '12-admin-visit-with-maps');
  });
}
