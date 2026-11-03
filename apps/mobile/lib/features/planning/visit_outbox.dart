import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'planning_repository.dart';

/// One outbox per person: a check is only ever sent under the account that made it.
String _storageKey(String userId) => 'outbox.visits.$userId';

enum PendingKind { checkIn, checkOut, unplanned }

/// A check-in, check-out or unplanned visit made without a connection. The moment and the position
/// are those of the tap; the server marks one that arrives late.
class PendingPresence {
  const PendingPresence({
    required this.id,
    required this.kind,
    required this.place,
    required this.body,
    this.visitId,
    this.error,
  });

  factory PendingPresence.fromJson(Json j) => PendingPresence(
    id: j.str('id'),
    kind: PendingKind.values.firstWhere(
      (k) => k.name == j.str('kind'),
      orElse: () => PendingKind.checkIn,
    ),
    visitId: j.strOrNull('visitId'),
    place: j.str('place'),
    body: j.obj('body'),
    error: j.strOrNull('error'),
  );

  /// The visit id for a check-in or out; the unplanned visit's own id (chosen by the phone) otherwise.
  final String id;
  final PendingKind kind;
  final String? visitId;
  final String place;
  final Json body;
  final String? error;

  PendingPresence withError(String? code) => PendingPresence(
    id: id,
    kind: kind,
    visitId: visitId,
    place: place,
    body: body,
    error: code,
  );

  PendingPresence withReason(String reason) => PendingPresence(
    id: id,
    kind: kind,
    visitId: visitId,
    place: place,
    body: {...body, 'reason': reason},
  );

  Json toJson() => {
    'id': id,
    'kind': kind.name,
    'visitId': visitId,
    'place': place,
    'body': body,
    'error': error,
  };
}

/// Arrivals and departures made without a connection wait here, on the phone, and are sent again
/// (the server answers a repeat with the first one) as soon as it answers.
class VisitOutbox extends Notifier<List<PendingPresence>>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _flushing = false;
  String? _userId;

  @override
  List<PendingPresence> build() {
    _userId = ref.watch(sessionProvider.select((s) => s.value?.me.id));
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _timer?.cancel();
    });
    if (_userId != null) unawaited(_load(_userId!));
    return const [];
  }

  Future<void> _load(String userId) async {
    final prefs = await ref.read(preferencesProvider.future);
    final raw = prefs.getString(_storageKey(userId));
    if (raw == null || _userId != userId) return;
    state = jsonList(jsonDecode(raw)).map(PendingPresence.fromJson).toList();
    _schedule();
  }

  Future<void> _save() async {
    final userId = _userId;
    if (userId == null) return;
    final prefs = await ref.read(preferencesProvider.future);
    await prefs.setString(
      _storageKey(userId),
      jsonEncode([for (final p in state) p.toJson()]),
    );
  }

  Future<void> add(PendingPresence pending) async {
    state = [...state, pending];
    await _save();
    _schedule();
  }

  Future<void> discard(String id, PendingKind kind) async {
    state = state.where((p) => !(p.id == id && p.kind == kind)).toList();
    await _save();
  }

  /// A refused check-in that only lacked a reason is sent again with one.
  Future<void> retryWithReason(PendingPresence pending, String reason) async {
    state = [
      for (final p in state)
        if (p.id == pending.id && p.kind == pending.kind)
          p.withReason(reason)
        else
          p,
    ];
    await _save();
    unawaited(flush());
  }

  @override
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) unawaited(flush());
  }

  void _schedule() {
    _timer?.cancel();
    if (state.any((p) => p.error == null)) {
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(flush()),
      );
    }
  }

  Future<void> _send(PendingPresence p) {
    final api = ref.read(apiClientProvider);
    return switch (p.kind) {
      PendingKind.checkIn => api.post(
        '/v1/visits/${p.visitId}/check-in',
        p.body,
      ),
      PendingKind.checkOut => api.post(
        '/v1/visits/${p.visitId}/check-out',
        p.body,
      ),
      PendingKind.unplanned => api.post('/v1/visits/unplanned', p.body),
    };
  }

  /// Try to send everything waiting, oldest first. Stops at the first connection problem.
  Future<void> flush() async {
    final owner = _userId;
    if (_flushing || owner == null || ref.read(tokenProvider) == null) return;
    _flushing = true;
    try {
      var sent = false;
      for (final p in state.where((p) => p.error == null).toList()) {
        if (_userId != owner || ref.read(accountProvider) != owner) return;
        try {
          await _send(p);
          state = state
              .where((x) => !(x.id == p.id && x.kind == p.kind))
              .toList();
          sent = true;
        } on ApiException catch (error) {
          final status = error.status ?? 0;
          if (error.isOffline ||
              error.code == 'TIMEOUT' ||
              status >= 500 ||
              status == 429 ||
              error.isUnauthorized) {
            break;
          }
          // The server understood and said no: retrying would not help, so show it.
          state = [
            for (final x in state)
              if (x.id == p.id && x.kind == p.kind)
                x.withError(error.code)
              else
                x,
          ];
        }
      }
      await _save();
      _schedule();
      if (sent) ref.invalidate(visitsProvider);
    } finally {
      _flushing = false;
    }
  }
}

final visitOutboxProvider =
    NotifierProvider<VisitOutbox, List<PendingPresence>>(VisitOutbox.new);
