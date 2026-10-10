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
import '../analytics/explorer_screen.dart' show storesBoardLocation;
import '../analytics/lens.dart';
import '../network/network_models.dart';
import '../network/network_repository.dart';
import '../network/region_moves.dart';
import '../network/regions_screen.dart';
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

  /// Choose who looks after this region: any responsable can be moved here (swapping with the current one), or a new one created.
  Future<void> _changeResponsable(
    BuildContext context,
    WidgetRef ref,
    RegionInfo? info,
  ) async {
    final t = AppLocalizations.of(context);
    final people = await ref.read(
      peopleProvider((
        role: 'RESPONSABLE',
        pdvId: null,
        regionId: null,
        status: null,
      )).future,
    );
    if (!context.mounted) return;
    final regions = await ref.read(regionsOverviewProvider.future);
    if (!context.mounted) return;
    final candidates = people
        .where(
          (p) =>
              p.regionId != regionId &&
              (p.status == ItemStatus.active || p.status == ItemStatus.pending),
        )
        .toList();
    final chosen = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                t.regionPickResponsable(name ?? info?.name ?? ''),
                style: context.text.titleLarge,
              ),
            ),
            for (final p in candidates)
              ListTile(
                leading: Avatar(p.initials, size: 36),
                title: Text(p.name),
                subtitle: Text(
                  t.regionCurrently(
                    regions
                            .where((r) => r.id == p.regionId)
                            .firstOrNull
                            ?.name ??
                        '—',
                  ),
                ),
                onTap: () => Navigator.pop(context, p),
              ),
            ListTile(
              leading: const Icon(LucideIcons.userPlus),
              title: Text(t.regionNewResponsable),
              onTap: () => Navigator.pop(context, 'new'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (chosen == 'new') {
      await context.push('/people/new', extra: regionId);
      refreshAfterMove(ref);
    } else if (chosen is Person) {
      await moveResponsableTo(context, ref, chosen, regionId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final data = ref.watch(dashboardProvider(regionId));
    final pdvs = ref.watch(pdvsProvider(regionId)).value ?? const <Pdv>[];
    final groups = ref.watch(groupsProvider(regionId)).value ?? const [];
    final info =
        (ref.watch(regionsOverviewProvider).value ?? const <RegionInfo>[])
            .where((r) => r.id == regionId)
            .firstOrNull;
    final depots = (ref.watch(depotsProvider).value ?? const <Depot>[])
        .where((d) => d.regionId == regionId)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(name ?? t.regions),
        actions: [
          IconButton(
            tooltip: t.regionRename,
            icon: const Icon(LucideIcons.pencil),
            onPressed: () async {
              if (await renameRegionFlow(context, ref, regionId, name ?? '') &&
                  context.mounted) {
                context.pop();
              }
            },
          ),
          if (info?.deletable ?? false)
            IconButton(
              tooltip: t.regionDelete,
              icon: const Icon(LucideIcons.trash2),
              onPressed: () async {
                if (await deleteRegionFlow(context, ref, info!) &&
                    context.mounted) {
                  context.pop();
                }
              },
            ),
        ],
      ),
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
            final day = d.str('today', tunisToday());
            Lens here(int days, {Metric sort = Metric.units}) => Lens.lastDays(
              days,
              today: day,
              sort: sort,
            ).withFacet(Facet.region, regionId);
            void open(Lens lens) => context.push(lens.location());
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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
                      TextButton(
                        onPressed: () => _changeResponsable(context, ref, info),
                        child: Text(t.regionChangeResponsable),
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
                AutoGrid(
                  children: [
                    StatTile(
                      icon: LucideIcons.store,
                      label: t.regionStores,
                      value: '${region?.integer('pdvs') ?? 0}',
                      onTap: () => context.push(storesBoardLocation(here(30))),
                    ),
                    StatTile(
                      icon: LucideIcons.users,
                      label: t.tabPeople,
                      value: '${region?.integer('members') ?? 0}',
                      onTap: () => open(here(30)),
                    ),
                    StatTile(
                      icon: LucideIcons.receipt,
                      label: t.last7Days,
                      value: t.units(sales.obj('week').integer('units')),
                      hint: t.salesCount(sales.obj('week').integer('sales')),
                      onTap: () => open(here(7)),
                    ),
                    StatTile(
                      icon: LucideIcons.banknote,
                      label: t.rewardsMonth,
                      value: Money.format(
                        sales.obj('month').integer('rewardMillimes'),
                        locale,
                      ),
                      onTap: () => open(here(30, sort: Metric.reward)),
                    ),
                  ],
                ),
                const Gap(12),
                FilledButton.tonalIcon(
                  onPressed: () => open(here(30)),
                  icon: const Icon(LucideIcons.chartColumnBig),
                  label: Text(t.regionAnalytics),
                ),
                SectionHeader(t.salesLast14Days),
                AppCard(
                  child: TrendChart(
                    days: d.list('trend'),
                    onTapDay: (x) =>
                        open(Lens.day(x).withFacet(Facet.region, regionId)),
                  ),
                ),
                ...attentionSections(context, t, d, admin: true),
                if (d.list('topProducts').isNotEmpty) ...[
                  SectionHeader(t.topProducts),
                  TopProducts(
                    items: d.list('topProducts'),
                    onTap: (p) => open(
                      here(30).withFacet(Facet.product, p.str('productId')),
                    ),
                  ),
                ],
                if (d.list('topPdvs').isNotEmpty) ...[
                  SectionHeader(t.topPdvs),
                  TopPlaces(
                    items: d.list('topPdvs'),
                    onTap: (p) =>
                        open(here(30).withFacet(Facet.pdv, p.str('pdvId'))),
                  ),
                ],
                if (groups.isNotEmpty) ...[
                  SectionHeader(t.regionGroups),
                  for (final g in groups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        onTap: () =>
                            open(here(30).withFacet(Facet.group, g.id)),
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
                            const SizedBox(width: 4),
                            Icon(
                              LucideIcons.chevronRight,
                              size: 18,
                              color: context.status.muted,
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
                        onTap: () => context.push('/depots/${dep.id}'),
                        child: Row(
                          children: [
                            const IconBadge(LucideIcons.warehouse),
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
                                    dep.counted
                                        ? '${dep.city} · ${t.depotHolds(dep.units, dep.products)}'
                                        : '${dep.city} · ${t.depotNoStock}',
                                    style: context.text.bodySmall?.copyWith(
                                      color: context.status.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              LucideIcons.chevronRight,
                              size: 18,
                              color: context.status.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
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
