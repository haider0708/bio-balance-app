import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/session.dart';
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
import '../stock/stock_models.dart';
import '../stock/stock_repository.dart';
import 'sales_repository.dart';

/// Pick products, adjust quantities, record the sale. Built to be done with one hand at the till.
/// Stands for "no limit known" while the phone cannot read the stock.
const _unknownStock = 9999;

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

  /// What the store holds right now; a sale can never go beyond it.
  /// When the phone cannot reach the server the stock is unknown: the sale is kept
  /// and the server checks it when it is sent.
  Map<String, int> _stock = const {};
  bool _stockKnown = false;

  int _most(String productId) =>
      _stockKnown ? (_stock[productId] ?? 0) : _unknownStock;

  void _set(Product p, int quantity) {
    final most = _most(p.id);
    final next = quantity > most ? most : quantity;
    setState(() => next <= 0 ? _cart.remove(p.id) : _cart[p.id] = next);
  }

  Future<void> _scan(List<Product> products) async {
    final t = AppLocalizations.of(context);
    final code = await context.push<String>('/scan');
    if (code == null || !mounted) return;
    final match = products.where((p) => p.barcode == code).firstOrNull;
    if (match == null) {
      showMessage(context, t.barcodeUnknown, error: true);
      return;
    }
    if (_most(match.id) <= 0) {
      showMessage(context, t.outOfStockName(match.name), error: true);
      return;
    }
    _set(match, (_cart[match.id] ?? 0) + 1);
    showMessage(context, t.addedToSale(match.name));
  }

  Future<void> _review(List<Product> products) async {
    final lines = [
      for (final e in _cart.entries)
        CartLine(products.firstWhere((p) => p.id == e.key), e.value),
    ];
    final outcome = await showModalBottomSheet<SaleOutcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReviewSheet(
        lines: lines,
        stock: {for (final l in lines) l.product.id: _most(l.product.id)},
        onChanged: _set,
      ),
    );
    if (outcome != null && mounted)
      context.pushReplacement('/sale-done', extra: outcome);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final products = ref.watch(productsProvider);
    final pdvId = ref.watch(meProvider).pdv?.id;
    final levels = pdvId == null ? null : ref.watch(stockLevelsProvider(pdvId));
    _stockKnown = levels?.hasValue ?? false;
    _stock = {
      for (final i in levels?.value?.items ?? const <StockItem>[])
        i.productId: i.quantity,
    };
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
        // Wait for the stock too, so nothing looks sellable before we know what the store holds.
        value: levels != null && levels.isLoading && !levels.hasValue
            ? const AsyncLoading<List<Product>>()
            : products,
        onRetry: () => ref.invalidate(productsProvider),
        builder: (everything) {
          // Only what the store holds can be sold, so only that is shown.
          final all = everything.where((p) => _most(p.id) > 0).toList();
          final families = {for (final p in all) p.family}.toList()..sort();
          final shown = all
              .where((p) => _family == null || p.family == _family)
              .where(
                (p) =>
                    _query.isEmpty ||
                    p.name.toLowerCase().contains(_query) ||
                    (p.barcode ?? '').contains(_query),
              )
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: t.searchProducts,
                    prefixIcon: const Icon(LucideIcons.search, size: 20),
                  ),
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
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
                      child: ChoiceChip(
                        label: Text(t.all),
                        selected: _family == null,
                        onSelected: (_) => setState(() => _family = null),
                      ),
                    ),
                    for (final f in families)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(f),
                          selected: _family == f,
                          onSelected: (_) =>
                              setState(() => _family = _family == f ? null : f),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? EmptyState(
                        icon: LucideIcons.packageSearch,
                        title: all.isEmpty
                            ? t.nothingInStock
                            : t.noProductsFound,
                        message: all.isEmpty ? t.nothingInStockHint : null,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const Gap(8),
                        itemBuilder: (context, i) => _ProductTile(
                          product: shown[i],
                          stock: _most(shown[i].id),
                          quantity: _cart[shown[i].id] ?? 0,
                          onChanged: (q) => _set(shown[i], q),
                        ),
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
  const _ProductTile({
    required this.product,
    required this.stock,
    required this.quantity,
    required this.onChanged,
  });

  final Product product;
  final int stock;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final picked = quantity > 0;
    return AppCard(
      padding: const EdgeInsets.all(10),
      borderColor: picked ? context.colors.primary : null,
      onTap: picked || stock <= 0 ? null : () => onChanged(1),
      child: Row(
        children: [
          AuthImage(
            product.imageId,
            width: 56,
            height: 56,
            radius: 12,
            placeholderIcon: LucideIcons.package,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: context.text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  stock >= _unknownStock
                      ? product.family
                      : stock > 0
                      ? '${product.family} · ${t.inStockCount(stock)}'
                      : '${product.family} · ${t.outOfStock}',
                  style: context.text.bodySmall?.copyWith(
                    color: stock > 0
                        ? context.status.muted
                        : context.status.danger,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (picked)
            QtyStepper(value: quantity, max: stock, onChanged: onChanged)
          else if (stock <= 0)
            Icon(LucideIcons.ban, color: context.status.muted)
          else
            Semantics(
              button: true,
              label: t.addToSale(product.name),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: context.status.gradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(LucideIcons.plus, color: context.colors.onPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({
    required this.lines,
    required this.stock,
    required this.onChanged,
  });

  final List<CartLine> lines;
  final Map<String, int> stock;
  final void Function(Product product, int quantity) onChanged;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  late final Map<String, int> _quantities = {
    for (final l in widget.lines) l.product.id: l.quantity,
  };

  Future<void> _confirm() async {
    final lines = [
      for (final l in widget.lines)
        if ((_quantities[l.product.id] ?? 0) > 0)
          CartLine(l.product, _quantities[l.product.id]!),
    ];
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
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
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
                        Expanded(
                          child: Text(
                            l.product.name,
                            style: context.text.bodyLarge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        QtyStepper(
                          value: _quantities[l.product.id] ?? 0,
                          max: widget.stock[l.product.id],
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
          Row(
            children: [
              Expanded(
                child: Text(t.totalUnits, style: context.text.titleMedium),
              ),
              Text(t.units(units), style: context.text.titleMedium),
            ],
          ),
          const Gap(16),
          AsyncButton(
            label: t.recordSale,
            icon: LucideIcons.check,
            onPressed: units == 0 ? null : _confirm,
          ),
        ],
      ),
    );
  }
}
