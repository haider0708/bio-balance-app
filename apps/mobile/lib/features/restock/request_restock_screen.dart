import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/drafts/drafts.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/photo_set.dart';
import '../../core/widgets/quantity_editor.dart';
import '../../l10n/app_localizations.dart';
import '../approvals/approvals_repository.dart';
import '../network/network_models.dart';
import '../network/network_repository.dart';
import 'restock_models.dart';
import 'restock_repository.dart';

/// Ask BioBalance for products for a point of sale or a grossiste of the region (responsable).
class RequestRestockScreen extends ConsumerStatefulWidget {
  const RequestRestockScreen({this.destId, super.key});

  final String? destId;

  @override
  ConsumerState<RequestRestockScreen> createState() =>
      _RequestRestockScreenState();
}

class _RequestRestockScreenState extends ConsumerState<RequestRestockScreen> {
  final _quantities = QuantityController();
  final _note = TextEditingController();
  late String? _destId = widget.destId;

  /// The grossiste suggested (a responsable the admin allowed); the admin decides.
  SupplierCoverage? _supplier;

  /// The admin's choice for a store: record the delivery now (with proof, the stock moves at once) or
  /// send it and leave the receipt to the store's responsable.
  String _deliver = 'now';
  List<String> _photoIds = const [];
  bool _photosBusy = false;

  /// The request is kept for a week until it is sent; one opened from a place has its own.
  late final _draft = DraftKeeper(
    ref,
    'restock.${widget.destId ?? 'any'}',
    life: const Duration(days: 7),
  );
  bool _restored = false;
  int _round = 0;

  @override
  void initState() {
    super.initState();
    final left = _draft.restored;
    if (left != null) {
      final lines = left['lines'];
      if (lines is List) _quantities.restore(lines);
      _note.text = left['note'] as String? ?? '';
      _destId ??= left['destId'] as String?;
      _restored = _pending;
    }
    _quantities.addListener(_keep);
    _note.addListener(_keep);
  }

  bool get _pending =>
      _quantities.items.any((i) => i.quantity > 0) ||
      _note.text.trim().isNotEmpty;

  void _keep() => _draft.save(
    _pending
        ? {
            'lines': _quantities.toDraft(),
            'note': _note.text,
            'destId': _destId,
          }
        : null,
  );

  void _startOver() {
    setState(() {
      _restored = false;
      _destId = widget.destId;
      _round++;
    });
    _note.clear();
    _quantities.reset(const []);
    _keep();
  }

  @override
  void dispose() {
    _quantities.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Lists the grossistes with whether each covers what is asked, and keeps the one chosen.
  Future<void> _chooseSupplier() async {
    final t = AppLocalizations.of(context);
    final lines = _quantities.lines(skipZero: true);
    if (lines.isEmpty) {
      showMessage(context, t.addProductsFirst);
      return;
    }
    try {
      final list = await ref.read(restockRepositoryProvider).coverage(lines);
      if (!mounted) return;
      final picked = await showModalBottomSheet<SupplierCoverage?>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _SupplierSheet(list: list, current: _supplier),
      );
      // Dismissed: no change. "No preference" comes back as an empty choice.
      if (picked == null) return;
      setState(() => _supplier = picked.id.isEmpty ? null : picked);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  bool get _admin => ref.read(meProvider).role == Role.admin;

  /// A grossiste's delivery is always recorded when it arrives; a store's can be left to its responsable.
  bool get _isDepot => (ref.read(depotsProvider).value ?? const <Depot>[]).any(
    (d) => d.id == _destId,
  );

  bool get _recordNow => _isDepot || _deliver == 'now';

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref
          .read(restockRepositoryProvider)
          .create(
            destId: _destId!,
            note: _note.text.trim(),
            lines: _quantities.lines(skipZero: true),
            supplierId: _supplier?.id,
            photoIds: _admin && _recordNow ? _photoIds : const [],
            deliver: _admin ? (_recordNow ? 'now' : 'later') : null,
          ),
      success: !_admin
          ? t.restockSent
          : _recordNow
          ? t.deliveryRecorded
          : t.orderSentToStore,
    );
    if (ok && mounted) {
      _draft.discard();
      ref.invalidate(restocksProvider);
      ref.invalidate(approvalsProvider);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final pdvs = ref.watch(pdvsProvider(null));
    final depots = ref.watch(depotsProvider);
    // Active points of sale and grossistes of the region, the place's own name first.
    final places = <(String, String, IconData)>[
      for (final p in pdvs.value ?? const <Pdv>[])
        if (p.status == ItemStatus.active) (p.id, p.name, LucideIcons.store),
      for (final d in depots.value ?? const <Depot>[])
        if (d.active) (d.id, d.name, LucideIcons.warehouse),
    ];
    return DraftLeaveNote(
      pending: () => _pending && !_draft.done,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            ref.watch(meProvider).role == Role.admin
                ? t.newOrder
                : t.requestRestock,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_restored) DraftNotice(onStartOver: _startOver),
            AsyncBody(
              value: pdvs,
              onRetry: () {
                ref
                  ..invalidate(pdvsProvider(null))
                  ..invalidate(depotsProvider);
              },
              builder: (_) {
                if (places.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      t.noActivePdv,
                      style: context.text.bodyMedium?.copyWith(
                        color: context.status.muted,
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: DropdownButtonFormField<String>(
                    // Made again when the grossistes arrive after the stores, or on starting over.
                    key: ValueKey((_round, places.length)),
                    initialValue: places.any((p) => p.$1 == _destId)
                        ? _destId
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t.deliverTo),
                    items: [
                      for (final (id, name, icon) in places)
                        DropdownMenuItem(
                          value: id,
                          child: Row(
                            children: [
                              Icon(icon, size: 18, color: context.status.muted),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() => _destId = v);
                      _keep();
                    },
                  ),
                );
              },
            ),
            Text(t.productsNeeded, style: context.text.titleMedium),
            const Gap(8),
            QuantityEditor(controller: _quantities, allowPaste: true),
            const Gap(16),
            if (ref.watch(meProvider).role == Role.admin &&
                _destId != null) ...[
              if (!_isDepot) ...[
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'now', label: Text(t.deliverNow)),
                    ButtonSegment(value: 'later', label: Text(t.deliverLater)),
                  ],
                  selected: {_deliver},
                  onSelectionChanged: (s) => setState(() => _deliver = s.first),
                ),
                const Gap(8),
                Text(
                  _deliver == 'now' ? t.deliverNowHint : t.deliverLaterHint,
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
                const Gap(12),
              ],
              if (_recordNow) ...[
                PhotoSet(
                  label: t.photoOfDeliveryPaper,
                  initialIds: _photoIds,
                  onChanged: (ids, busy) => setState(() {
                    _photoIds = ids;
                    _photosBusy = busy;
                  }),
                ),
                const Gap(16),
              ],
            ],
            // A responsable the admin allowed may suggest where a store's goods come from.
            if (ref.watch(meProvider).canChooseSupplier &&
                (pdvs.value ?? const <Pdv>[]).any((p) => p.id == _destId)) ...[
              AppCard(
                onTap: _chooseSupplier,
                child: Row(
                  spacing: 12,
                  children: [
                    const Icon(LucideIcons.warehouse),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.supplierSuggest,
                            style: context.text.titleSmall,
                          ),
                          Text(
                            _supplier?.name ?? t.supplierSuggestHint,
                            style: context.text.bodySmall?.copyWith(
                              color: context.status.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 18,
                      color: context.status.muted,
                    ),
                  ],
                ),
              ),
              const Gap(16),
            ],
            TextField(
              controller: _note,
              maxLength: 300,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: '${t.note} (${t.optional})',
              ),
            ),
            const Gap(8),
            ListenableBuilder(
              listenable: _quantities,
              builder: (context, _) => AsyncButton(
                label: !_admin
                    ? t.sendRequest
                    : _recordNow
                    ? t.recordDeliverySave
                    : t.sendToStore,
                icon: LucideIcons.send,
                onPressed:
                    _quantities.total == 0 ||
                        _destId == null ||
                        (_admin &&
                            _recordNow &&
                            (_photosBusy || _photoIds.isEmpty))
                    ? null
                    : _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The grossistes a responsable may suggest, with whether each covers the order.
class _SupplierSheet extends StatelessWidget {
  const _SupplierSheet({required this.list, required this.current});

  final List<SupplierCoverage> list;
  final SupplierCoverage? current;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(t.chooseGrossiste, style: context.text.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                t.supplierSuggestHint,
                style: context.text.bodyMedium?.copyWith(
                  color: context.status.muted,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(LucideIcons.circleSlash),
              title: Text(t.supplierNone),
              trailing: current == null ? const Icon(LucideIcons.check) : null,
              onTap: () => Navigator.pop(
                context,
                const SupplierCoverage(
                  id: '',
                  name: '',
                  city: '',
                  regionName: '',
                  missing: 0,
                ),
              ),
            ),
            for (final d in list)
              ListTile(
                leading: const Icon(LucideIcons.warehouse),
                title: Text(d.name),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${d.city} · ${d.regionName}'),
                      StatusChip(
                        d.missing == 0
                            ? t.supplierHasAll
                            : t.supplierMissing(d.missing),
                        tone: d.missing == 0 ? Tone.success : Tone.warning,
                      ),
                    ],
                  ),
                ),
                trailing: current?.id == d.id
                    ? const Icon(LucideIcons.check)
                    : null,
                onTap: () => Navigator.pop(context, d),
              ),
          ],
        ),
      ),
    );
  }
}
