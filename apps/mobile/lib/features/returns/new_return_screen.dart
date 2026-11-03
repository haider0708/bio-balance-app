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
import '../transfers/transfer_models.dart';
import 'return_models.dart';
import 'returns_repository.dart';

/// Ask for a return (a responsable), or do it now (the admin: take out, move to another para, or only add).
class NewReturnScreen extends ConsumerStatefulWidget {
  const NewReturnScreen({super.key});

  @override
  ConsumerState<NewReturnScreen> createState() => _NewReturnScreenState();
}

class _NewReturnScreenState extends ConsumerState<NewReturnScreen> {
  ReturnAction _action = ReturnAction.remove;
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
      _items.total > 0 &&
      (_action != ReturnAction.move || _to != null);

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final body = <String, Object?>{
      'pdvId': _para!.id,
      'action': _action.wire,
      if (_action == ReturnAction.move) 'toPdvId': _to!.id,
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
            SegmentedButton<ReturnAction>(
              segments: [
                ButtonSegment(
                  value: ReturnAction.remove,
                  label: Text(t.returnActionRemove),
                  icon: const Icon(LucideIcons.arrowUpFromLine),
                ),
                ButtonSegment(
                  value: ReturnAction.move,
                  label: Text(t.returnActionMove),
                  icon: const Icon(LucideIcons.arrowLeftRight),
                ),
                ButtonSegment(
                  value: ReturnAction.add,
                  label: Text(t.returnActionAdd),
                  icon: const Icon(LucideIcons.arrowDownToLine),
                ),
              ],
              showSelectedIcon: false,
              selected: {_action},
              onSelectionChanged: (s) => setState(() {
                _action = s.first;
                if (_action != ReturnAction.move) _to = null;
              }),
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
              }
            },
          ),
          if (_action == ReturnAction.move) ...[
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
          const Gap(8),
          QuantityEditor(controller: _items),
          const Gap(20),
          TextField(
            controller: _note,
            maxLength: 300,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: '${t.note} (${t.optional})'),
          ),
          const Gap(8),
          ListenableBuilder(
            listenable: _items,
            builder: (context, _) => AsyncButton(
              label: admin ? t.returnSubmitNow : t.returnSubmit,
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
