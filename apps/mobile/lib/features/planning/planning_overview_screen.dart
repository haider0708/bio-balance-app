import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import 'planning_models.dart';
import 'planning_repository.dart';
import 'visit_widgets.dart';

/// The admin's view (read only): per responsable, what was planned, done, missed, and what the check-ins said.
class PlanningOverviewScreen extends ConsumerStatefulWidget {
  const PlanningOverviewScreen({super.key});

  @override
  ConsumerState<PlanningOverviewScreen> createState() =>
      _PlanningOverviewScreenState();
}

class _PlanningOverviewScreenState
    extends ConsumerState<PlanningOverviewScreen> {
  /// Days back from today: 0 is today only.
  int _days = 7;

  OverviewQuery get _query {
    final now = DateTime.now();
    return (
      from: Dates.day(now.subtract(Duration(days: _days))),
      to: Dates.day(now),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lines = ref.watch(planningOverviewProvider(_query));
    return Scaffold(
      appBar: AppBar(title: Text(t.planningOverviewTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final (days, label) in [
                (0, t.today),
                (7, t.overviewRange7),
                (30, t.overviewRange30),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _days == days,
                  onSelected: (_) => setState(() => _days = days),
                ),
            ],
          ),
          const Gap(12),
          AsyncBody<List<PlanningLine>>(
            value: lines,
            onRetry: () => ref.invalidate(planningOverviewProvider(_query)),
            builder: (list) => list.isEmpty
                ? EmptyState(
                    icon: LucideIcons.calendarX,
                    title: t.overviewEmpty,
                  )
                : Column(
                    spacing: 12,
                    children: [
                      for (final line in list)
                        _LineCard(
                          line: line,
                          onTap: () => context.push(
                            '/planning/overview/${line.responsableId}',
                            extra: (line.name, _query),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line, required this.onTap});

  final PlanningLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.name, style: context.text.titleMedium),
                    Text(
                      line.region,
                      style: context.text.bodySmall?.copyWith(
                        color: context.status.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronRight, size: 18),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip(
                '${t.overviewPlanned} ${line.planned}',
                tone: Tone.info,
              ),
              StatusChip('${t.overviewDone} ${line.done}', tone: Tone.success),
              if (line.missed > 0)
                StatusChip(
                  '${t.overviewMissed} ${line.missed}',
                  tone: Tone.danger,
                ),
              StatusChip(
                '${t.overviewAtPlace} ${line.verified}',
                tone: Tone.success,
                icon: LucideIcons.mapPinCheck,
              ),
              if (line.outOfRange > 0)
                StatusChip(
                  '${t.overviewAway} ${line.outOfRange}',
                  tone: Tone.warning,
                  icon: LucideIcons.mapPinOff,
                ),
              if (line.noFix > 0)
                StatusChip(
                  '${t.overviewNoPosition} ${line.noFix}',
                  icon: LucideIcons.mapPin,
                ),
            ],
          ),
          if (line.avgMinutes != null)
            Text(
              t.overviewAverage(line.avgMinutes!),
              style: context.text.bodySmall?.copyWith(
                color: context.status.muted,
              ),
            ),
        ],
      ),
    );
  }
}

/// The visits of one responsable over the period the admin was looking at.
class ResponsableVisitsScreen extends ConsumerWidget {
  const ResponsableVisitsScreen({
    required this.responsableId,
    required this.name,
    required this.query,
    super.key,
  });

  final String responsableId;
  final String name;
  final OverviewQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final visits = ref.watch(
      visitsProvider((
        from: query.from,
        to: query.to,
        responsableId: responsableId,
        regionId: null,
      )),
    );
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: AsyncBody<List<Visit>>(
        value: visits,
        onRetry: () => ref.invalidate(visitsProvider),
        builder: (list) => list.isEmpty
            ? EmptyState(icon: LucideIcons.calendarX, title: t.overviewEmpty)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final v in list.reversed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: VisitCard(
                        visit: v,
                        onTap: () => context.push('/planning/visits/${v.id}'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
