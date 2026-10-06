import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.pinned,
    required this.scheduled,
    required this.recipientCount,
    required this.readCount,
    required this.createdAt,
    this.scheduledFor,
    this.sentAt,
  });

  factory Announcement.fromJson(Json j) => Announcement(
    id: j.str('id'),
    title: j.str('title'),
    body: j.str('body'),
    pinned: j.flag('pinned'),
    scheduled: j.str('status') == 'SCHEDULED',
    recipientCount: j.integer('recipientCount'),
    readCount: j.integer('readCount'),
    createdAt: j.date('createdAt'),
    scheduledFor: j.dateOrNull('scheduledFor'),
    sentAt: j.dateOrNull('sentAt'),
  );

  final String id;
  final String title;
  final String body;
  final bool pinned;
  final bool scheduled;
  final int recipientCount;
  final int readCount;
  final DateTime createdAt;
  final DateTime? scheduledFor;
  final DateTime? sentAt;
}

class Recipient {
  const Recipient({
    required this.userId,
    required this.name,
    required this.role,
    this.readAt,
  });

  factory Recipient.fromJson(Json j) => Recipient(
    userId: j.str('userId'),
    name: j.str('name'),
    role: j.str('role'),
    readAt: j.dateOrNull('readAt'),
  );

  final String userId;
  final String name;
  final String role;
  final DateTime? readAt;
}

/// Who an announcement is for. Roles, regions and points of sale narrow each other down.
class Audience {
  const Audience({
    this.all = false,
    this.roles = const {},
    this.regionIds = const {},
    this.pdvIds = const {},
  });

  final bool all;
  final Set<String> roles;
  final Set<String> regionIds;
  final Set<String> pdvIds;

  bool get isEmpty =>
      !all && roles.isEmpty && regionIds.isEmpty && pdvIds.isEmpty;

  Audience copyWith({
    bool? all,
    Set<String>? roles,
    Set<String>? regionIds,
    Set<String>? pdvIds,
  }) => Audience(
    all: all ?? this.all,
    roles: roles ?? this.roles,
    regionIds: regionIds ?? this.regionIds,
    pdvIds: pdvIds ?? this.pdvIds,
  );

  Json toJson() => {
    if (all) 'all': true,
    if (roles.isNotEmpty) 'roles': roles.toList(),
    if (regionIds.isNotEmpty) 'regionIds': regionIds.toList(),
    if (pdvIds.isNotEmpty) 'pdvIds': pdvIds.toList(),
  };
}

class MessagesRepository {
  MessagesRepository(this._ref);

  final Ref _ref;

  Future<List<Announcement>> list() async =>
      jsonList(await _ref.read(apiClientProvider).get('/v1/messages'))
          .map(Announcement.fromJson)
          .toList();

  Future<({int recipients, Map<String, int> byRole})> preview(
    Audience audience,
  ) async {
    final data = await _ref.read(apiClientProvider).post(
      '/v1/messages/preview',
      {'audience': audience.toJson()},
    ) as Json;
    return (
      recipients: data.integer('recipients'),
      byRole: {
        for (final e in data.obj('byRole').entries)
          e.key: (e.value as num).toInt(),
      },
    );
  }

  Future<void> send({
    required String title,
    required String body,
    required Audience audience,
    required bool pinned,
    DateTime? scheduledFor,
  }) => _ref.read(apiClientProvider).post('/v1/messages', {
    'title': title,
    'body': body,
    'audience': audience.toJson(),
    'pinned': pinned,
    if (scheduledFor != null)
      'scheduledFor': scheduledFor.toUtc().toIso8601String(),
  });

  Future<({Announcement message, List<Recipient> recipients})> recipients(
    String id,
  ) async {
    final data =
        await _ref.read(apiClientProvider).get('/v1/messages/$id/recipients')
            as Json;
    return (
      message: Announcement.fromJson(data.obj('message')),
      recipients: data.list('recipients').map(Recipient.fromJson).toList(),
    );
  }

  Future<void> withdraw(String id) =>
      _ref.read(apiClientProvider).delete('/v1/messages/$id');
}

final messagesRepositoryProvider = Provider<MessagesRepository>(
  MessagesRepository.new,
);

final announcementsProvider = FutureProvider.autoDispose<List<Announcement>>(
  (ref) => ref.watch(messagesRepositoryProvider).list(),
);

final recipientsProvider = FutureProvider.autoDispose
    .family<({Announcement message, List<Recipient> recipients}), String>(
      (ref, id) => ref.watch(messagesRepositoryProvider).recipients(id),
    );
