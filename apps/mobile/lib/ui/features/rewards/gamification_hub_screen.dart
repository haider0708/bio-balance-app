import 'package:flutter/material.dart';

import '../../../data/repositories/gamification_repository.dart';
import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../catalog/catalog_view_model.dart';
import '../workspace/workspace_view_model.dart';

String _audienceLabel(String audience) =>
    audience == 'wholesale' ? 'tous les grossistes' : 'tous les magasins';

/// BioBalance's points and rewards: a default for every store or every
/// grossiste, and exceptions per place.
class GamificationHubScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  const GamificationHubScreen({super.key, required this.vm});
  @override
  State<GamificationHubScreen> createState() => _GamificationHubScreenState();
}

class _GamificationHubScreenState extends State<GamificationHubScreen> {
  bool wholesale = false;
  String get audience => wholesale ? 'wholesale' : 'retail';

  void open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final places =
        widget.vm.state.stores.where((s) => s.wholesale == wholesale).toList()
          ..sort(
            (a, b) => '${a.organizationName}${a.name}'.compareTo(
              '${b.organizationName}${b.name}',
            ),
          );
    return Scaffold(
      appBar: AppBar(title: const Text('Points et récompenses')),
      body: Content(
        children: [
          const SectionTitle(
            'Par défaut, puis par exception',
            subtitle: 'Le barème et les récompenses par défaut s’appliquent à chacun ; un magasin ou un grossiste peut avoir son propre barème.',
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Magasins'),
                icon: Icon(AppIcons.storefrontOutlined),
              ),
              ButtonSegment(
                value: true,
                label: Text('Grossistes'),
                icon: Icon(AppIcons.localShippingOutlined),
              ),
            ],
            selected: {wholesale},
            onSelectionChanged: (v) => setState(() => wholesale = v.first),
          ),
          const SizedBox(height: 12),
          CompactRow(
            key: ValueKey('points.default.$audience'),
            title: 'Points par défaut',
            subtitle: wholesale
                ? 'Points par unité livrée, pour ${_audienceLabel(audience)}'
                : 'Points par unité vendue, pour ${_audienceLabel(audience)}',
            icon: AppIcons.tuneOutlined,
            tone: AppTone.info,
            onTap: () =>
                open(DefaultPointsScreen(vm: widget.vm, audience: audience)),
          ),
          CompactRow(
            key: ValueKey('rewards.default.$audience'),
            title: 'Récompenses par défaut',
            subtitle: 'Proposées à ${_audienceLabel(audience)}',
            icon: AppIcons.redeemOutlined,
            tone: AppTone.info,
            onTap: () =>
                open(DefaultRewardsScreen(vm: widget.vm, audience: audience)),
          ),
          const SizedBox(height: 12),
          Text(
            wholesale
                ? 'Barème particulier par grossiste'
                : 'Barème particulier par magasin',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (places.isEmpty)
            EmptyState(
              title: wholesale ? 'Aucun grossiste' : 'Aucun magasin',
              description: 'Ils apparaîtront ici dès leur création.',
              icon: wholesale
                  ? AppIcons.localShippingOutlined
                  : AppIcons.storefrontOutlined,
            ),
          for (final place in places)
            CompactRow(
              title: wholesale ? place.organizationName : place.name,
              subtitle: wholesale ? place.city : place.organizationName,
              icon: wholesale
                  ? AppIcons.localShippingOutlined
                  : AppIcons.storefrontOutlined,
              onTap: () => open(StorePointsScreen(vm: widget.vm, store: place)),
            ),
        ],
      ),
    );
  }
}

/// Default points per product for every store or every grossiste.
class DefaultPointsScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  final String audience;
  const DefaultPointsScreen({
    super.key,
    required this.vm,
    required this.audience,
  });
  @override
  State<DefaultPointsScreen> createState() => _DefaultPointsScreenState();
}

class _DefaultPointsScreenState extends State<DefaultPointsScreen> {
  late final repository = GamificationRepository(widget.vm.repositoryContext);
  late final catalog = CatalogViewModel(widget.vm)..load();
  Map<String, int> points = const {};
  String? error;
  bool loading = true;
  String query = '';

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
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result = await repository.defaults(widget.audience);
      if (mounted) {
        setState(() {
          points = result.points;
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
    final saved = await openEditor(
      context,
      title: product['name'],
      description:
          'S’applique à ${_audienceLabel(widget.audience)}, sauf à ceux qui ont leur propre barème. Les ventes passées gardent leurs points.',
      fields: [
        FieldSpec(
          'points',
          widget.audience == 'wholesale'
              ? 'Points par unité livrée'
              : 'Points par unité vendue',
          initial: '${points[product['id']] ?? ''}',
          numeric: true,
        ),
      ],
      submit: (values) async {
        final value = int.tryParse(values['points']!.trim());
        if (value == null || value < 0) {
          throw const FormatException('Saisissez un nombre entier de points.');
        }
        await repository.setDefault(widget.audience, product['id'], value);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Points par défaut')),
      body: Content.builder(
        onRefresh: () async {
          await Future.wait([load(), catalog.load()]);
        },
        itemCount: products.length,
        itemBuilder: (context, i) {
          final p = products[i];
          final value = points[p['id']];
          return CompactRow(
            key: ValueKey(p['id']),
            title: p['name'],
            subtitle: value == null ? 'Aucun barème' : null,
            value: value == null ? null : '$value pts',
            icon: AppIcons.redeemOutlined,
            onTap: () => change(p),
          );
        },
        children: [
          SectionTitle(
            'Pour ${_audienceLabel(widget.audience)}',
            subtitle: widget.audience == 'wholesale'
                ? 'Points gagnés par unité livrée et confirmée par le magasin.'
                : 'Points gagnés par le vendeur pour chaque unité vendue.',
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Notice(error!, retry: load),
          TextField(
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

/// Rewards offered to every store or every grossiste.
class DefaultRewardsScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  final String audience;
  const DefaultRewardsScreen({
    super.key,
    required this.vm,
    required this.audience,
  });
  @override
  State<DefaultRewardsScreen> createState() => _DefaultRewardsScreenState();
}

class _DefaultRewardsScreenState extends State<DefaultRewardsScreen> {
  late final repository = GamificationRepository(widget.vm.repositoryContext);
  List<Json> rewards = const [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await repository.defaults(widget.audience);
      if (mounted) {
        setState(() {
          rewards = result.rewards;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit([Json? reward]) async {
    final saved = await openEditor(
      context,
      title: reward == null ? 'Nouvelle récompense' : 'Modifier la récompense',
      description:
          'Proposée à ${_audienceLabel(widget.audience)}. Une modification s’applique partout.',
      fields: [
        FieldSpec(
          'title',
          'Nom de la récompense',
          initial: reward?['title'] ?? '',
        ),
        FieldSpec(
          'description',
          'Description',
          initial: reward?['description'] ?? '',
          required: false,
        ),
        FieldSpec(
          'cost',
          'Coût en points',
          initial: '${reward?['cost'] ?? ''}',
          numeric: true,
        ),
        FieldSpec(
          'quantity',
          'Quantité remise',
          initial: '${reward?['quantity'] ?? 1}',
          numeric: true,
        ),
        FieldSpec(
          'active',
          'Disponible',
          choice: true,
          initial: reward?['active'] == false ? 'no' : 'yes',
          options: const {'yes': 'Oui', 'no': 'Non, masquée'},
        ),
      ],
      submit: (values) async {
        final cost = int.tryParse(values['cost']!.trim());
        final quantity = int.tryParse(values['quantity']!.trim());
        if (cost == null || cost < 1 || quantity == null || quantity < 1) {
          throw const FormatException(
            'Le coût et la quantité sont des nombres entiers positifs.',
          );
        }
        await repository.saveReward({
          if (reward != null) ...{
            'id': reward['id'],
            'expectedVersion': integer(reward['version']),
          },
          'audience': widget.audience,
          'title': values['title']!.trim(),
          'description': (values['description'] ?? '').trim(),
          'cost': cost,
          'quantity': quantity,
          'productId': reward?['productId'],
          'active': values['active'] != 'no',
        });
      },
    );
    if (saved && mounted) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Récompenses par défaut')),
    body: Content(
      onRefresh: load,
      children: [
        SectionTitle(
          'Pour ${_audienceLabel(widget.audience)}',
          subtitle: 'Chacun les voit et peut les demander avec ses points.',
          action: FilledButton.tonalIcon(
            key: const ValueKey('rewards.default.add'),
            onPressed: () => edit(),
            icon: const Icon(AppIcons.add),
            label: const Text('Ajouter'),
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Notice(error!, retry: load),
        if (!loading && rewards.isEmpty)
          const EmptyState(
            title: 'Aucune récompense par défaut',
            description: 'Ajoutez-en une : elle sera proposée partout.',
            icon: AppIcons.redeemOutlined,
          ),
        for (final r in rewards)
          CompactRow(
            title: r['title'],
            subtitle: [
              if ((r['description'] as String?)?.isNotEmpty == true)
                r['description'],
              if (r['active'] == false) 'Masquée',
            ].join(' · '),
            value: '${r['cost']} pts',
            icon: AppIcons.redeemOutlined,
            onTap: () => edit(r),
          ),
      ],
    ),
  );
}

/// One place's rates: the default, or its own rate.
class StorePointsScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  final Store store;
  const StorePointsScreen({super.key, required this.vm, required this.store});
  @override
  State<StorePointsScreen> createState() => _StorePointsScreenState();
}

class _StorePointsScreenState extends State<StorePointsScreen> {
  late final repository = GamificationRepository(widget.vm.repositoryContext);
  late final catalog = CatalogViewModel(widget.vm)..load();
  Map<String, Json> rows = const {};
  String? error;
  bool loading = true;
  String query = '';
  String get name => widget.store.wholesale
      ? widget.store.organizationName
      : widget.store.name;

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
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result = await repository.storePoints(widget.store);
      if (mounted) {
        setState(() {
          rows = result;
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
    final row = rows[product['id']];
    final exception = row?['exception'] == true;
    final fallback = row?['defaultPointsPerUnit'];
    final saved = await openEditor(
      context,
      title: product['name'],
      description: fallback == null
          ? 'Aucun barème par défaut pour ce produit.'
          : 'Barème par défaut : $fallback pts.',
      fields: [
        FieldSpec(
          'points',
          'Points pour $name',
          initial: '${row?['pointsPerUnit'] ?? ''}',
          numeric: true,
          required: false,
        ),
        FieldSpec(
          'scope',
          'Pour qui ?',
          choice: true,
          initial: 'one',
          options: {
            'one': 'Seulement $name (barème particulier)',
            if (exception && fallback != null)
              'reset': 'Revenir au barème par défaut',
          },
        ),
      ],
      submit: (values) async {
        if (values['scope'] == 'reset') {
          await repository.setStorePoints(widget.store, product['id'], null);
          return;
        }
        final value = int.tryParse((values['points'] ?? '').trim());
        if (value == null || value < 0) {
          throw const FormatException('Saisissez un nombre entier de points.');
        }
        await repository.setStorePoints(widget.store, product['id'], value);
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
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Content.builder(
        onRefresh: () async {
          await Future.wait([load(), catalog.load()]);
        },
        itemCount: products.length,
        itemBuilder: (context, i) {
          final p = products[i];
          final row = rows[p['id']];
          final value = row?['pointsPerUnit'];
          return CompactRow(
            key: ValueKey(p['id']),
            title: p['name'],
            subtitle: value == null
                ? 'Aucun barème'
                : row?['exception'] == true
                ? 'Barème particulier · défaut ${row?['defaultPointsPerUnit'] ?? '—'} pts'
                : 'Barème par défaut',
            value: value == null ? null : '$value pts',
            icon: AppIcons.redeemOutlined,
            onTap: () => change(p),
          );
        },
        children: [
          SectionTitle(
            'Points · $name',
            subtitle: 'Touchez un produit pour lui donner un barème particulier, ou revenir au défaut.',
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Notice(error!, retry: load),
          TextField(
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
