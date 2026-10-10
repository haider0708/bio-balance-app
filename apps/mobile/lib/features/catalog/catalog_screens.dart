import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/json.dart';
import '../../core/theme/app_theme.dart';
import '../analytics/analytics_widgets.dart' show AnalyticsButton;
import '../analytics/lens.dart' show Facet;
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/photo_field.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../media/media_repository.dart';
import 'catalog_repository.dart';
import 'product.dart';

/// The product catalog: browsed by everyone who can see it, edited by the admin.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({this.editable = false, super.key});

  final bool editable;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String _query = '';
  String? _family;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final products = ref.watch(
      widget.editable ? allProductsProvider : productsProvider,
    );
    return Scaffold(
      appBar: AppBar(title: Text(t.catalogTitle)),
      floatingActionButton: widget.editable
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () async {
                await context.push('/catalog/new');
                ref.invalidate(allProductsProvider);
                ref.invalidate(productsProvider);
              },
              icon: const Icon(LucideIcons.plus),
              label: Text(t.newProduct),
            )
          : null,
      body: AsyncBody(
        value: products,
        onRetry: () {
          ref.invalidate(allProductsProvider);
          ref.invalidate(productsProvider);
        },
        builder: (all) {
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
                        title: t.noProductsFound,
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(allProductsProvider);
                          ref.invalidate(productsProvider);
                          await ref.read(
                            widget.editable
                                ? allProductsProvider.future
                                : productsProvider.future,
                          );
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          itemCount: shown.length,
                          separatorBuilder: (_, _) => const Gap(8),
                          itemBuilder: (context, i) {
                            final p = shown[i];
                            return AppCard(
                              padding: const EdgeInsets.all(10),
                              onTap: () async {
                                await context.push(
                                  '/catalog/${p.id}',
                                  extra: p,
                                );
                                ref.invalidate(allProductsProvider);
                                ref.invalidate(productsProvider);
                              },
                              child: Row(
                                children: [
                                  AuthImage(
                                    p.imageId,
                                    width: 56,
                                    height: 56,
                                    radius: 12,
                                    placeholderIcon: LucideIcons.package,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: context.text.titleSmall,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          [
                                            p.family,
                                            if (p.packageSize.isNotEmpty)
                                              p.packageSize,
                                          ].join(' · '),
                                          style: context.text.bodySmall
                                              ?.copyWith(
                                                color: context.status.muted,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!p.active)
                                    StatusChip(t.inactive, tone: Tone.muted),
                                ],
                              ),
                            );
                          },
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

/// A product's information page; the admin can edit it.
class ProductScreen extends ConsumerWidget {
  const ProductScreen({
    required this.product,
    this.editable = false,
    super.key,
  });

  final Product product;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    Widget section(String title, String body) => body.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                const Gap(4),
                Text(
                  body,
                  style: context.text.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(product.name),
        actions: [
          AnalyticsButton(facet: Facet.product, id: product.id),
          if (editable)
            IconButton(
              icon: const Icon(LucideIcons.pencil),
              onPressed: () => context.pushReplacement(
                '/catalog/${product.id}/edit',
                extra: product,
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: AuthImage(
              product.imageId,
              width: 220,
              height: 220,
              radius: 20,
              placeholderIcon: LucideIcons.package,
            ),
          ),
          const Gap(16),
          Text(product.name, style: context.text.headlineSmall),
          const Gap(6),
          Wrap(
            spacing: 8,
            children: [
              StatusChip(product.family, tone: Tone.success),
              if (product.packageSize.isNotEmpty)
                StatusChip(product.packageSize),
              if (product.barcode != null)
                StatusChip(product.barcode!, icon: LucideIcons.scanBarcode),
            ],
          ),
          section(t.description, product.description),
          section(t.howToUse, product.instructions),
          section(t.ingredients, product.ingredients),
          section(t.precautions, product.precautions),
        ],
      ),
    );
  }
}

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({this.existing, super.key});

  final Product? existing;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _reference = TextEditingController(
    text: widget.existing?.reference,
  );
  late final _barcode = TextEditingController(text: widget.existing?.barcode);
  late final _family = TextEditingController(text: widget.existing?.family);
  late final _size = TextEditingController(text: widget.existing?.packageSize);
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late bool _active = widget.existing?.active ?? true;
  late String? _imageId = widget.existing?.imageId;

  @override
  void dispose() {
    for (final c in [
      _name,
      _reference,
      _barcode,
      _family,
      _size,
      _description,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    final body = <String, Object?>{
      'name': _name.text.trim(),
      'reference': _reference.text.trim(),
      'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      'family': _family.text.trim(),
      'packageSize': _size.text.trim(),
      'description': _description.text.trim(),
      'imageId': _imageId,
      'active': _active,
    };
    final repo = ref.read(catalogRepositoryProvider);
    final existing = widget.existing;
    final ok = await perform(
      context,
      () => existing == null
          ? repo.create(Json.from(body))
          : repo.update(existing.id, Json.from(body)),
      success: t.saved,
    );
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final families = {
      for (final p in ref.watch(allProductsProvider).value ?? const <Product>[])
        p.family,
    }.toList()..sort();
    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? t.fieldRequired : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? t.newProduct : t.editProduct),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PhotoField(
              label: t.productPhoto,
              purpose: 'PRODUCT',
              initialId: _imageId,
              onChanged: (id) => _imageId = id ?? _imageId,
            ),
            const Gap(16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: t.productName),
              validator: required,
            ),
            const Gap(12),
            TextFormField(
              controller: _reference,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: t.reference),
              validator: required,
            ),
            const Gap(12),
            TextFormField(
              controller: _barcode,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: '${t.barcode} (${t.optional})',
              ),
            ),
            const Gap(12),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _family.text),
              optionsBuilder: (v) => families.where(
                (f) => f.toLowerCase().contains(v.text.toLowerCase()),
              ),
              onSelected: (v) => _family.text = v,
              fieldViewBuilder: (context, controller, focus, _) =>
                  TextFormField(
                    controller: controller,
                    focusNode: focus,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: t.family,
                      helperText: t.familyHint,
                    ),
                    onChanged: (v) => _family.text = v,
                    validator: required,
                  ),
            ),
            const Gap(12),
            TextFormField(
              controller: _size,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: '${t.packageSize} (${t.optional})',
              ),
            ),
            const Gap(12),
            TextFormField(
              controller: _description,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: '${t.description} (${t.optional})',
                alignLabelWithHint: true,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: Text(t.productActive),
              subtitle: Text(t.productActiveHint),
            ),
            const Gap(8),
            AsyncButton(label: t.save, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
