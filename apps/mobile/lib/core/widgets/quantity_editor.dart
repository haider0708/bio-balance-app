import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/catalog/catalog_repository.dart';
import '../../features/catalog/product.dart';
import '../../features/media/media_repository.dart';
import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'async_body.dart';
import 'components.dart';
import 'states.dart';

class QuantityItem {
  QuantityItem({
    required this.productId,
    required this.name,
    required this.family,
    required this.quantity,
    this.imageId,
    this.hint,
    this.max,
  });

  final String productId;
  final String name;
  final String family;
  final String? imageId;
  int quantity;

  /// Shown under the name, e.g. "Requested 10".
  final String? hint;

  /// Highest quantity allowed (e.g. what the depot holds).
  final int? max;
}

/// The products and quantities being edited on a form.
class QuantityController extends ChangeNotifier {
  QuantityController([Iterable<QuantityItem> initial = const []]) {
    for (final item in initial) {
      _items[item.productId] = item;
    }
  }

  final Map<String, QuantityItem> _items = {};

  List<QuantityItem> get items => _items.values.toList();
  bool get isEmpty => _items.isEmpty;
  int get total => _items.values.fold(0, (sum, i) => sum + i.quantity);
  bool contains(String productId) => _items.containsKey(productId);

  void addProduct(Product product, {int quantity = 1}) {
    _items.putIfAbsent(
      product.id,
      () => QuantityItem(
        productId: product.id,
        name: product.name,
        family: product.family,
        imageId: product.imageId,
        quantity: quantity,
      ),
    );
    notifyListeners();
  }

  /// Add a row that is not a catalog product (e.g. an existing stock line).
  void addItem(QuantityItem item) {
    _items.putIfAbsent(item.productId, () => item);
    notifyListeners();
  }

  void setQuantity(String productId, int quantity) {
    final item = _items[productId];
    if (item == null) return;
    item.quantity = quantity.clamp(0, item.max ?? 100000);
    notifyListeners();
  }

  void remove(String productId) {
    _items.remove(productId);
    notifyListeners();
  }

  /// The lines to send to the server.
  List<Map<String, Object>> lines({bool skipZero = false}) => [
    for (final i in _items.values)
      if (!skipZero || i.quantity > 0)
        {'productId': i.productId, 'quantity': i.quantity},
  ];
}

/// Rows with a product, a quantity stepper and (optionally) a remove button.
class QuantityEditor extends StatelessWidget {
  const QuantityEditor({
    required this.controller,
    this.allowAdd = true,
    this.allowRemove = true,
    this.addLabel,
    super.key,
  });

  final QuantityController controller;
  final bool allowAdd;
  final bool allowRemove;
  final String? addLabel;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in controller.items) ...[
            _Row(item: item, controller: controller, removable: allowRemove),
            const Gap(8),
          ],
          if (allowAdd)
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await ProductPickerSheet.show(
                  context,
                  exclude: controller.items.map((i) => i.productId).toSet(),
                );
                if (picked == null) return;
                for (final product in picked) {
                  controller.addProduct(product);
                }
              },
              icon: const Icon(LucideIcons.plus, size: 20),
              label: Text(addLabel ?? t.addProduct),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.controller,
    required this.removable,
  });

  final QuantityItem item;
  final QuantityController controller;
  final bool removable;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          AuthImage(
            item.imageId,
            width: 48,
            height: 48,
            radius: 10,
            placeholderIcon: LucideIcons.package,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: context.text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.hint != null)
                  Text(
                    item.hint!,
                    style: context.text.bodySmall?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          QtyStepper(
            value: item.quantity,
            max: item.max,
            onChanged: (v) => controller.setQuantity(item.productId, v),
          ),
          if (removable)
            IconButton(
              tooltip: t.remove,
              onPressed: () => controller.remove(item.productId),
              icon: Icon(LucideIcons.x, size: 18, color: context.status.muted),
            ),
        ],
      ),
    );
  }
}

/// − 12 +  with a tappable number for typing larger quantities.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
    super.key,
  });

  final int value;
  final int min;
  final int? max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    Widget button(
      IconData icon,
      bool enabled,
      VoidCallback onTap,
      String label,
    ) => Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 24,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: enabled
                ? context.colors.primaryContainer
                : context.status.mutedSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 20,
            color: enabled ? context.colors.primary : context.status.muted,
          ),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          LucideIcons.minus,
          value > min,
          () => onChanged(value - 1),
          t.decrease,
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final typed = await _askNumber(context, value, max);
            if (typed != null) onChanged(typed);
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 40),
            height: 40,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('$value', style: context.text.titleMedium),
          ),
        ),
        button(
          LucideIcons.plus,
          max == null || value < max!,
          () => onChanged(value + 1),
          t.increase,
        ),
      ],
    );
  }

  Future<int?> _askNumber(BuildContext context, int current, int? max) {
    final t = AppLocalizations.of(context);
    final controller = TextEditingController(text: '$current');
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.quantity),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(
            helperText: max == null ? null : t.quantityMax(max),
          ),
          onSubmitted: (v) => Navigator.pop(context, int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text)),
            child: Text(t.confirm),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}

/// Choose one or several products from the catalog.
class ProductPickerSheet extends ConsumerStatefulWidget {
  const ProductPickerSheet({
    required this.exclude,
    this.single = false,
    super.key,
  });

  final Set<String> exclude;
  final bool single;

  static Future<List<Product>?> show(
    BuildContext context, {
    Set<String> exclude = const {},
    bool single = false,
  }) {
    return showModalBottomSheet<List<Product>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductPickerSheet(exclude: exclude, single: single),
    );
  }

  @override
  ConsumerState<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends ConsumerState<ProductPickerSheet> {
  final _selected = <String, Product>{};
  String _query = '';
  String? _family;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final products = ref.watch(productsProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: t.searchProducts,
                    prefixIcon: const Icon(LucideIcons.search, size: 20),
                  ),
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
                const Gap(10),
                products.maybeWhen(
                  data: (list) {
                    final families = {for (final p in list) p.family}.toList()
                      ..sort();
                    return SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
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
                                onSelected: (_) => setState(
                                  () => _family = _family == f ? null : f,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                  orElse: () => const SizedBox(height: 40),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: products,
              onRetry: () => ref.invalidate(productsProvider),
              builder: (list) {
                final shown = list
                    .where((p) => !widget.exclude.contains(p.id))
                    .where((p) => _family == null || p.family == _family)
                    .where(
                      (p) =>
                          _query.isEmpty ||
                          p.name.toLowerCase().contains(_query) ||
                          (p.barcode ?? '').contains(_query),
                    )
                    .toList();
                if (shown.isEmpty)
                  return EmptyState(
                    icon: LucideIcons.packageSearch,
                    title: t.noProductsFound,
                  );
                return ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final p = shown[i];
                    final on = _selected.containsKey(p.id);
                    return ListTile(
                      leading: AuthImage(
                        p.imageId,
                        width: 44,
                        height: 44,
                        radius: 10,
                        placeholderIcon: LucideIcons.package,
                      ),
                      title: Text(
                        p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(p.family),
                      trailing: widget.single
                          ? null
                          : Checkbox(value: on, onChanged: (_) => _toggle(p)),
                      onTap: () => widget.single
                          ? Navigator.pop(context, [p])
                          : _toggle(p),
                    );
                  },
                );
              },
            ),
          ),
          if (!widget.single)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selected.values.toList()),
                  child: Text(t.addSelected(_selected.length)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _toggle(Product p) => setState(
    () => _selected.containsKey(p.id)
        ? _selected.remove(p.id)
        : _selected[p.id] = p,
  );
}
