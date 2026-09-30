import '../catalog/product_information.dart';
import '../../core/navigation.dart';
import 'stock_view_model.dart';
import '../../../domain/models/inventory_rules.dart';
import '../../../domain/models/receipt_plan.dart';

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:flutter/material.dart';

import '../reporting/history_screen.dart';

import '../../../domain/models/models.dart';
import '../../../data/repositories/pricing_repository.dart';
import '../../../domain/models/delivery_ticket.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../../domain/models/money.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../sales/sale_screen.dart';
import '../media/image_input.dart';
import '../authentication/session_view_model.dart';
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
        itemCount: products.length,
        itemBuilder: (context, index) => productCard(products[index]),
        children: [
          SectionTitle(
            'Stock du magasin',
            subtitle: 'Les lots, les quantités et les dates au même endroit.',
            action: FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ReceiptScreen(vm: vm)),
              ),
              icon: const Icon(AppIcons.add),
              label: const Text('Entrée de stock'),
            ),
          ),
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
          FilterBar<String>(
            options: const {
              'all': 'Tous',
              'low': 'Stock faible',
              'discrepancy': 'À vérifier',
              'approaching': 'Péremption ≤ 30 jours',
              'expired': 'Périmés',
            },
            selected: stock.filter,
            itemKey: (value) => ValueKey('stock.$value'),
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
      title: p.name,
      subtitle: [
        p.reference,
        if (summary.low) 'À réapprovisionner',
        if (summary.discrepancy) 'Stock à vérifier',
        if (summary.expired) 'Lots périmés',
      ].join(' · '),
      value: '${summary.available} u.',
      leading: ProductPhoto(vm: widget.vm, productId: p.id),
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
                StatusChip(
                  '${config['pointsPerUnit']} points / unité',
                  icon: AppIcons.starsOutlined,
                ),
              ],
            ),
            if (config['pointsConfigured'] != true) ...[
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
                description: 'Les lots épuisés restent dans l’historique. Réceptionnez une livraison ou enregistrez une entrée de stock.',
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
                      onPressed: () => adjust(context, lot, false),
                      child: const Text('Ajuster'),
                    ),
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

  Future<void> adjust(
    BuildContext context,
    InventoryLot lot,
    bool damage,
  ) async {
    final store = vm.state.store!;
    await openEditor(
      context,
      draftKey: 'stock:${damage ? 'damage' : 'adjust'}:${lot.id}',
      title: damage ? 'Enregistrer des dommages' : 'Réconcilier le stock',
      description:
          '${vm.productName(lot.productId)} · Lot ${lot.batch}. Cette modification sera conservée avec votre identité et son motif.',
      fields: [
        FieldSpec(
          'quantity',
          damage ? 'Unités endommagées' : 'Quantité réellement comptée',
          numeric: true,
        ),
        const FieldSpec('reason', 'Motif'),
      ],
      submitWithDraft: (v, draftKey) => vm.queue(
        {
          'type': damage ? 'stock.damage' : 'stock.adjust',
          'lotId': lot.id,
          'quantity': whole(v['quantity']!, allowZero: !damage),
          'reason': v['reason'],
        },
        expectedVersion: lot.version,
        targetStore: store,
        draftKey: draftKey,
      ),
    );
  }
}

class ReceiptScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  final Json? delivery;
  // The code already read from the parcel's QR, when the scan came first.
  final String? scannedCode;
  const ReceiptScreen({
    super.key,
    required this.vm,
    this.delivery,
    this.scannedCode,
  });
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  List<Json> lines = [];
  final note = TextEditingController();
  // Proof of the physical parcel: the scanned QR code, or why it was not scanned.
  final manualReason = TextEditingController();
  String? ticketCode, error;
  bool manualEntry = false;
  bool busy = false,
      loading = true,
      missing = false,
      completed = false,
      restored = false,
      committing = false;
  Future<void> _tail = Future.value();
  late final VoidCallback unregister;

  late final Store store = widget.vm.state.store!;
  ReceiptPlan get plan =>
      ReceiptPlan(objects(widget.delivery?['lines']), lines);
  String get key => 'receipt:${widget.delivery?['id'] ?? 'stock'}';
  @override
  void initState() {
    super.initState();
    unregister = widget.vm.registerDraft(persist);
    note.addListener(changed);
    manualReason.addListener(changed);
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
          ticketCode = draft?['ticketCode'];
          manualEntry = draft?['manual'] == true;
          manualReason.text = draft?['manualReason'] ?? '';
          restored = true;
          if (ticketCode == null && widget.scannedCode != null) {
            ticketCode = widget.scannedCode;
            manualEntry = false;
            if (lines.isEmpty) prefill();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> persist() {
    if (completed || !restored) return Future.value();
    if (committing) return _tail;
    final values = <String, dynamic>{
      'lines': List<Json>.from(lines),
      'note': note.text,
      'missing': missing,
      'ticketCode': ticketCode,
      'manual': manualEntry,
      'manualReason': manualReason.text,
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
    manualReason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: widget.delivery == null
        ? 'Entrée de stock'
        : 'Réceptionner la livraison',
    maxWidth: 760,
    action: FilledButton(
      onPressed: busy || !restored || (lines.isEmpty && !missing) ? null : save,
      child: Text(
        busy
            ? 'Enregistrement…'
            : missing
            ? 'Signaler non reçue'
            : 'Confirmer la réception',
      ),
    ),
    children: [
      StatusChip(store.name, icon: AppIcons.storefrontOutlined),
      const SizedBox(height: 20),
      if (error != null) Notice(error!, error: true),
      if (loading) const LinearProgressIndicator(),
      if (!loading && !restored)
        TextButton(
          onPressed: () {
            setState(() {
              loading = true;
              error = null;
            });
            unawaited(restore());
          },
          child: const Text('Recharger le brouillon'),
        ),
      if (widget.delivery != null) ...[
        ticketPanel(),
        const SizedBox(height: 16),
        const Text(
          'Pour chaque produit : quantité reçue, numéro de lot et péremption.',
        ),
        const SizedBox(height: 16),
        for (final expected in objects(widget.delivery!['lines']))
          CompactRow(
            title: widget.vm.productName(expected['productId']),
            leading: ProductPhoto(
              vm: widget.vm,
              productId: expected['productId'],
            ),
            subtitle:
                '${expected['quantity']} attendues · ${plan.enteredUnits(expected['productId'])} saisies${objects(expected['allocations']).isEmpty ? '' : '\nLots annoncés : ${objects(expected['allocations']).map((a) => '${a['batch']} (exp. ${TunisDates.dateOnlyLabel(a['expiry'])}) × ${a['quantity']}').join(', ')}'}',
            footer: TextButton.icon(
              onPressed: busy || !restored || missing
                  ? null
                  : () => addProduct(expected['productId']),
              icon: const Icon(AppIcons.add, size: 18),
              label: Text(
                plan.enteredUnits(expected['productId']) == 0
                    ? 'Saisir le lot reçu'
                    : 'Ajouter un autre lot',
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (lines.isEmpty)
          CheckboxListTile(
            value: missing,
            contentPadding: EdgeInsets.zero,
            title: const Text('Aucune unité reçue'),
            subtitle: const Text(
              'Signaler une livraison entièrement manquante.',
            ),
            onChanged: busy || !restored || lines.isNotEmpty
                ? null
                : (value) {
                    setState(() => missing = value ?? false);
                    changed();
                  },
          ),
        TextField(
          controller: note,
          enabled: !busy && restored,
          maxLength: 500,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: missing
                ? 'Explication obligatoire'
                : plan.requiresExplanation
                ? 'Explication de l’écart (obligatoire)'
                : 'Remarque (facultatif)',
          ),
        ),
        const SizedBox(height: 20),
      ],
      if (widget.delivery == null)
        OutlinedButton.icon(
          onPressed: busy || !restored ? null : add,
          icon: const Icon(AppIcons.add),
          label: const Text('Ajouter un produit et un lot'),
        ),
      if (lines.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          'Lots saisis · ${plan.sellable} vendables${plan.damaged > 0 ? ' · ${plan.damaged} abîmées' : ''}${plan.refused > 0 ? ' · ${plan.refused} refusées' : ''}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
      for (final entry in lines.asMap().entries)
        CompactRow(
          title: widget.vm.productName(entry.value['productId']),
          subtitle:
              '${entry.value['quantity']} unités · ${receiptCondition(entry.value)}\nLot ${entry.value['batch']} · ${TunisDates.dateOnlyLabel(entry.value['expiry'])}',
          onTap: busy || !restored
              ? null
              : () => editLot(entry.value['productId'], index: entry.key),
          trailing: IconButton(
            onPressed: busy || !restored
                ? null
                : () {
                    setState(() => lines.removeAt(entry.key));
                    changed();
                  },
            icon: const Icon(AppIcons.close),
            tooltip: 'Retirer ce lot',
          ),
        ),
      if (lines.isEmpty && !missing)
        const EmptyState(
          title: 'Ajoutez les unités reçues',
          description: 'Un produit peut être réparti sur plusieurs lots et plusieurs dates de péremption.',
        ),
      const SizedBox(height: 24),
    ],
  );
  Widget ticketPanel() {
    final number = widget.delivery?['ticketNumber'];
    if (ticketCode != null) {
      return CompactRow(
        title: 'Bon ${number ?? ''} vérifié',
        subtitle: 'Le QR du colis a été scanné. Comptez ce que vous recevez.',
        icon: AppIcons.checkCircleOutline,
        tone: AppTone.success,
      );
    }
    if (manualEntry) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: manualReason,
            enabled: !busy && restored,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Pourquoi le QR ne peut pas être scanné (obligatoire)',
            ),
          ),
          const Text(
            'Cette réception sera signalée à BioBalance comme faite sans scan.',
            style: TextStyle(fontSize: 14, color: muted),
          ),
          TextButton.icon(
            onPressed: busy
                ? null
                : () {
                    setState(() => manualEntry = false);
                    changed();
                  },
            icon: const Icon(AppIcons.qrCode, size: 18),
            label: const Text('Scanner plutôt le QR'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: busy || !restored ? null : scan,
          icon: const Icon(AppIcons.qrCode),
          label: Text(
            number == null
                ? 'Scanner le QR du colis'
                : 'Scanner le QR du bon $number',
          ),
        ),
        TextButton(
          onPressed: busy || !restored
              ? null
              : () {
                  setState(() => manualEntry = true);
                  changed();
                },
          child: const Text('Je ne peux pas scanner'),
        ),
      ],
    );
  }

  /// Announced lots become the starting point; the receiver confirms or corrects.
  void prefill() {
    for (final expected in objects(widget.delivery?['lines'])) {
      for (final a in objects(expected['allocations'])) {
        lines.add({
          'productId': expected['productId'],
          'quantity': integer(a['quantity']),
          'batch': a['batch'],
          'expiry': a['expiry'],
          'condition': 'sellable',
        });
      }
    }
  }

  Future<void> scan() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(
          title: 'Scanner le bon de livraison',
          hint: 'Placez le QR collé sur le colis dans le cadre.',
          manualLabel: 'Revenir sans scanner',
        ),
      ),
    );
    if (raw == null || !mounted) return;
    final scanned = TicketScan.parse(raw);
    if (scanned == null || scanned.deliveryId != widget.delivery!['id']) {
      setState(
        () => error = scanned == null
            ? 'Ce QR n’est pas un bon de livraison BioBalance.'
            : 'Ce QR appartient à une autre livraison.',
      );
      return;
    }
    setState(() {
      ticketCode = scanned.code;
      manualEntry = false;
      error = null;
      if (lines.isEmpty) prefill();
    });
    changed();
  }

  Future<void> add() async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductPicker(
        workspace: widget.vm,
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
    await editLot(product.id);
  }

  Future<void> addProduct(String productId) => editLot(productId);

  Future<void> editLot(String productId, {int? index}) async {
    final target = index ?? lines.length;
    final original = index == null ? null : lines[index];
    final quantity = original == null
        ? (widget.delivery == null
              ? 1
              : plan.remaining(productId).clamp(1, 1000000))
        : integer(original['quantity']);
    await openEditor(
      context,
      title: widget.vm.productName(productId),
      fields: [
        FieldSpec(
          'quantity',
          'Quantité de ce lot',
          initial: '$quantity',
          numeric: true,
        ),
        FieldSpec(
          'batch',
          'Numéro de lot sur l’emballage',
          initial: original?['batch'] ?? '',
        ),
        FieldSpec(
          'expiry',
          'Péremption : JJ/MM/AAAA ou MM/AAAA',
          initial: original == null
              ? ''
              : TunisDates.dateOnlyLabel(original['expiry']),
        ),
        if (widget.delivery != null)
          FieldSpec(
            'condition',
            'État des unités',
            initial: original?['condition'] ?? 'sellable',
            options: const {
              'sellable': 'Acceptées — stock vendable',
              'damaged': 'Abîmées — stock non vendable',
              'refused': 'Refusées — laissées au transporteur',
            },
          ),
      ],
      submit: (values) async {
        final value = <String, dynamic>{
          'productId': productId,
          'quantity': whole(values['quantity']!),
          'batch': values['batch']!.trim(),
          'expiry': TunisDates.expiry(values['expiry']!),
          if (widget.delivery != null) 'condition': values['condition'],
        };
        setState(() {
          // Retrying a failed draft save replaces this row instead of duplicating it.
          if (target < lines.length) {
            lines[target] = value;
          } else {
            lines.add(value);
          }
        });
        await persist();
      },
    );
  }

  Future<void> save() async {
    if (busy || !restored || completed) return;
    setState(() => busy = true);
    try {
      final vm = widget.vm;
      vm.requireAccess(store, 'manage');
      await persist();
      if (widget.delivery != null &&
          plan.requiresExplanation &&
          note.text.trim().length < 3) {
        throw const FormatException(
          'Expliquez les unités abîmées, refusées ou supplémentaires.',
        );
      }
      if (widget.delivery != null &&
          lines.isNotEmpty &&
          ticketCode == null &&
          !(manualEntry && manualReason.text.trim().length >= 3)) {
        throw const FormatException(
          'Scannez le QR du colis, ou indiquez pourquoi vous ne pouvez pas.',
        );
      }
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
              'Votre signalement sera transmis à BioBalance. Le stock reste inchangé et cette livraison pourra encore être réceptionnée après vérification.',
              label: 'Signaler non reçue',
            )) {
          return;
        }
      }
      committing = true;
      await _tail;
      await vm.queue(
        widget.delivery == null
            ? {'type': 'stock.receive', 'reason': 'receipt', 'lines': lines}
            : {
                'type': 'delivery.receive',
                'deliveryId': widget.delivery!['id'],
                'lines': lines,
                'note': note.text.trim(),
                if (lines.isNotEmpty && ticketCode != null)
                  'ticketCode': ticketCode
                else if (lines.isNotEmpty && manualEntry)
                  'manualReason': manualReason.text.trim(),
              },
        expectedVersion: widget.delivery == null
            ? null
            : integer(widget.delivery!['version']),
        targetStore: store,
        draftKey: key,
      );
      completed = true;
      if (mounted) {
        completeRoute(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              missing
                  ? 'Signalement enregistré. Le stock reste inchangé.'
                  : 'Réception enregistrée sur ce téléphone.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      committing = false;
      if (mounted) setState(() => busy = false);
    }
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
      final points = vm.user.admin
          ? whole(v['points']!, allowZero: true)
          : integer(config['pointsPerUnit']);
      if (vm.user.admin &&
          points == 0 &&
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
