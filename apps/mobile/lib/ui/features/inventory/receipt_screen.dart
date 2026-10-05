import '../catalog/product_information.dart';
import '../../core/navigation.dart';
import '../../../domain/models/receipt_plan.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/delivery_ticket.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../sales/sale_screen.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

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
          // Lots already counted by hand stay in the hand-count mode.
          manualEntry =
              draft?['manual'] == true ||
              (widget.delivery != null &&
                  ticketCode == null &&
                  lines.isNotEmpty);
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
    for (final c in stateInputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: widget.delivery == null
        ? 'Entrée de stock'
        : 'Réceptionner la livraison',
    maxWidth: 760,
    action: FilledButton(
      onPressed:
          busy ||
              !restored ||
              !(scanned || lines.isNotEmpty || missing) ||
              (widget.delivery != null && !scanned && !manualEntry)
          ? null
          : save,
      child: Text(
        busy
            ? 'Enregistrement…'
            : missing
            ? 'Signaler non reçue'
            : widget.delivery != null && !scanned && !manualEntry
            ? 'Scannez le QR pour confirmer'
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
          'Le QR confirme les quantités, les lots et les dates. Indiquez seulement les unités abîmées ou refusées, s’il y en a.',
        ),
        const SizedBox(height: 12),
        ...ticketLots(editable: true),
        if (flags.isNotEmpty) ...[
          const SizedBox(height: 12),
          TextField(
            controller: note,
            enabled: !busy && restored,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Raison des unités abîmées ou refusées (obligatoire)',
            ),
          ),
        ],
        refuseButton(),
      ],
      if (widget.delivery != null && !scanned && !manualEntry) ...[
        ticketPanel(),
        const SizedBox(height: 20),
        const SectionTitle(
          'Contenu annoncé',
          subtitle: 'Vérifiez le colis : s’il correspond, scannez son QR ; sinon, refusez-le.',
        ),
        ...ticketLots(editable: false),
        refuseButton(),
      ],
      if (widget.delivery != null && !scanned && manualEntry) ...[
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
      if (!scanned &&
          lines.isNotEmpty &&
          (widget.delivery == null || manualEntry)) ...[
        const SizedBox(height: 12),
        Text(
          'Lots saisis · ${plan.sellable + plan.damaged + plan.refused} reçues${plan.damaged > 0 ? ' · dont ${plan.damaged} abîmées' : ''}${plan.refused > 0 ? ' · dont ${plan.refused} refusées' : ''}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
      if (!scanned && (widget.delivery == null || manualEntry))
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
      if (lines.isEmpty &&
          !missing &&
          !scanned &&
          (widget.delivery == null || manualEntry))
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
              labelText: 'Raison sans scan (obligatoire)',
              helperText: 'Pourquoi le QR ne peut pas être scanné',
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

  /// One input per lot and state, created once the draft is restored.
  final stateInputs = <String, TextEditingController>{};
  TextEditingController stateInput(String lot, String kind) =>
      stateInputs.putIfAbsent('$lot|$kind', () {
        final saved = flags
            .where((f) => '${f['productId']}|${f['batch']}' == lot)
            .firstOrNull;
        final controller = TextEditingController(
          text: '${integer(saved?[kind])}',
        )..addListener(syncFlags);
        return controller;
      });

  /// The lots of the ticket, with damaged/refused fields once it is scanned.
  List<Widget> ticketLots({required bool editable}) => [
    // An older ticket may list products without their lots.
    for (final expected in objects(
      widget.delivery!['lines'],
    ).where((l) => objects(l['allocations']).isEmpty))
      CompactRow(
        title: widget.vm.productName(expected['productId']),
        leading: ProductPhoto(vm: widget.vm, productId: expected['productId']),
        subtitle: 'Lots non précisés sur le bon',
        value: '${expected['quantity']} u.',
      ),
    for (final expected in objects(widget.delivery!['lines']))
      for (final a in objects(expected['allocations']))
        CompactRow(
          title: widget.vm.productName(expected['productId']),
          leading: ProductPhoto(
            vm: widget.vm,
            productId: expected['productId'],
          ),
          subtitle:
              'Lot ${a['batch']} · exp. ${TunisDates.dateOnlyLabel(a['expiry'])}',
          value: '${a['quantity']} u.',
          footer: !editable || !restored
              ? null
              : Row(
                  children: [
                    for (final kind in const ['damaged', 'refused']) ...[
                      Expanded(
                        child: TextField(
                          key: ValueKey(
                            'receipt.$kind.${expected['productId']}.${a['batch']}',
                          ),
                          controller: stateInput(
                            '${expected['productId']}|${a['batch']}',
                            kind,
                          ),
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: kind == 'damaged'
                                ? 'Abîmées'
                                : 'Refusées',
                            isDense: true,
                          ),
                        ),
                      ),
                      if (kind == 'damaged') const SizedBox(width: 12),
                    ],
                  ],
                ),
        ),
  ];

  /// Rebuilds the reports from the fields, keeping only lots with a problem.
  void syncFlags() {
    final next = <Json>[];
    for (final expected in objects(widget.delivery?['lines'])) {
      for (final a in objects(expected['allocations'])) {
        final lot = '${expected['productId']}|${a['batch']}';
        final damaged =
            int.tryParse(stateInputs['$lot|damaged']?.text.trim() ?? '') ?? 0;
        final refused =
            int.tryParse(stateInputs['$lot|refused']?.text.trim() ?? '') ?? 0;
        if (damaged > 0 || refused > 0) {
          next.add({
            'productId': expected['productId'],
            'batch': a['batch'],
            'damaged': damaged,
            'refused': refused,
          });
        }
      }
    }
    setState(() => flags = next);
    changed();
  }

  Widget refuseButton() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: OutlinedButton.icon(
      key: const ValueKey('receipt.refuse'),
      onPressed: busy || !restored ? null : refuse,
      icon: const Icon(AppIcons.close),
      label: const Text('Refuser le colis'),
    ),
  );

  /// The whole parcel is turned away; BioBalance approves its return.
  Future<void> refuse() async {
    final done = await openEditor(
      context,
      title: 'Refuser le colis',
      description: 'Rien n’entre dans votre stock. BioBalance vérifiera puis validera le retour du colis à l’expéditeur.',
      fields: const [FieldSpec('reason', 'Pourquoi refusez-vous ce colis ?')],
      submitLabel: 'Refuser le colis',
      submit: (values) async {
        await widget.vm.online({
          'type': 'delivery.refuse',
          'deliveryId': widget.delivery!['id'],
          'reason': values['reason']!.trim(),
        }, expectedVersion: integer(widget.delivery!['version']));
      },
    );
    if (!done || !mounted) return;
    completed = true;
    await widget.vm.repository
        .saveDraft(widget.vm.user.id, store.id, key, {})
        .catchError((Object _) {});
    if (!mounted) return;
    completeRoute(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Colis refusé. BioBalance va valider son retour.'),
      ),
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
