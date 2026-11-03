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

/// The person chose to go on without a position (they will be asked why).
class Without extends Reading {
  const Without();
}

class Cancelled extends Reading {
  const Cancelled();
}

/// To fix a place's position the reading must be this precise (metres); the server checks too.
const _maxPositionAccuracy = 50.0;
const _uuid = Uuid();

/// Reads the position once, with a waiting message; when it fails, explains and offers to go on without.
Future<Reading> readPosition(BuildContext context, WidgetRef ref) async {
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
  return _explain(context, service, failure ?? LocationFailure.unavailable);
}

Future<Reading> _explain(
  BuildContext context,
  LocationService service,
  LocationFailure failure,
) async {
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
      content: Text(body),
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
        TextButton(
          onPressed: () => Navigator.pop(context, 'without'),
          child: Text(t.locationContinueWithout),
        ),
      ],
    ),
  );
  if (choice == 'settings') await service.openSettings();
  return choice == 'without' ? const Without() : const Cancelled();
}

bool _noConnection(ApiException error) =>
    error.isOffline || error.code == 'TIMEOUT';

/// What the server needs after any check: lists and the visit are read again.
void _refresh(WidgetRef ref, String? visitId) {
  ref.invalidate(visitsProvider);
  if (visitId != null) ref.invalidate(visitProvider(visitId));
}

/// "I'm here": read the position, offer to fix a place's position the first time, send the arrival
/// (with a reason if the position does not match), or keep it on the phone when there is no connection.
Future<void> checkIn(BuildContext context, WidgetRef ref, Visit visit) async {
  final t = AppLocalizations.of(context);
  final reading = await readPosition(context, ref);
  if (reading is Cancelled || !context.mounted) return;
  final fix = reading is Got ? reading.fix : null;
  final repo = ref.read(planningRepositoryProvider);
  if (fix != null &&
      !visit.target.hasPosition &&
      !visit.target.positionLocked) {
    if (fix.accuracyMeters > _maxPositionAccuracy) {
      showMessage(context, t.positionTooPoor(fix.accuracyMeters.round()));
    } else if (await confirm(
      context,
      title: t.positionSetTitle,
      message: t.positionSetBody(visit.target.name, fix.accuracyMeters.round()),
      confirmLabel: t.positionSetYes,
    )) {
      if (!context.mounted) return;
      await perform(
        context,
        () => repo.setPosition(
          isDepot: visit.target.isDepot,
          id: visit.target.id,
          fix: fix,
        ),
        success: t.positionSaved,
      );
    }
    if (!context.mounted) return;
  }
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
  final reading = await readPosition(context, ref);
  if (reading is Cancelled || !context.mounted) return;
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
      ...repo.presence(
        occurredAt: at,
        fix: reading is Got ? reading.fix : null,
        reason: reason,
      ),
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
