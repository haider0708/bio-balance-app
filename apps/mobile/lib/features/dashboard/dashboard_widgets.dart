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
import '../restock/restock_repository.dart';

/// A titled group of attention rows, shown only when it has something to say.
class AttentionGroup extends StatelessWidget {
  const AttentionGroup({required this.title, required this.rows, super.key});

  final String title;
  final List<AttentionRow> rows;

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

class AttentionRow extends StatelessWidget {
  const AttentionRow({
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
class TopProducts extends StatelessWidget {
  const TopProducts({required this.items, super.key});

  final List<Json> items;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final top = items.fold<int>(
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
        ],
      ),
    );
  }
}

/// Stores (or groups) ranked by units sold.
class TopPlaces extends StatelessWidget {
  const TopPlaces({
    required this.items,
    this.icon = LucideIcons.store,
    super.key,
  });

  final List<Json> items;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final top = items.fold<int>(
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
        ],
      ),
    );
  }
}

/// What is running out in the responsable's stores, with an Order button right there.
class RunningLow extends ConsumerWidget {
  const RunningLow({required this.items, required this.onOrdered, super.key});

  final List<Json> items;
  final VoidCallback onOrdered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return Column(
      children: [
        for (final row in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  AuthImage(
                    row.strOrNull('imageId'),
                    width: 48,
                    height: 48,
                    radius: 12,
                    placeholderIcon: LucideIcons.package,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.str('product'),
                          style: context.text.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${row.str('place')} · ${row.integer('quantity') <= 0 ? t.outOfStock : t.inStockCount(row.integer('quantity'))}',
                          style: context.text.bodySmall?.copyWith(
                            color: row.integer('quantity') <= 0
                                ? context.status.danger
                                : context.status.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () async {
                      if (await orderProduct(
                        context,
                        ref,
                        pdvId: row.str('pdvId'),
                        productId: row.str('productId'),
                        product: row.str('product'),
                        place: row.str('place'),
                      )) {
                        onOrdered();
                      }
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(72, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: Text(t.orderNow),
                  ),
                ],
              ),
            ),
          ),
      ],
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
