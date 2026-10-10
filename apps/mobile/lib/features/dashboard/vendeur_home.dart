import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/util/money.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../l10n/app_localizations.dart';
import '../catalog/catalog_repository.dart';
import '../notifications/notifications_repository.dart';
import '../sales/sales_outbox.dart';
import '../wallet/wallet_models.dart';
import 'dashboard_repository.dart';
import 'home_scaffold.dart';

/// A team member's home: what they earned today, and the one big button.
class VendeurHome extends ConsumerWidget {
  const VendeurHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final data = ref.watch(dashboardProvider(null));
    // Keep the catalog fresh on the phone: it is what lets a sale be recorded without a connection.
    ref.watch(productsProvider);
    final pending = ref
        .watch(salesOutboxProvider)
        .where((s) => s.error == null)
        .length;
    return HomeScaffold(
      title: t.helloName(me.name.split(' ').first),
      subtitle: me.pdv?.name,
      onRefresh: () async {
        ref.invalidate(dashboardProvider(null));
        unawaited(ref.read(unreadCountProvider.notifier).refresh());
        await ref.read(dashboardProvider(null).future);
      },
      body: AsyncBody(
        value: data,
        onRetry: () => ref.invalidate(dashboardProvider(null)),
        builder: (d) {
          final wallet = WalletSummary.fromJson(d.obj('wallet'));
          final week = EarningsWindow.fromJson(d.obj('week'));
          final latest = d.list('latest');
          final locale = t.localeName;
          final pdv = d.objOrNull('pdv');
          final inactive = pdv != null && pdv.str('status') != 'ACTIVE';
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              if (inactive)
                _Banner(
                  icon: LucideIcons.clock,
                  tone: Tone.warning,
                  text: t.pdvNotActive,
                ),
              if (pending > 0)
                _Banner(
                  icon: LucideIcons.cloudUpload,
                  tone: Tone.info,
                  text: t.salesWaiting(pending),
                  onTap: () => context.go('/sales'),
                ),
              _TodayCard(wallet: wallet),
              const Gap(12),
              FilledButton.icon(
                onPressed: inactive ? null : () => context.push('/sell'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
                icon: const Icon(LucideIcons.plus, size: 26),
                label: Text(t.newSale),
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      icon: LucideIcons.wallet,
                      label: t.balanceShort,
                      value: Money.format(wallet.balanceMillimes, locale),
                      tone: Tone.success,
                      onTap: () => context.go('/wallet'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      icon: LucideIcons.calendarDays,
                      label: t.thisWeek,
                      value: Money.format(week.rewardMillimes, locale),
                      hint: t.units(week.units),
                    ),
                  ),
                ],
              ),
              if (latest.isNotEmpty) ...[
                SectionHeader(
                  t.latestSales,
                  trailing: TextButton(
                    onPressed: () => context.go('/sales'),
                    child: Text(t.seeAll),
                  ),
                ),
                for (final s in latest)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () => context.push('/sales/${s.str('id')}'),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.receipt,
                            color: context.colors.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${Dates.relativeDay(s.date('occurredAt'), locale, today: t.today, yesterday: t.yesterday)} · ${Dates.time(s.date('occurredAt'), locale)}',
                                  style: context.text.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  t.units(s.integer('units')),
                                  style: context.text.bodySmall?.copyWith(
                                    color: context.status.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // The reward sits at the end of the row, whatever the width.
                          Text(
                            '+ ${Money.format(s.integer('rewardMillimes'), locale)}',
                            style: context.text.titleSmall?.copyWith(
                              color: context.colors.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
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
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.wallet});

  final WalletSummary wallet;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.status.hero,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.status.hero.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Two faint rings: depth without noise.
          Positioned(
            right: -70,
            top: -80,
            child: _Ring(size: 200, color: context.status.onHero),
          ),
          Positioned(
            right: 30,
            bottom: -90,
            child: _Ring(size: 140, color: context.status.onHero),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.earnedToday,
                style: TextStyle(
                  color: context.status.onHero.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Gap(6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: CountUpText(
                  Money.format(wallet.today.rewardMillimes, t.localeName),
                  style: context.text.displaySmall?.copyWith(
                    color: context.status.onHero,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const Gap(6),
              Text(
                '${t.salesCount(wallet.today.sales)} · ${t.units(wallet.today.units)}',
                style: TextStyle(
                  color: context.status.onHero.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color.withValues(alpha: 0.12), width: 18),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.tone,
    required this.text,
    this.onTap,
  });

  final IconData icon;
  final Tone tone;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = tone.colors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        color: c.soft,
        borderColor: Colors.transparent,
        child: Row(
          children: [
            Icon(icon, color: c.strong, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: context.text.bodyMedium?.copyWith(
                  color: c.strong,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
