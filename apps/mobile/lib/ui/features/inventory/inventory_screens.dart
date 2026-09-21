import 'dart:async';

import 'package:flutter/material.dart';

import '../reporting/history_screen.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/inventory_rules.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../../domain/models/money.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../sales/sale_screen.dart';
import '../media/image_input.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class StockPage extends StatefulWidget {
  final WorkspaceViewModel vm;
  const StockPage({super.key, required this.vm});
  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  String query = '', filter = 'all';
  @override
  Widget build(BuildContext context) {
    final vm = widget.vm, data = vm.state.data;
    final all = data?.products ?? [];
    final products = all.where((p) {
      if (!'${p.name} ${p.reference} ${p.barcode}'.toLowerCase().contains(
        query.toLowerCase(),
      )) {
        return false;
      }
      return StockSummary.forProduct(data!, p.id).matches(filter);
    }).toList();
    return Content(
      children: [
        SectionTitle(
          'Stock du magasin',
          subtitle: 'Les lots, les quantités et les dates au même endroit.',
          action: FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ReceiptScreen(vm: vm)),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Entrée de stock'),
          ),
        ),
        TextField(
          onChanged: (q) => setState(() => query = q),
          decoration: const InputDecoration(
            hintText: 'Produit, référence ou code-barres',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in {
              'all': 'Tous',
              'low': 'Stock faible',
              'discrepancy': 'À vérifier',
              'approaching': 'Péremption ≤ 30 jours',
              'expired': 'Périmés',
            }.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: filter == e.key,
                onSelected: (_) => setState(() => filter = e.key),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (products.isEmpty)
          const EmptyState(
            title: 'Aucun produit à afficher',
            description:
                'Changez les filtres ou ajoutez vos premières références.',
          ),
        ...products.map((p) {
          final summary = StockSummary.forProduct(data!, p.id);
          final quantity = summary.available, low = summary.low;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: low
                        ? const Color(0xFFFFF3DE)
                        : const Color(0xFFEDF6E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    low ? Icons.inventory_2_outlined : Icons.spa_outlined,
                    color: low ? const Color(0xFF815B12) : darkGreen,
                  ),
                ),
                title: Text(p.name),
                subtitle: Text(
                  '${p.reference}\n$quantity unité(s) disponible(s)${low ? ' · À réapprovisionner' : ''}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductDetail(vm: vm, product: p),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class ProductDetail extends StatelessWidget {
  final WorkspaceViewModel vm;
  final Product product;
  const ProductDetail({super.key, required this.vm, required this.product});
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
      final lots = (data.lotsByProduct[product.id] ?? <InventoryLot>[]).toList()
        ..sort((a, b) => a.expiry.compareTo(b.expiry));
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
                  icon: Icons.notifications_outlined,
                ),
                StatusChip(
                  '${config['pointsPerUnit']} points / unité',
                  icon: Icons.stars_outlined,
                ),
              ],
            ),
            if (config['pointsConfigured'] != true) ...[
              const SizedBox(height: 16),
              const Notice(
                'Aucun barème configuré : ce produit attribue actuellement zéro point.',
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => configure(context),
              icon: const Icon(Icons.tune),
              label: const Text('Prix, seuil et points'),
            ),
            const SizedBox(height: 20),
            SectionTitle(
              'Lots et péremptions',
              action: IconButton(
                tooltip: 'Historique du stock',
                icon: const Icon(Icons.history),
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
                title: 'Aucun lot enregistré',
                description: 'Enregistrez votre stock initial ou réceptionnez une livraison.',
              ),
            ...lots.map(
              (lot) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lot ${lot.batch}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('Péremption : ${dateLabel(lot.expiry)}'),
                        Text(
                          '${lot.sellable} unités · ${lot.damaged} non vendables',
                        ),
                        if (lot.expired)
                          const StatusChip(
                            'Périmé · exclu du stock vendable',
                            icon: Icons.event_busy,
                          ),
                        if (lot.sellable < 0)
                          const Notice(
                            'Écart de stock : vérifiez la quantité physique.',
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => adjust(context, lot, false),
                              child: const Text('Ajuster'),
                            ),
                            TextButton(
                              onPressed: () => adjust(context, lot, true),
                              child: const Text('Signaler des dommages'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  Future<void> configure(BuildContext context) async {
    final config = vm.state.data!.config(product.id), store = vm.state.store!;
    if (await openEditor(
      context,
      title: 'Paramétrer le produit',
      fields: [
        FieldSpec(
          'price',
          'Prix par défaut (TND)',
          initial: Money(integer(config['priceMillimes'])).input,
          numeric: true,
        ),
        FieldSpec(
          'threshold',
          'Seuil de réapprovisionnement',
          initial: '${config['threshold']}',
          numeric: true,
        ),
        FieldSpec(
          'points',
          'Points par unité vendue',
          initial: '${config['pointsPerUnit']}',
          numeric: true,
        ),
      ],
      submit: (v) async {
        final points = whole(v['points']!, allowZero: true);
        if (points == 0 &&
            !await confirmAction(
              context,
              'Confirmer : zéro point',
              'Les ventes de ${product.name} ne rapporteront aucun point dans ${store.name}.',
              label: 'Confirmer zéro point',
            )) {
          throw const FormatException(
            'Configuration non enregistrée. Confirmez le choix de zéro point.',
          );
        }
        vm.requireAccess(store, 'manage');
        await vm.catalog.configure(store, product.id, {
          'priceMillimes': Money.parse(v['price']!).millimes.toString(),
          'threshold': whole(v['threshold']!, allowZero: true),
          'pointsPerUnit': points,
          'zeroPointsConfirmed': points == 0,
          if (config['version'] != null) 'expectedVersion': config['version'],
        });
      },
    )) {
      await vm.synchronize();
    }
  }

  Future<void> adjust(
    BuildContext context,
    InventoryLot lot,
    bool damage,
  ) async {
    await openEditor(
      context,
      title: damage ? 'Enregistrer des dommages' : 'Réconcilier le stock',
      description:
          'Cette modification sera conservée avec votre identité et son motif.',
      fields: [
        FieldSpec(
          'quantity',
          damage ? 'Unités endommagées' : 'Quantité réellement comptée',
          numeric: true,
        ),
        const FieldSpec('reason', 'Motif'),
      ],
      submit: (v) => vm.queue({
        'type': damage ? 'stock.damage' : 'stock.adjust',
        'lotId': lot.id,
        'quantity': whole(v['quantity']!, allowZero: !damage),
        'reason': v['reason'],
      }, expectedVersion: lot.version),
    );
  }
}

class ReceiptScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  final Json? delivery;
  const ReceiptScreen({super.key, required this.vm, this.delivery});
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  List<Json> lines = [];
  final note = TextEditingController();
  String? error;
  bool busy = false, loading = true, missing = false, completed = false;
  Future<void> _tail = Future.value();
  late final VoidCallback unregister;

  late final Store store = widget.vm.state.store!;
  String get key => 'receipt:${widget.delivery?['id'] ?? 'stock'}';
  @override
  void initState() {
    super.initState();
    unregister = widget.vm.registerDraft(persist);
    note.addListener(changed);
    unawaited(restore());
  }

  Future<void> restore() async {
    try {
      final draft = await widget.vm.repository.draft(
        widget.vm.user.id,
        store.id,
        key,
      );
      if (mounted) {
        setState(() {
          lines = objects(draft?['lines']);
          note.text = draft?['note'] ?? '';
          missing = draft?['missing'] == true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> persist() {
    if (completed || loading) return Future.value();
    final values = <String, dynamic>{
      'lines': List<Json>.from(lines),
      'note': note.text,
      'missing': missing,
    };
    return _tail = _tail
        .catchError((Object _) {})
        .then(
          (_) => widget.vm.repository.saveDraft(
            widget.vm.user.id,
            store.id,
            key,
            values,
          ),
        );
  }

  void changed() => unawaited(
    persist().catchError((Object e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    }),
  );
  @override
  void dispose() {
    unregister();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.delivery == null
            ? 'Entrée de stock'
            : 'Réceptionner la livraison',
      ),
    ),
    body: Content(
      maxWidth: 760,
      children: [
        StatusChip(store.name, icon: Icons.storefront_outlined),
        const SizedBox(height: 20),
        if (error != null) Notice(error!, error: true),
        if (loading) const LinearProgressIndicator(),
        if (widget.delivery != null) ...[
          const Notice(
            'Saisissez les quantités réellement reçues. Les écarts seront conservés et cette livraison ne pourra être confirmée qu’une seule fois.',
          ),
          const SizedBox(height: 16),
          ...objects(widget.delivery!['lines']).map(
            (l) => Text(
              '${widget.vm.productName(l['productId'])} · ${l['quantity']} unités attendues',
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: missing,
            contentPadding: EdgeInsets.zero,
            title: const Text('Aucune unité reçue'),
            subtitle: const Text(
              'Signaler une livraison entièrement manquante.',
            ),
            onChanged: busy || loading || lines.isNotEmpty
                ? null
                : (value) {
                    setState(() => missing = value ?? false);
                    changed();
                  },
          ),
          TextField(
            controller: note,
            enabled: !busy && !loading,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: missing
                  ? 'Explication obligatoire'
                  : 'Écart ou remarque (facultatif)',
            ),
          ),
          const SizedBox(height: 20),
        ],
        FilledButton.icon(
          onPressed: busy || loading || missing ? null : add,
          icon: const Icon(Icons.add),
          label: const Text('Ajouter un produit et un lot'),
        ),
        const SizedBox(height: 20),
        ...lines.asMap().entries.map(
          (e) => Card(
            child: ListTile(
              title: Text(widget.vm.productName(e.value['productId'])),
              subtitle: Text(
                '${e.value['quantity']} unités · Lot ${e.value['batch']}\nPéremption : ${TunisDates.dateOnlyLabel(e.value['expiry'])}',
              ),
              trailing: IconButton(
                onPressed: busy || loading
                    ? null
                    : () {
                        setState(() => lines.removeAt(e.key));
                        changed();
                      },
                icon: const Icon(Icons.close),
                tooltip: 'Retirer',
              ),
            ),
          ),
        ),
        if (lines.isEmpty && !missing)
          const EmptyState(
            title: 'Ajoutez les unités reçues',
            description: 'Un produit peut être réparti sur plusieurs lots et plusieurs dates de péremption.',
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy || loading || (lines.isEmpty && !missing)
              ? null
              : save,
          child: Text(busy ? 'Enregistrement…' : 'Confirmer la réception'),
        ),
      ],
    ),
  );
  Future<void> add() async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductPicker(
        products: widget.vm.state.data!.products
            .where(
              (p) =>
                  widget.delivery == null ||
                  objects(widget.delivery!['lines'])
                      .any((l) => l['productId'] == p.id),
            )
            .toList(),
      ),
    );
    if (product == null || !mounted) return;
    await openEditor(
      context,
      title: product.name,
      fields: const [
        FieldSpec('quantity', 'Unités reçues', initial: '1', numeric: true),
        FieldSpec('batch', 'Numéro de lot'),
        FieldSpec('expiry', 'Péremption : JJ/MM/AAAA ou MM/AAAA'),
      ],
      submit: (v) async {
        final expiry = TunisDates.expiry(v['expiry']!);
        setState(
          () => lines.add({
            'productId': product.id,
            'quantity': whole(v['quantity']!),
            'batch': v['batch'],
            'expiry': expiry,
          }),
        );
        await persist();
      },
    );
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final vm = widget.vm;
      vm.requireAccess(store, widget.delivery == null ? 'manage' : 'receive');
      await persist();
      if (lines.isEmpty) {
        if (widget.delivery == null || !missing || note.text.trim().isEmpty) {
          throw const FormatException(
            'Expliquez pourquoi aucune unité n’a été reçue.',
          );
        }
        if (!mounted ||
            !await confirmAction(
              context,
              'Confirmer : aucune unité reçue',
              'Cette réception sera conservée avec votre explication. Le stock ne sera pas augmenté. BioBalance pourra préparer une nouvelle livraison.',
              label: 'Confirmer zéro unité',
            )) {
          return;
        }
      }
      await vm.queue(
        widget.delivery == null
            ? {'type': 'stock.receive', 'reason': 'receipt', 'lines': lines}
            : {
                'type': 'delivery.receive',
                'deliveryId': widget.delivery!['id'],
                'lines': lines,
                'note': note.text.trim(),
              },
        expectedVersion: widget.delivery == null
            ? null
            : integer(widget.delivery!['version']),
        targetStore: store,
        draftKey: key,
      );
      completed = true;
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Réception enregistrée sur ce téléphone.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
