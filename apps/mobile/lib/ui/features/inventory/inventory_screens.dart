import 'receipt_screen.dart';
import '../catalog/product_information.dart';
import 'stock_view_model.dart';
import '../../../domain/models/inventory_rules.dart';

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:flutter/material.dart';

import '../reporting/history_screen.dart';

import '../../../domain/models/models.dart';
import '../../../data/repositories/pricing_repository.dart';
import '../../../data/repositories/store_settings_repository.dart';
import '../../../domain/models/money.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../../core/segment_bar.dart';
import '../sales/sale_screen.dart';
import '../media/image_input.dart';
import '../workspace/workspace_view_model.dart';
import '../workspace/operation_helpers.dart';

class StockPage extends StatefulWidget {
  final WorkspaceViewModel vm;
  const StockPage({super.key, required this.vm});
  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  late StockViewModel stock;
  final search = TextEditingController();
  bool restored = false;
  String get filterKey => 'stock-filter:${widget.vm.state.store?.id}';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!restored) {
      final saved = PageStorage.maybeOf(
        context,
      )?.readState(context, identifier: filterKey) as Map?;
      stock.search(saved?['query'] as String? ?? '');
      stock.selectFilter(saved?['filter'] as String? ?? 'all');
      search.text = stock.query;
      restored = true;
    }
  }

  void remember() => PageStorage.maybeOf(context)?.writeState(context, {
    'query': stock.query,
    'filter': stock.filter,
  }, identifier: filterKey);

  @override
  void initState() {
    super.initState();
    stock = StockViewModel(widget.vm);
  }

  @override
  void didUpdateWidget(covariant StockPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vm != widget.vm) {
      stock.dispose();
      stock = StockViewModel(widget.vm);
    }
    stock.refresh();
  }

  @override
  void dispose() {
    stock.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: stock,
    builder: (context, _) {
      final vm = widget.vm, products = stock.rows;
      return Content.builder(
        key: PageStorageKey('stock-list:${vm.state.store?.id}'),
        onRefresh: () => vm.synchronize().catchError((Object _) {}),
        itemCount: products.length,
        itemBuilder: (context, index) => productCard(products[index]),
        children: [
          SectionTitle(
            'Stock du magasin',
            subtitle: 'Les lots, les quantités et les dates au même endroit.',
          ),
          OpeningStockCard(vm: vm),
          TextField(
            controller: search,
            onChanged: (value) {
              stock.search(value);
              remember();
            },
            decoration: const InputDecoration(
              hintText: 'Rechercher un produit',
              prefixIcon: Icon(AppIcons.search),
            ),
          ),
          const SizedBox(height: 16),
          SegmentBar(
            keyPrefix: 'stock',
            segments: {
              for (final e in const {
                'all': ('Tous', AppIcons.inventory2Outlined),
                'low': ('Stock faible', AppIcons.errorOutline),
                'discrepancy': ('Alertes', AppIcons.infoOutline),
                'approaching': ('Péremption proche', AppIcons.schedule),
                'expired': ('Périmés', AppIcons.close),
              }.entries)
                e.key: Segment(
                  e.value.$1,
                  e.value.$2,
                  stock.counts[e.key] ?? 0,
                ),
            },
            selected: stock.filter,
            onChanged: (value) {
              stock.selectFilter(value);
              remember();
            },
          ),
          const SizedBox(height: 20),
          if (stock.loading) const LinearProgressIndicator(),
          if (stock.error != null) Notice(stock.error!, error: true),
          if (!stock.loading && stock.error == null && products.isEmpty)
            const EmptyState(
              title: 'Aucun produit à afficher',
              description:
                  'Changez les filtres ou ajoutez vos premières références.',
            ),
        ],
      );
    },
  );

  Widget productCard(StockRow row) {
    final p = row.product, summary = row.summary;
    return CompactRow(
      key: ValueKey(p.id),
      title: p.name,
      subtitle: [
        p.reference,
        if (summary.low) 'À réapprovisionner',
        if (summary.discrepancy) 'Stock à vérifier',
        if (summary.expired) 'Lots périmés',
      ].join(' · '),
      value: '${summary.available} u.',
      leading: ProductPhoto(vm: widget.vm, productId: p.id, imageId: p.imageId),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetail(vm: widget.vm, product: p),
        ),
      ),
    );
  }
}

class ProductDetail extends StatelessWidget {
  final WorkspaceViewModel vm;
  final Product product;
  const ProductDetail({super.key, required this.vm, required this.product});
  // Points are BioBalance's business: a store manager never sees them.
  bool get showPoints => vm.user.admin || vm.state.store?.wholesale == true;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final data = vm.state.data;
      if (data == null) {
        return Scaffold(
          appBar: AppBar(title: Text(product.name)),
          body: const Center(
            child: Text('Accès à vérifier. Vos saisies sont conservées.'),
          ),
        );
      }
      final config = data.config(product.id);
      final imageId =
          data
                  .list('products')
                  .where((p) => p['id'] == product.id)
                  .firstOrNull?['imageId']
              as String?;
      final lots = InventorySelection.inStock(
        data.lotsByProduct[product.id] ?? [],
      );
      return Scaffold(
        appBar: AppBar(title: Text(product.name)),
        body: Content(
          maxWidth: 760,
          children: [
            if (imageId != null)
              ProtectedImage(vm: vm, id: imageId, height: 160),
            SectionTitle(product.reference, subtitle: product.description),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                StatusChip(
                  'Seuil : ${config['threshold']} unités',
                  icon: AppIcons.notificationsOutlined,
                ),
                if (showPoints)
                  StatusChip(
                    '${config['pointsPerUnit']} points / unité',
                    icon: AppIcons.starsOutlined,
                  ),
              ],
            ),
            if (showPoints && config['pointsConfigured'] != true) ...[
              const SizedBox(height: 16),
              Notice(
                vm.user.admin
                    ? 'Aucun barème configuré : ce produit attribue actuellement zéro point.'
                    : 'Aucun barème de points défini par BioBalance : ce produit attribue actuellement zéro point.',
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => configure(context),
              icon: const Icon(AppIcons.tune),
              label: Text(
                vm.user.admin ? 'Prix, seuil et points' : 'Prix et seuil',
              ),
            ),
            const SizedBox(height: 20),
            SectionTitle(
              'Lots et péremptions',
              action: IconButton(
                tooltip: 'Historique du stock',
                icon: const Icon(AppIcons.history),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HistoryScreen(
                      vm: vm,
                      resource: 'movements',
                      title: 'Mouvements de stock',
                      productId: product.id,
                    ),
                  ),
                ),
              ),
            ),
            if (lots.isEmpty)
              const EmptyState(
                title: 'Aucun lot en stock',
                description: 'Les lots épuisés restent dans l’historique. Le stock arrive par commande et livraison.',
              ),
            ...lots.map(
              (lot) => CompactRow(
                title: 'Lot ${lot.batch}',
                subtitle:
                    '${dateLabel(lot.expiry)} · ${lot.damaged} non vendables${lot.expired ? ' · Périmé' : ''}${lot.sellable < 0 ? ' · Stock à vérifier' : ''}',
                value: '${lot.sellable} u.',
                footer: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => flag(context, lot),
                      child: Text(
                        lot.expired && lot.sellable > 0
                            ? 'Signaler comme périmé'
                            : 'Signaler non conforme',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  Future<void> configure(BuildContext context) =>
      configureStoreProduct(context, vm, product);

  /// Damaged or expired goods: held out of sale at once, then BioBalance decides.
  Future<void> flag(BuildContext context, InventoryLot lot) async {
    final store = vm.state.store!;
    final expired = lot.expired && lot.sellable > 0;
    // One flag per form: a retry never flags the same units twice.
    final flagId = const Uuid().v4();
    await openEditor(
      context,
      draftKey: 'quality:${lot.id}',
      title: expired
          ? 'Signaler un lot périmé'
          : 'Signaler un produit non conforme',
      description:
          '${vm.productName(lot.productId)} · Lot ${lot.batch}. Les unités sortent du stock vendable tout de suite ; BioBalance décide ensuite de leur sort.',
      fields: [
        if (expired)
          const FieldSpec(
            'kind',
            'Motif',
            initial: 'expired',
            options: {'expired': 'Périmé', 'damaged': 'Abîmé'},
            choice: true,
          ),
        FieldSpec(
          'quantity',
          'Unités concernées',
          initial: expired ? '${lot.sellable}' : '',
          numeric: true,
        ),
        FieldSpec(
          'note',
          expired ? 'Remarque (facultatif)' : 'Décrivez le dommage constaté',
          required: !expired,
        ),
      ],
      submitWithDraft: (v, draftKey) async {
        final note = (v['note'] ?? '').trim();
        await vm.queue(
          {
            'type': 'quality.flag',
            'flagId': flagId,
            'lotId': lot.id,
            'quantity': whole(v['quantity']!),
            'kind': expired ? (v['kind'] ?? 'expired') : 'damaged',
            if (note.isNotEmpty) 'note': note,
          },
          expectedVersion: lot.version,
          targetStore: store,
          draftKey: draftKey,
        );
      },
    );
  }
}

Future<void> configureStoreProduct(
  BuildContext context,
  WorkspaceViewModel vm,
  Product product,
) async {
  final config = vm.state.data!.config(product.id), store = vm.state.store!;
  // What this role pays is shown beside the price it sets; a hidden level is null.
  Json? prices;
  try {
    prices = (await PricingRepository(vm.repositoryContext)
        .current(store))[product.id];
  } catch (_) {
    /* Offline: the editor still works without the purchase price. */
  }
  final purchase = store.wholesale
      ? [
          if (prices?['wholesaleMillimes'] != null)
            'Vous payez ${Money(integer(prices!['wholesaleMillimes'])).formatted}',
          if (prices?['supplyMillimes'] != null)
            'les magasins paient ${Money(integer(prices!['supplyMillimes'])).formatted}',
        ].join(' · ')
      : prices?['supplyMillimes'] == null
      ? null
      : 'Prix d’achat fixé par BioBalance : ${Money(integer(prices!['supplyMillimes'])).formatted}';
  if (!context.mounted) return;
  if (await openEditor(
    context,
    title: 'Paramétrer le produit',
    description: purchase == null || purchase.isEmpty ? null : purchase,
    fields: [
      // A depot sells nothing over a counter: it has no retail price.
      if (!store.wholesale)
        FieldSpec(
          'price',
          'Prix de vente (TND)',
          initial: Money(integer(config['priceMillimes'])).input,
          numeric: true,
        ),
      FieldSpec(
        'threshold',
        'Seuil de réapprovisionnement',
        initial: '${config['threshold']}',
        numeric: true,
      ),
      // The points rate is set by BioBalance only.
      if (vm.user.admin)
        FieldSpec(
          'points',
          store.wholesale
              ? 'Points par unité livrée'
              : 'Points par unité vendue',
          initial: '${config['pointsPerUnit']}',
          numeric: true,
        ),
      // Changes are recorded with their date; a reason makes them traceable.
      const FieldSpec('reason', 'Motif du changement', required: false),
    ],
    submit: (v) async {
      // Selling below what the store pays is allowed, but never by accident.
      final paid = prices?['supplyMillimes'];
      if (!store.wholesale && paid != null) {
        final entered = Money.tryParse(v['price'] ?? '');
        if (entered != null &&
            entered.millimes < integer(paid) &&
            (!context.mounted ||
                !await confirmAction(
                  context,
                  'Prix inférieur au prix d’achat',
                  'Vous achetez ${product.name} ${Money(integer(paid)).formatted} et vous le vendriez ${entered.formatted} : vous perdriez de l’argent sur chaque vente.',
                  label: 'Garder ce prix',
                ))) {
          throw const FormatException(
            'Prix non enregistré. Corrigez-le ou confirmez-le.',
          );
        }
      }
      final points = vm.user.admin
          ? whole(v['points']!, allowZero: true)
          : integer(config['pointsPerUnit']);
      if (vm.user.admin &&
          points == 0 &&
          (!context.mounted ||
              !await confirmAction(
                context,
                'Confirmer : zéro point',
                'Les ventes de ${product.name} ne rapporteront aucun point dans ${store.name}.',
                label: 'Confirmer zéro point',
              ))) {
        throw const FormatException(
          'Configuration non enregistrée. Confirmez le choix de zéro point.',
        );
      }
      vm.requireAccess(store, 'manage');
      final reason = (v['reason'] ?? '').trim();
      await vm.catalog.configure(store, product.id, {
        'priceMillimes': store.wholesale
            ? '0'
            : Money.parse(v['price']!).millimes.toString(),
        if (reason.length >= 3) 'reason': reason,
        'threshold': whole(v['threshold']!, allowZero: true),
        'pointsPerUnit': points,
        'zeroPointsConfirmed': vm.user.admin && points == 0,
        if (config['version'] != null) 'expectedVersion': config['version'],
      });
    },
  )) {
    await vm.synchronize();
  }
}

/// The one chance to declare the stock already on the shelves. Afterwards stock
/// only arrives by order and delivery, so every count can be traced.
class OpeningStockCard extends StatelessWidget {
  final WorkspaceViewModel vm;
  const OpeningStockCard({super.key, required this.vm});

  Future<void> noStock(BuildContext context) async {
    final store = vm.state.store!;
    if (!await confirmAction(
      context,
      'Je n’ai pas de stock',
      'Vos produits arriveront par commande et livraison. Vous pouvez changer d’avis tant que vous n’avez ni saisi de stock ni reçu de livraison.',
      label: 'Confirmer',
    )) {
      return;
    }
    if (!context.mounted) return;
    await run(context, () async {
      vm.requireAccess(store, 'manage');
      await StoreSettingsRepository(vm.api).onboarding(store, {
        'noOpeningStock': true,
        'expectedVersion': (vm.state.data!.raw['store'] as Map)['version'],
      });
      await vm.synchronize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = vm.state.store;
    final data = vm.state.data;
    if (store == null ||
        data == null ||
        store.openingClosed ||
        data.lots.isNotEmpty ||
        !(store.canManage || vm.user.admin)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CompactRow(
        title: 'Avez-vous déjà du stock ?',
        subtitle: 'Vous avez une seule occasion de le déclarer. Ensuite, le stock n’arrive que par commande et livraison.',
        icon: AppIcons.infoOutline,
        tone: AppTone.warning,
        footer: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ReceiptScreen(vm: vm)),
              ),
              icon: const Icon(AppIcons.add),
              label: const Text('Oui, je le saisis'),
            ),
            OutlinedButton(
              onPressed: () => noStock(context),
              child: const Text('Non, je commande'),
            ),
          ],
        ),
      ),
    );
  }
}
