import 'catalog_import_screen.dart';
import 'catalog_view_model.dart';
import '../../../domain/models/money.dart';
import 'product_information.dart';
import '../media/image_input.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../workspace/workspace_view_model.dart';

class CatalogPage extends StatefulWidget {
  final WorkspaceViewModel vm;
  const CatalogPage({super.key, required this.vm});
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  WorkspaceViewModel get vm => widget.vm;
  String query = '';
  final search = TextEditingController();
  bool restored = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!restored) {
      query =
          PageStorage.maybeOf(context)
                  ?.readState(context, identifier: 'catalog-query')
              as String? ??
          '';
      search.text = query;
      restored = true;
    }
  }

  late final catalog = CatalogViewModel(vm)..load();
  @override
  void dispose() {
    search.dispose();
    catalog.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: catalog,
    builder: (context, _) => content(context),
  );
  Widget content(BuildContext context) {
    final products = catalog.products
        .where(
          (p) => '${p['name']} ${p['reference']} ${p['barcode'] ?? ''}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Content.builder(
      key: const PageStorageKey('catalog-list'),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final p = products[index];
        return CompactRow(
          title: p['name'],
          subtitle:
              '${p['reference']} · ${p['active'] == true ? 'Actif' : 'Archivé'}',
          leading: SizedBox(
            width: 48,
            height: 60,
            child: p['imageId'] == null
                ? const Icon(AppIcons.photo, color: muted)
                : ProtectedImage(vm: vm, id: p['imageId'], height: 60),
          ),
          trailing: const Icon(AppIcons.chevronRight, size: 20, color: muted),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(
                  title: const Text('Fiche produit'),
                  actions: [
                    if (vm.user.admin)
                      IconButton(
                        onPressed: () => edit(context, p),
                        tooltip: 'Modifier',
                        icon: const Icon(AppIcons.editOutlined),
                      ),
                  ],
                ),
                body: ProductInformation(vm: vm, product: p),
              ),
            ),
          ),
        );
      },
      children: [
        SectionTitle(
          'Catalogue BioBalance',
          action: !vm.user.admin
              ? null
              : FilledButton.icon(
                  onPressed: () => edit(context),
                  icon: const Icon(AppIcons.add),
                  label: const Text('Ajouter un produit'),
                ),
        ),
        if (vm.user.admin)
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CatalogImportScreen(vm: vm)),
            ),
            icon: const Icon(AppIcons.uploadFile),
            label: const Text('Importer un CSV'),
          ),
        if (catalog.loading) const LinearProgressIndicator(),
        if (catalog.error != null) Notice(catalog.error!, retry: catalog.load),
        const SizedBox(height: 16),
        TextField(
          controller: search,
          onChanged: (value) {
            setState(() => query = value.trim().toLowerCase());
            PageStorage.maybeOf(context)
                ?.writeState(context, query, identifier: 'catalog-query');
          },
          decoration: const InputDecoration(
            hintText: 'Rechercher un produit',
            prefixIcon: Icon(AppIcons.search),
          ),
        ),
        const SizedBox(height: 8),
        if (products.isEmpty)
          EmptyState(
            title: query.isEmpty
                ? 'Votre catalogue est vide'
                : 'Aucun produit trouvé',
            description: query.isEmpty
                ? 'Ajoutez un produit ou importez votre catalogue.'
                : 'Essayez un autre nom, une référence ou un code-barres.',
          ),
      ],
    );
  }

  Future<void> edit(BuildContext context, [Json? p]) async {
    if (await openEditor(
      context,
      title: p == null ? 'Créer un produit' : 'Modifier le produit',
      fields: [
        FieldSpec('reference', 'Référence', initial: p?['reference'] ?? ''),
        FieldSpec('name', 'Nom du produit', initial: p?['name'] ?? ''),
        FieldSpec(
          'imageId',
          'Image du produit',
          initial: p?['imageId'] ?? '',
          required: false,
          imagePurpose: 'catalog',
        ),
        FieldSpec(
          'barcode',
          'Code-barres',
          initial: p?['barcode'] ?? '',
          required: false,
        ),
        FieldSpec(
          'description',
          'Description',
          initial: p?['description'] ?? '',
          multiline: true,
          required: false,
        ),
        for (final f in {
          'category': 'Catégorie',
          'range': 'Gamme',
          'packageSize': 'Contenance',
          'instructions': 'Conseils d’utilisation',
          'ingredients': 'Ingrédients',
          'precautions': 'Précautions',
        }.entries)
          FieldSpec(
            f.key,
            f.value,
            initial: p?[f.key] ?? '',
            required: false,
            multiline: [
              'instructions',
              'ingredients',
              'precautions',
            ].contains(f.key),
          ),
        FieldSpec(
          'priceStatus',
          'Statut du prix de référence',
          initial: p?['priceStatus'] ?? 'missing',
          options: const {
            'missing': 'À compléter',
            'verified': 'Vérifié',
            'sample': 'Tarif de démonstration',
          },
        ),
        FieldSpec(
          'referencePriceMillimes',
          'Prix de référence (TND)',
          initial: p?['referencePriceMillimes'] == null
              ? ''
              : Money(integer(p!['referencePriceMillimes'])).input,
          numeric: true,
          required: false,
        ),
        FieldSpec(
          'sourceUrls',
          'Sources vérifiées (une URL par ligne)',
          initial: (p?['sourceUrls'] as List? ?? []).join('\n'),
          required: false,
          multiline: true,
        ),
        FieldSpec(
          'active',
          'Statut',
          initial: p?['active'] == false ? 'no' : 'yes',
          options: const {'yes': 'Actif', 'no': 'Archivé'},
        ),
      ],
      submit: (v) async {
        await vm.catalog.save({
          if (p != null) 'id': p['id'],
          if (p != null) 'expectedVersion': p['version'],
          'reference': v['reference'],
          'name': v['name'],
          'imageId': v['imageId']!.isEmpty ? null : v['imageId'],
          if (v['barcode']!.isNotEmpty) 'barcode': v['barcode'],
          'description': v['description'],
          'active': v['active'] == 'yes',
          for (final key in [
            'category',
            'range',
            'packageSize',
            'instructions',
            'ingredients',
            'precautions',
            'priceStatus',
          ])
            key: v[key],
          'referencePriceMillimes': v['referencePriceMillimes']!.isEmpty
              ? null
              : Money.parse(v['referencePriceMillimes']!).millimes.toString(),
          'sourceUrls': v['sourceUrls']!
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
        });
      },
    )) {
      await catalog.load();
    }
  }
}
