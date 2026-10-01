import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/money.dart';
import '../../core/design.dart';
import '../inventory/inventory_screens.dart';
import '../workspace/workspace_view_model.dart';

class ProductSettingsPage extends StatefulWidget {
  final WorkspaceViewModel vm;
  const ProductSettingsPage({super.key, required this.vm});
  @override
  State<ProductSettingsPage> createState() => _ProductSettingsPageState();
}

class _ProductSettingsPageState extends State<ProductSettingsPage> {
  String query = '';
  bool get showPoints =>
      widget.vm.user.admin || widget.vm.state.store?.wholesale == true;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.vm,
    builder: (context, _) {
      final data = widget.vm.state.data;
      final products =
          data?.products.where((p) => p.active && p.matches(query)).toList() ??
          <Product>[];
      return Content.builder(
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index],
              config = data!.config(products[index].id);
          return CompactRow(
            title: product.name,
            subtitle: [
              '${Money(integer(config['priceMillimes'])).formatted} · Seuil ${config['threshold']} u.',
              // Points are BioBalance's business: a store manager never sees them.
              if (showPoints)
                config['pointsConfigured'] == true
                    ? '${config['pointsPerUnit']} points / unité'
                    : widget.vm.user.admin
                    ? 'Points à configurer'
                    : 'Points définis par BioBalance',
            ].join('\n'),
            trailing: const Icon(AppIcons.editOutlined, size: 20, color: muted),
            onTap: () => configureStoreProduct(context, widget.vm, product),
          );
        },
        children: [
          SectionTitle(
            showPoints ? 'Prix, points et seuils' : 'Prix et seuils',
            subtitle: 'Paramètres propres à ce magasin',
          ),
          TextField(
            onChanged: (value) =>
                setState(() => query = value.trim().toLowerCase()),
            decoration: const InputDecoration(
              hintText: 'Rechercher un produit',
              prefixIcon: Icon(AppIcons.search),
            ),
          ),
          const SizedBox(height: 8),
          if (products.isEmpty)
            const EmptyState(
              title: 'Aucun produit à afficher',
              description: 'Essayez une autre recherche ou ajoutez des produits au catalogue.',
            ),
        ],
      );
    },
  );
}
