import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'planning_models.dart';

typedef VisitsQuery = ({
  String from,
  String to,
  String? responsableId,
  String? regionId,
});

/// A position read on the phone at one moment (never followed).
class Fix {
  const Fix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.mocked = false,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final bool mocked;
}

class PlanningRepository {
  PlanningRepository(this._ref);

  final Ref _ref;

  Future<List<Visit>> visits(VisitsQuery q) async => jsonList(
    await _ref
        .read(apiClientProvider)
        .get(
          '/v1/visits',
          query: {
            'from': q.from,
            'to': q.to,
            'responsableId': q.responsableId,
            'regionId': q.regionId,
          },
        ),
  ).map(Visit.fromJson).toList();

  Future<Visit> visit(String id) async => Visit.fromJson(
    await _ref.read(apiClientProvider).get('/v1/visits/$id') as Json,
  );

  Future<Visit> create(Json body) async => Visit.fromJson(
    await _ref.read(apiClientProvider).post('/v1/visits', body) as Json,
  );

  Future<Visit> update(String id, Json body) async => Visit.fromJson(
    await _ref.read(apiClientProvider).patch('/v1/visits/$id', body) as Json,
  );

  Future<Visit> cancel(String id) async => Visit.fromJson(
    await _ref.read(apiClientProvider).post('/v1/visits/$id/cancel') as Json,
  );

  Json presence({required DateTime occurredAt, Fix? fix, String? reason}) => {
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    if (fix != null) ...{
      'latitude': fix.latitude,
      'longitude': fix.longitude,
      'accuracyMeters': fix.accuracyMeters,
      if (fix.mocked) 'mocked': true,
    },
    if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
  };

  Future<Visit> checkIn(String id, Json body) async => Visit.fromJson(
    await _ref.read(apiClientProvider).post('/v1/visits/$id/check-in', body)
        as Json,
  );

  Future<Visit> checkOut(String id, Json body) async => Visit.fromJson(
    await _ref.read(apiClientProvider).post('/v1/visits/$id/check-out', body)
        as Json,
  );

  Future<Visit> unplanned(Json body) async => Visit.fromJson(
    await _ref.read(apiClientProvider).post('/v1/visits/unplanned', body)
        as Json,
  );

  Future<void> setPosition({
    required bool isDepot,
    required String id,
    required Fix fix,
  }) => _ref.read(apiClientProvider).put(
    '/v1/planning/positions/${isDepot ? 'depot' : 'pdv'}/$id',
    {
      'latitude': fix.latitude,
      'longitude': fix.longitude,
      'accuracyMeters': fix.accuracyMeters,
    },
  );

  Future<PlanningPreferences> preferences() async =>
      PlanningPreferences.fromJson(
        await _ref.read(apiClientProvider).get('/v1/planning/preferences')
            as Json,
      );

  Future<PlanningPreferences> setPreferences(Json body) async =>
      PlanningPreferences.fromJson(
        await _ref.read(apiClientProvider).put('/v1/planning/preferences', body)
            as Json,
      );

  Future<CalendarLink> calendarLink({bool rotate = false}) async =>
      CalendarLink.fromJson(
        (rotate
                ? await _ref
                      .read(apiClientProvider)
                      .post('/v1/planning/calendar-link/rotate')
                : await _ref
                      .read(apiClientProvider)
                      .get('/v1/planning/calendar-link'))
            as Json,
      );

  Future<List<PlanningLine>> overview(String from, String to) async => jsonList(
    ((await _ref
            .read(apiClientProvider)
            .get('/v1/planning/overview', query: {'from': from, 'to': to}))
        as Json)['responsables'],
  ).map(PlanningLine.fromJson).toList();
}

final planningRepositoryProvider = Provider<PlanningRepository>(
  PlanningRepository.new,
);

final visitsProvider = FutureProvider.autoDispose
    .family<List<Visit>, VisitsQuery>(
      (ref, q) => ref.watch(planningRepositoryProvider).visits(q),
    );

final visitProvider = FutureProvider.autoDispose.family<Visit, String>(
  (ref, id) => ref.watch(planningRepositoryProvider).visit(id),
);

final planningPreferencesProvider =
    FutureProvider.autoDispose<PlanningPreferences>(
      (ref) => ref.watch(planningRepositoryProvider).preferences(),
    );

final calendarLinkProvider = FutureProvider.autoDispose<CalendarLink>(
  (ref) => ref.watch(planningRepositoryProvider).calendarLink(),
);

typedef OverviewQuery = ({String from, String to});

final planningOverviewProvider = FutureProvider.autoDispose
    .family<List<PlanningLine>, OverviewQuery>(
      (ref, q) => ref.watch(planningRepositoryProvider).overview(q.from, q.to),
    );
