import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/util/money.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/paged_list.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import 'sales_models.dart';
import 'sales_outbox.dart';
import 'sales_repository.dart';

/// Past sales, newest first. A team member sees their own; a responsable or the admin see more.
class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({
    this.pdvId,
    this.sellerId,
    this.regionId,
    this.embedded = false,
    super.key,
  });

  final String? pdvId;
  final String? sellerId;
  final String? regionId;

  /// True when shown as a tab (no back button, new-sale button).
  final bool embedded;

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  late final PagedController<Sale> _paged = PagedController<Sale>((
    cursor,
  ) async {
    final page = await ref
        .read(salesRepositoryProvider)
        .list(
          cursor: cursor,
          pdvId: widget.pdvId,
          sellerId: widget.sellerId,
          regionId: widget.regionId,
        );
    return PageResult(page.items, page.nextCursor);
  });

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final pending = ref.watch(salesOutboxProvider);
    ref.listen(salesOutboxProvider, (previous, next) {
      if ((previous?.length ?? 0) > next.length) _paged.refresh();
    });
    return Scaffold(
      appBar: AppBar(title: Text(t.salesTitle)),
      floatingActionButton: me.role == Role.vendeur
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => context.push('/sell'),
              icon: const Icon(LucideIcons.plus),
              label: Text(t.newSale),
            )
          : null,
      body: PagedList<Sale>(
        controller: _paged,
        header: pending.isEmpty ? null : _Pending(sales: pending),
        empty: EmptyState(
          icon: LucideIcons.receipt,
          title: t.noSalesYet,
          message: me.role == Role.vendeur ? t.noSalesYetHint : null,
        ),
        itemBuilder: (context, sale, index) {
          final previous = index > 0 ? _paged.items[index - 1] : null;
          final newDay = previous == null || previous.day != sale.day;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (newDay)
                SectionHeader(
                  Dates.relativeDay(
                    sale.occurredAt,
                    t.localeName,
                    today: t.today,
                    yesterday: t.yesterday,
                  ),
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SaleTile(
                  sale: sale,
                  showSeller: me.role != Role.vendeur,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SaleTile extends StatelessWidget {
  const SaleTile({required this.sale, this.showSeller = false, super.key});

  final Sale sale;
  final bool showSeller;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppCard(
      onTap: () => context.push('/sales/${sale.id}'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: sale.voided
                  ? context.status.mutedSoft
                  : context.colors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              sale.voided ? LucideIcons.ban : LucideIcons.receipt,
              size: 22,
              color: sale.voided
                  ? context.status.muted
                  : context.colors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showSeller
                      ? '${sale.seller.name} · ${sale.pdv.name}'
                      : t.units(sale.units),
                  style: context.text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    Dates.time(sale.occurredAt, t.localeName),
                    if (showSeller) t.units(sale.units),
                    if (sale.version > 1) t.corrected,
                  ].join(' · '),
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              ],
            ),
          ),
          if (sale.voided)
            StatusChip(t.saleVoided, tone: Tone.muted)
          else if (sale.rewardMillimes > 0)
            Text(
              '+ ${Money.format(sale.rewardMillimes, t.localeName)}',
              style: context.text.titleSmall?.copyWith(
                color: context.colors.primary,
              ),
            ),
        ],
      ),
    );
  }
}

class _Pending extends ConsumerWidget {
  const _Pending({required this.sales});

  final List<PendingSale> sales;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            t.waitingToSend,
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          ),
          for (final s in sales)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                color: s.error != null
                    ? context.status.dangerSoft
                    : context.status.infoSoft,
                borderColor: Colors.transparent,
                child: Row(
                  children: [
                    Icon(
                      s.error != null
                          ? LucideIcons.circleAlert
                          : LucideIcons.cloudUpload,
                      color: s.error != null
                          ? context.status.danger
                          : context.status.info,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.units(s.units),
                            style: context.text.titleSmall,
                          ),
                          Text(
                            s.error != null
                                ? t.saleRefused
                                : Dates.dateTime(s.occurredAt, t.localeName),
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (s.error != null)
                      TextButton(
                        onPressed: () => ref
                            .read(salesOutboxProvider.notifier)
                            .discard(s.id),
                        child: Text(t.discard),
                      )
                    else
                      TextButton(
                        onPressed: () =>
                            ref.read(salesOutboxProvider.notifier).flush(),
                        child: Text(t.sendNow),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
