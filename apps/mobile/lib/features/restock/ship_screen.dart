import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/quantity_editor.dart';
import '../../l10n/app_localizations.dart';
import '../stock/stock_repository.dart';
import 'restock_models.dart';
import 'restock_repository.dart';

/// The responsable (or the admin) prepares the order: what is really leaving the grossiste.
class ShipScreen extends ConsumerStatefulWidget {
  const ShipScreen({required this.order, super.key});

  final RestockOrder order;

  @override
  ConsumerState<ShipScreen> createState() => _ShipScreenState();
}

class _ShipScreenState extends ConsumerState<ShipScreen> {
  QuantityController? _quantities;

  @override
  void dispose() {
    _quantities?.dispose();
    super.dispose();
  }

  Future<void> _ship() async {
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref
          .read(restockRepositoryProvider)
          .ship(widget.order.id, _quantities!.lines()),
      success: t.restockShippedMessage,
    );
    if (ok && mounted) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final depotId = widget.order.supplierId ?? '';
    final stock = ref.watch(stockLevelsProvider(depotId));
    return Scaffold(
      appBar: AppBar(title: Text(t.prepareAndShip)),
      body: AsyncBody(
        value: stock,
        onRetry: () => ref.invalidate(stockLevelsProvider(depotId)),
        builder: (levels) {
          final held = {for (final i in levels.items) i.productId: i.quantity};
          _quantities ??= QuantityController([
            for (final l in widget.order.lines)
              QuantityItem(
                productId: l.productId,
                name: l.name,
                family: l.family,
                quantity: (held[l.productId] ?? 0).clamp(0, l.requested),
                max: (held[l.productId] ?? 0).clamp(0, l.requested),
                hint: t.requestedInStock(l.requested, held[l.productId] ?? 0),
              ),
          ]);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                t.shipFromHint(
                  widget.order.supplier ?? '',
                  widget.order.destination,
                ),
                style: context.text.bodyMedium?.copyWith(
                  color: context.status.muted,
                ),
              ),
              const Gap(16),
              QuantityEditor(
                controller: _quantities!,
                allowAdd: false,
                allowRemove: false,
              ),
              const Gap(16),
              ListenableBuilder(
                listenable: _quantities!,
                builder: (context, _) => AsyncButton(
                  label: t.markShipped,
                  icon: LucideIcons.truck,
                  onPressed: _quantities!.total == 0 ? null : _ship,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
