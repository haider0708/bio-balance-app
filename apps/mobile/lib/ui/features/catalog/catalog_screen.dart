import 'catalog_import_screen.dart';

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
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) => content(context),
  );
  Widget content(BuildContext context) {
    final products = (vm.state.data?.list('products') ?? <Json>[])
        .where(
          (p) => '${p['name']} ${p['reference']} ${p['barcode'] ?? ''}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Content.builder(
      itemCount: products.length,
      itemBuilder: (context, index) {
        final p = products[index];
        return CompactRow(
          title: p['name'],
          subtitle:
              '${p['reference']} · ${p['active'] == true ? 'Actif' : 'Archivé'}',
          icon: Icons.spa_outlined,
          trailing: const Icon(Icons.edit_outlined, size: 20, color: muted),
          onTap: () => edit(context, p),
        );
      },
      children: [
        SectionTitle(
          'Catalogue BioBalance',
          action: FilledButton.icon(
            onPressed: () => edit(context),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un produit'),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CatalogImportScreen(vm: vm)),
          ),
          icon: const Icon(Icons.upload_file),
          label: const Text('Importer un CSV'),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (value) =>
              setState(() => query = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            hintText: 'Rechercher un produit',
            prefixIcon: Icon(Icons.search),
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
        });
      },
    )) {
      await vm.synchronize();
    }
  }
}
