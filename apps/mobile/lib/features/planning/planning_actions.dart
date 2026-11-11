import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_exception.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/feedback.dart';
import '../../l10n/app_localizations.dart';
import 'location_service.dart';
import 'planning_models.dart';
import 'planning_repository.dart';
import 'visit_outbox.dart';

/// What came of asking the phone where it is.
sealed class Reading {
  const Reading();
}

/// A position (the person may have been asked to allow it).
class Got extends Reading {
  const Got(this.fix);

  final Fix fix;
}

/// The person chose to go on without a position (leaving only: arriving always records one).
class Without extends Reading {
  const Without();
}

class Cancelled extends Reading {
  const Cancelled();
}

const _uuid = Uuid();

/// Reads the position once, with a waiting message. When it fails it explains why; arriving needs
/// the position ([required]: try again or give up), leaving can go on without it.
Future<Reading> readPosition(
  BuildContext context,
  WidgetRef ref, {
  bool required = false,
}) async {
  final t = AppLocalizations.of(context);
  final service = ref.read(locationServiceProvider);
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            spacing: 16,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              Expanded(child: Text(t.visitGettingPosition)),
            ],
          ),
        ),
      ),
    ),
  );
  Fix? fix;
  LocationFailure? failure;
  try {
    fix = await service.current();
  } on LocationException catch (error) {
    failure = error.failure;
  }
  navigator.pop();
  if (fix != null) return Got(fix);
  if (!context.mounted) return const Cancelled();
  final next = await _explain(
    context,
    service,
    failure ?? LocationFailure.unavailable,
    required: required,
  );
  if (next == 'without') return const Without();
  if (next == 'retry' && context.mounted) {
    return readPosition(context, ref, required: required);
  }
  return const Cancelled();
}

/// What the person chose after a failed reading: 'retry', 'without', or nothing (cancelled).
Future<String?> _explain(
  BuildContext context,
  LocationService service,
  LocationFailure failure, {
  required bool required,
}) async {
  final t = AppLocalizations.of(context);
  final (title, body, canOpen) = switch (failure) {
    LocationFailure.serviceOff => (
      t.locationOffTitle,
      t.locationOffBody,
      false,
    ),
    LocationFailure.unavailable => (
      t.locationUnavailableTitle,
      t.locationUnavailableBody,
      false,
    ),
    LocationFailure.denied || LocationFailure.deniedForever => (
      t.locationDeniedTitle,
      t.locationDeniedBody,
      true,
    ),
  };
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(required ? '$body\n\n${t.locationNeeded}' : body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(t.cancel),
        ),
        if (canOpen)
          TextButton(
            onPressed: () => Navigator.pop(context, 'settings'),
            child: Text(t.locationOpenSettings),
          ),
        if (required)
          TextButton(
            onPressed: () => Navigator.pop(context, 'retry'),
            child: Text(t.retry),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(context, 'without'),
            child: Text(t.locationContinueWithout),
          ),
      ],
    ),
  );
  if (choice == 'settings') await service.openSettings();
  return choice == 'settings' ? null : choice;
}

bool _noConnection(ApiException error) =>
    error.isOffline || error.code == 'TIMEOUT';

/// What the server needs after any check: lists and the visit are read again.
void _refresh(WidgetRef ref, String? visitId) {
  ref.invalidate(visitsProvider);
  if (visitId != null) ref.invalidate(visitProvider(visitId));
}

/// "Record my position": one tap reads where the phone is and sends the arrival with it (with a
/// reason if it does not match the place), or keeps it on the phone when there is no connection.
/// Without a position nothing is recorded.
Future<void> checkIn(BuildContext context, WidgetRef ref, Visit visit) async {
  final t = AppLocalizations.of(context);
  final reading = await readPosition(context, ref, required: true);
  if (reading is! Got || !context.mounted) return;
  final fix = reading.fix;
  final repo = ref.read(planningRepositoryProvider);
  final at = DateTime.now();
  String? reason;
  for (var attempt = 0; attempt < 2; attempt++) {
    final body = repo.presence(occurredAt: at, fix: fix, reason: reason);
    try {
      await repo.checkIn(visit.id, body);
      _refresh(ref, visit.id);
      if (context.mounted) showMessage(context, t.visitArrived);
      return;
    } on ApiException catch (error) {
      if (!context.mounted) return;
      if (_noConnection(error)) {
        await ref
            .read(visitOutboxProvider.notifier)
            .add(
              PendingPresence(
                id: visit.id,
                kind: PendingKind.checkIn,
                visitId: visit.id,
                place: visit.target.name,
                body: body,
              ),
            );
        if (context.mounted) showMessage(context, t.visitSavedOffline);
        return;
      }
      if (error.code == 'POSITION_REASON_REQUIRED' && attempt == 0) {
        reason = await askNote(
          context,
          title: t.visitReasonTitle,
          confirmLabel: t.visitReasonSend,
          hint: t.visitReasonHint,
        );
        if (reason == null || !context.mounted) return;
        continue;
      }
      showError(context, error);
      return;
    }
  }
}

/// "I'm leaving": the position at the exit is kept too; it never blocks leaving.
Future<void> checkOut(BuildContext context, WidgetRef ref, Visit visit) async {
  final t = AppLocalizations.of(context);
  final reading = await readPosition(context, ref);
  if (reading is Cancelled || !context.mounted) return;
  final repo = ref.read(planningRepositoryProvider);
  final body = repo.presence(
    occurredAt: DateTime.now(),
    fix: reading is Got ? reading.fix : null,
  );
  try {
    await repo.checkOut(visit.id, body);
    _refresh(ref, visit.id);
    if (context.mounted) showMessage(context, t.visitLeft);
  } on ApiException catch (error) {
    if (!context.mounted) return;
    if (_noConnection(error)) {
      await ref
          .read(visitOutboxProvider.notifier)
          .add(
            PendingPresence(
              id: visit.id,
              kind: PendingKind.checkOut,
              visitId: visit.id,
              place: visit.target.name,
              body: body,
            ),
          );
      if (context.mounted) showMessage(context, t.visitSavedOffline);
      return;
    }
    showError(context, error);
  }
}

/// "I'm at this place": a visit nobody planned, started on the spot. The phone picks its id, so a retry
/// (after a dropped connection) never makes two.
Future<void> startUnplanned(
  BuildContext context,
  WidgetRef ref, {
  required bool isDepot,
  required String placeId,
  required String placeName,
  required VisitKind kind,
}) async {
  final t = AppLocalizations.of(context);
  final reading = await readPosition(context, ref, required: true);
  if (reading is! Got || !context.mounted) return;
  final repo = ref.read(planningRepositoryProvider);
  final id = _uuid.v4();
  final at = DateTime.now();
  String? reason;
  for (var attempt = 0; attempt < 2; attempt++) {
    final body = {
      'id': id,
      'targetKind': isDepot ? 'DEPOT' : 'PDV',
      'targetId': placeId,
      'kind': kind.wire,
      ...repo.presence(occurredAt: at, fix: reading.fix, reason: reason),
    };
    try {
      await repo.unplanned(body);
      _refresh(ref, null);
      if (context.mounted) showMessage(context, t.visitArrived);
      return;
    } on ApiException catch (error) {
      if (!context.mounted) return;
      if (_noConnection(error)) {
        await ref
            .read(visitOutboxProvider.notifier)
            .add(
              PendingPresence(
                id: id,
                kind: PendingKind.unplanned,
                place: placeName,
                body: body,
              ),
            );
        if (context.mounted) showMessage(context, t.visitSavedOffline);
        return;
      }
      if (error.code == 'POSITION_REASON_REQUIRED' && attempt == 0) {
        reason = await askNote(
          context,
          title: t.visitReasonTitle,
          confirmLabel: t.visitReasonSend,
          hint: t.visitReasonHint,
        );
        if (reason == null || !context.mounted) return;
        continue;
      }
      showError(context, error);
      return;
    }
  }
}

/// A visit's day and time for the screens ("Tue 4 Nov · 10:00–11:00").
String visitWhen(Visit v, String locale) =>
    '${Dates.short(v.plannedStart, locale)} · ${Dates.time(v.plannedStart, locale)}–${Dates.time(v.plannedEnd, locale)}';
