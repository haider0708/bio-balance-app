import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/money.dart';
import '../../core/design.dart';
import '../media/image_input.dart';
import '../workspace/workspace_view_model.dart';

class ProductInformation extends StatelessWidget {
  final WorkspaceViewModel vm;
  final Json product;
  const ProductInformation({
    super.key,
    required this.vm,
    required this.product,
  });
  @override
  Widget build(BuildContext context) {
    final price = product['referencePriceMillimes'];
    return Content(
      maxWidth: 760,
      children: [
        if (product['imageId'] != null)
          ProtectedImage(vm: vm, id: product['imageId'], height: 220),
        const SizedBox(height: 20),
        SectionTitle(
          product['name'],
          subtitle: [
            product['range'],
            product['category'],
            product['packageSize'],
          ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
        ),
        CompactRow(title: 'Référence', value: product['reference']),
        CompactRow(
          title: 'Code-barres',
          subtitle: product['barcode'] ?? 'Code-barres à compléter',
          icon: AppIcons.scan,
        ),
        CompactRow(
          title: 'Prix de référence',
          value: price == null
              ? 'À compléter'
              : Money(integer(price)).formatted,
          subtitle: product['priceStatus'] == 'sample'
              ? 'Tarif de démonstration'
              : product['priceStatus'] == 'verified'
              ? 'Prix vérifié · chaque magasin fixe son prix de vente'
              : 'Prix non vérifié',
        ),
        const SizedBox(height: 20),
        const SectionTitle('À propos du produit'),
        Text(
          product['description']?.toString().trim().isNotEmpty == true
              ? product['description']
              : 'Description à compléter.',
        ),
        for (final field in {
          'instructions': 'Conseils d’utilisation',
          'ingredients': 'Ingrédients',
          'precautions': 'Précautions',
        }.entries)
          ExpansionTile(
            trailing: const Icon(AppIcons.keyboardArrowDown),
            key: PageStorageKey('product:${product['id']}:${field.key}'),
            tilePadding: EdgeInsets.zero,
            title: Text(field.value),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    product[field.key]?.toString().trim().isNotEmpty == true
                        ? product[field.key]
                        : 'Information vérifiée à compléter.',
                  ),
                ),
              ),
            ],
          ),
        if ((product['sourceUrls'] as List? ?? []).isNotEmpty)
          ExpansionTile(
            trailing: const Icon(AppIcons.keyboardArrowDown),
            key: PageStorageKey('product:${product['id']}:sources'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Sources des informations'),
            children: [
              for (final source in product['sourceUrls'])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SelectableText(
                    source,
                    style: const TextStyle(fontSize: 14, color: muted),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class ProductPhoto extends StatelessWidget {
  final WorkspaceViewModel vm;
  final String productId;
  final double size;
  const ProductPhoto({
    super.key,
    required this.vm,
    required this.productId,
    this.size = 48,
  });
  @override
  Widget build(BuildContext context) {
    final image = vm.state.data
        ?.list('products')
        .where((p) => p['id'] == productId)
        .firstOrNull?['imageId'];
    return SizedBox(
      width: size,
      height: size + 8,
      child: image == null
          ? const Icon(AppIcons.photo, color: muted)
          : ProtectedImage(vm: vm, id: image, height: size + 8),
    );
  }
}
