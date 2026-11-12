import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../l10n/app_localizations.dart';
import 'planning_actions.dart';
import 'planning_labels.dart';
import 'planning_models.dart';
import 'position_map.dart';
import 'planning_repository.dart';

/// One visit: where and when, what the check-in and check-out said, and what to do now.
class VisitDetailScreen extends ConsumerWidget {
  const VisitDetailScreen({required this.visitId, super.key});

  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final visit = ref.watch(visitProvider(visitId));
    final role = ref.watch(meProvider).role;
    return Scaffold(
      appBar: AppBar(title: Text(t.visitDetailTitle)),
      body: AsyncBody<Visit>(
        value: visit,
        onRetry: () => ref.invalidate(visitProvider(visitId)),
        builder: (v) => _Body(
          visit: v,
          isResponsable: role == Role.responsable,
          isAdmin: role == Role.admin,
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.visit,
    required this.isResponsable,
    required this.isAdmin,
  });

  final Visit visit;
  final bool isResponsable;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final locale = t.localeName;
    final target = visit.target;
    final today = Dates.day(DateTime.now());
    // Any time of the planned day (the server refuses another day).
    final canStart = visit.status == VisitStatus.planned && visit.day == today;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Row(
                spacing: 8,
                children: [
                  IconBadge(visit.kind.icon, size: 36),
                  Expanded(
                    child: Text(
                      visit.kind.label(t),
                      style: context.text.titleMedium,
                    ),
                  ),
                  StatusChip(visit.status.label(t), tone: visit.status.tone),
                ],
              ),
              Text(target.name, style: context.text.titleLarge),
              if (target.address.isNotEmpty || target.city.isNotEmpty)
                Text(
                  [
                    target.address,
                    target.city,
                  ].where((s) => s.isNotEmpty).join(', '),
                  style: context.text.bodyMedium?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              InfoRow(t.visitDate, visitWhen(visit, locale)),
              if (visit.responsableName != null)
                InfoRow(t.visitDetailTitle, visit.responsableName!),
              if (visit.note != null && visit.note!.isNotEmpty)
                InfoRow(t.note, visit.note!),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _maps(target),
                    icon: const Icon(LucideIcons.map, size: 16),
                    label: Text(t.visitOpenInMaps),
                  ),
                  if (target.phone != null && target.phone!.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () =>
                          launchUrl(Uri(scheme: 'tel', path: target.phone)),
                      icon: const Icon(LucideIcons.phone, size: 16),
                      label: Text(t.call),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (visit.events.isNotEmpty) ...[
          SectionHeader(t.visitDetailTitle),
          for (final e in visit.events)
            _EventCard(event: e, visit: visit, isAdmin: isAdmin),
        ],
        const Gap(16),
        if (isResponsable) ..._actions(context, ref, canStart),
        if (isResponsable) ...[
          const Gap(12),
          Text(
            t.locationPrivacy,
            style: context.text.bodySmall?.copyWith(
              color: context.status.muted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref, bool canStart) {
    final t = AppLocalizations.of(context);
    switch (visit.status) {
      case VisitStatus.planned:
        return [
          FilledButton.icon(
            onPressed: canStart ? () => checkIn(context, ref, visit) : null,
            icon: const Icon(LucideIcons.mapPinCheck),
            label: Text(t.visitCheckIn),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          if (!canStart)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t.visitAvailableOnDay,
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(
                  color: context.status.muted,
                ),
              ),
            ),
          const Gap(12),
          OutlinedButton.icon(
            onPressed: () async {
              await context.push('/planning/${visit.id}/edit', extra: visit);
              ref.invalidate(visitProvider(visit.id));
            },
            icon: const Icon(LucideIcons.pencil),
            label: Text(t.edit),
          ),
          TextButton.icon(
            onPressed: () => _cancel(context, ref),
            icon: Icon(LucideIcons.x, color: context.status.danger),
            label: Text(
              t.visitCancel,
              style: TextStyle(color: context.status.danger),
            ),
          ),
        ];
      case VisitStatus.onSite:
        return [
          // The visit is recorded already: saying when one leaves is extra.
          StatusChip(
            t.visitRecorded,
            tone: Tone.success,
            icon: LucideIcons.mapPinCheck,
          ),
          const Gap(12),
          OutlinedButton.icon(
            onPressed: () => checkOut(context, ref, visit),
            icon: const Icon(LucideIcons.logOut),
            label: Text(t.visitCheckOut),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ];
      case VisitStatus.done || VisitStatus.missed || VisitStatus.cancelled:
        return const [];
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    if (!await confirm(
      context,
      title: t.visitCancelAsk,
      confirmLabel: t.visitCancel,
      destructive: true,
    )) {
      return;
    }
    if (!context.mounted) return;
    final ok = await perform(
      context,
      () => ref.read(planningRepositoryProvider).cancel(visit.id),
      success: t.visitCancelled,
    );
    if (ok) {
      ref.invalidate(visitsProvider);
      if (context.mounted) context.pop();
    }
  }
}

Future<void> _maps(VisitTarget target) {
  final query = target.latitude != null && target.longitude != null
      ? '${target.latitude},${target.longitude}'
      : [
          target.name,
          target.address,
          target.city,
        ].where((s) => s.isNotEmpty).join(', ');
  return launchUrl(
    Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': query}),
    mode: LaunchMode.externalApplication,
  );
}

/// A check-in or check-out: when, what the position said, where it was on the map, and what to
/// look at. The admin can make the recorded point the place's own position.
class _EventCard extends ConsumerWidget {
  const _EventCard({
    required this.event,
    required this.visit,
    required this.isAdmin,
  });

  final VisitEvent event;
  final Visit visit;
  final bool isAdmin;

  Future<void> _usePosition(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final target = visit.target;
    if (!await confirm(
      context,
      title: t.placePositionUse,
      message: target.hasPosition
          ? t.placePositionReplaceAsk(target.name)
          : t.placePositionSetAsk(target.name),
      confirmLabel: t.placePositionUse,
    )) {
      return;
    }
    if (!context.mounted) return;
    final ok = await perform(
      context,
      () => ref
          .read(planningRepositoryProvider)
          .setPosition(
            isDepot: target.isDepot,
            id: target.id,
            fix: Fix(
              latitude: event.latitude!,
              longitude: event.longitude!,
              accuracyMeters: event.accuracyMeters ?? 0,
            ),
          ),
      success: t.positionSaved,
    );
    if (ok) {
      ref
        ..invalidate(visitProvider(visit.id))
        ..invalidate(visitsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final target = visit.target;
    final recorded = event.latitude != null && event.longitude != null
        ? LatLng(event.latitude!, event.longitude!)
        : null;
    final place = target.latitude != null && target.longitude != null
        ? LatLng(target.latitude!, target.longitude!)
        : null;
    final locale = t.localeName;
    final at = Dates.time(event.occurredAt, locale);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Row(
              spacing: 8,
              children: [
                Icon(
                  event.isCheckIn ? LucideIcons.logIn : LucideIcons.logOut,
                  size: 18,
                ),
                Expanded(
                  child: Text(
                    event.isCheckIn ? t.visitArrivedAt(at) : t.visitLeftAt(at),
                    style: context.text.titleSmall,
                  ),
                ),
              ],
            ),
            // On its own line: what the position said can be a long sentence. "The place has no
            // position" is what was true at the visit: once the place has one, the distance below
            // says more.
            if (!(event.presence == Presence.noPosition && place != null))
              StatusChip(event.label(t), tone: event.tone, icon: event.icon),
            if (event.reason != null && event.reason!.isNotEmpty)
              Text(event.reason!, style: context.text.bodyMedium),
            if (event.flags.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in event.flags)
                    StatusChip(_flag(t, f), tone: Tone.warning),
                ],
              ),
            if (recorded != null) ...[
              PositionMap(
                recorded: recorded,
                place: place,
                accuracyMeters: event.accuracyMeters,
              ),
              Text(
                [
                  if (place != null)
                    t.positionFromPlace(
                      distanceText(metersBetween(recorded, place)),
                      target.name,
                    )
                  else
                    t.placeHasNoPosition(target.name),
                  if (event.accuracyMeters != null)
                    t.positionPrecision(event.accuracyMeters!.round()),
                ].join(' · '),
                style: context.text.bodySmall?.copyWith(
                  color: context.status.muted,
                ),
              ),
            ],
            if (recorded != null && isAdmin && event.isCheckIn)
              OutlinedButton.icon(
                onPressed: () => _usePosition(context, ref),
                icon: const Icon(LucideIcons.mapPinPlus, size: 16),
                label: Text(t.placePositionUse),
              ),
            if (event.latitude != null && event.longitude != null)
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.https('www.google.com', '/maps/search/', {
                    'api': '1',
                    'query': '${event.latitude},${event.longitude}',
                  }),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(LucideIcons.map, size: 16),
                label: Text(t.visitOpenInMaps),
              ),
          ],
        ),
      ),
    );
  }

  String _flag(AppLocalizations t, String code) => switch (code) {
    'MOCK_LOCATION' => t.flagMock,
    'LATE_SYNC' => t.flagLate,
    'LOW_ACCURACY' => t.flagImprecise,
    _ => code,
  };
}
