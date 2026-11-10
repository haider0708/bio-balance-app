import '../../core/api/json.dart';

/// What a responsable goes to do at a place.
enum VisitKind {
  count,
  delivery,
  training,
  followUp,
  other;

  static VisitKind parse(String value) => switch (value) {
    'COUNT' => count,
    'DELIVERY' => delivery,
    'TRAINING' => training,
    'FOLLOW_UP' => followUp,
    _ => other,
  };

  String get wire => switch (this) {
    count => 'COUNT',
    delivery => 'DELIVERY',
    training => 'TRAINING',
    followUp => 'FOLLOW_UP',
    other => 'OTHER',
  };
}

enum VisitStatus {
  planned,
  onSite,
  done,
  missed,
  cancelled;

  static VisitStatus parse(String value) => switch (value) {
    'ON_SITE' => onSite,
    'DONE' => done,
    'MISSED' => missed,
    'CANCELLED' => cancelled,
    _ => planned,
  };
}

/// What the position given at a check-in said about being at the place.
enum Presence {
  verified,
  outOfRange,
  noFix,
  noPosition;

  static Presence parse(String value) => switch (value) {
    'VERIFIED' => verified,
    'OUT_OF_RANGE' => outOfRange,
    'NO_FIX' => noFix,
    _ => noPosition,
  };
}

class VisitTarget {
  const VisitTarget({
    required this.isDepot,
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.hasPosition,
    required this.positionLocked,
    this.phone,
    this.latitude,
    this.longitude,
  });

  factory VisitTarget.fromJson(Json j) => VisitTarget(
    isDepot: j.str('kind') == 'DEPOT',
    id: j.str('id'),
    name: j.str('name'),
    address: j.str('address'),
    city: j.str('city'),
    phone: j.strOrNull('phone'),
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    hasPosition: j.flag('hasPosition'),
    positionLocked: j.flag('positionLocked'),
  );

  final bool isDepot;
  final String id;
  final String name;
  final String address;
  final String city;
  final String? phone;
  final double? latitude;
  final double? longitude;
  final bool hasPosition;
  final bool positionLocked;

  String get kindWire => isDepot ? 'DEPOT' : 'PDV';
}

/// A check-in or check-out, with what the position said.
class VisitEvent {
  const VisitEvent({
    required this.isCheckIn,
    required this.occurredAt,
    required this.presence,
    this.distanceMeters,
    this.accuracyMeters,
    this.latitude,
    this.longitude,
    this.flags = const [],
    this.reason,
  });

  factory VisitEvent.fromJson(Json j) => VisitEvent(
    isCheckIn: j.str('kind') == 'CHECK_IN',
    occurredAt: j.date('occurredAt'),
    presence: Presence.parse(j.str('verdict')),
    distanceMeters: j.integerOrNull('distanceM'),
    accuracyMeters: (j['accuracyM'] as num?)?.toDouble(),
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    flags: ((j['flags'] as List<dynamic>?) ?? const []).cast<String>(),
    reason: j.strOrNull('reason'),
  );

  final bool isCheckIn;
  final DateTime occurredAt;
  final Presence presence;
  final int? distanceMeters;
  final double? accuracyMeters;
  final double? latitude;
  final double? longitude;
  final List<String> flags;
  final String? reason;
}

class Visit {
  const Visit({
    required this.id,
    required this.kind,
    required this.status,
    required this.unplanned,
    required this.plannedStart,
    required this.plannedEnd,
    required this.day,
    required this.target,
    required this.events,
    required this.canStartFrom,
    this.note,
    this.checkedInAt,
    this.checkedOutAt,
    this.responsableName,
  });

  factory Visit.fromJson(Json j) => Visit(
    id: j.str('id'),
    kind: VisitKind.parse(j.str('kind')),
    status: VisitStatus.parse(j.str('status')),
    unplanned: j.flag('unplanned'),
    plannedStart: j.date('plannedStart'),
    plannedEnd: j.date('plannedEnd'),
    day: j.str('day'),
    note: j.strOrNull('note'),
    checkedInAt: j.dateOrNull('checkedInAt'),
    checkedOutAt: j.dateOrNull('checkedOutAt'),
    canStartFrom: j.date('canStartFrom'),
    responsableName: j.objOrNull('responsable')?.strOrNull('name'),
    target: VisitTarget.fromJson(j.obj('target')),
    events: j.list('events').map(VisitEvent.fromJson).toList(),
  );

  final String id;
  final VisitKind kind;
  final VisitStatus status;
  final bool unplanned;
  final DateTime plannedStart;
  final DateTime plannedEnd;
  final String day;
  final String? note;
  final DateTime? checkedInAt;
  final DateTime? checkedOutAt;
  final DateTime canStartFrom;
  final String? responsableName;
  final VisitTarget target;
  final List<VisitEvent> events;

  VisitEvent? get checkIn => events.where((e) => e.isCheckIn).firstOrNull;
  VisitEvent? get checkOut => events.where((e) => !e.isCheckIn).firstOrNull;
}

/// One responsable's numbers over a period, for the admin.
class PlanningLine {
  const PlanningLine({
    required this.responsableId,
    required this.name,
    required this.region,
    required this.planned,
    required this.done,
    required this.missed,
    required this.onSite,
    required this.unplanned,
    required this.verified,
    required this.outOfRange,
    required this.noFix,
    required this.flagged,
    this.avgMinutes,
  });

  factory PlanningLine.fromJson(Json j) => PlanningLine(
    responsableId: j.str('responsableId'),
    name: j.str('name'),
    region: j.str('region'),
    planned: j.integer('planned'),
    done: j.integer('done'),
    missed: j.integer('missed'),
    onSite: j.integer('onSite'),
    unplanned: j.integer('unplanned'),
    verified: j.integer('verified'),
    outOfRange: j.integer('outOfRange'),
    noFix: j.integer('noFix'),
    flagged: j.integer('flagged'),
    avgMinutes: j.integerOrNull('avgMinutes'),
  );

  final String responsableId;
  final String name;
  final String region;
  final int planned;
  final int done;
  final int missed;
  final int onSite;
  final int unplanned;
  final int verified;
  final int outOfRange;
  final int noFix;
  final int flagged;
  final int? avgMinutes;
}

class PlanningPreferences {
  const PlanningPreferences({
    required this.leadMinutes,
    required this.eveningSummary,
  });

  factory PlanningPreferences.fromJson(Json j) => PlanningPreferences(
    leadMinutes: j.integer('leadMinutes', 60),
    eveningSummary: j.flag('eveningSummary', true),
  );

  final int leadMinutes;
  final bool eveningSummary;
}

class CalendarLink {
  const CalendarLink({required this.url, required this.webcal});

  factory CalendarLink.fromJson(Json j) =>
      CalendarLink(url: j.str('url'), webcal: j.str('webcal'));

  final String url;
  final String webcal;
}
