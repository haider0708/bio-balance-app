import 'catalog_import_screen.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../workspace/workspace_view_model.dart';

class CatalogPage extends StatelessWidget {
  final WorkspaceViewModel vm;
  const CatalogPage({super.key, required this.vm});
  @override
  Widget build(BuildContext context) => Content(
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
      ...objects(vm.state.data?.raw['products']).map(
        (p) => Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const Icon(Icons.spa_outlined, color: darkGreen),
            title: Text(p['name']),
            subtitle: Text(
              '${p['reference']} · ${p['active'] == true ? 'Actif' : 'Archivé'}',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => edit(context, p),
          ),
        ),
      ),
    ],
  );
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
