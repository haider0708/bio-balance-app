import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/money.dart';
import '../../core/widgets/components.dart';
import '../../l10n/app_localizations.dart';
import 'confetti.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

/// The moment after a sale: a clear "well done" with the TND the sale earned.
class CelebrationScreen extends StatefulWidget {
  const CelebrationScreen({required this.outcome, super.key});

  final SaleOutcome outcome;

  @override
  State<CelebrationScreen> createState() => _CelebrationScreenState();
}

class _CelebrationScreenState extends State<CelebrationScreen> {
  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final outcome = widget.outcome;
    return switch (outcome) {
      SaleRecorded(:final sale) => _Recorded(sale: sale),
      SaleQueued(:final pending) => _Queued(pending: pending),
    };
  }
}

class _Recorded extends StatelessWidget {
  const _Recorded({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = t.localeName;
    final earned = sale.rewardMillimes > 0;
    final wallet = sale.wallet;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    context.colors.primaryContainer,
                    context.theme.scaffoldBackgroundColor,
                  ],
                ),
              ),
            ),
          ),
          if (earned)
            Positioned.fill(
              child: ConfettiBurst(
                colors: [
                  context.colors.primary,
                  Palette.leaf,
                  const Color(0xFFFFC857),
                  const Color(0xFF4FC3F7),
                  const Color(0xFFFF8A80),
                ],
              ),
            ),
          SafeArea(
            child: _Fill(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.elasticOut,
                      builder: (context, v, child) =>
                          Transform.scale(scale: v, child: child),
                      child: Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          color: context.colors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: context.colors.primary.withValues(
                                alpha: 0.35,
                              ),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Icon(
                          earned ? LucideIcons.partyPopper : LucideIcons.check,
                          size: 52,
                          color: context.colors.onPrimary,
                        ),
                      ),
                    ),
                    const Gap(28),
                    Text(
                      earned ? t.celebrateTitle : t.saleRecordedTitle,
                      style: context.text.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const Gap(6),
                    Text(
                      t.celebrateSubtitle(sale.units),
                      style: context.text.bodyLarge?.copyWith(
                        color: context.status.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (earned) ...[
                      const Gap(28),
                      Text(
                        t.youEarned,
                        style: context.text.labelLarge?.copyWith(
                          color: context.status.muted,
                        ),
                      ),
                      const Gap(4),
                      TweenAnimationBuilder<int>(
                        tween: IntTween(begin: 0, end: sale.rewardMillimes),
                        duration: const Duration(milliseconds: 1100),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Semantics(
                          liveRegion: true,
                          label: Money.format(sale.rewardMillimes, locale),
                          child: ExcludeSemantics(
                            child: Text(
                              '+ ${Money.format(v, locale)}',
                              style: context.text.displayMedium?.copyWith(
                                color: context.colors.primary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const Gap(24),
                    if (wallet != null)
                      AppCard(
                        child: Column(
                          children: [
                            InfoRow(
                              t.celebrateToday,
                              '${t.salesCount(wallet.today.sales)} · ${Money.format(wallet.today.rewardMillimes, locale)}',
                            ),
                            InfoRow(
                              t.walletBalance,
                              Money.format(wallet.balanceMillimes, locale),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(flex: 3),
                    FilledButton.icon(
                      onPressed: () => context.go('/sell'),
                      icon: const Icon(LucideIcons.plus),
                      label: Text(t.newSale),
                    ),
                    const Gap(8),
                    TextButton(
                      onPressed: () => context.go('/home'),
                      child: Text(t.done),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Queued extends StatelessWidget {
  const _Queued({required this.pending});

  final PendingSale pending;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: _Fill(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: context.status.infoSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.cloudUpload,
                    size: 48,
                    color: context.status.info,
                  ),
                ),
                const Gap(28),
                Text(
                  t.savedOnPhoneTitle,
                  style: context.text.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const Gap(8),
                Text(
                  t.savedOnPhoneBody(pending.units),
                  style: context.text.bodyLarge?.copyWith(
                    color: context.status.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(flex: 3),
                FilledButton.icon(
                  onPressed: () => context.go('/sell'),
                  icon: const Icon(LucideIcons.plus),
                  label: Text(t.newSale),
                ),
                const Gap(8),
                TextButton(
                  onPressed: () => context.go('/home'),
                  child: Text(t.done),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fills the screen so the content can centre itself, and scrolls when the screen is too short.
class _Fill extends StatelessWidget {
  const _Fill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
  );
}
