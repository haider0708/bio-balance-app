import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/util/money.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import 'wallet_models.dart';
import 'wallet_repository.dart';

final walletEntriesProvider = FutureProvider.autoDispose<WalletPage>(
  (ref) => ref.watch(walletRepositoryProvider).entries(),
);

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(walletSummaryProvider);
    ref.invalidate(walletEntriesProvider);
    ref.invalidate(myPayoutsProvider);
    await ref.read(walletSummaryProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final wallet = ref.watch(walletSummaryProvider);
    final entries = ref.watch(walletEntriesProvider);
    final payouts = ref.watch(myPayoutsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.walletTitle)),
      body: AsyncBody(
        value: wallet,
        onRetry: () => ref.invalidate(walletSummaryProvider),
        builder: (w) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _BalanceCard(wallet: w),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: t.today,
                      value: Money.format(w.today.rewardMillimes, t.localeName),
                      hint: t.salesCount(w.today.sales),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: t.thisWeek,
                      value: Money.format(w.week.rewardMillimes, t.localeName),
                      hint: t.salesCount(w.week.sales),
                    ),
                  ),
                ],
              ),
              const Gap(12),
              StatTile(
                label: t.thisMonth,
                value: Money.format(w.month.rewardMillimes, t.localeName),
                hint:
                    '${t.salesCount(w.month.sales)} · ${t.units(w.month.units)}',
              ),
              if (payouts.value?.isNotEmpty == true) ...[
                SectionHeader(t.payouts),
                for (final p in payouts.value!.take(5)) _PayoutTile(payout: p),
              ],
              SectionHeader(t.activity),
              AsyncBody(
                value: entries,
                onRetry: () => ref.invalidate(walletEntriesProvider),
                isEmpty: (page) => page.entries.isEmpty,
                empty: EmptyState(
                  icon: LucideIcons.wallet,
                  title: t.noActivityYet,
                ),
                builder: (page) => Column(
                  children: [
                    for (final e in page.entries) _EntryTile(entry: e),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.wallet});

  final WalletSummary wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final locale = t.localeName;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.primary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.colors.primary.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.availableBalance,
            style: TextStyle(
              color: context.colors.onPrimary.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
          const Gap(6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              Money.format(wallet.availableMillimes, locale),
              style: context.text.displaySmall?.copyWith(
                color: context.colors.onPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (wallet.pendingMillimes > 0) ...[
            const Gap(6),
            Text(
              t.pendingPayout(Money.format(wallet.pendingMillimes, locale)),
              style: TextStyle(
                color: context.colors.onPrimary.withValues(alpha: 0.85),
              ),
            ),
          ],
          const Gap(18),
          FilledButton.icon(
            onPressed: wallet.availableMillimes > 0
                ? () => _request(context, ref, wallet.availableMillimes)
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.onPrimary,
              foregroundColor: context.colors.primary,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(LucideIcons.banknote),
            label: Text(t.requestPayout),
          ),
        ],
      ),
    );
  }

  Future<void> _request(
    BuildContext context,
    WidgetRef ref,
    int available,
  ) async {
    final t = AppLocalizations.of(context);
    final amount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PayoutSheet(available: available),
    );
    if (amount == null || !context.mounted) return;
    final ok = await perform(
      context,
      () => ref.read(walletRepositoryProvider).request(amount),
      success: t.payoutRequested,
    );
    if (ok) {
      ref.invalidate(walletSummaryProvider);
      ref.invalidate(myPayoutsProvider);
    }
  }
}

class _PayoutSheet extends StatefulWidget {
  const _PayoutSheet({required this.available});

  final int available;

  @override
  State<_PayoutSheet> createState() => _PayoutSheetState();
}

class _PayoutSheetState extends State<_PayoutSheet> {
  late final _controller = TextEditingController(
    text: (widget.available / 1000).toStringAsFixed(3),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final amount = Money.parse(_controller.text);
    final valid = amount != null && amount > 0 && amount <= widget.available;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.requestPayout, style: context.text.titleLarge),
          const Gap(6),
          Text(
            t.payoutExplain,
            style: context.text.bodyMedium?.copyWith(
              color: context.status.muted,
            ),
          ),
          const Gap(16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: t.amountTnd,
              helperText: t.availableUpTo(
                Money.format(widget.available, t.localeName),
              ),
              suffixText: 'TND',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const Gap(16),
          FilledButton(
            onPressed: valid ? () => Navigator.pop(context, amount) : null,
            child: Text(t.requestPayout),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final WalletEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final positive = entry.amountMillimes >= 0;
    final (icon, label) = switch (entry.kind) {
      WalletKind.sale => (LucideIcons.receipt, t.entrySale),
      WalletKind.correction => (LucideIcons.pencilLine, t.entryCorrection),
      WalletKind.payout => (LucideIcons.banknote, t.entryPayout),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: positive
              ? context.colors.primaryContainer
              : context.status.mutedSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 20,
          color: positive ? context.colors.primary : context.status.muted,
        ),
      ),
      title: Text(label),
      subtitle: Text(Dates.dateTime(entry.createdAt, t.localeName)),
      trailing: Text(
        Money.format(entry.amountMillimes, t.localeName, sign: true),
        style: context.text.titleSmall?.copyWith(
          color: positive ? context.colors.primary : context.status.muted,
        ),
      ),
    );
  }
}

class _PayoutTile extends ConsumerWidget {
  const _PayoutTile({required this.payout});

  final Payout payout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final (tone, label) = switch (payout.status) {
      PayoutStatus.pending => (Tone.warning, t.statusPending),
      PayoutStatus.approved => (Tone.success, t.payoutPaid),
      PayoutStatus.rejected => (Tone.danger, t.statusRejected),
      PayoutStatus.cancelled => (Tone.muted, t.statusCancelled),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Money.format(payout.amountMillimes, t.localeName),
                    style: context.text.titleSmall,
                  ),
                  Text(
                    Dates.dateTime(payout.createdAt, t.localeName),
                    style: context.text.bodySmall?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
                  if (payout.decisionNote != null)
                    Text(payout.decisionNote!, style: context.text.bodySmall),
                ],
              ),
            ),
            StatusChip(label, tone: tone),
            if (payout.status == PayoutStatus.pending)
              IconButton(
                tooltip: t.cancelRequest,
                icon: const Icon(LucideIcons.x, size: 18),
                onPressed: () async {
                  final ok = await perform(
                    context,
                    () => ref.read(walletRepositoryProvider).cancel(payout.id),
                  );
                  if (ok) {
                    ref.invalidate(myPayoutsProvider);
                    ref.invalidate(walletSummaryProvider);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
