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
import '../../../data/repositories/store_settings_repository.dart';
import '../../../domain/models/delivery_ticket.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../../domain/models/money.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../../core/segment_bar.dart';
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
  List<Json> lines = [], flags = [];
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
  bool get scanned => widget.delivery != null && ticketCode != null;
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
          flags = objects(draft?['flags']);
          note.text = draft?['note'] ?? '';
          missing = draft?['missing'] == true;
          ticketCode = draft?['ticketCode'];
          manualEntry = draft?['manual'] == true;
          manualReason.text = draft?['manualReason'] ?? '';
          restored = true;
          if (ticketCode == null && widget.scannedCode != null) {
            ticketCode = widget.scannedCode;
            manualEntry = false;
            lines = [];
            flags = [];
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
      'flags': List<Json>.from(flags),
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
      onPressed: busy || !restored || !(scanned || lines.isNotEmpty || missing)
          ? null
          : save,
      child: Text(
        busy
            ? 'Enregistrement…'
            : missing
            ? 'Signaler non reçue'
            : widget.delivery != null && !scanned
            ? 'Envoyer à BioBalance pour validation'
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
      if (scanned) ...[
        ticketPanel(),
        const SizedBox(height: 16),
        const Text(
          'Voici ce que contient le colis d’après son bon. Confirmez si c’est bien ce que vous recevez ; sinon, reprenez sans scanner et BioBalance tranchera.',
        ),
        const SizedBox(height: 16),
        for (final expected in objects(widget.delivery!['lines']))
          CompactRow(
            title: widget.vm.productName(expected['productId']),
            leading: ProductPhoto(
              vm: widget.vm,
              productId: expected['productId'],
            ),
            subtitle: objects(expected['allocations'])
                .map(
                  (a) =>
                      '${a['quantity']} × lot ${a['batch']} (exp. ${TunisDates.dateOnlyLabel(a['expiry'])})',
                )
                .join('\n'),
            value: '${expected['quantity']} u.',
          ),
        const SizedBox(height: 8),
        Text(
          'Le QR confirme les quantités, les lots et les dates. Il ne dit rien de l’état : signalez ici les unités abîmées ou refusées.',
          style: const TextStyle(fontSize: 14, color: muted),
        ),
        for (final entry in flags.asMap().entries)
          CompactRow(
            title: widget.vm.productName(entry.value['productId']),
            subtitle:
                'Lot ${entry.value['batch']} · ${[if (integer(entry.value['damaged']) > 0) '${entry.value['damaged']} abîmées', if (integer(entry.value['refused']) > 0) '${entry.value['refused']} refusées'].join(' · ')}',
            icon: AppIcons.errorOutline,
            tone: AppTone.warning,
            onTap: busy ? null : () => flagUnits(index: entry.key),
            trailing: IconButton(
              onPressed: busy
                  ? null
                  : () {
                      setState(() => flags.removeAt(entry.key));
                      changed();
                    },
              icon: const Icon(AppIcons.close),
              tooltip: 'Retirer ce signalement',
            ),
          ),
        OutlinedButton.icon(
          onPressed: busy || !restored ? null : flagUnits,
          icon: const Icon(AppIcons.errorOutline),
          label: const Text('Signaler des unités abîmées ou refusées'),
        ),
        if (flags.isNotEmpty) ...[
          const SizedBox(height: 12),
          TextField(
            controller: note,
            enabled: !busy && restored,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Explication (obligatoire)',
            ),
          ),
        ],
        TextButton(
          onPressed: busy
              ? null
              : () {
                  setState(() {
                    ticketCode = null;
                    manualEntry = true;
                    flags = [];
                  });
                  changed();
                },
          child: const Text('Ce n’est pas ce que je reçois'),
        ),
      ],
      if (widget.delivery != null && !scanned) ...[
        ticketPanel(),
        const SizedBox(height: 16),
        const Text(
          'Pour chaque produit : quantité reçue, numéro de lot et péremption. Le stock sera ajouté après validation par BioBalance.',
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
      if (!scanned && lines.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          'Lots saisis · ${plan.sellable + plan.damaged + plan.refused} reçues${plan.damaged > 0 ? ' · dont ${plan.damaged} abîmées' : ''}${plan.refused > 0 ? ' · dont ${plan.refused} refusées' : ''}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
      if (!scanned)
        for (final group in lotGroups())
          CompactRow(
            title: widget.vm.productName(group.productId),
            subtitle:
                '${group.total} reçues${group.damaged > 0 ? ' · ${group.damaged} abîmées' : ''}${group.refused > 0 ? ' · ${group.refused} refusées' : ''}\nLot ${group.batch} · ${TunisDates.dateOnlyLabel(group.expiry)}',
            onTap: busy || !restored
                ? null
                : () => editLot(group.productId, group: group),
            trailing: IconButton(
              onPressed: busy || !restored
                  ? null
                  : () {
                      setState(() => lines.removeWhere(group.owns));
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
            'BioBalance comparera avec ce qui a été expédié, puis validera. Le stock n’augmente qu’à ce moment.',
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
      // A scanned parcel is booked as its ticket says: nothing to enter.
      lines = [];
      missing = false;
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

  /// A lot as the store counted it: one row per product, batch and expiry.
  List<_LotGroup> lotGroups() {
    final groups = <String, _LotGroup>{};
    for (final line in lines) {
      final key = '${line['productId']}|${line['batch']}|${line['expiry']}';
      final group = groups.putIfAbsent(
        key,
        () => _LotGroup(line['productId'], line['batch'], line['expiry']),
      );
      final n = integer(line['quantity']);
      group.total += n;
      switch (line['condition']) {
        case 'damaged':
          group.damaged += n;
        case 'refused':
          group.refused += n;
      }
    }
    return groups.values.toList();
  }

  /// Units of a lot whose ticket is scanned: how many arrived damaged or were refused.
  Future<void> flagUnits({int? index}) async {
    final lots = <String, String>{};
    final sources = <String, Json>{};
    for (final line in objects(widget.delivery!['lines'])) {
      for (final a in objects(line['allocations'])) {
        final key = '${line['productId']}|${a['batch']}';
        lots[key] =
            '${widget.vm.productName(line['productId'])} · lot ${a['batch']} (${a['quantity']} u.)';
        sources[key] = {...a, 'productId': line['productId']};
      }
    }
    final original = index == null ? null : flags[index];
    await openEditor(
      context,
      title: 'Signaler des unités',
      description: 'Indiquez combien d’unités de ce lot sont abîmées (elles entrent en stock non vendable) ou refusées (laissées au transporteur).',
      fields: [
        FieldSpec(
          'lot',
          'Produit et lot',
          options: lots,
          initial: original == null
              ? ''
              : '${original['productId']}|${original['batch']}',
        ),
        FieldSpec(
          'damaged',
          'Unités abîmées',
          initial: '${original?['damaged'] ?? 0}',
          numeric: true,
        ),
        FieldSpec(
          'refused',
          'Unités refusées',
          initial: '${original?['refused'] ?? 0}',
          numeric: true,
        ),
      ],
      submit: (values) async {
        final source = sources[values['lot']]!;
        final damaged = whole(values['damaged']!, allowZero: true);
        final refused = whole(values['refused']!, allowZero: true);
        if (damaged + refused == 0) {
          throw const FormatException(
            'Indiquez au moins une unité abîmée ou refusée.',
          );
        }
        if (damaged + refused > integer(source['quantity'])) {
          throw FormatException(
            'Ce lot ne contient que ${source['quantity']} unités.',
          );
        }
        final value = {
          'productId': source['productId'],
          'batch': source['batch'],
          'damaged': damaged,
          'refused': refused,
        };
        setState(() {
          flags.removeWhere(
            (f) =>
                f['productId'] == value['productId'] &&
                f['batch'] == value['batch'],
          );
          flags.add(value);
        });
        await persist();
      },
    );
  }

  Future<void> editLot(String productId, {_LotGroup? group}) async {
    final quantity = group != null
        ? group.total
        : (widget.delivery == null
              ? 1
              : plan.remaining(productId).clamp(1, 1000000));
    await openEditor(
      context,
      title: widget.vm.productName(productId),
      fields: [
        FieldSpec(
          'quantity',
          widget.delivery == null
              ? 'Quantité de ce lot'
              : 'Quantité reçue de ce lot',
          initial: '$quantity',
          numeric: true,
        ),
        FieldSpec(
          'batch',
          'Numéro de lot sur l’emballage',
          initial: group?.batch ?? '',
        ),
        FieldSpec(
          'expiry',
          'Date de péremption',
          date: true,
          hint: 'Si seul le mois est imprimé, choisissez le dernier jour du mois.',
          initial: group == null ? '' : TunisDates.dateOnlyLabel(group.expiry),
        ),
        if (widget.delivery != null) ...[
          FieldSpec(
            'damaged',
            'Dont abîmées (non vendables)',
            initial: '${group?.damaged ?? 0}',
            numeric: true,
          ),
          FieldSpec(
            'refused',
            'Dont refusées (laissées au transporteur)',
            initial: '${group?.refused ?? 0}',
            numeric: true,
          ),
        ],
      ],
      submit: (values) async {
        final total = whole(values['quantity']!);
        final damaged = widget.delivery == null
            ? 0
            : whole(values['damaged']!, allowZero: true);
        final refused = widget.delivery == null
            ? 0
            : whole(values['refused']!, allowZero: true);
        if (damaged + refused > total) {
          throw const FormatException(
            'Les unités abîmées et refusées ne peuvent pas dépasser la quantité reçue.',
          );
        }
        final base = {
          'productId': productId,
          'batch': values['batch']!.trim(),
          'expiry': TunisDates.expiry(values['expiry']!),
        };
        final created = <Json>[
          if (widget.delivery == null)
            {...base, 'quantity': total}
          else ...[
            if (total - damaged - refused > 0)
              {
                ...base,
                'quantity': total - damaged - refused,
                'condition': 'sellable',
              },
            if (damaged > 0)
              {...base, 'quantity': damaged, 'condition': 'damaged'},
            if (refused > 0)
              {...base, 'quantity': refused, 'condition': 'refused'},
          ],
        ];
        setState(() {
          // Retrying a failed draft save replaces the lot instead of duplicating it.
          final at = group == null
              ? lines.length
              : lines.indexWhere(group.owns).clamp(0, lines.length);
          if (group != null) lines.removeWhere(group.owns);
          lines.insertAll(at.clamp(0, lines.length), created);
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
      if (scanned && flags.isNotEmpty && note.text.trim().length < 3) {
        throw const FormatException(
          'Expliquez les unités abîmées ou refusées.',
        );
      }
      if (widget.delivery != null &&
          !scanned &&
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
      if (lines.isEmpty && !scanned) {
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
            ? {'type': 'stock.receive', 'reason': 'opening', 'lines': lines}
            : {
                'type': 'delivery.receive',
                'deliveryId': widget.delivery!['id'],
                // A scanned parcel is booked as its ticket says; nothing is sent.
                'lines': scanned ? <Json>[] : lines,
                'note': scanned && flags.isEmpty ? '' : note.text.trim(),
                if (scanned) ...{
                  'ticketCode': ticketCode,
                  'flags': flags,
                } else if (lines.isNotEmpty && manualEntry)
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
                  : widget.delivery != null && !scanned
                  ? 'Réception envoyée à BioBalance. Le stock augmentera après sa validation.'
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

/// One lot as counted by the receiver, gathered from its condition lines.
class _LotGroup {
  final String productId, batch;
  final dynamic expiry;
  int total = 0, damaged = 0, refused = 0;
  _LotGroup(this.productId, this.batch, this.expiry);
  bool owns(Json line) =>
      line['productId'] == productId &&
      line['batch'] == batch &&
      line['expiry'] == expiry;
}
