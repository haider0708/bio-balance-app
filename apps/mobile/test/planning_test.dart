// The responsable's planning: the calendar of visits, planning one, and proving presence with the
// position read once at "I'm here" and "I'm leaving" (denied, far, without a connection...); the
// admin reads the overview. The position comes from a fake, never from a phone.
import 'dart:async';
import 'dart:convert';

import 'package:biobalance/app/router.dart';
import 'package:biobalance/features/planning/location_service.dart';
import 'package:biobalance/features/planning/planning_repository.dart';
import 'package:biobalance/features/planning/visit_outbox.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

/// A phone whose position is whatever the test says.
class FakeLocation implements LocationService {
  FakeLocation({this.fix, this.failure});

  final Fix? fix;
  final LocationFailure? failure;
  int reads = 0;
  int settingsOpened = 0;

  @override
  Future<Fix> current() async {
    reads++;
    if (failure != null) throw LocationException(failure!);
    return fix!;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

const near = Fix(latitude: 36.8065, longitude: 10.1815, accuracyMeters: 10);

String day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, Object?> visitJson({
  String id = 'v1',
  String status = 'PLANNED',
  bool hasPosition = true,
  List<Map<String, Object?>> events = const [],
  DateTime? start,
  bool unplanned = false,
}) {
  final s = start ?? DateTime.now().subtract(const Duration(minutes: 1));
  return {
    'id': id,
    'kind': 'COUNT',
    'status': status,
    'unplanned': unplanned,
    'plannedStart': s.toUtc().toIso8601String(),
    'plannedEnd': s.add(const Duration(hours: 1)).toUtc().toIso8601String(),
    'day': day(s),
    'note': 'Count the serums',
    'revision': 0,
    'checkedInAt': null,
    'checkedOutAt': null,
    'canStartFrom': s
        .subtract(const Duration(hours: 1))
        .toUtc()
        .toIso8601String(),
    'target': {
      'kind': 'PDV',
      'id': 'p1',
      'name': 'Para Lac',
      'address': '12 rue de Marseille',
      'city': 'Tunis',
      'phone': null,
      'latitude': hasPosition ? 36.8065 : null,
      'longitude': hasPosition ? 10.1815 : null,
      'hasPosition': hasPosition,
      'positionLocked': false,
    },
    'events': events,
  };
}

Map<String, Object?> event(String kind, String verdict, {int? distance}) => {
  'kind': kind,
  'occurredAt': DateTime.now().toUtc().toIso8601String(),
  'verdict': verdict,
  'distanceM': distance,
  'accuracyM': 10,
  'latitude': 36.8065,
  'longitude': 10.1815,
  'flags': <String>[],
  'reason': null,
};

FakeServer server({String role = 'RESPONSABLE', Object? visit, Object? list}) =>
    FakeServer()
      ..on('GET /v1/me', meJson(role: role))
      ..on('GET /v1/notifications/unread-count', {'unread': 0})
      ..on('GET /v1/dashboard', <String, Object?>{})
      ..on('GET /v1/visits', list ?? [visitJson()])
      ..on('GET /v1/visits/v1', visit ?? visitJson())
      ..on('GET /v1/pdvs', [
        {
          'id': 'p1',
          'name': 'Para Lac',
          'status': 'ACTIVE',
          'address': '12 rue de Marseille',
          'city': 'Tunis',
          'regionId': 'r1',
          'memberCount': 2,
          'initialStock': 'APPROVED',
        },
      ])
      ..on('GET /v1/depots', <Object>[])
      ..on('POST /v1/visits', visitJson(), status: 201);

Map<String, Object?> sent(FakeServer s, String method, [String? path]) =>
    jsonDecode(
      jsonEncode(
        s.calls
            .lastWhere(
              (c) => c.method == method && (path == null || c.path == path),
            )
            .data,
      ),
    ) as Map<String, Object?>;

Future<ProviderContainer> open(
  WidgetTester tester,
  FakeServer s,
  String path, {
  FakeLocation? location,
  Object? extra,
}) async {
  final container = await launch(
    tester,
    s,
    language: 'en',
    overrides: [
      locationServiceProvider.overrideWithValue(
        location ?? FakeLocation(fix: near),
      ),
    ],
  );
  unawaited(container.read(routerProvider).push(path, extra: extra));
  await settle(tester);
  return container;
}

void main() {
  testWidgets('the calendar shows the day\'s visits and opens one', (
    tester,
  ) async {
    final s = server();
    await open(tester, s, '/planning');
    expect(find.text('Planning'), findsWidgets);
    expect(find.text('Para Lac'), findsOneWidget);
    expect(find.text('Stock count'), findsOneWidget);
    expect(find.text('Planned'), findsOneWidget);
    await tester.tap(find.text('Para Lac'));
    await settle(tester);
    expect(find.text("I'm here"), findsOneWidget);
    expect(find.text('Count the serums'), findsOneWidget);
  });

  testWidgets('a day without visits invites to plan one', (tester) async {
    final s = server(list: <Object>[]);
    await open(tester, s, '/planning');
    expect(find.text('No visit this day'), findsOneWidget);
    expect(find.text('Plan a visit'), findsWidgets);
  });

  testWidgets('planning a visit sends the place, the kind and the time', (
    tester,
  ) async {
    final s = server(list: <Object>[]);
    await open(tester, s, '/planning/new', extra: DateTime.now());
    await tester.tap(find.text('Choose a store or a grossiste'));
    await settle(tester);
    await tester.tap(find.text('Para Lac'));
    await settle(tester);
    await tester.tap(find.text('Delivery'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Bring the form');
    await tester.tap(find.text('90 min'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester);
    final body = sent(s, 'POST', '/v1/visits');
    expect(body['targetKind'], 'PDV');
    expect(body['targetId'], 'p1');
    expect(body['kind'], 'DELIVERY');
    expect(body['durationMinutes'], 90);
    expect(body['note'], 'Bring the form');
    expect(body['start'], isA<String>());
  });

  testWidgets('a clash is confirmed before the visit is kept', (tester) async {
    final s = server(list: <Object>[])
      ..handle('POST /v1/visits', (o) {
        final again = (o.data as Map)['allowOverlap'] == true;
        return again
            ? (status: 201, body: visitJson())
            : (
                status: 409,
                body: {
                  'code': 'VISIT_OVERLAP',
                  'message': 'Another visit covers some of this time.',
                },
              );
      });
    await open(tester, s, '/planning/new', extra: DateTime.now());
    await tester.tap(find.text('Choose a store or a grossiste'));
    await settle(tester);
    await tester.tap(find.text('Para Lac'));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Another visit at this time'), findsOneWidget);
    await tester.tap(find.text('Keep both'));
    await settle(tester);
    expect(s.count('POST /v1/visits'), 2);
    expect(sent(s, 'POST', '/v1/visits')['allowOverlap'], isTrue);
  });

  testWidgets('"I\'m here" sends the position read at the tap', (tester) async {
    final s = server()
      ..on(
        'POST /v1/visits/v1/check-in',
        visitJson(status: 'ON_SITE', events: [event('CHECK_IN', 'VERIFIED')]),
        status: 201,
      );
    final phone = FakeLocation(fix: near);
    await open(tester, s, '/planning/visits/v1', location: phone);
    await tester.tap(find.text("I'm here"));
    await settle(tester);
    expect(phone.reads, 1);
    final body = sent(s, 'POST', '/v1/visits/v1/check-in');
    expect(body['latitude'], 36.8065);
    expect(body['longitude'], 10.1815);
    expect(body['accuracyMeters'], 10);
    expect(body.containsKey('reason'), isFalse);
    expect(body['occurredAt'], isA<String>());
  });

  testWidgets('without permission the person can go on, and must say why', (
    tester,
  ) async {
    final calls = <Map<Object?, Object?>>[];
    final s = server()
      ..handle('POST /v1/visits/v1/check-in', (o) {
        calls.add(Map<Object?, Object?>.from(o.data as Map));
        return calls.length == 1
            ? (
                status: 422,
                body: {
                  'code': 'POSITION_REASON_REQUIRED',
                  'message': 'say why',
                },
              )
            : (
                status: 201,
                body: visitJson(
                  status: 'ON_SITE',
                  events: [event('CHECK_IN', 'NO_FIX')],
                ),
              );
      });
    final phone = FakeLocation(failure: LocationFailure.denied);
    await open(tester, s, '/planning/visits/v1', location: phone);
    await tester.tap(find.text("I'm here"));
    await settle(tester);
    expect(find.text('Position not allowed'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await settle(tester);
    expect(phone.settingsOpened, 1);
    expect(s.count('POST /v1/visits/v1/check-in'), 0);

    await tester.tap(find.text("I'm here"));
    await settle(tester);
    await tester.tap(find.text('Check in without a position'));
    await settle(tester);
    expect(find.text('Why does the position not match?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'The phone has no GPS');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await settle(tester);
    expect(calls, hasLength(2));
    expect(calls.first.containsKey('latitude'), isFalse);
    expect(calls.last['reason'], 'The phone has no GPS');
  });

  testWidgets('a place with no position offers to take where the phone is', (
    tester,
  ) async {
    final s = server(visit: visitJson(hasPosition: false))
      ..on('PUT /v1/planning/positions/pdv/p1', {'id': 'p1'})
      ..on(
        'POST /v1/visits/v1/check-in',
        visitJson(
          status: 'ON_SITE',
          events: [event('CHECK_IN', 'VERIFIED', distance: 0)],
        ),
        status: 201,
      );
    await open(tester, s, '/planning/visits/v1');
    await tester.tap(find.text("I'm here"));
    await settle(tester);
    expect(find.text("Save this place's position?"), findsOneWidget);
    await tester.tap(find.text('Use this position'));
    await settle(tester);
    final position = sent(s, 'PUT', '/v1/planning/positions/pdv/p1');
    expect(position['latitude'], 36.8065);
    expect(position['accuracyMeters'], 10);
    expect(s.count('POST /v1/visits/v1/check-in'), 1);
  });

  testWidgets(
    'without a connection the arrival waits on the phone and is sent later',
    (tester) async {
      final s = server()
        ..on(
          'POST /v1/visits/v1/check-in',
          visitJson(status: 'ON_SITE', events: [event('CHECK_IN', 'VERIFIED')]),
          status: 201,
        );
      final container = await open(tester, s, '/planning/visits/v1');
      s.offline = true;
      await tester.tap(find.text("I'm here"));
      await settle(tester);
      expect(
        find.text('No connection: saved on the phone, it will be sent'),
        findsOneWidget,
      );
      final waiting = container.read(visitOutboxProvider);
      expect(waiting, hasLength(1));
      expect(waiting.single.visitId, 'v1');
      expect(waiting.single.body['latitude'], 36.8065);
      // The connection is back: the same arrival goes, with the moment of the tap.
      s.offline = false;
      final flushed = container.read(visitOutboxProvider.notifier).flush();
      await settle(tester);
      await flushed;
      expect(container.read(visitOutboxProvider), isEmpty);
      expect(
        sent(s, 'POST', '/v1/visits/v1/check-in')['occurredAt'],
        waiting.single.body['occurredAt'],
      );
    },
  );

  testWidgets('on site, "I\'m leaving" ends the visit', (tester) async {
    final s =
        server(
          visit: visitJson(
            status: 'ON_SITE',
            events: [event('CHECK_IN', 'VERIFIED')],
          ),
        )..on(
          'POST /v1/visits/v1/check-out',
          visitJson(
            status: 'DONE',
            events: [
              event('CHECK_IN', 'VERIFIED'),
              event('CHECK_OUT', 'VERIFIED'),
            ],
          ),
          status: 201,
        );
    await open(tester, s, '/planning/visits/v1');
    expect(find.text('At the place'), findsOneWidget);
    await tester.tap(find.text("I'm leaving"));
    await settle(tester);
    expect(s.count('POST /v1/visits/v1/check-out'), 1);
  });

  testWidgets('a visit not yet open says when it opens', (tester) async {
    // A visit more than an hour away, still today: the screen only counts down within the day.
    final now = DateTime.now();
    var later = now.add(const Duration(hours: 3));
    if (later.day != now.day) later = now.add(const Duration(minutes: 61));
    if (later.day != now.day) {
      markTestSkipped('Too close to midnight to plan a visit later today.');
      return;
    }
    final s = server(visit: visitJson(start: later));
    await open(tester, s, '/planning/visits/v1');
    expect(find.textContaining('Available from'), findsOneWidget);
    await tester.tap(find.text("I'm here"), warnIfMissed: false);
    await settle(tester);
    expect(s.count('POST /v1/visits/v1/check-in'), 0);
  });

  testWidgets('the settings change the reminder and show the calendar link', (
    tester,
  ) async {
    final s = server()
      ..on('GET /v1/planning/preferences', {
        'leadMinutes': 60,
        'eveningSummary': true,
      })
      ..on('PUT /v1/planning/preferences', {
        'leadMinutes': 30,
        'eveningSummary': true,
      })
      ..on('GET /v1/planning/calendar-link', {
        'url': 'https://api.example.test/cal/abc.ics',
        'webcal': 'webcal://api.example.test/cal/abc.ics',
      });
    await open(tester, s, '/planning/settings');
    await tester.tap(find.text('30 min before'));
    await settle(tester);
    expect(sent(s, 'PUT', '/v1/planning/preferences')['leadMinutes'], 30);
    expect(find.text('Add to my calendar'), findsOneWidget);
    expect(find.text('Copy the link'), findsOneWidget);
  });

  testWidgets(
    'the admin reads each responsable\'s numbers and opens their visits',
    (tester) async {
      final s = server(role: 'ADMIN')
        ..on('GET /v1/planning/overview', {
          'from': '2026-10-27',
          'to': '2026-11-03',
          'responsables': [
            {
              'responsableId': 'u9',
              'name': 'Nora Nord',
              'regionId': 'r1',
              'region': 'Nord',
              'planned': 6,
              'done': 4,
              'missed': 1,
              'onSite': 0,
              'cancelled': 0,
              'unplanned': 1,
              'verified': 3,
              'outOfRange': 1,
              'noFix': 0,
              'flagged': 1,
              'avgMinutes': 42,
            },
          ],
        });
      await open(tester, s, '/planning/overview');
      expect(find.text('Nora Nord'), findsOneWidget);
      expect(find.text('Planned 6'), findsOneWidget);
      expect(find.text('Missed 1'), findsOneWidget);
      expect(find.text('Away 1'), findsOneWidget);
      expect(find.text('Average time on site: 42 min'), findsOneWidget);
      await tester.tap(find.text('Nora Nord'));
      await settle(tester);
      expect(find.text('Para Lac'), findsOneWidget);
      // The admin only reads: no button to start or change a visit.
      await tester.tap(find.text('Para Lac'));
      await settle(tester);
      expect(find.text("I'm here"), findsNothing);
      expect(find.text('Cancel this visit'), findsNothing);
    },
  );
}
