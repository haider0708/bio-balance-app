import 'dart:async';

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
import '../analytics/explorer_screen.dart' show storesBoardLocation;
import '../analytics/lens.dart';
import '../notifications/notifications_repository.dart';
import 'dashboard_repository.dart';
import 'dashboard_widgets.dart';
import 'home_scaffold.dart';
import 'trend_chart.dart';

/// The home of the admin and of each responsable: numbers for the network (or the region), and what needs attention.
class ManagementHome extends ConsumerWidget {
  const ManagementHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final admin = me.role == Role.admin;
    final data = ref.watch(dashboardProvider(null));
    return HomeScaffold(
      title: admin
          ? t.helloName(me.name.split(' ').first)
          : t.helloName(me.name.split(' ').first),
      subtitle: admin ? t.wholeNetwork : t.regionOf(me.region?.name ?? ''),
      onRefresh: () async {
        ref.invalidate(dashboardProvider(null));
        unawaited(ref.read(unreadCountProvider.notifier).refresh());
        await ref.read(dashboardProvider(null).future);
      },
      body: AsyncBody(
        value: data,
        onRetry: () => ref.invalidate(dashboardProvider(null)),
        builder: (d) => _Body(data: d, admin: admin),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data, required this.admin});

  final Json data;
  final bool admin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final locale = t.localeName;
    final sales = data.obj('sales');
    final today = sales.obj('today');
    final week = sales.obj('week');
    final month = sales.obj('month');
    final approvals = data.obj('approvals');
    final restocks = data.obj('restocks');
    final regions = data.list('regions');
    final waiting = approvals.integer('total');
    // Every number opens what it is made of, counted on the same Tunis day as the dashboard.
    final day = data.str('today', tunisToday());
    void open(Lens lens) => context.push(lens.location());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (admin && waiting > 0)
          _Hero(
            icon: LucideIcons.inbox,
            title: t.waitingForYou(waiting),
            subtitle: _approvalSummary(t, approvals),
            highlight: true,
            onTap: () => context.go('/approvals'),
          )
        else if (!admin && waiting > 0)
          _Hero(
            icon: LucideIcons.clock,
            title: t.waitingAdmin(waiting),
            subtitle: _approvalSummary(t, approvals),
            highlight: false,
            onTap: () => context.go('/pdvs'),
          ),
        if (!admin && restocks.integer('SHIPPED') > 0) ...[
          const Gap(12),
          _Hero(
            icon: LucideIcons.packageCheck,
            title: t.deliveriesToConfirm(restocks.integer('SHIPPED')),
            subtitle: t.deliveriesToConfirmHint,
            highlight: true,
            onTap: () => context.go('/restocks'),
          ),
        ],
        const Gap(12),
        AutoGrid(
          children: [
            StatTile(
              icon: LucideIcons.receipt,
              label: t.today,
              value: t.units(today.integer('units')),
              hint: t.salesCount(today.integer('sales')),
              onTap: () => open(Lens.day(day)),
            ),
            StatTile(
              icon: LucideIcons.calendarDays,
              label: t.last7Days,
              value: t.units(week.integer('units')),
              hint: t.salesCount(week.integer('sales')),
              onTap: () => open(Lens.lastDays(7, today: day)),
            ),
            StatTile(
              icon: LucideIcons.banknote,
              label: t.rewardsMonth,
              value: Money.format(month.integer('rewardMillimes'), locale),
              hint: t.units(month.integer('units')),
              onTap: () =>
                  open(Lens.lastDays(30, today: day, sort: Metric.reward)),
            ),
            StatTile(
              icon: LucideIcons.store,
              label: t.activePdvs,
              value: '${data.obj('pdvs').integer('active')}',
              hint: data.obj('pdvs').integer('pending') > 0
                  ? t.pendingCount(data.obj('pdvs').integer('pending'))
                  : null,
              onTap: () => context.push(
                storesBoardLocation(Lens.lastDays(30, today: day)),
              ),
            ),
          ],
        ),
        SectionHeader(
          t.salesLast14Days,
          trailing: _SeeAll(onTap: () => open(Lens.lastDays(14, today: day))),
        ),
        AppCard(
          child: TrendChart(
            days: data.list('trend'),
            onTapDay: (d) => open(Lens.day(d)),
          ),
        ),
        if (admin && regions.isNotEmpty) ...[
          SectionHeader(t.regions),
          AutoGrid(
            minItemWidth: 300,
            maxColumns: 3,
            spacing: 8,
            children: [
              for (final r in regions)
                AppCard(
                  onTap: () => context.push(
                    '/regions/${r.str('id')}',
                    extra: r.str('name'),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.colors.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          (r.str('name')).substring(0, 1),
                          style: context.text.titleMedium?.copyWith(
                            color: context.colors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.str('name'), style: context.text.titleSmall),
                            Text(
                              '${t.pdvCount(r.integer('pdvs'))} · ${t.teamCount(r.integer('members'))}',
                              style: context.text.bodySmall?.copyWith(
                                color: context.status.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            t.units(r.integer('units')),
                            style: context.text.titleSmall,
                          ),
                          Text(
                            t.last7Days,
                            style: context.text.bodySmall?.copyWith(
                              color: context.status.muted,
                            ),
                          ),
                        ],
                      ),
                      if (r.integer('pending') > 0) ...[
                        const SizedBox(width: 8),
                        StatusChip(
                          '${r.integer('pending')}',
                          tone: Tone.warning,
                        ),
                      ],
                      const SizedBox(width: 4),
                      Icon(
                        LucideIcons.chevronRight,
                        size: 18,
                        color: context.status.muted,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        ...attentionSections(context, t, data, admin: admin),
        if (data.list('lowByPlace').isNotEmpty) ...[
          SectionHeader(t.runningLow),
          LowByStore(items: data.list('lowByPlace'), canOrder: !admin),
        ],
        if (data.list('topProducts').isNotEmpty) ...[
          SectionHeader(
            t.topProducts,
            trailing: _SeeAll(onTap: () => open(Lens.lastDays(30, today: day))),
          ),
          TopProducts(
            items: data.list('topProducts'),
            onTap: (p) => open(
              Lens.lastDays(
                30,
                today: day,
              ).withFacet(Facet.product, p.str('productId')),
            ),
          ),
        ],
        if (data.list('topPdvs').isNotEmpty) ...[
          SectionHeader(
            admin ? t.topPdvs : t.bestStores,
            trailing: _SeeAll(
              onTap: () => context.push(
                storesBoardLocation(Lens.lastDays(30, today: day)),
              ),
            ),
          ),
          TopPlaces(
            items: data.list('topPdvs'),
            onTap: (p) => open(
              Lens.lastDays(
                30,
                today: day,
              ).withFacet(Facet.pdv, p.str('pdvId')),
            ),
          ),
        ],
        if (!admin && data.list('topGroups').isNotEmpty) ...[
          SectionHeader(t.bestGroups),
          TopPlaces(
            items: data.list('topGroups'),
            icon: LucideIcons.layers,
            onTap: (g) => open(
              Lens.lastDays(
                30,
                today: day,
              ).withFacet(Facet.group, g.str('groupId')),
            ),
          ),
        ],
      ],
    );
  }

  String _approvalSummary(AppLocalizations t, Json c) {
    final parts = <String>[
      if (c.integer('PDV') > 0) t.approvalPdvs(c.integer('PDV')),
      if (c.integer('MEMBER') > 0) t.approvalMembers(c.integer('MEMBER')),
      if (c.integer('STOCK') > 0) t.approvalStock(c.integer('STOCK')),
      if (c.integer('RECEIPT') > 0) t.approvalReceipts(c.integer('RECEIPT')),
      if (c.integer('RESTOCK_REQUEST') > 0)
        t.approvalRequests(c.integer('RESTOCK_REQUEST')),
      if (c.integer('PAYOUT') > 0) t.approvalPayouts(c.integer('PAYOUT')),
      if (c.integer('GROUP') > 0) t.approvalGroups(c.integer('GROUP')),
    ];
    return parts.join(' · ');
  }
}

/// "See all" at the end of a section title: opens the analytics behind it.
class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onTap,
    iconAlignment: IconAlignment.end,
    icon: const Icon(LucideIcons.chevronRight, size: 16),
    label: Text(AppLocalizations.of(context).analyticsDetails),
  );
}

/// "Needs attention", split by what it is about, so each kind of work has its own place.
List<Widget> attentionSections(
  BuildContext context,
  AppLocalizations t,
  Json data, {
  required bool admin,
  String? regionId,
}) {
  final approvals = data.obj('approvals');
  final restocks = data.obj('restocks');
  final attention = data.obj('attention');
  final payouts = data.objOrNull('payouts');
  final grossistes = data.objOrNull('grossistes');
  final uncounted = grossistes?.integer('uncounted') ?? 0;
  final locale = t.localeName;
  void approvals_() => context.go('/approvals');
  return [
    SectionHeader(t.needsAttention),
    if (admin) ...[
      AttentionGroup(
        title: t.toApprove,
        rows: [
          AttentionLine(
            icon: LucideIcons.store,
            tone: Tone.warning,
            label: t.attnStores,
            count: approvals.integer('PDV'),
            onTap: approvals_,
          ),
          AttentionLine(
            icon: LucideIcons.layers,
            tone: Tone.warning,
            label: t.attnGroups,
            count: approvals.integer('GROUP'),
            onTap: approvals_,
          ),
          AttentionLine(
            icon: LucideIcons.userPlus,
            tone: Tone.warning,
            label: t.attnMembers,
            count: approvals.integer('MEMBER'),
            onTap: approvals_,
          ),
          AttentionLine(
            icon: LucideIcons.boxes,
            tone: Tone.warning,
            label: t.attnStockCounts,
            count: approvals.integer('STOCK'),
            onTap: approvals_,
          ),
          AttentionLine(
            icon: LucideIcons.packageCheck,
            tone: Tone.warning,
            label: t.attnReceipts,
            count: approvals.integer('RECEIPT'),
            onTap: approvals_,
          ),
          AttentionLine(
            icon: LucideIcons.truck,
            tone: Tone.warning,
            label: t.attnRestockRequests,
            count: approvals.integer('RESTOCK_REQUEST'),
            onTap: approvals_,
          ),
          AttentionLine(
            icon: LucideIcons.rotateCcw,
            tone: Tone.warning,
            label: t.attnRecounts,
            count: approvals.integer('RECOUNT'),
            onTap: approvals_,
          ),
        ],
      ),
    ],
    AttentionGroup(
      title: t.stockSection,
      rows: [
        AttentionLine(
          icon: LucideIcons.packageMinus,
          tone: Tone.warning,
          label: t.lowStock,
          count: attention.integer('lowStock'),
          onTap: () => context.push('/stock-attention'),
        ),
      ],
    ),
    if (uncounted > 0)
      AttentionGroup(
        title: t.grossistesTitle,
        rows: [
          AttentionLine(
            icon: LucideIcons.warehouse,
            tone: Tone.warning,
            label: t.attnGrossisteUncounted,
            count: uncounted,
            onTap: () => context.push('/depots'),
          ),
        ],
      ),
    AttentionGroup(
      title: t.restocksSection,
      rows: [
        // The responsable ships the orders the admin gave to a grossiste.
        if (!admin)
          AttentionLine(
            icon: LucideIcons.packageCheck,
            tone: Tone.warning,
            label: t.attnToShip,
            count: data.integer('toShip'),
            onTap: () => context.go('/restocks'),
          ),
        AttentionLine(
          icon: LucideIcons.truck,
          tone: Tone.info,
          label: t.openRestocks,
          count:
              restocks.integer('REQUESTED') +
              restocks.integer('ASSIGNED') +
              restocks.integer('SHIPPED') +
              restocks.integer('RECEIVED'),
          onTap: () => context.go('/restocks'),
        ),
      ],
    ),
    if (payouts != null)
      AttentionGroup(
        title: t.paymentsSection,
        rows: [
          AttentionLine(
            icon: LucideIcons.banknote,
            tone: Tone.warning,
            label: t.payoutRequests,
            count: payouts.integer('pending'),
            trailing: Money.format(payouts.integer('amountMillimes'), locale),
            onTap: () => context.push('/payouts'),
          ),
        ],
      ),
    if ((approvals.integer('total') == 0 || !admin) &&
        uncounted == 0 &&
        attention.integer('negativeStock') == 0 &&
        attention.integer('lowStock') == 0 &&
        restocks.integer('REQUESTED') +
                restocks.integer('ASSIGNED') +
                restocks.integer('SHIPPED') +
                restocks.integer('RECEIVED') ==
            0 &&
        (payouts?.integer('pending') ?? 0) == 0)
      AppCard(
        child: Row(
          children: [
            Icon(LucideIcons.circleCheck, color: context.status.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text(t.allCaughtUp, style: context.text.titleSmall),
            ),
          ],
        ),
      ),
  ];
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.highlight,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = highlight ? context.colors.onPrimary : context.colors.primary;
    return Container(
      decoration: BoxDecoration(
        color: highlight
            ? context.colors.primary
            : context.colors.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: highlight ? null : Border.all(color: context.status.hairline),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: context.colors.primary.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, size: 26, color: fg),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.text.titleMedium?.copyWith(color: fg),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: context.text.bodySmall?.copyWith(
                            color: fg.withValues(alpha: 0.88),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(LucideIcons.arrowRight, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
