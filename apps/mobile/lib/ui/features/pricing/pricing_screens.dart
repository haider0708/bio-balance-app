import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/pricing_repository.dart';
import '../../../data/repositories/wholesale_repository.dart';
import '../../../domain/models/models.dart';
import '../../../domain/models/money.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

String priceLevelLabel(String level) => switch (level) {
  'wholesale' => 'Prix de gros',
  'store_supply' => 'Prix d’approvisionnement',
  _ => 'Prix de vente',
};

String millimesLabel(dynamic value) =>
    value == null ? 'Non défini' : Money(integer(value)).formatted;

/// Every recorded price of a product that this role may see. Nothing recorded
/// here is ever edited or removed: a change adds a line.
class PriceHistoryScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  final Json product;
  // A store or depot limits the history to that place; BioBalance may omit it.
  final Store? store;
  const PriceHistoryScreen({
    super.key,
    required this.vm,
    required this.product,
    this.store,
  });
  @override
  State<PriceHistoryScreen> createState() => _PriceHistoryScreenState();
}

class _PriceHistoryScreenState extends State<PriceHistoryScreen> {
  late final repository = PricingRepository(widget.vm.repositoryContext);
  List<Json> items = const [];
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final result = await repository.history(
        widget.product['id'],
        store: widget.store,
      );
      if (mounted) {
        setState(() {
          items = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String place(Json entry) {
    final stores = widget.vm.state.stores;
    final store = stores.where((s) => s.id == entry['storeId']).firstOrNull;
    if (store != null) return store.name;
    final group = stores
        .where((s) => s.organizationId == entry['organizationId'])
        .firstOrNull;
    return group?.organizationName ?? 'Par défaut';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Historique des prix')),
    body: Content(
      children: [
        SectionTitle(
          widget.product['name'],
          subtitle: 'Chaque changement est conservé ; les ventes passées gardent leur prix',
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Notice(error!, retry: load),
        if (!loading && items.isEmpty && error == null)
          const EmptyState(
            title: 'Aucun prix enregistré',
            description:
                'Les prix apparaîtront ici avec leur date et leur motif.',
            icon: AppIcons.tuneOutlined,
          ),
        for (final entry in items)
          CompactRow(
            title: entry['cleared'] == true
                ? 'Prix particulier retiré · ${priceLevelLabel(entry['level'])}'
                : '${millimesLabel(entry['priceMillimes'])} · ${priceLevelLabel(entry['level'])}',
            subtitle: [
              place(entry),
              TunisDates.timestampLabel(entry['createdAt']),
              if (entry['author'] != null) 'Par ${entry['author']}',
              if (entry['seeded'] == true)
                'Prix existant avant l’historique'
              else if (entry['reason'] != null)
                entry['reason'],
            ].join('\n'),
            icon: AppIcons.tuneOutlined,
          ),
      ],
    ),
  );
}

/// BioBalance sets wholesale and store-supply prices, by default or as an
/// exception for one grossiste or one store.
class ProductPricesScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  final Json product;
  const ProductPricesScreen({
    super.key,
    required this.vm,
    required this.product,
  });
  @override
  State<ProductPricesScreen> createState() => _ProductPricesScreenState();
}

class _ProductPricesScreenState extends State<ProductPricesScreen> {
  late final repository = PricingRepository(widget.vm.repositoryContext);
  List<Json> entries = const [], wholesalers = const [];
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final history = await repository.history(widget.product['id']);
      final list = await WholesaleRepository(widget.vm.repositoryContext)
          .list();
      if (mounted) {
        setState(() {
          entries = history;
          wholesalers = list;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// The newest entry of one level and scope; history is newest first.
  /// A withdrawn exception counts as no exception.
  Json? latest(String level, {String? organizationId, String? storeId}) {
    final entry = entries
        .where(
          (e) =>
              e['level'] == level &&
              e['organizationId'] == organizationId &&
              e['storeId'] == storeId,
        )
        .firstOrNull;
    return entry?['cleared'] == true ? null : entry;
  }

  Future<void> change(
    String level,
    String title, {
    String? organizationId,
    String? storeId,
  }) async {
    final operationId = const Uuid().v4();
    final current = latest(
      level,
      organizationId: organizationId,
      storeId: storeId,
    );
    final saved = await openEditor(
      context,
      title: title,
      description: 'Le nouveau prix s’applique aux prochaines commandes. Les commandes, livraisons et ventes déjà enregistrées gardent leur prix.',
      fields: [
        FieldSpec(
          'price',
          'Prix (TND)',
          initial: current == null
              ? ''
              : Money(integer(current['priceMillimes'])).input,
          numeric: true,
        ),
        const FieldSpec('reason', 'Motif du changement', required: false),
      ],
      submit: (values) async {
        final reason = (values['reason'] ?? '').trim();
        await repository.set({
          'level': level,
          'productId': widget.product['id'],
          'organizationId': ?organizationId,
          'storeId': ?storeId,
          'priceMillimes': Money.parse(values['price']!).millimes.toString(),
          if (reason.length >= 3) 'reason': reason,
        }, operationId: operationId);
      },
    );
    if (saved && mounted) await load();
  }

  Future<void> addStoreException() async {
    final stores = widget.vm.state.stores.where((s) => !s.wholesale).toList();
    final options = {
      for (final s in stores) s.id: '${s.organizationName} · ${s.name}',
    };
    Store? chosen;
    final picked = await openEditor(
      context,
      title: 'Choisir le magasin',
      fields: [FieldSpec('store', 'Magasin', options: options)],
      submit: (values) async {
        chosen = stores.where((s) => s.id == values['store']).firstOrNull;
      },
      submitLabel: 'Continuer',
    );
    if (!picked || chosen == null || !mounted) return;
    await change(
      'store_supply',
      'Prix pour ${chosen!.name}',
      organizationId: chosen!.organizationId,
      storeId: chosen!.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final exceptions = entries
        .where((e) => e['level'] == 'store_supply' && e['storeId'] != null)
        .map((e) => e['storeId'])
        .toSet()
        .where(
          (id) =>
              latest(
                'store_supply',
                organizationId: widget.vm.state.stores
                    .where((s) => s.id == id)
                    .firstOrNull
                    ?.organizationId,
                storeId: id,
              ) !=
              null,
        )
        .toSet();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prix du produit'),
        actions: [
          IconButton(
            tooltip: 'Historique complet',
            icon: const Icon(AppIcons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    PriceHistoryScreen(vm: widget.vm, product: widget.product),
              ),
            ),
          ),
        ],
      ),
      body: Content(
        children: [
          SectionTitle(
            widget.product['name'],
            subtitle: 'Vous voyez tous les niveaux ; chaque rôle ne voit que les siens',
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Notice(error!, retry: load),
          const SectionTitle(
            'Gros · BioBalance → grossistes',
            subtitle: 'Ce que paie un grossiste',
          ),
          CompactRow(
            title: 'Par défaut',
            value: millimesLabel(latest('wholesale')?['priceMillimes']),
            icon: AppIcons.localShippingOutlined,
            onTap: () => change('wholesale', 'Prix de gros par défaut'),
          ),
          for (final w in wholesalers.where((w) => w['activated'] == true))
            CompactRow(
              title: w['name'],
              subtitle: latest('wholesale', organizationId: w['id']) == null
                  ? 'Prix par défaut'
                  : 'Prix particulier',
              value: millimesLabel(
                (latest('wholesale', organizationId: w['id']) ??
                    latest('wholesale'))?['priceMillimes'],
              ),
              icon: AppIcons.localShippingOutlined,
              onTap: () => change(
                'wholesale',
                'Prix de gros · ${w['name']}',
                organizationId: w['id'],
              ),
            ),
          const SizedBox(height: 12),
          const SectionTitle(
            'Magasins · fournisseur → magasin',
            subtitle: 'Ce que paie un responsable, que BioBalance ou un grossiste livre',
          ),
          CompactRow(
            title: 'Par défaut',
            value: millimesLabel(latest('store_supply')?['priceMillimes']),
            icon: AppIcons.storefrontOutlined,
            onTap: () => change('store_supply', 'Prix aux magasins par défaut'),
          ),
          for (final id in exceptions)
            Builder(
              builder: (context) {
                final store = widget.vm.state.stores
                    .where((s) => s.id == id)
                    .firstOrNull;
                final entry = latest(
                  'store_supply',
                  organizationId: store?.organizationId,
                  storeId: id,
                );
                return CompactRow(
                  title: store?.name ?? 'Magasin',
                  subtitle: 'Prix particulier',
                  value: millimesLabel(entry?['priceMillimes']),
                  icon: AppIcons.storefrontOutlined,
                  onTap: store == null
                      ? null
                      : () => change(
                          'store_supply',
                          'Prix pour ${store.name}',
                          organizationId: store.organizationId,
                          storeId: store.id,
                        ),
                );
              },
            ),
          TextButton.icon(
            onPressed: addStoreException,
            icon: const Icon(AppIcons.add),
            label: const Text('Prix particulier pour un magasin'),
          ),
        ],
      ),
    );
  }
}
