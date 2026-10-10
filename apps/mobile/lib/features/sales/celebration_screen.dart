import 'dart:async';
import 'dart:math';

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
  Timer? _ticks;

  @override
  void initState() {
    super.initState();
    unawaited(HapticFeedback.mediumImpact());
    // Light ticks while the amount counts up, then a firm one when it lands.
    final outcome = widget.outcome;
    if (outcome is SaleRecorded) {
      var n = 0;
      _ticks = Timer.periodic(const Duration(milliseconds: 140), (timer) {
        n++;
        if (n < 8) {
          unawaited(HapticFeedback.selectionClick());
        } else {
          unawaited(HapticFeedback.heavyImpact());
          timer.cancel();
        }
      });
    }
  }

  @override
  void dispose() {
    _ticks?.cancel();
    super.dispose();
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
                    context.status.mutedSoft,
                    context.theme.scaffoldBackgroundColor,
                  ],
                ),
              ),
            ),
          ),
          // Every sale is celebrated, with or without a reward.
          const Positioned.fill(child: CoinRain()),
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
                          LucideIcons.partyPopper,
                          size: 52,
                          color: context.colors.onPrimary,
                        ),
                      ),
                    ),
                    const Gap(28),
                    Text(
                      t.celebrateTitle,
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
                            // The number swells a little when it lands.
                            child: Transform.scale(
                              scale: v == sale.rewardMillimes
                                  ? 1.0
                                  : 1 +
                                        0.1 *
                                            sin(
                                              pi *
                                                  (v / sale.rewardMillimes)
                                                      .clamp(0.0, 1.0),
                                            ),
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
                      ),
                      const Gap(14),
                      for (var i = 0; i < sale.lines.length; i++)
                        if (sale.lines[i].rewardMillimes > 0)
                          _Pop(
                            delay: Duration(milliseconds: 700 + i * 220),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      '${sale.lines[i].name} × ${sale.lines[i].quantity}',
                                      overflow: TextOverflow.ellipsis,
                                      style: context.text.bodyMedium?.copyWith(
                                        color: context.status.muted,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '+ ${Money.format(sale.lines[i].rewardMillimes, locale)}',
                                    style: context.text.titleSmall?.copyWith(
                                      color: context.colors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ] else ...[
                      const Gap(28),
                      TweenAnimationBuilder<int>(
                        tween: IntTween(begin: 0, end: sale.units),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Text(
                          '+ ${t.units(v)}',
                          style: context.text.displayMedium?.copyWith(
                            color: context.colors.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      const Gap(10),
                      for (var i = 0; i < sale.lines.length; i++)
                        _Pop(
                          delay: Duration(milliseconds: 500 + i * 200),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              '${sale.lines[i].name} × ${sale.lines[i].quantity}',
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodyMedium?.copyWith(
                                color: context.status.muted,
                              ),
                            ),
                          ),
                        ),
                      const Gap(8),
                      Text(
                        t.noRewardForSale,
                        textAlign: TextAlign.center,
                        style: context.text.bodySmall?.copyWith(
                          color: context.status.muted,
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
      body: Stack(
        children: [
          Positioned.fill(
            child: ConfettiBurst(
              colors: [
                context.colors.primary,
                context.status.info,
                const Color(0xFFFFC857),
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
                          color: context.status.infoSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.cloudUpload,
                          size: 48,
                          color: context.status.info,
                        ),
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
        ],
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

/// Slides and fades its child in after a short delay, for lines that appear one by one.
class _Pop extends StatefulWidget {
  const _Pop({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_Pop> createState() => _PopState();
}

class _PopState extends State<_Pop> {
  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSlide(
    duration: const Duration(milliseconds: 380),
    curve: Curves.easeOutBack,
    offset: _shown ? Offset.zero : const Offset(0, 0.6),
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _shown ? 1 : 0,
      child: widget.child,
    ),
  );
}
