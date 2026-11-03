import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/quantity_editor.dart';
import '../../l10n/app_localizations.dart';
import '../network/network_models.dart';
import '../network/network_repository.dart';
import '../transfers/transfer_models.dart';
import '../transfers/transfer_widgets.dart';
import 'return_models.dart';
import 'returns_repository.dart';
import 'returns_screen.dart' show actionLabel;

/// One return: the para, the quantities, what changed, and what the person may do now.
class ReturnDetailScreen extends ConsumerWidget {
  const ReturnDetailScreen({required this.returnId, super.key});

  final String returnId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final item = ref.watch(returnProvider(returnId));
    return Scaffold(
      appBar: AppBar(title: Text(item.value?.number ?? t.returnsTitle)),
      body: AsyncBody<StockReturn>(
        value: item,
        onRetry: () => ref.invalidate(returnProvider(returnId)),
        builder: (x) => _Body(item: x),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.item});

  final StockReturn item;

  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(returnProvider(item.id))
      ..invalidate(returnsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final locale = t.localeName;
    final x = item;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Row(
                children: [
                  const IconBadge(LucideIcons.undo2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      x.action == ReturnAction.move
                          ? '${x.para.name} → ${x.to?.name ?? ''}'
                          : x.para.name,
                      style: context.text.titleMedium,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  StatusChip(x.status.label(t), tone: x.status.tone),
                  StatusChip(actionLabel(t, x), tone: Tone.info),
                ],
              ),
              InfoRow(
                t.byName(x.createdBy),
                Dates.dateTime(x.createdAt, locale),
              ),
              if (x.note != null && x.note!.isNotEmpty)
                InfoRow(t.note, x.note!),
              if (x.pending && x.expiresAt != null)
                Text(
                  t.transferExpires(Dates.full(x.expiresAt!, locale)),
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              if (x.decidedBy != null && x.decidedAt != null)
                InfoRow(
                  x.decidedBy!,
                  '${x.status.label(t)} · ${Dates.dateTime(x.decidedAt!, locale)}',
                ),
              if (x.decisionNote != null && x.decisionNote!.isNotEmpty)
                InfoRow(t.note, x.decisionNote!),
            ],
          ),
        ),
        SectionHeader(t.transferProducts),
        AppCard(
          child: Column(
            children: [
              for (final l in x.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.name, style: context.text.bodyLarge),
                            if (l.changed)
                              Text(
                                t.transferAsked(l.requestedQuantity),
                                style: context.text.bodySmall?.copyWith(
                                  color: context.status.warning,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '× ${l.quantity}',
                        style: context.text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (x.changes.isNotEmpty) ...[
          SectionHeader(t.transferChanges),
          for (final c in x.changes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(LucideIcons.pencilLine, color: context.status.info),
              title: Text(t.transferChangedBy(c.by)),
              subtitle: Text(Dates.dateTime(c.at, locale)),
            ),
        ],
        const Gap(20),
        if (x.canDecide) ..._adminActions(context, ref),
        if (x.canEdit && !x.canDecide) ..._askerActions(context, ref),
      ],
    );
  }

  List<Widget> _adminActions(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return [
      AsyncButton(
        label: t.transferApprove,
        icon: LucideIcons.check,
        onPressed: () async {
          final ok = await perform(
            context,
            () => ref.read(returnsRepositoryProvider).approve(item.id),
            success: t.returnDone,
          );
          if (ok) _refresh(ref);
        },
      ),
      const Gap(8),
      OutlinedButton.icon(
        onPressed: () => _approveMoving(context, ref),
        icon: const Icon(LucideIcons.arrowLeftRight),
        label: Text(t.returnApproveMove),
      ),
      const Gap(8),
      OutlinedButton.icon(
        onPressed: () => _edit(context, ref, approve: true),
        icon: const Icon(LucideIcons.pencil),
        label: Text(t.transferApproveChange),
      ),
      TextButton.icon(
        onPressed: () async {
          final note = await askNote(
            context,
            title: t.transferRejectTitle,
            confirmLabel: t.transferReject,
          );
          if (note == null || !context.mounted) return;
          final ok = await perform(
            context,
            () => ref.read(returnsRepositoryProvider).reject(item.id, note),
            success: t.returnRejected,
          );
          if (ok) _refresh(ref);
        },
        icon: Icon(LucideIcons.x, color: context.status.danger),
        label: Text(
          t.transferReject,
          style: TextStyle(color: context.status.danger),
        ),
      ),
    ];
  }

  List<Widget> _askerActions(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return [
      OutlinedButton.icon(
        onPressed: () => _edit(context, ref, approve: false),
        icon: const Icon(LucideIcons.pencil),
        label: Text(t.transferEdit),
      ),
      if (item.canCancel)
        TextButton.icon(
          onPressed: () async {
            if (!await confirm(
              context,
              title: t.returnCancelAsk,
              confirmLabel: t.returnCancel,
              destructive: true,
            )) {
              return;
            }
            if (!context.mounted) return;
            final ok = await perform(
              context,
              () => ref.read(returnsRepositoryProvider).cancel(item.id),
              success: t.returnCancelled,
            );
            if (ok) _refresh(ref);
          },
          icon: Icon(LucideIcons.x, color: context.status.danger),
          label: Text(
            t.returnCancel,
            style: TextStyle(color: context.status.danger),
          ),
        ),
    ];
  }

  /// Approve, but put the quantities into another para instead of only taking them out.
  Future<void> _approveMoving(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final pdvs = await ref.read(pdvsProvider(null).future);
    if (!context.mounted) return;
    final options = [
      for (final p in pdvs)
        if (p.status == ItemStatus.active && p.id != item.para.id)
          TransferPara(
            id: p.id,
            name: p.name,
            address: p.address,
            city: p.city,
          ),
    ];
    final to = await showModalBottomSheet<TransferPara>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(t.returnApproveMove, style: context.text.titleLarge),
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
      ),
    );
    if (to == null || !context.mounted) return;
    final ok = await perform(
      context,
      () =>
          ref.read(returnsRepositoryProvider).approve(item.id, toPdvId: to.id),
      success: t.returnDone,
    );
    if (ok) _refresh(ref);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    required bool approve,
  }) async {
    final t = AppLocalizations.of(context);
    final controller = QuantityController([
      for (final l in item.lines)
        QuantityItem(
          productId: l.productId,
          name: l.name,
          family: l.family,
          quantity: l.quantity,
        ),
    ]);
    final lines = await showModalBottomSheet<List<Map<String, Object>>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              approve ? t.transferApproveChange : t.transferEdit,
              style: context.text.titleLarge,
            ),
            const Gap(12),
            Flexible(
              child: SingleChildScrollView(
                child: QuantityEditor(controller: controller),
              ),
            ),
            const Gap(12),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => FilledButton(
                onPressed: controller.total > 0
                    ? () => Navigator.pop(
                        context,
                        controller.lines(skipZero: true),
                      )
                    : null,
                child: Text(t.save),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (lines == null || !context.mounted) return;
    final repo = ref.read(returnsRepositoryProvider);
    final ok = await perform(
      context,
      () => approve
          ? repo.approve(item.id, lines: lines)
          : repo.edit(item.id, lines),
      success: approve ? t.returnDone : t.transferEdited,
    );
    if (ok) _refresh(ref);
  }
}
