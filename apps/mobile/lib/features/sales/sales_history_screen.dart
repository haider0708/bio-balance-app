import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/util/money.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/quantity_editor.dart' show ProductPickerSheet;
import '../../core/widgets/paged_list.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import 'sales_models.dart';
import 'sales_outbox.dart';
import 'sales_repository.dart';

/// Past sales. Months and days give the overview (a long history stays easy to read);
/// open a day to see its sales, or pick a product to find every sale that included it.
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
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _productId;
  String? _productName;
  PagedController<Sale>? _byProduct;

  @override
  void dispose() {
    _byProduct?.dispose();
    super.dispose();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  SalesDaysQuery get _query => (
    from: Dates.day(_month),
    to: Dates.day(DateTime(_month.year, _month.month + 1, 0)),
    pdvId: widget.pdvId,
    sellerId: widget.sellerId,
  );

  Future<void> _pickProduct() async {
    final picked = await ProductPickerSheet.show(context, single: true);
    if (picked == null || !mounted) return;
    _byProduct?.dispose();
    setState(() {
      _productId = picked.first.id;
      _productName = picked.first.name;
      _byProduct = PagedController<Sale>((cursor) async {
        final page = await ref
            .read(salesRepositoryProvider)
            .list(
              cursor: cursor,
              pdvId: widget.pdvId,
              sellerId: widget.sellerId,
              regionId: widget.regionId,
              productId: _productId,
            );
        return PageResult(page.items, page.nextCursor);
      });
    });
  }

  void _clearProduct() {
    _byProduct?.dispose();
    setState(() {
      _productId = null;
      _productName = null;
      _byProduct = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final pending = ref.watch(salesOutboxProvider);
    ref.listen(salesOutboxProvider, (previous, next) {
      if ((previous?.length ?? 0) > next.length) {
        ref.invalidate(salesDaysProvider);
        ref.invalidate(salesOfDayProvider);
        _byProduct?.refresh();
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(t.salesTitle),
        actions: [
          IconButton(
            tooltip: t.findByProduct,
            onPressed: _pickProduct,
            icon: const Icon(LucideIcons.search),
          ),
        ],
      ),
      floatingActionButton: me.role == Role.vendeur
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () async {
                await context.push('/sell');
                ref.invalidate(salesDaysProvider);
                ref.invalidate(salesOfDayProvider);
              },
              icon: const Icon(LucideIcons.plus),
              label: Text(t.newSale),
            )
          : null,
      body: _productId == null
          ? _overview(context, t, me, pending)
          : _search(context, t, me, pending),
    );
  }

  Widget _search(
    BuildContext context,
    AppLocalizations t,
    Me me,
    List<PendingSale> pending,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: InputChip(
              avatar: const Icon(LucideIcons.package, size: 16),
              label: Text(_productName ?? ''),
              onDeleted: _clearProduct,
            ),
          ),
        ),
        Expanded(
          child: PagedList<Sale>(
            controller: _byProduct!,
            empty: EmptyState(
              icon: LucideIcons.receipt,
              title: t.noSalesWithProduct,
            ),
            itemBuilder: (context, sale, index) {
              final previous = index > 0 ? _byProduct!.items[index - 1] : null;
              final newDay = previous == null || previous.day != sale.day;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (newDay)
                    SectionHeader(
                      Dates.full(sale.occurredAt, t.localeName),
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
        ),
      ],
    );
  }

  Widget _overview(
    BuildContext context,
    AppLocalizations t,
    Me me,
    List<PendingSale> pending,
  ) {
    final days = ref.watch(salesDaysProvider(_query));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(salesDaysProvider);
        ref.invalidate(salesOfDayProvider);
        await ref.read(salesDaysProvider(_query).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          if (pending.isNotEmpty) _Pending(sales: pending),
          Row(
            children: [
              IconButton(
                tooltip: t.previousMonth,
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
                icon: const Icon(LucideIcons.chevronLeft),
              ),
              Expanded(
                child: Text(
                  Dates.monthYear(_month, t.localeName),
                  textAlign: TextAlign.center,
                  style: context.text.titleMedium,
                ),
              ),
              IconButton(
                tooltip: t.nextMonth,
                onPressed: _isCurrentMonth
                    ? null
                    : () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      ),
                icon: const Icon(LucideIcons.chevronRight),
              ),
            ],
          ),
          AsyncBody(
            value: days,
            onRetry: () => ref.invalidate(salesDaysProvider(_query)),
            builder: (list) {
              final units = list.fold(0, (a, d) => a + d.units);
              final reward = list.fold(0, (a, d) => a + d.rewardMillimes);
              final sales = list.fold(0, (a, d) => a + d.sales);
              if (list.isEmpty) {
                return EmptyState(
                  icon: LucideIcons.receipt,
                  title: t.noSalesThisMonth,
                  message: me.role == Role.vendeur ? t.noSalesYetHint : null,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: t.totalUnits,
                          value: '$units',
                          hint: t.salesCount(sales),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          label: t.reward,
                          value: Money.format(
                            reward,
                            t.localeName,
                            unit: false,
                          ),
                          hint: 'TND',
                        ),
                      ),
                    ],
                  ),
                  const Gap(8),
                  for (final d in list)
                    _DayCard(
                      day: d,
                      showSeller: me.role != Role.vendeur,
                      pdvId: widget.pdvId,
                      sellerId: widget.sellerId,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A day with its totals; open it to see each sale.
class _DayCard extends ConsumerStatefulWidget {
  const _DayCard({
    required this.day,
    required this.showSeller,
    this.pdvId,
    this.sellerId,
  });

  final SaleDay day;
  final bool showSeller;
  final String? pdvId;
  final String? sellerId;

  @override
  ConsumerState<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends ConsumerState<_DayCard> {
  late bool _open = widget.day.day == Dates.day(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final date = Dates.parseDay(widget.day.day);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: context.colors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${date.day}',
                            style: context.text.titleMedium?.copyWith(
                              color: context.colors.primary,
                            ),
                          ),
                          Text(
                            DateFormat.MMM(t.localeName).format(date),
                            style: context.text.labelSmall?.copyWith(
                              color: context.colors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Dates.relativeDay(
                              date,
                              t.localeName,
                              today: t.today,
                              yesterday: t.yesterday,
                            ),
                            style: context.text.titleSmall,
                          ),
                          Text(
                            '${t.salesCount(widget.day.sales)} · ${t.units(widget.day.units)}',
                            style: context.text.bodySmall?.copyWith(
                              color: context.status.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.day.rewardMillimes > 0)
                      Text(
                        '+ ${Money.format(widget.day.rewardMillimes, t.localeName)}',
                        style: context.text.titleSmall?.copyWith(
                          color: context.colors.primary,
                        ),
                      ),
                    const SizedBox(width: 6),
                    Icon(
                      _open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 18,
                      color: context.status.muted,
                    ),
                  ],
                ),
              ),
            ),
            if (_open)
              _Sales(
                day: widget.day.day,
                showSeller: widget.showSeller,
                pdvId: widget.pdvId,
                sellerId: widget.sellerId,
              ),
          ],
        ),
      ),
    );
  }
}

class _Sales extends ConsumerWidget {
  const _Sales({
    required this.day,
    required this.showSeller,
    this.pdvId,
    this.sellerId,
  });

  final String day;
  final bool showSeller;
  final String? pdvId;
  final String? sellerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(
      salesOfDayProvider((day: day, pdvId: pdvId, sellerId: sellerId)),
    );
    return sales.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: TextButton.icon(
          onPressed: () => ref.invalidate(salesOfDayProvider),
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          label: Text(AppLocalizations.of(context).retry),
        ),
      ),
      data: (list) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Column(
          children: [
            const Divider(height: 1),
            const SizedBox(height: 8),
            for (final s in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SaleTile(sale: s, showSeller: showSeller, flat: true),
              ),
          ],
        ),
      ),
    );
  }
}

class SaleTile extends StatelessWidget {
  const SaleTile({
    required this.sale,
    this.showSeller = false,
    this.flat = false,
    super.key,
  });

  final Sale sale;
  final bool showSeller;

  /// Inside a day card: no frame of its own.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final what = sale.lines.map((l) => '${l.name} ×${l.quantity}').join(' · ');
    return AppCard(
      onTap: () => context.push('/sales/${sale.id}'),
      color: flat ? context.status.mutedSoft : null,
      borderColor: flat ? Colors.transparent : null,
      padding: const EdgeInsets.all(12),
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
                if (what.isNotEmpty)
                  Text(
                    what,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall,
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
