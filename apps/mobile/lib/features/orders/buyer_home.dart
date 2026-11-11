import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/home_scaffold.dart';
import '../notifications/notifications_repository.dart';
import '../restock/restock_list_screen.dart';
import '../restock/restock_repository.dart';
import '../stock/stock_models.dart';
import '../stock/stock_repository.dart';
import '../transfers/transfers_repository.dart';

/// The orders still moving for the buyer's para.
const _openOrders = (active: true, status: null, regionId: null, destId: null);

void _order(BuildContext context, String? pdvId) =>
    context.push('/restocks/new', extra: pdvId);

/// The buyer's home: how the para's stock stands, what to order, and the orders on their way.
class BuyerHome extends ConsumerWidget {
  const BuyerHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final pdvId = me.pdv?.id;
    return HomeScaffold(
      title: t.helloName(me.name.split(' ').first),
      subtitle: me.pdv?.name,
      onRefresh: () async {
        if (pdvId != null) ref.invalidate(stockLevelsProvider(pdvId));
        ref.invalidate(restocksProvider(_openOrders));
        unawaited(ref.read(unreadCountProvider.notifier).refresh());
        await ref.read(restocksProvider(_openOrders).future);
      },
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (pdvId == null)
            EmptyState(icon: LucideIcons.store, title: t.buyerNoPara)
          else
            _BuyerPanel(pdvId: pdvId, showOrders: true),
        ],
      ),
    );
  }
}

/// A seller who is also a buyer: the same panel, in short, among the sales.
class BuyerShortcut extends ConsumerWidget {
  const BuyerShortcut({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pdvId = ref.watch(meProvider).pdv?.id;
    if (pdvId == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _BuyerPanel(pdvId: pdvId, showOrders: false),
    );
  }
}

class _BuyerPanel extends ConsumerWidget {
  const _BuyerPanel({required this.pdvId, required this.showOrders});

  final String pdvId;
  final bool showOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final stock = ref.watch(stockLevelsProvider(pdvId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        AsyncBody<StockLevels>(
          value: stock,
          onRetry: () => ref.invalidate(stockLevelsProvider(pdvId)),
          builder: (levels) {
            final low = levels.items
                .where((i) => i.level != StockLevel.ok)
                .toList();
            final out = low.where((i) => i.quantity <= 0).length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                AutoGrid(
                  minItemWidth: 120,
                  maxColumns: 3,
                  children: [
                    StatTile(
                      label: t.buyerUnits,
                      value: '${levels.units}',
                      icon: LucideIcons.package,
                      onTap: () => context.push('/stock/$pdvId'),
                    ),
                    StatTile(
                      label: t.paraLow,
                      value: '${low.length - out}',
                      icon: LucideIcons.triangleAlert,
                      tone: low.length - out > 0 ? Tone.warning : Tone.neutral,
                    ),
                    StatTile(
                      label: t.paraOut,
                      value: '$out',
                      icon: LucideIcons.circleX,
                      tone: out > 0 ? Tone.danger : Tone.neutral,
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: () => _order(context, pdvId),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  icon: const Icon(LucideIcons.truck),
                  label: Text(t.buyerOrderNow),
                ),
                if (low.isNotEmpty) ...[
                  SectionHeader(t.buyerRunningLow),
                  for (final item in low.take(showOrders ? 12 : 4))
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        spacing: 12,
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              style: context.text.titleSmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          StatusChip(
                            '${item.quantity}',
                            tone: item.quantity <= 0
                                ? Tone.danger
                                : Tone.warning,
                          ),
                        ],
                      ),
                    ),
                ] else
                  StatusChip(
                    t.paraStockOk,
                    tone: Tone.success,
                    icon: LucideIcons.circleCheck,
                  ),
              ],
            );
          },
        ),
        // What else moves the para's stock: exchanges inside the group (when there is one) and
        // returns, both decided by the admin. A seller who buys has the exchange among the sales.
        Row(
          spacing: 8,
          children: [
            if (showOrders &&
                (ref
                        .watch(transferPartnersProvider(null))
                        .value
                        ?.paras
                        .isNotEmpty ??
                    false))
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/transfers'),
                  icon: const Icon(LucideIcons.arrowLeftRight),
                  label: Text(t.transfersTitle),
                ),
              ),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.push('/returns'),
                icon: const Icon(LucideIcons.undo2),
                label: Text(t.returnsTitle),
              ),
            ),
          ],
        ),
        if (showOrders) _OpenOrders(pdvId: pdvId),
      ],
    );
  }
}

class _OpenOrders extends ConsumerWidget {
  const _OpenOrders({required this.pdvId});

  final String pdvId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final orders = ref.watch(restocksProvider(_openOrders));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          t.buyerMyOrders,
          trailing: TextButton(
            onPressed: () => context.go('/restocks'),
            child: Text(t.seeAll),
          ),
        ),
        AsyncBody(
          value: orders,
          onRetry: () => ref.invalidate(restocksProvider(_openOrders)),
          builder: (list) => list.isEmpty
              ? EmptyState(
                  icon: LucideIcons.truck,
                  title: t.buyerNoOrders,
                  message: t.buyerNoOrdersHint,
                )
              : Column(
                  spacing: 8,
                  children: [
                    for (final o in list.take(5)) RestockTile(order: o),
                  ],
                ),
        ),
      ],
    );
  }
}
