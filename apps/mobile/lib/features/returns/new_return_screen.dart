import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/quantity_editor.dart';
import '../../l10n/app_localizations.dart';
import '../network/network_models.dart';
import '../network/network_repository.dart';
import '../stock/stock_repository.dart';
import '../transfers/transfer_models.dart';
import 'return_models.dart';
import 'returns_repository.dart';

/// What the admin does to a para's stock from here.
enum _Mode { remove, move, add, set }

/// Ask for a return (a responsable), or do it now (the admin: take out, move to another para, only add,
/// or set the quantities he wants, with a note).
class NewReturnScreen extends ConsumerStatefulWidget {
  const NewReturnScreen({super.key});

  @override
  ConsumerState<NewReturnScreen> createState() => _NewReturnScreenState();
}

class _NewReturnScreenState extends ConsumerState<NewReturnScreen> {
  _Mode _mode = _Mode.remove;
  TransferPara? _para;
  TransferPara? _to;
  final _items = QuantityController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _items.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _admin => ref.read(meProvider).role == Role.admin;

  bool get _valid =>
      _para != null &&
      (_mode == _Mode.set
          ? _note.text.trim().length >= 3
          : _items.total > 0 && (_mode != _Mode.move || _to != null));

  /// Setting quantities starts from what the para holds now.
  Future<void> _seed(TransferPara para) async {
    final levels = await ref.read(stockLevelsProvider(para.id).future);
    if (!mounted) return;
    _items.reset([
      for (final i in levels.items)
        QuantityItem(
          productId: i.productId,
          name: i.name,
          family: i.family,
          imageId: i.imageId,
          quantity: i.quantity < 0 ? 0 : i.quantity,
        ),
    ]);
  }

  void _chooseMode(_Mode mode) {
    setState(() {
      _mode = mode;
      if (mode != _Mode.move) _to = null;
    });
    if (mode == _Mode.set && _para != null) {
      unawaited(_seed(_para!));
    } else {
      _items.reset(const []);
    }
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    if (_mode == _Mode.set) {
      final para = _para!;
      final ok = await perform(
        context,
        () => ref
            .read(stockRepositoryProvider)
            .adjust(
              locationId: para.id,
              reason: _note.text.trim(),
              lines: _items.lines(),
            ),
        success: t.stockAdjusted,
      );
      if (ok) {
        ref.invalidate(stockLevelsProvider(para.id));
        if (mounted) context.pop();
      }
      return;
    }
    final body = <String, Object?>{
      'pdvId': _para!.id,
      'action': switch (_mode) {
        _Mode.move => ReturnAction.move.wire,
        _Mode.add => ReturnAction.add.wire,
        _ => ReturnAction.remove.wire,
      },
      if (_mode == _Mode.move) 'toPdvId': _to!.id,
      'lines': _items.lines(skipZero: true),
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
    };
    final ok = await perform(
      context,
      () => ref.read(returnsRepositoryProvider).create(body),
      success: _admin ? t.returnDone : t.returnSent,
    );
    if (ok) {
      ref.invalidate(returnsProvider);
      if (mounted) context.pop();
    }
  }

  /// The active paras to choose from: the responsable's region, or every one for the admin.
  Future<TransferPara?> _pick({TransferPara? except}) async {
    final pdvs = await ref.read(pdvsProvider(null).future);
    if (!mounted) return null;
    final options = [
      for (final p in pdvs)
        if (p.status == ItemStatus.active && p.id != except?.id)
          TransferPara(
            id: p.id,
            name: p.name,
            address: p.address,
            city: p.city,
          ),
    ];
    return showModalBottomSheet<TransferPara>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ParaSheet(options: options),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final admin = ref.watch(meProvider).role == Role.admin;
    return Scaffold(
      appBar: AppBar(title: Text(t.returnNew)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (admin) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (mode, label, icon) in [
                  (
                    _Mode.remove,
                    t.returnActionRemove,
                    LucideIcons.arrowUpFromLine,
                  ),
                  (_Mode.move, t.returnActionMove, LucideIcons.arrowLeftRight),
                  (_Mode.add, t.returnActionAdd, LucideIcons.arrowDownToLine),
                  (_Mode.set, t.returnActionSet, LucideIcons.slidersHorizontal),
                ])
                  ChoiceChip(
                    // The icon already says what it is; the colour says it is chosen.
                    showCheckmark: false,
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    selected: _mode == mode,
                    onSelected: (_) => _chooseMode(mode),
                  ),
              ],
            ),
            const Gap(16),
          ],
          _ParaRow(
            label: t.returnPara,
            para: _para,
            onTap: () async {
              final picked = await _pick();
              if (picked != null) {
                setState(() {
                  _para = picked;
                  if (_to?.id == picked.id) _to = null;
                });
                if (_mode == _Mode.set) await _seed(picked);
              }
            },
          ),
          if (_mode == _Mode.move) ...[
            const Gap(8),
            _ParaRow(
              label: t.returnMoveTo,
              para: _to,
              onTap: () async {
                final picked = await _pick(except: _para);
                if (picked != null) setState(() => _to = picked);
              },
            ),
          ],
          const Gap(20),
          Text(t.transferProducts, style: context.text.labelLarge),
          if (_mode == _Mode.set) ...[
            const Gap(4),
            Text(
              t.returnSetHint,
              style: context.text.bodySmall?.copyWith(
                color: context.status.muted,
              ),
            ),
          ],
          const Gap(8),
          QuantityEditor(controller: _items, allowPaste: _mode == _Mode.set),
          const Gap(20),
          TextField(
            controller: _note,
            maxLength: 300,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _mode == _Mode.set
                  ? t.adjustReason
                  : '${t.note} (${t.optional})',
            ),
          ),
          const Gap(8),
          ListenableBuilder(
            listenable: _items,
            builder: (context, _) => AsyncButton(
              label: _mode == _Mode.set
                  ? t.save
                  : admin
                  ? t.returnSubmitNow
                  : t.returnSubmit,
              onPressed: _valid ? _submit : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParaRow extends StatelessWidget {
  const _ParaRow({
    required this.label,
    required this.para,
    required this.onTap,
  });

  final String label;
  final TransferPara? para;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        spacing: 12,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: context.text.labelMedium?.copyWith(
                color: context.status.muted,
              ),
            ),
          ),
          const Icon(LucideIcons.store),
          Expanded(
            child: Text(
              para?.name ?? t.transferChoosePara,
              style: para == null
                  ? context.text.bodyLarge?.copyWith(
                      color: context.status.muted,
                    )
                  : context.text.titleSmall,
            ),
          ),
          const Icon(LucideIcons.chevronRight, size: 18),
        ],
      ),
    );
  }
}

class _ParaSheet extends StatelessWidget {
  const _ParaSheet({required this.options});

  final List<TransferPara> options;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(t.transferChoosePara, style: context.text.titleLarge),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in options)
                ListTile(
                  leading: const Icon(LucideIcons.store),
                  title: Text(p.name),
                  subtitle: Text(
                    [p.address, p.city].where((s) => s.isNotEmpty).join(', '),
                  ),
                  onTap: () => Navigator.pop(context, p),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
