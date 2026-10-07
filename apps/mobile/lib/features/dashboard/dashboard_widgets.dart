import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/json.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/quantity_editor.dart' show QtyStepper;
import '../../l10n/app_localizations.dart';
import '../media/media_repository.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/states.dart';
import '../reports/reports_repository.dart';
import '../restock/restock_repository.dart';

/// A titled group of attention rows, shown only when it has something to say.
class AttentionGroup extends StatelessWidget {
  const AttentionGroup({required this.title, required this.rows, super.key});

  final String title;
  final List<AttentionLine> rows;

  @override
  Widget build(BuildContext context) {
    final active = rows.where((r) => r.count > 0).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: Text(
            title.toUpperCase(),
            style: context.text.labelSmall?.copyWith(
              color: context.status.muted,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final r in active) r,
      ],
    );
  }
}

class AttentionLine extends StatelessWidget {
  const AttentionLine({
    required this.icon,
    required this.tone,
    required this.label,
    required this.count,
    required this.onTap,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final Tone tone;
  final String label;
  final int count;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = tone.colors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.soft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: c.strong),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: context.text.titleSmall)),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  trailing!,
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.soft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count',
                style: context.text.titleSmall?.copyWith(color: c.strong),
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
    );
  }
}

/// The best sellers with their picture, name and units, bars scaled to the leader.
class TopProducts extends StatefulWidget {
  const TopProducts({required this.items, this.initial = 5, super.key});

  final List<Json> items;
  final int initial;

  @override
  State<TopProducts> createState() => _TopProductsState();
}

class _TopProductsState extends State<TopProducts> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final items = _all
        ? widget.items
        : widget.items.take(widget.initial).toList();
    final top = widget.items.fold<int>(
      1,
      (m, p) => p.integer('units') > m ? p.integer('units') : m,
    );
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      style: context.text.titleMedium?.copyWith(
                        color: i == 0
                            ? context.colors.primary
                            : context.status.muted,
                      ),
                    ),
                  ),
                  AuthImage(
                    items[i].strOrNull('imageId'),
                    width: 52,
                    height: 52,
                    radius: 12,
                    placeholderIcon: LucideIcons.package,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[i].str('name'),
                          style: context.text.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: items[i].integer('units') / top,
                            minHeight: 5,
                            backgroundColor: context.status.mutedSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    t.units(items[i].integer('units')),
                    style: context.text.titleSmall,
                  ),
                ],
              ),
            ),
          if (widget.items.length > widget.initial)
            _SeeMore(
              all: _all,
              total: widget.items.length,
              onTap: () => setState(() => _all = !_all),
            ),
        ],
      ),
    );
  }
}

/// "See more (30)" / "See less" under a ranking.
class _SeeMore extends StatelessWidget {
  const _SeeMore({required this.all, required this.total, required this.onTap});

  final bool all;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(
        all ? LucideIcons.chevronUp : LucideIcons.chevronDown,
        size: 18,
      ),
      label: Text(all ? t.seeLess : t.seeMore(total)),
    );
  }
}

/// Stores (or groups) ranked by units sold.
class TopPlaces extends StatefulWidget {
  const TopPlaces({
    required this.items,
    this.icon = LucideIcons.store,
    this.initial = 5,
    super.key,
  });

  final List<Json> items;
  final IconData icon;
  final int initial;

  @override
  State<TopPlaces> createState() => _TopPlacesState();
}

class _TopPlacesState extends State<TopPlaces> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final icon = widget.icon;
    final items = _all
        ? widget.items
        : widget.items.take(widget.initial).toList();
    final top = widget.items.fold<int>(
      1,
      (m, p) => p.integer('units') > m ? p.integer('units') : m,
    );
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      style: context.text.titleMedium?.copyWith(
                        color: i == 0
                            ? context.colors.primary
                            : context.status.muted,
                      ),
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 20, color: context.colors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[i].str('name'),
                          style: context.text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (items[i].strOrNull('city') != null)
                          Text(
                            items[i].str('city'),
                            style: context.text.bodySmall?.copyWith(
                              color: context.status.muted,
                            ),
                          ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: items[i].integer('units') / top,
                            minHeight: 5,
                            backgroundColor: context.status.mutedSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    t.units(items[i].integer('units')),
                    style: context.text.titleSmall,
                  ),
                ],
              ),
            ),
          if (widget.items.length > widget.initial)
            _SeeMore(
              all: _all,
              total: widget.items.length,
              onTap: () => setState(() => _all = !_all),
            ),
        ],
      ),
    );
  }
}

/// Stores with products running out: one line per store; tap for its products.
class LowByStore extends ConsumerWidget {
  const LowByStore({required this.items, required this.canOrder, super.key});

  final List<Json> items;
  final bool canOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return Column(
      children: [
        for (final row in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              onTap: () => showStoreStock(
                context,
                pdvId: row.str('pdvId'),
                place: row.str('place'),
                canOrder: canOrder,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.status.warningSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      LucideIcons.packageMinus,
                      size: 20,
                      color: context.status.warning,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.str('place'), style: context.text.titleSmall),
                        Text(
                          [
                            t.almostOutCount(
                              row.integer('low') - row.integer('out'),
                            ),
                            if (row.integer('out') > 0)
                              t.outCount(row.integer('out')),
                          ].where((x) => x.isNotEmpty).join(' · '),
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
    );
  }
}

/// The products running out in one store, in a sheet; the responsable can order from it.
Future<void> showStoreStock(
  BuildContext context, {
  required String pdvId,
  required String place,
  required bool canOrder,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.95,
    builder: (context, scroll) => Consumer(
      builder: (context, ref, _) {
        final t = AppLocalizations.of(context);
        final rows = ref.watch(stockAttentionProvider);
        return AsyncBody(
          value: rows,
          onRetry: () => ref.invalidate(stockAttentionProvider),
          builder: (all) {
            final mine = all.where((r) => r.locationId == pdvId).toList();
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(place, style: context.text.titleLarge),
                const Gap(12),
                if (mine.isEmpty)
                  EmptyState(
                    icon: LucideIcons.circleCheck,
                    title: t.stockAllGood,
                  ),
                for (final r in mine)
                  StockAttentionTile(row: r, canOrder: canOrder),
              ],
            );
          },
        );
      },
    ),
  ),
);

/// One product that is running out, with the Order button for the responsable.
class StockAttentionTile extends ConsumerWidget {
  const StockAttentionTile({
    required this.row,
    required this.canOrder,
    super.key,
  });

  final AttentionRow row;
  final bool canOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final out = row.quantity <= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.product,
                    style: context.text.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    row.family,
                    style: context.text.bodySmall?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
                ],
              ),
            ),
            StatusChip(
              out ? t.outOfStock : t.leftCount(row.quantity),
              tone: out ? Tone.danger : Tone.warning,
            ),
            if (canOrder) ...[
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () async {
                  if (await orderProduct(
                    context,
                    ref,
                    pdvId: row.locationId,
                    productId: row.productId,
                    product: row.product,
                    place: row.place,
                  )) {
                    ref.invalidate(stockAttentionProvider);
                  }
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(t.orderNow),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ask how many, then send the restock request. True when it was sent.
Future<bool> orderProduct(
  BuildContext context,
  WidgetRef ref, {
  required String pdvId,
  required String productId,
  required String product,
  required String place,
}) async {
  final t = AppLocalizations.of(context);
  final quantity = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _OrderSheet(product: product, place: place),
  );
  if (quantity == null || !context.mounted) return false;
  return perform(
    context,
    () => ref
        .read(restockRepositoryProvider)
        .create(
          destId: pdvId,
          lines: [
            {'productId': productId, 'quantity': quantity},
          ],
        ),
    success: t.orderSent,
  );
}

class _OrderSheet extends StatefulWidget {
  const _OrderSheet({required this.product, required this.place});

  final String product;
  final String place;

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  int _quantity = 20;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.product, style: context.text.titleMedium),
          Text(
            widget.place,
            style: context.text.bodyMedium?.copyWith(
              color: context.status.muted,
            ),
          ),
          const Gap(20),
          Text(t.orderQuantity, style: context.text.titleSmall),
          const Gap(10),
          Center(
            child: QtyStepper(
              value: _quantity,
              min: 1,
              onChanged: (v) => setState(() => _quantity = v),
            ),
          ),
          const Gap(20),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _quantity),
            icon: const Icon(LucideIcons.send),
            label: Text(t.sendOrder),
          ),
        ],
      ),
    );
  }
}
