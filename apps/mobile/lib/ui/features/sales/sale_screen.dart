import '../../core/navigation.dart';

import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import '../scanning/scanner_screen.dart';
export '../scanning/scanner_screen.dart';

import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/batch_declaration.dart';
import '../../../domain/models/inventory_rules.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/forms.dart';
import '../../../domain/models/money.dart';
import '../../core/design.dart';
import '../../core/form_draft.dart';
import '../../core/formatting.dart';
export '../../core/formatting.dart';
import '../workspace/workspace_view_model.dart';
import 'sale_view_model.dart';

class SaleScreen extends StatelessWidget {
  final WorkspaceViewModel workspace;
  final Json? original;
  final Json? recovery;
  const SaleScreen({
    super.key,
    required this.workspace,
    this.original,
    this.recovery,
  });
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) =>
        SaleViewModel(workspace, original: original, recovery: recovery)
          ..restore(),
    child: const _SaleEditor(),
  );
}

class _SaleEditor extends StatefulWidget {
  const _SaleEditor();
  @override
  State<_SaleEditor> createState() => _SaleEditorState();
}

class _SaleEditorState extends State<_SaleEditor> {
  final reason = TextEditingController(text: 'Correction de saisie');
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SaleViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          vm.original == null ? 'Nouvelle vente' : 'Corriger la vente',
        ),
      ),
      body: Content(
        maxWidth: 760,
        children: [
          StatusChip(vm.store.name, icon: Icons.storefront_outlined),
          const SizedBox(height: 20),
          if (vm.recovery != null) ...[
            const Notice(
              'Vérifiez les lignes proposées avec la vente réelle. La version synchronisée sert de référence ; les anciennes saisies restent dans l’historique de résolution.',
            ),
            const SizedBox(height: 16),
          ],
          if (vm.state.error != null) ...[
            Notice(vm.state.error!, error: true),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => scan(vm),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scanner un produit'),
              ),
              OutlinedButton.icon(
                onPressed: () => choose(vm),
                icon: const Icon(Icons.search),
                label: const Text('Rechercher'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (vm.state.lines.isEmpty)
            const EmptyState(
              title: 'Votre vente commence ici',
              description: 'Scannez un produit ou recherchez sa référence. Le brouillon est enregistré automatiquement.',
              icon: Icons.shopping_bag_outlined,
            ),
          ...vm.state.lines.map(
            (line) => CompactRow(
              title: vm.workspace.productName(line.productId),
              subtitle:
                  '${line.quantity} unité${line.quantity > 1 ? 's' : ''} × ${line.price.formatted}\n${line.allocations.map((a) {
                    final lot = vm.workspace.state.data?.lots.where((l) => l.id == a['lotId']).firstOrNull;
                    return 'Lot ${lot?.batch ?? '—'} · ${a['quantity']} u.';
                  }).join(' / ')}',
              footer: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: vm.state.saving
                        ? null
                        : () => editLine(vm, line.productId, line),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'),
                  ),
                  TextButton.icon(
                    onPressed: vm.state.saving
                        ? null
                        : () => vm.remove(line.id),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Retirer'),
                  ),
                ],
              ),
            ),
          ),
          if (vm.original != null) ...[
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Motif de la correction',
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Notice(
            'Le prix et le lot doivent correspondre aux produits réellement vendus. Les points seront confirmés à la synchronisation.',
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE5E9E1))),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Text(
                        Money(vm.total).formatted,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '≈ ${vm.estimatedPoints} points',
                        style: const TextStyle(color: darkGreen),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: vm.state.saving || vm.state.lines.isEmpty
                          ? null
                          : () => save(vm),
                      icon: const Icon(Icons.check),
                      label: Text(
                        vm.state.saving
                            ? 'Enregistrement…'
                            : 'Enregistrer la vente',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> choose(SaleViewModel vm) async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductPicker(
        products:
            vm.workspace.state.data?.products.where((p) => p.active).toList() ??
            [],
      ),
    );
    if (product != null && mounted) await editLine(vm, product.id, null);
  }

  Future<void> scan(SaleViewModel vm) async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (code == null || !mounted) return;
    final product = vm.workspace.state.data?.productForBarcode(code);
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Code inconnu. Choisissez le produit dans le catalogue.',
          ),
        ),
      );
      await choose(vm);
    } else {
      await editLine(vm, product.id, null);
    }
  }

  Future<void> editLine(
    SaleViewModel vm,
    String productId,
    SaleLine? line,
  ) async {
    final result = await Navigator.push<SaleLine>(
      context,
      MaterialPageRoute(
        builder: (_) => LineEditor(
          workspace: vm.workspace,
          productId: productId,
          occurredAt: vm.original?['occurredAt'] ?? vm.recovery?['occurredAt'],
          line: line,
        ),
      ),
    );
    if (result != null) {
      final saved = await vm.put(result);
      if (!saved) return;
      await vm.workspace.repository.saveDraft(
        vm.workspace.user.id,
        vm.store.id,
        'sale-line:${line?.id ?? 'new:$productId'}',
        {},
      );
    }
  }

  Future<void> save(SaleViewModel vm) async {
    if (await vm.save(reason.text.trim()) && mounted) {
      completeRoute(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enregistrée sur ce téléphone · En attente de synchronisation',
          ),
        ),
      );
      unawaited(vm.workspace.synchronize(silent: true));
    }
  }
}

class ProductPicker extends StatefulWidget {
  final List<Product> products;
  const ProductPicker({super.key, required this.products});
  @override
  State<ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<ProductPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final products = widget.products
        .where((p) => p.matches(normalized))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .85,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            const SliverToBoxAdapter(child: SectionTitle('Choisir un produit')),
            SliverToBoxAdapter(
              child: TextField(
                autofocus: true,
                onChanged: (q) => setState(() => query = q),
                decoration: const InputDecoration(
                  hintText: 'Rechercher un produit',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            if (products.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  title: 'Aucun produit trouvé',
                  description: 'Essayez une autre référence.',
                ),
              ),
            SliverList.builder(
              itemCount: products.length,
              itemBuilder: (_, i) => CompactRow(
                title: products[i].name,
                subtitle: products[i].reference,
                trailing: const Icon(Icons.add),
                onTap: () => Navigator.pop(context, products[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LineEditor extends StatefulWidget {
  final WorkspaceViewModel workspace;
  final String productId;
  final SaleLine? line;
  final String? occurredAt;
  const LineEditor({
    super.key,
    required this.workspace,
    required this.productId,
    this.line,
    this.occurredAt,
  });
  @override
  State<LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<LineEditor> {
  late final TextEditingController price;
  late final FormDraftController draft;
  bool restoringDraft = false;
  final allocations = <String, TextEditingController>{};
  String? error;
  late final List<InventoryLot> lots;
  final declarations = <BatchDeclaration>[];
  late final Store store = widget.workspace.state.store!;
  String get saleDate => TunisDates.today(
    DateTime.tryParse(widget.occurredAt ?? '') ?? DateTime.now(),
  );
  @override
  void initState() {
    super.initState();
    price = TextEditingController(
      text:
          widget.line?.price.input ??
          Money(
            integer(
              widget.workspace.state.data?.config(
                widget.productId,
              )['priceMillimes'],
            ),
          ).input,
    );
    lots = InventorySelection.forSale(
      widget.workspace.state.data?.lots.where(
            (l) => l.productId == widget.productId,
          ) ??
          [],
      saleDate,
    );
    declarations.addAll(widget.line?.batchDeclarations ?? []);
    for (final declaration in declarations) {
      addDeclaredLot(declaration);
    }
    for (var i = 0; i < lots.length; i++) {
      final old = widget.line?.allocations
          .where((a) => a['lotId'] == lots[i].id)
          .firstOrNull;
      allocations[lots[i].id] = TextEditingController(
        text: old != null
            ? '${old['quantity']}'
            : widget.line == null && i == 0
            ? '1'
            : '0',
      );
    }
    draft = FormDraftController(
      widget.workspace,
      store,
      'sale-line:${widget.line?.id ?? 'new:${widget.productId}'}',
      draftValues(),
    );
    price.addListener(persistDraft);
    for (final c in allocations.values) {
      c.addListener(persistDraft);
    }
    unawaited(restoreDraft());
  }

  Map<String, String> draftValues() => {
    'price': price.text,
    'declarations': jsonEncode(declarations.map((b) => b.toJson()).toList()),
    for (final e in allocations.entries) e.key: e.value.text,
  };
  void persistDraft() {
    if (restoringDraft) return;
    if (mounted) setState(() {});
    unawaited(
      draft.change(draftValues()).catchError((Object e) {
        if (mounted) {
          setState(() => error = 'Impossible de conserver le brouillon.');
        }
      }),
    );
  }

  Future<void> restoreDraft() async {
    try {
      final values = await draft.restore();
      if (!mounted || values == null) return;
      restoringDraft = true;
      for (final raw in objects(jsonDecode(values['declarations'] ?? '[]'))) {
        final declaration = BatchDeclaration.fromJson(raw);
        if (!declarations.any((d) => d.lotId == declaration.lotId)) {
          declarations.add(declaration);
        }
        addDeclaredLot(declaration);
        allocations.putIfAbsent(
          declaration.lotId,
          () => TextEditingController(text: '0')..addListener(persistDraft),
        );
      }
      price.text = values['price'] ?? price.text;
      for (final entry in allocations.entries) {
        entry.value.text = values[entry.key] ?? entry.value.text;
      }
      restoringDraft = false;
      setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Impossible de restaurer le brouillon.');
      }
    }
  }

  void addDeclaredLot(BatchDeclaration declaration) {
    if (lots.any((l) => l.id == declaration.lotId)) return;
    lots.add(
      InventoryLot.fromJson({
        ...declaration.toJson(),
        'id': declaration.lotId,
        'sellable': 0,
        'damaged': 0,
        'version': 1,
      }),
    );
  }

  Future<void> missingBatch() async {
    await openEditor(
      context,
      title: 'Renseigner le lot vendu',
      description: 'Cette saisie enregistre les informations du lot. La vente signalera le stock manquant au responsable.',
      fields: const [
        FieldSpec('batch', 'Numéro du lot'),
        FieldSpec('expiry', 'Péremption : JJ/MM/AAAA ou MM/AAAA'),
        FieldSpec('quantity', 'Unités vendues', initial: '1', numeric: true),
      ],
      submit: (values) async {
        final declaration = BatchDeclaration.create(
          store.id,
          widget.productId,
          values['batch']!,
          values['expiry']!,
        );
        if (declaration.expiry.compareTo(saleDate) < 0) {
          throw const FormatException(
            'Ce lot était périmé à la date de vente.',
          );
        }
        final quantity = whole(values['quantity']!);
        if (!mounted) return;
        setState(() {
          if (!declarations.any((d) => d.lotId == declaration.lotId)) {
            declarations.add(declaration);
          }
          addDeclaredLot(declaration);
          allocations
                  .putIfAbsent(
                    declaration.lotId,
                    () => TextEditingController()..addListener(persistDraft),
                  )
                  .text =
              '$quantity';
        });
        await draft.change(draftValues());
      },
    );
  }

  bool get hasShortage => lots.any(
    (lot) =>
        (int.tryParse(allocations[lot.id]?.text ?? '') ?? 0) > 0 &&
        (int.tryParse(allocations[lot.id]?.text ?? '') ?? 0) > lot.sellable,
  );

  @override
  void dispose() {
    draft.dispose();
    price.dispose();
    for (final c in allocations.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quantité, prix et lots')),
    body: Content(
      maxWidth: 640,
      children: [
        SectionTitle(widget.workspace.productName(widget.productId)),
        if (error != null) ...[
          Notice(error!, error: true),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Prix unitaire réel (TND)',
            helperText: 'Exemple : 49,900',
          ),
        ),
        const SizedBox(height: 24),
        const SectionTitle(
          'Unités par lot',
          subtitle: 'Le lot valide le plus proche de sa péremption est proposé. Vérifiez le lot réellement remis.',
        ),
        if (lots.isEmpty)
          const EmptyState(
            title: 'Aucun lot disponible',
            description: 'Renseignez le numéro du lot et sa péremption pour enregistrer la vente réelle.',
          ),
        OutlinedButton.icon(
          onPressed: missingBatch,
          icon: const Icon(Icons.add),
          label: const Text('Lot manquant ? Le renseigner'),
        ),
        if (hasShortage)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Notice(
              'Le stock enregistré est insuffisant. La vente sera conservée et un écart sera signalé au responsable.',
            ),
          ),
        ...lots.map(
          (l) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: allocations[l.id],
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Lot ${l.batch} · ${dateLabel(l.expiry)}',
                helperText: 'Stock enregistré : ${l.sellable} unité(s)',
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: lots.isEmpty ? null : submit,
          child: const Text('Ajouter à la vente'),
        ),
      ],
    ),
  );
  void submit() {
    try {
      final selected = <Json>[];
      for (final entry in allocations.entries) {
        final q = int.tryParse(entry.value.text);
        if (q == null || q < 0 || q > 1000000) {
          throw const FormatException(
            'Saisissez des quantités entières valides.',
          );
        }
        if (q > 0) selected.add({'lotId': entry.key, 'quantity': q});
      }
      final quantity = selected.fold<int>(
        0,
        (s, a) => s + integer(a['quantity']),
      );
      if (quantity < 1) {
        throw const FormatException('Choisissez au moins une unité.');
      }
      final line = SaleLine(
        id: widget.line?.id ?? const Uuid().v4(),
        productId: widget.productId,
        quantity: quantity,
        price: Money.parse(price.text),
        allocations: selected,
        batchDeclarations: declarations
            .where((d) => selected.any((a) => a['lotId'] == d.lotId))
            .toList(),
      );
      Navigator.pop(context, line);
    } catch (e) {
      setState(
        () => error = e is FormatException
            ? e.message
            : 'Vérifiez les quantités et le prix.',
      );
    }
  }
}
