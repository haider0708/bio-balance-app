import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/quantity_editor.dart' show QtyStepper;
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/product.dart';
import '../media/media_repository.dart';
import 'sales_repository.dart';

/// Pick products, adjust quantities, record the sale. Built to be done with one hand at the till.
class NewSaleScreen extends ConsumerStatefulWidget {
  const NewSaleScreen({super.key});

  @override
  ConsumerState<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends ConsumerState<NewSaleScreen> {
  final Map<String, int> _cart = {};
  String _query = '';
  String? _family;

  int get _units => _cart.values.fold(0, (a, b) => a + b);

  void _set(Product p, int quantity) => setState(() => quantity <= 0 ? _cart.remove(p.id) : _cart[p.id] = quantity);

  Future<void> _scan(List<Product> products) async {
    final t = AppLocalizations.of(context);
    final code = await context.push<String>('/scan');
    if (code == null || !mounted) return;
    final match = products.where((p) => p.barcode == code).firstOrNull;
    if (match == null) {
      showMessage(context, t.barcodeUnknown, error: true);
      return;
    }
    _set(match, (_cart[match.id] ?? 0) + 1);
    showMessage(context, t.addedToSale(match.name));
  }

  Future<void> _review(List<Product> products) async {
    final lines = [for (final e in _cart.entries) CartLine(products.firstWhere((p) => p.id == e.key), e.value)];
    final outcome = await showModalBottomSheet<SaleOutcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReviewSheet(lines: lines, onChanged: _set),
    );
    if (outcome != null && mounted) context.pushReplacement('/sale-done', extra: outcome);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final products = ref.watch(productsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.newSale),
        actions: [
          IconButton(
            tooltip: t.scanTitle,
            onPressed: products.hasValue ? () => _scan(products.value!) : null,
            icon: const Icon(LucideIcons.scanBarcode),
          ),
        ],
      ),
      body: AsyncBody(
        value: products,
        onRetry: () => ref.invalidate(productsProvider),
        builder: (all) {
          final families = {for (final p in all) p.family}.toList()..sort();
          final shown = all
              .where((p) => _family == null || p.family == _family)
              .where((p) => _query.isEmpty || p.name.toLowerCase().contains(_query) || (p.barcode ?? '').contains(_query))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: InputDecoration(hintText: t.searchProducts, prefixIcon: const Icon(LucideIcons.search, size: 20)),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(label: Text(t.all), selected: _family == null, onSelected: (_) => setState(() => _family = null)),
                    ),
                    for (final f in families)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(label: Text(f), selected: _family == f, onSelected: (_) => setState(() => _family = _family == f ? null : f)),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? EmptyState(icon: LucideIcons.packageSearch, title: t.noProductsFound)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const Gap(8),
                        itemBuilder: (context, i) => _ProductTile(product: shown[i], quantity: _cart[shown[i].id] ?? 0, onChanged: (q) => _set(shown[i], q)),
                      ),
              ),
              if (_cart.isNotEmpty)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: FilledButton.icon(
                      onPressed: () => _review(all),
                      icon: const Icon(LucideIcons.shoppingBasket),
                      label: Text(t.reviewSale(_units)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.quantity, required this.onChanged});

  final Product product;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final picked = quantity > 0;
    return AppCard(
      padding: const EdgeInsets.all(10),
      borderColor: picked ? context.colors.primary : null,
      onTap: picked ? null : () => onChanged(1),
      child: Row(
        children: [
          AuthImage(product.imageId, width: 56, height: 56, radius: 12, placeholderIcon: LucideIcons.package),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: context.text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(product.family, style: context.text.bodySmall?.copyWith(color: context.status.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (picked)
            QtyStepper(value: quantity, onChanged: onChanged)
          else
            Semantics(
              button: true,
              label: t.addToSale(product.name),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: context.colors.primary, borderRadius: BorderRadius.circular(14)),
                child: Icon(LucideIcons.plus, color: context.colors.onPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.lines, required this.onChanged});

  final List<CartLine> lines;
  final void Function(Product product, int quantity) onChanged;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  late final Map<String, int> _quantities = {for (final l in widget.lines) l.product.id: l.quantity};

  Future<void> _confirm() async {
    final lines = [for (final l in widget.lines) if ((_quantities[l.product.id] ?? 0) > 0) CartLine(l.product, _quantities[l.product.id]!)];
    try {
      final outcome = await ref.read(salesRepositoryProvider).record(lines);
      if (mounted) Navigator.pop(context, outcome);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final units = _quantities.values.fold(0, (a, b) => a + b);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.reviewTitle, style: context.text.titleLarge),
          const Gap(12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final l in widget.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(l.product.name, style: context.text.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        QtyStepper(
                          value: _quantities[l.product.id] ?? 0,
                          onChanged: (q) {
                            setState(() => _quantities[l.product.id] = q);
                            widget.onChanged(l.product, q);
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 24),
          Row(children: [Expanded(child: Text(t.totalUnits, style: context.text.titleMedium)), Text(t.units(units), style: context.text.titleMedium)]),
          const Gap(16),
          AsyncButton(label: t.recordSale, icon: LucideIcons.check, onPressed: units == 0 ? null : _confirm),
        ],
      ),
    );
  }
}
