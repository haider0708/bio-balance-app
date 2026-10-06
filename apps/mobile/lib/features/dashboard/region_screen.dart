import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/json.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/money.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../l10n/app_localizations.dart';
import '../network/network_models.dart';
import '../network/network_repository.dart';
import '../network/network_screen.dart' show PdvTile;
import 'dashboard_repository.dart';
import 'dashboard_widgets.dart';
import 'management_home.dart' show attentionSections;
import 'trend_chart.dart';

/// One region as the admin sees it: who runs it, the numbers, its groups, stores and grossistes.
class RegionScreen extends ConsumerWidget {
  const RegionScreen({required this.regionId, this.name, super.key});

  final String regionId;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final data = ref.watch(dashboardProvider(regionId));
    final pdvs = ref.watch(pdvsProvider(regionId)).value ?? const <Pdv>[];
    final groups = ref.watch(groupsProvider(regionId)).value ?? const [];
    final depots = (ref.watch(depotsProvider).value ?? const <Depot>[])
        .where((d) => d.regionId == regionId)
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(name ?? t.regions)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardProvider(regionId));
          ref.invalidate(pdvsProvider(regionId));
          ref.invalidate(groupsProvider(regionId));
          await ref.read(dashboardProvider(regionId).future);
        },
        child: AsyncBody(
          value: data,
          onRetry: () => ref.invalidate(dashboardProvider(regionId)),
          builder: (d) {
            final region = d.objOrNull('region');
            final boss = region?.objOrNull('responsable');
            final sales = d.obj('sales');
            final locale = t.localeName;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                AppCard(
                  child: Row(
                    children: [
                      Avatar(_initials(boss?.str('name') ?? '?')),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.regionPageResponsable,
                              style: context.text.bodySmall?.copyWith(
                                color: context.status.muted,
                              ),
                            ),
                            Text(
                              boss?.str('name') ?? t.regionNoResponsable,
                              style: context.text.titleMedium,
                            ),
                          ],
                        ),
                      ),
                      if (boss?.strOrNull('phone') != null)
                        IconButton.filledTonal(
                          tooltip: t.call,
                          onPressed: () => launchUrl(
                            Uri(
                              scheme: 'tel',
                              path: boss!.str('phone').replaceAll(' ', ''),
                            ),
                          ),
                          icon: const Icon(LucideIcons.phone),
                        ),
                    ],
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        icon: LucideIcons.store,
                        label: t.regionStores,
                        value: '${region?.integer('pdvs') ?? 0}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatTile(
                        icon: LucideIcons.users,
                        label: t.tabPeople,
                        value: '${region?.integer('members') ?? 0}',
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        icon: LucideIcons.receipt,
                        label: t.last7Days,
                        value: t.units(sales.obj('week').integer('units')),
                        hint: t.salesCount(sales.obj('week').integer('sales')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatTile(
                        icon: LucideIcons.banknote,
                        label: t.rewardsMonth,
                        value: Money.format(
                          sales.obj('month').integer('rewardMillimes'),
                          locale,
                        ),
                      ),
                    ),
                  ],
                ),
                SectionHeader(t.salesLast14Days),
                AppCard(child: TrendChart(days: d.list('trend'))),
                ...attentionSections(context, t, d, admin: true),
                if (d.list('topProducts').isNotEmpty) ...[
                  SectionHeader(t.topProducts),
                  TopProducts(items: d.list('topProducts')),
                ],
                if (d.list('topPdvs').isNotEmpty) ...[
                  SectionHeader(t.topPdvs),
                  TopPlaces(items: d.list('topPdvs')),
                ],
                if (groups.isNotEmpty) ...[
                  SectionHeader(t.regionGroups),
                  for (final g in groups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        child: Row(
                          children: [
                            const Icon(LucideIcons.layers),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                g.name,
                                style: context.text.titleSmall,
                              ),
                            ),
                            Text(
                              t.pdvCount(g.pdvCount),
                              style: context.text.bodySmall?.copyWith(
                                color: context.status.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (pdvs.isNotEmpty) ...[
                  SectionHeader(t.regionStores),
                  for (final p in pdvs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PdvTile(pdv: p),
                    ),
                ],
                if (depots.isNotEmpty) ...[
                  SectionHeader(t.regionGrossistes),
                  for (final dep in depots)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        child: Row(
                          children: [
                            const Icon(LucideIcons.warehouse),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dep.name,
                                    style: context.text.titleSmall,
                                  ),
                                  Text(
                                    [?dep.grossisteName, dep.city].join(' · '),
                                    style: context.text.bodySmall?.copyWith(
                                      color: context.status.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                const Gap(8),
                OutlinedButton.icon(
                  onPressed: () => context.push('/reports'),
                  icon: const Icon(LucideIcons.chartNoAxesColumn),
                  label: Text(t.reportsTitle),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.isEmpty
      ? '?'
      : parts.take(2).map((p) => p[0].toUpperCase()).join();
}
