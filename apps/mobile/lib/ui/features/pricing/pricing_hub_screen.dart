import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/pricing_repository.dart';
import '../../../data/repositories/wholesale_repository.dart';
import '../../../domain/models/models.dart';
import '../../../domain/models/money.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../catalog/catalog_view_model.dart';
import '../workspace/workspace_view_model.dart';
import 'pricing_screens.dart';

/// One place for BioBalance to set what grossistes and stores pay, and to see
/// what each store sells at: pick who, then see and change every product.
class PricingHubScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  const PricingHubScreen({super.key, required this.vm});
  @override
  State<PricingHubScreen> createState() => _PricingHubScreenState();
}

class _PricingHubScreenState extends State<PricingHubScreen> {
  List<Json> wholesalers = const [];
  String? error;
  bool loading = true, wholesale = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final list = await WholesaleRepository(widget.vm.repositoryContext)
          .list();
      if (mounted) {
        setState(() {
          wholesalers = list.where((w) => w['activated'] == true).toList();
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void open(Store store, {required bool supply}) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          PartyPricesScreen(vm: widget.vm, store: store, wholesale: supply),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final stores = widget.vm.state.stores.where((s) => !s.wholesale).toList()
      ..sort(
        (a, b) => '${a.organizationName}${a.name}'.compareTo(
          '${b.organizationName}${b.name}',
        ),
      );
    final depots = widget.vm.state.stores.where((s) => s.wholesale).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Prix')),
      body: Content(
        onRefresh: load,
        children: [
          const SectionTitle(
            'Qui paie quoi',
            subtitle: 'Choisissez un grossiste ou un magasin pour voir et changer ses prix.',
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Grossistes'),
                icon: Icon(AppIcons.localShippingOutlined),
              ),
              ButtonSegment(
                value: false,
                label: Text('Magasins'),
                icon: Icon(AppIcons.storefrontOutlined),
              ),
            ],
            selected: {wholesale},
            onSelectionChanged: (v) => setState(() => wholesale = v.first),
          ),
          const SizedBox(height: 8),
          Text(
            wholesale
                ? 'Prix de gros : ce que paie chaque grossiste à BioBalance.'
                : 'Prix d’approvisionnement : ce que paie chaque magasin. Le prix de vente au public, fixé par le responsable, est affiché pour information.',
            style: const TextStyle(fontSize: 14, color: muted),
          ),
          const SizedBox(height: 12),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Notice(error!, retry: load),
          if (wholesale) ...[
            if (!loading && wholesalers.isEmpty)
              const EmptyState(
                title: 'Aucun grossiste actif',
                description: 'Les prix de gros apparaissent dès qu’un grossiste a activé son compte.',
                icon: AppIcons.localShippingOutlined,
              ),
            for (final w in wholesalers)
              Builder(
                builder: (context) {
                  final depot = depots
                      .where((d) => d.organizationId == w['id'])
                      .firstOrNull;
                  return CompactRow(
                    title: w['name'],
                    subtitle: w['city'],
                    icon: AppIcons.localShippingOutlined,
                    onTap: depot == null
                        ? null
                        : () => open(depot, supply: false),
                  );
                },
              ),
          ] else ...[
            if (stores.isEmpty)
              const EmptyState(
                title: 'Aucun magasin',
                description:
                    'Les magasins créés par les responsables apparaissent ici.',
                icon: AppIcons.storefrontOutlined,
              ),
            for (final s in stores)
              CompactRow(
                title: s.name,
                subtitle: s.organizationName,
                icon: AppIcons.storefrontOutlined,
                onTap: () => open(s, supply: true),
              ),
          ],
        ],
      ),
    );
  }
}

/// Every product with the price this grossiste or store pays now (and, for a
/// store, its public price). Tapping a product changes the price.
class PartyPricesScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  final Store store;

  /// True for a store (supply price), false for a grossiste (wholesale price).
  final bool wholesale;
  const PartyPricesScreen({
    super.key,
    required this.vm,
    required this.store,
    required this.wholesale,
  });
  @override
  State<PartyPricesScreen> createState() => _PartyPricesScreenState();
}

class _PartyPricesScreenState extends State<PartyPricesScreen> {
  late final repository = PricingRepository(widget.vm.repositoryContext);
  late final catalog = CatalogViewModel(widget.vm)..load();
  final search = TextEditingController();
  Map<String, Json> prices = const {};
  String? error;
  bool loading = true;
  String query = '';

  bool get supply => widget.wholesale;
  String get key => supply ? 'supplyMillimes' : 'wholesaleMillimes';

  @override
  void initState() {
    super.initState();
    catalog.addListener(_rebuild);
    load();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    catalog.removeListener(_rebuild);
    catalog.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result = await repository.current(widget.store);
      if (mounted) {
        setState(() {
          prices = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> change(Json product) async {
    final operationId = const Uuid().v4();
    final level = supply ? 'store_supply' : 'wholesale';
    final current = prices[product['id']]?[key];
    final name = widget.store.wholesale
        ? widget.store.organizationName
        : widget.store.name;
    final saved = await openEditor(
      context,
      title: product['name'],
      description: 'Le nouveau prix s’applique aux prochaines commandes. Les commandes, livraisons et ventes déjà enregistrées gardent leur prix.',
      fields: [
        FieldSpec(
          'price',
          'Prix (TND)',
          initial: current == null ? '' : Money(integer(current)).input,
          numeric: true,
        ),
        FieldSpec(
          'scope',
          'Pour qui ?',
          options: {
            'one': 'Seulement $name',
            'all': supply
                ? 'Tous les magasins (prix par défaut)'
                : 'Tous les grossistes (prix par défaut)',
          },
          choice: true,
          initial: 'one',
        ),
        const FieldSpec('reason', 'Motif du changement', required: false),
      ],
      submit: (values) async {
        final reason = (values['reason'] ?? '').trim();
        final everyone = values['scope'] == 'all';
        await repository.set({
          'level': level,
          'productId': product['id'],
          if (!everyone && supply) ...{
            'organizationId': widget.store.organizationId,
            'storeId': widget.store.id,
          },
          if (!everyone && !supply)
            'organizationId': widget.store.organizationId,
          'priceMillimes': Money.parse(values['price']!).millimes.toString(),
          if (reason.length >= 3) 'reason': reason,
        }, operationId: operationId);
      },
    );
    if (saved && mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final products = catalog.products
        .where(
          (p) =>
              p['active'] != false &&
              (q.isEmpty ||
                  '${p['name']} ${p['reference'] ?? ''}'.toLowerCase().contains(
                    q,
                  )),
        )
        .toList();
    final undefined = catalog.products
        .where((p) => p['active'] != false && prices[p['id']]?[key] == null)
        .length;
    final title = widget.store.wholesale
        ? widget.store.organizationName
        : widget.store.name;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Content.builder(
        onRefresh: () async {
          await Future.wait([load(), catalog.load()]);
        },
        itemCount: products.length,
        itemBuilder: (context, i) {
          final p = products[i];
          final row = prices[p['id']];
          final retail = row?['retailMillimes'];
          return CompactRow(
            key: ValueKey(p['id']),
            title: p['name'],
            subtitle: [
              if (row?[key] == null) 'Prix à définir',
              if (supply && retail != null)
                'Vente au public : ${millimesLabel(retail)}',
            ].join(' · '),
            value: row?[key] == null ? null : millimesLabel(row![key]),
            icon: AppIcons.tuneOutlined,
            onTap: () => change(p),
          );
        },
        children: [
          SectionTitle(
            supply ? 'Prix d’approvisionnement' : 'Prix de gros',
            subtitle: widget.store.wholesale
                ? title
                : '${widget.store.organizationName} · $title',
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Notice(error!, retry: load),
          if (!loading && undefined > 0)
            Notice(
              '$undefined produit(s) sans prix : touchez-les pour le définir.',
            ),
          TextField(
            controller: search,
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(
              hintText: 'Rechercher un produit',
              prefixIcon: Icon(AppIcons.search),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
