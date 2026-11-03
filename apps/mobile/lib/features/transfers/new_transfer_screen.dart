import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/photo_field.dart';
import '../../core/widgets/quantity_editor.dart';
import '../../l10n/app_localizations.dart';
import '../network/network_models.dart';
import '../network/network_repository.dart';
import 'transfer_models.dart';
import 'transfers_repository.dart';

/// Record a transfer between two paras of the same group: who, which products, one photo.
/// A team member speaks for their own para; a responsable or the admin picks both sides.
class NewTransferScreen extends ConsumerStatefulWidget {
  const NewTransferScreen({super.key});

  @override
  ConsumerState<NewTransferScreen> createState() => _NewTransferScreenState();
}

class _NewTransferScreenState extends ConsumerState<NewTransferScreen> {
  /// A team member: does their para send (true) or receive (false)?
  bool _send = true;
  TransferPara? _from;
  TransferPara? _to;
  final _items = QuantityController();
  final _note = TextEditingController();
  String? _photoId;

  @override
  void dispose() {
    _items.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _admin => ref.read(meProvider).role == Role.admin;

  bool get _valid =>
      _from != null &&
      _to != null &&
      _items.total > 0 &&
      (_admin || _photoId != null);

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final me = ref.read(meProvider);
    final repo = ref.read(transfersRepositoryProvider);
    final vendeur = me.role == Role.vendeur;
    final body = <String, Object?>{
      'fromPdvId': _from!.id,
      'toPdvId': _to!.id,
      'direction': vendeur && !_send ? 'REQUEST' : 'SEND',
      'lines': _items.lines(skipZero: true),
      'photoId': ?_photoId,
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
    };
    final ok = await perform(
      context,
      () => repo.create(body),
      success: _admin ? t.transferMoved : t.transferSent,
    );
    if (ok) {
      ref.invalidate(transfersProvider);
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final vendeur = me.role == Role.vendeur;
    final mine = me.pdv == null
        ? null
        : TransferPara(id: me.pdv!.id, name: me.pdv!.name);
    // A team member: their para is one side, the other is chosen among the group.
    if (vendeur && mine != null) {
      if (_send) {
        _from = mine;
        if (_to?.id == mine.id) _to = null;
      } else {
        _to = mine;
        if (_from?.id == mine.id) _from = null;
      }
    }
    final partners = vendeur
        ? ref.watch(transferPartnersProvider(null))
        : _from == null
        ? null
        : ref.watch(transferPartnersProvider(_from!.id));
    return Scaffold(
      appBar: AppBar(title: Text(t.transferNew)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (vendeur) ...[
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text(t.transferMySends),
                  icon: const Icon(LucideIcons.arrowUpFromLine),
                ),
                ButtonSegment(
                  value: false,
                  label: Text(t.transferMyReceives),
                  icon: const Icon(LucideIcons.arrowDownToLine),
                ),
              ],
              selected: {_send},
              onSelectionChanged: (s) => setState(() => _send = s.first),
            ),
            const Gap(16),
          ],
          _ParaRow(
            label: t.transferFrom,
            para: _from,
            locked: vendeur && _send,
            onTap: () => _choose(isFrom: true, partners: partners),
          ),
          const Gap(8),
          _ParaRow(
            label: t.transferTo,
            para: _to,
            locked: vendeur && !_send,
            onTap: () => _choose(isFrom: false, partners: partners),
          ),
          if (vendeur)
            partners!.when(
              data: (p) => p.groupName == null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        t.transferNoGroup,
                        style: context.text.bodyMedium?.copyWith(
                          color: context.status.warning,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          const Gap(20),
          Text(t.transferProducts, style: context.text.labelLarge),
          const Gap(8),
          QuantityEditor(controller: _items),
          const Gap(20),
          if (!_admin) ...[
            PhotoField(
              label: t.transferPhotoLabel,
              onChanged: (id) => setState(() => _photoId = id),
            ),
            const Gap(16),
          ],
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
              label: _admin ? t.transferSubmitNow : t.transferSubmit,
              onPressed: _valid ? _submit : null,
            ),
          ),
        ],
      ),
    );
  }

  /// The para to pick for one side: a responsable or the admin starts from any grouped para of their scope.
  Future<void> _choose({
    required bool isFrom,
    required AsyncValue<Partners>? partners,
  }) async {
    final me = ref.read(meProvider);
    final vendeur = me.role == Role.vendeur;
    List<TransferPara> options;
    final otherIsFixed = vendeur;
    if (otherIsFixed || !isFrom) {
      // The side that depends on the group of the first one (or the team member's partners).
      if (partners == null) return;
      final p = partners.value;
      if (p == null || p.paras.isEmpty) {
        if (mounted && p != null) {
          showMessage(context, AppLocalizations.of(context).transferNoPartners);
        }
        return;
      }
      options = p.paras;
    } else {
      final pdvs = await ref.read(pdvsProvider(null).future);
      options = [
        for (final p in pdvs)
          if (p.status == ItemStatus.active && p.groupId != null)
            TransferPara(id: p.id, name: p.name, city: p.groupName ?? p.city),
      ];
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<TransferPara>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ParaSheet(options: options),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        if (_from?.id != picked.id) _to = null;
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }
}

class _ParaRow extends StatelessWidget {
  const _ParaRow({
    required this.label,
    required this.para,
    required this.locked,
    required this.onTap,
  });

  final String label;
  final TransferPara? para;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppCard(
      onTap: locked ? null : onTap,
      child: Row(
        spacing: 12,
        children: [
          SizedBox(
            width: 44,
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
          if (!locked)
            const Icon(LucideIcons.chevronRight, size: 18)
          else
            Icon(LucideIcons.lock, size: 16, color: context.status.muted),
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
