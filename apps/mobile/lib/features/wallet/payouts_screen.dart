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
import '../approvals/approvals_repository.dart';
import 'wallet_models.dart';
import 'wallet_repository.dart';

final _payoutsProvider = FutureProvider.autoDispose
    .family<List<Payout>, String?>(
      (ref, status) =>
          ref.watch(walletRepositoryProvider).payouts(status: status),
    );
final _overviewProvider = FutureProvider.autoDispose<List<WalletOverview>>(
  (ref) => ref.watch(walletRepositoryProvider).overview(),
);

/// The admin pays team members: requests to approve, history, and every wallet at a glance.
class PayoutsScreen extends ConsumerWidget {
  const PayoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.payoutsTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: t.toPay),
              Tab(text: t.history),
              Tab(text: t.wallets),
            ],
          ),
        ),
        body: const TabBarView(children: [_Requests(), _History(), _Wallets()]),
      ),
    );
  }
}

class _Requests extends ConsumerWidget {
  const _Requests();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final payouts = ref.watch(_payoutsProvider('PENDING'));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_payoutsProvider);
        await ref.read(_payoutsProvider('PENDING').future);
      },
      child: AsyncBody(
        value: payouts,
        onRetry: () => ref.invalidate(_payoutsProvider),
        isEmpty: (l) => l.isEmpty,
        empty: ListView(
          children: [
            EmptyState(
              icon: LucideIcons.circleCheck,
              title: t.noPayoutRequests,
            ),
          ],
        ),
        builder: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Gap(8),
          itemBuilder: (context, i) => _RequestCard(payout: list[i]),
        ),
      ),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.payout});

  final Payout payout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    void reload() {
      ref.invalidate(_payoutsProvider);
      ref.invalidate(_overviewProvider);
      ref.invalidate(approvalsProvider);
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  payout.userName ?? '',
                  style: context.text.titleMedium,
                ),
              ),
              Text(
                Money.format(payout.amountMillimes, t.localeName),
                style: context.text.titleMedium?.copyWith(
                  color: context.colors.primary,
                ),
              ),
            ],
          ),
          Text(
            [
              ?payout.userPdv,
              ?payout.userPhone,
              Dates.dateTime(payout.createdAt, t.localeName),
            ].join(' · '),
            style: context.text.bodySmall?.copyWith(
              color: context.status.muted,
            ),
          ),
          const Gap(12),
          Row(
            children: [
              Expanded(
                child: AsyncButton(
                  label: t.markAsPaid,
                  icon: LucideIcons.check,
                  onPressed: () async {
                    final result = await _paidSheet(context);
                    if (result == null || !context.mounted) return;
                    if (await perform(
                      context,
                      () => ref
                          .read(walletRepositoryProvider)
                          .approve(
                            payout.id,
                            reference: result.$1,
                            paidAt: result.$2,
                          ),
                      success: t.payoutApproved,
                    ))
                      reload();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AsyncButton(
                  label: t.decline,
                  style: AsyncButtonStyle.outlined,
                  onPressed: () async {
                    final note = await askNote(
                      context,
                      title: t.declinePayoutTitle,
                      confirmLabel: t.decline,
                      hint: t.rejectReasonHint,
                    );
                    if (note == null || !context.mounted) return;
                    if (await perform(
                      context,
                      () => ref
                          .read(walletRepositoryProvider)
                          .reject(payout.id, note),
                      success: t.rejected,
                    ))
                      reload();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<(String?, DateTime)?> _paidSheet(BuildContext context) {
    final t = AppLocalizations.of(context);
    final reference = TextEditingController();
    var paidAt = DateTime.now();
    return showModalBottomSheet<(String?, DateTime)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.markAsPaid, style: context.text.titleLarge),
              const Gap(6),
              Text(
                t.markAsPaidHint(
                  Money.format(payout.amountMillimes, t.localeName),
                ),
                style: context.text.bodyMedium?.copyWith(
                  color: context.status.muted,
                ),
              ),
              const Gap(16),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: paidAt,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 60),
                    ),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => paidAt = picked);
                },
                icon: const Icon(LucideIcons.calendar),
                label: Text(t.paidOn(Dates.full(paidAt, t.localeName))),
              ),
              const Gap(12),
              TextField(
                controller: reference,
                decoration: InputDecoration(
                  labelText: '${t.reference} (${t.optional})',
                ),
              ),
              const Gap(16),
              FilledButton(
                onPressed: () => Navigator.pop(context, (
                  reference.text.trim().isEmpty ? null : reference.text.trim(),
                  paidAt,
                )),
                child: Text(t.confirm),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(reference.dispose);
  }
}

class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final payouts = ref.watch(_payoutsProvider(null));
    return AsyncBody(
      value: payouts,
      onRetry: () => ref.invalidate(_payoutsProvider),
      isEmpty: (l) => l.isEmpty,
      empty: EmptyState(icon: LucideIcons.history, title: t.noPayoutsYet),
      builder: (all) {
        final list = all
            .where((p) => p.status != PayoutStatus.pending)
            .toList();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Gap(8),
          itemBuilder: (context, i) {
            final p = list[i];
            final (tone, label) = switch (p.status) {
              PayoutStatus.approved => (Tone.success, t.payoutPaid),
              PayoutStatus.rejected => (Tone.danger, t.statusRejected),
              _ => (Tone.muted, t.statusCancelled),
            };
            return AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.userName ?? '', style: context.text.titleSmall),
                        Text(
                          '${Dates.dateTime(p.paidAt ?? p.decidedAt ?? p.createdAt, t.localeName)}${p.reference != null ? ' · ${p.reference}' : ''}',
                          style: context.text.bodySmall?.copyWith(
                            color: context.status.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Money.format(p.amountMillimes, t.localeName),
                    style: context.text.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  StatusChip(label, tone: tone),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Wallets extends ConsumerWidget {
  const _Wallets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final wallets = ref.watch(_overviewProvider);
    return AsyncBody(
      value: wallets,
      onRetry: () => ref.invalidate(_overviewProvider),
      isEmpty: (l) => l.isEmpty,
      empty: EmptyState(icon: LucideIcons.wallet, title: t.noWalletsYet),
      builder: (list) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: list.length,
        separatorBuilder: (_, _) => const Gap(8),
        itemBuilder: (context, i) {
          final w = list[i];
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(w.name, style: context.text.titleSmall),
                    ),
                    Text(
                      Money.format(w.balance, t.localeName),
                      style: context.text.titleMedium?.copyWith(
                        color: context.colors.primary,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${w.pdv} · ${w.region}',
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
                const Gap(6),
                Text(
                  t.walletSummaryLine(
                    Money.format(w.earned, t.localeName),
                    Money.format(w.paid, t.localeName),
                  ),
                  style: context.text.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
