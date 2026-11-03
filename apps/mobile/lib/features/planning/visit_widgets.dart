import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/components.dart';
import '../../l10n/app_localizations.dart';
import 'planning_labels.dart';
import 'planning_models.dart';

/// One visit in a list: the time, the place, what it is for, how it went.
class VisitCard extends StatelessWidget {
  const VisitCard({
    required this.visit,
    required this.onTap,
    this.showResponsable = false,
    super.key,
  });

  final Visit visit;
  final VoidCallback onTap;
  final bool showResponsable;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = t.localeName;
    final arrival = visit.checkIn;
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 14,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Dates.time(visit.plannedStart, locale),
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  Dates.time(visit.plannedEnd, locale),
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    Icon(
                      visit.kind.icon,
                      size: 15,
                      color: context.colors.primary,
                    ),
                    Flexible(
                      child: Text(
                        visit.kind.label(t),
                        style: context.text.labelMedium?.copyWith(
                          color: context.colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (visit.unplanned)
                      Text(
                        '· ${t.visitUnplanned}',
                        style: context.text.labelSmall?.copyWith(
                          color: context.status.muted,
                        ),
                      ),
                  ],
                ),
                Text(visit.target.name, style: context.text.titleSmall),
                if (visit.target.address.isNotEmpty ||
                    visit.target.city.isNotEmpty)
                  Text(
                    [
                      visit.target.address,
                      visit.target.city,
                    ].where((s) => s.isNotEmpty).join(', '),
                    style: context.text.bodySmall?.copyWith(
                      color: context.status.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (showResponsable && visit.responsableName != null)
                  Text(
                    t.visitWithWho(visit.responsableName!),
                    style: context.text.bodySmall,
                  ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusChip(visit.status.label(t), tone: visit.status.tone),
                    if (arrival != null)
                      StatusChip(
                        arrival.label(t),
                        tone: arrival.tone,
                        icon: arrival.icon,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
