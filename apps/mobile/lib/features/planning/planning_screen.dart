import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import 'planning_actions.dart';
import 'planning_labels.dart';
import 'planning_models.dart';
import 'planning_places.dart';
import 'planning_repository.dart';
import 'visit_outbox.dart';
import 'visit_widgets.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _monday(DateTime d) =>
    _dateOnly(d).subtract(Duration(days: d.weekday - DateTime.monday));

/// The responsable's calendar: a week strip, the day's visits, and what to do now.
class PlanningScreen extends ConsumerStatefulWidget {
  const PlanningScreen({super.key});

  @override
  ConsumerState<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends ConsumerState<PlanningScreen> {
  DateTime _selected = _dateOnly(DateTime.now());

  /// The month shown, with a week on each side so the strip never runs out of data.
  VisitsQuery get _query {
    final first = DateTime(_selected.year, _selected.month);
    final last = DateTime(_selected.year, _selected.month + 1, 0);
    return (
      from: Dates.day(first.subtract(const Duration(days: 7))),
      to: Dates.day(last.add(const Duration(days: 7))),
      responsableId: null,
      regionId: null,
    );
  }

  void _select(DateTime day) => setState(() => _selected = _dateOnly(day));

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: AppLocalizations.of(context).planningPickDay,
    );
    if (picked != null) _select(picked);
  }

  Future<void> _plan() async {
    await context.push('/planning/new', extra: _selected);
    ref.invalidate(visitsProvider);
  }

  /// "I'm at a place now": choose the place and what for, then read the position.
  Future<void> _unplanned() async {
    final choice = await showModalBottomSheet<(PlaceOption, VisitKind)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _UnplannedSheet(),
    );
    if (choice == null || !mounted) return;
    await startUnplanned(
      context,
      ref,
      isDepot: choice.$1.isDepot,
      placeId: choice.$1.id,
      placeName: choice.$1.name,
      kind: choice.$2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = t.localeName;
    final visits = ref.watch(visitsProvider(_query));
    final pending = ref.watch(visitOutboxProvider);
    final week = [
      for (var i = 0; i < 7; i++) _monday(_selected).add(Duration(days: i)),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(t.planningTitle),
        actions: [
          IconButton(
            tooltip: t.planningPickDay,
            onPressed: _pickDay,
            icon: const Icon(LucideIcons.calendarDays),
          ),
          IconButton(
            tooltip: t.planningSettingsTitle,
            onPressed: () => context.push('/planning/settings'),
            icon: const Icon(LucideIcons.settings),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _plan,
        icon: const Icon(LucideIcons.plus),
        label: Text(t.planningPlanVisit),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(visitsProvider(_query));
          await ref.read(visitsProvider(_query).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () =>
                      _select(_selected.subtract(const Duration(days: 7))),
                  icon: const Icon(LucideIcons.chevronLeft),
                ),
                Expanded(
                  child: Center(
                    child: TextButton(
                      onPressed: () => _select(DateTime.now()),
                      child: Text(
                        Dates.monthYear(_selected, locale),
                        style: context.text.titleMedium,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      _select(_selected.add(const Duration(days: 7))),
                  icon: const Icon(LucideIcons.chevronRight),
                ),
              ],
            ),
            AsyncBody<List<Visit>>(
              value: visits,
              onRetry: () => ref.invalidate(visitsProvider(_query)),
              builder: (all) {
                final byDay = <String, List<Visit>>{};
                for (final v in all) {
                  if (v.status != VisitStatus.cancelled) {
                    (byDay[v.day] ??= []).add(v);
                  }
                }
                final today = byDay[Dates.day(_selected)] ?? const [];
                final listed = all
                    .where((v) => v.day == Dates.day(_selected))
                    .toList();
                final done = today
                    .where((v) => v.status == VisitStatus.done)
                    .length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    Row(
                      children: [
                        for (final day in week)
                          Expanded(
                            child: _DayChip(
                              day: day,
                              selected: day == _selected,
                              isToday: day == _dateOnly(DateTime.now()),
                              count: byDay[Dates.day(day)]?.length ?? 0,
                              onTap: () => _select(day),
                            ),
                          ),
                      ],
                    ),
                    if (pending.isNotEmpty) _OutboxBanner(pending: pending),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${DateFormat.MMMEd(locale).format(_selected)} · ${t.planningVisitCount(today.length)}'
                            '${done > 0 ? ' · ${t.planningDoneCount(done)}' : ''}',
                            style: context.text.titleSmall,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _unplanned,
                          icon: const Icon(LucideIcons.mapPin, size: 16),
                          label: Text(t.planningAtStore),
                        ),
                      ],
                    ),
                    if (listed.isEmpty)
                      EmptyState(
                        icon: LucideIcons.calendarPlus,
                        title: t.planningNoVisits,
                        message: t.planningNoVisitsHint,
                      )
                    else
                      for (final v in listed)
                        VisitCard(
                          visit: v,
                          onTap: () async {
                            await context.push('/planning/visits/${v.id}');
                            ref.invalidate(visitsProvider);
                          },
                        ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.count,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locale = AppLocalizations.of(context).localeName;
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          spacing: 4,
          children: [
            Text(
              DateFormat.E(locale).format(day),
              style: context.text.labelSmall?.copyWith(
                color: context.status.muted,
              ),
              maxLines: 1,
            ),
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? c.primary : null,
                border: !selected && isToday
                    ? Border.all(color: c.primary, width: 1.5)
                    : null,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.day}',
                style: context.text.titleSmall?.copyWith(
                  color: selected ? c.onPrimary : null,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              height: 6,
              child: count == 0
                  ? null
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 3,
                      children: [
                        for (var i = 0; i < count.clamp(1, 3); i++)
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: c.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Arrivals and departures waiting for a connection, or refused: the person sees them and can act.
class _OutboxBanner extends ConsumerWidget {
  const _OutboxBanner({required this.pending});

  final List<PendingPresence> pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final waiting = pending.where((p) => p.error == null).length;
    final refused = pending.where((p) => p.error != null).toList();
    return Column(
      spacing: 8,
      children: [
        if (waiting > 0)
          AppCard(
            borderColor: context.status.warning,
            child: Row(
              spacing: 10,
              children: [
                Icon(LucideIcons.cloudOff, color: context.status.warning),
                Expanded(child: Text(t.outboxWaiting(waiting))),
                TextButton(
                  onPressed: () =>
                      ref.read(visitOutboxProvider.notifier).flush(),
                  child: Text(t.retry),
                ),
              ],
            ),
          ),
        for (final p in refused)
          AppCard(
            borderColor: context.status.danger,
            child: Row(
              spacing: 10,
              children: [
                Icon(LucideIcons.triangleAlert, color: context.status.danger),
                Expanded(
                  child: Text('${p.place}: ${t.outboxRefused(p.error!)}'),
                ),
                if (p.error == 'POSITION_REASON_REQUIRED')
                  TextButton(
                    onPressed: () async {
                      final reason = await askNote(
                        context,
                        title: t.visitReasonTitle,
                        confirmLabel: t.visitReasonSend,
                        hint: t.visitReasonHint,
                      );
                      if (reason != null) {
                        await ref
                            .read(visitOutboxProvider.notifier)
                            .retryWithReason(p, reason);
                      }
                    },
                    child: Text(t.visitReasonSend),
                  )
                else
                  IconButton(
                    onPressed: () => ref
                        .read(visitOutboxProvider.notifier)
                        .discard(p.id, p.kind),
                    icon: const Icon(LucideIcons.x),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Choose where you are and why; the position is read right after.
class _UnplannedSheet extends ConsumerStatefulWidget {
  const _UnplannedSheet();

  @override
  ConsumerState<_UnplannedSheet> createState() => _UnplannedSheetState();
}

class _UnplannedSheetState extends ConsumerState<_UnplannedSheet> {
  VisitKind _kind = VisitKind.followUp;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final places = ref.watch(placeOptionsProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(t.unplannedTitle, style: context.text.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final k in VisitKind.values)
                  ChoiceChip(
                    label: Text(k.label(t)),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: AsyncBody<List<PlaceOption>>(
              value: places,
              onRetry: () => ref.invalidate(placeOptionsProvider),
              builder: (list) => ListView(
                controller: scroll,
                children: [
                  for (final p in list)
                    ListTile(
                      leading: Icon(
                        p.isDepot ? LucideIcons.warehouse : LucideIcons.store,
                      ),
                      title: Text(p.name),
                      subtitle: Text(p.subtitle),
                      onTap: () => Navigator.pop(context, (p, _kind)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
