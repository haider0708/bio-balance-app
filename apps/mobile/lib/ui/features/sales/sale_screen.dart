import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/money.dart';
import '../../core/design.dart';
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
      body: Column(
        children: [
          Expanded(
            child: Content(
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
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vm.workspace.productName(line.productId),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${line.quantity} unité${line.quantity > 1 ? 's' : ''} × ${line.price.formatted}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              line.allocations
                                  .map((a) {
                                    final lot = vm.workspace.state.data?.lots
                                        .where((l) => l.id == a['lotId'])
                                        .firstOrNull;
                                    return 'Lot ${lot?.batch ?? '—'} · ${a['quantity']} u.';
                                  })
                                  .join('  /  '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: () =>
                                      editLine(vm, line.productId, line),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Modifier'),
                                ),
                                TextButton.icon(
                                  onPressed: () => vm.remove(line.id),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Retirer'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
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
        ],
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
    final product = vm.workspace.state.data?.products
        .where((p) => p.barcode == code)
        .firstOrNull;
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
          line: line,
        ),
      ),
    );
    if (result != null) await vm.put(result);
  }

  Future<void> save(SaleViewModel vm) async {
    if (await vm.save(reason.text.trim()) && mounted) {
      Navigator.pop(context);
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
    final products = widget.products
        .where(
          (p) => '${p.name} ${p.reference} ${p.barcode}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SectionTitle('Choisir un produit'),
            TextField(
              autofocus: true,
              onChanged: (q) => setState(() => query = q),
              decoration: const InputDecoration(
                hintText: 'Nom, référence ou code-barres',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: products.isEmpty
                  ? const EmptyState(
                      title: 'Aucun produit trouvé',
                      description: 'Essayez une autre référence.',
                    )
                  : ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, i) => const Divider(),
                      itemBuilder: (_, i) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        title: Text(products[i].name),
                        subtitle: Text(products[i].reference),
                        trailing: const Icon(Icons.add),
                        onTap: () => Navigator.pop(context, products[i]),
                      ),
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
  const LineEditor({
    super.key,
    required this.workspace,
    required this.productId,
    this.line,
  });
  @override
  State<LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<LineEditor> {
  late final TextEditingController price;
  final allocations = <String, TextEditingController>{};
  String? error;
  late final List<InventoryLot> lots;
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
    lots =
        widget.workspace.state.data!.lots
            .where(
              (l) =>
                  l.productId == widget.productId &&
                  (!l.expired ||
                      widget.line?.allocations.any((a) => a['lotId'] == l.id) ==
                          true),
            )
            .toList()
          ..sort((a, b) => a.expiry.compareTo(b.expiry));
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
  }

  @override
  void dispose() {
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
            description: 'Demandez au responsable de renseigner le lot et sa date de péremption dans le stock.',
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

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool captured = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      controller.start();
    } else {
      controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Scanner un code-barres'),
      actions: [
        IconButton(
          onPressed: controller.toggleTorch,
          icon: const Icon(Icons.flashlight_on_outlined),
          tooltip: 'Lampe torche',
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: controller,
            errorBuilder: (_, error) => const EmptyState(
              title: 'Caméra indisponible',
              description: 'Autorisez la caméra dans les réglages ou utilisez la recherche manuelle.',
              icon: Icons.no_photography_outlined,
            ),
            onDetect: (capture) {
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (!captured && code != null) {
                captured = true;
                controller.stop();
                Navigator.pop(context, code);
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text('Placez le code-barres dans le cadre.'),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Utiliser la recherche manuelle'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
