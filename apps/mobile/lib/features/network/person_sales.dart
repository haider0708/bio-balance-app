import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/json.dart';
import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/money.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../l10n/app_localizations.dart';
import '../analytics/analytics_repository.dart';
import '../analytics/lens.dart';
import '../sales/sales_history_screen.dart' show SaleTile;
import 'network_models.dart';

/// What a team member sold: the numbers of a period (each opens its detail), the latest sales (each
/// opens the sale, where the admin can correct it), and the way to the full list and the analysis.
class PersonSales extends ConsumerStatefulWidget {
  const PersonSales({required this.person, super.key});

  final Person person;

  @override
  ConsumerState<PersonSales> createState() => _PersonSalesState();
}

class _PersonSalesState extends ConsumerState<PersonSales> {
  /// 1 = today, 7 and 30 = the last days.
  int _days = 30;

  Lens get _lens => (_days == 1 ? Lens.day(tunisToday()) : Lens.lastDays(_days))
      .withFacet(Facet.seller, widget.person.id);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lens = _lens;
    final overview = ref.watch(analyticsProvider(lens));
    final latest = ref.watch(latestSalesProvider(lens));
    final money = ref.watch(meProvider).role == Role.admin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(t.salesOfPerson),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (days, label) in [
              (1, t.today),
              (7, t.days7Short),
              (30, t.days30Short),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _days == days,
                onSelected: (_) => setState(() => _days = days),
              ),
          ],
        ),
        const Gap(12),
        AsyncBody(
          value: overview,
          onRetry: () => ref.invalidate(analyticsProvider(lens)),
          builder: (data) {
            final totals = data.obj('totals');
            void open() => context.push(lens.location());
            return Row(
              spacing: 10,
              children: [
                Expanded(
                  child: _Metric(
                    value: '${totals.integer('units')}',
                    label: t.unitsShort,
                    onTap: open,
                  ),
                ),
                Expanded(
                  child: _Metric(
                    value: '${totals.integer('sales')}',
                    label: t.kpiSales,
                    onTap: () => context.push(lens.location('/explore/sales')),
                  ),
                ),
                if (money)
                  Expanded(
                    child: _Metric(
                      value: Money.format(
                        totals.integer('rewardMillimes'),
                        t.localeName,
                      ),
                      label: t.rewardsShort,
                      onTap: open,
                    ),
                  ),
              ],
            );
          },
        ),
        const Gap(16),
        SectionHeader(t.latestSales),
        latest.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (sales) => sales.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      t.noSalesInPeriod,
                      style: context.text.bodyMedium?.copyWith(
                        color: context.status.muted,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final sale in sales) ...[
                      SaleTile(sale: sale, showDate: true),
                      const Gap(8),
                    ],
                    Text(
                      t.tapSaleHint,
                      style: context.text.bodySmall?.copyWith(
                        color: context.status.muted,
                      ),
                    ),
                  ],
                ),
        ),
        const Gap(12),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.push(lens.location('/explore/sales')),
                icon: const Icon(LucideIcons.list),
                label: Text(t.allSalesOfPerson),
              ),
            ),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.push(lens.location()),
                icon: const Icon(LucideIcons.chartColumnBig),
                label: Text(t.fullAnalysis),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A number with its name under it, small enough for three in a row; it opens its detail.
class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  style: context.text.titleLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: context.text.bodySmall?.copyWith(
                  color: context.status.muted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Icon(LucideIcons.chevronRight, size: 16, color: context.status.muted),
      ],
    ),
  );
}
