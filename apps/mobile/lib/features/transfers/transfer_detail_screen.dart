import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/quantity_editor.dart';
import '../../l10n/app_localizations.dart';
import '../media/proof_thumb.dart';
import 'transfer_models.dart';
import 'transfer_widgets.dart';
import 'transfers_repository.dart';

/// One transfer: who, what, the photo, the changes, and what the person may do now.
class TransferDetailScreen extends ConsumerWidget {
  const TransferDetailScreen({required this.transferId, super.key});

  final String transferId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final transfer = ref.watch(transferProvider(transferId));
    return Scaffold(
      appBar: AppBar(title: Text(transfer.value?.number ?? t.transfersTitle)),
      body: AsyncBody<Transfer>(
        value: transfer,
        onRetry: () => ref.invalidate(transferProvider(transferId)),
        builder: (x) => _Body(transfer: x),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.transfer});

  final Transfer transfer;

  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(transferProvider(transfer.id))
      ..invalidate(transfersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final locale = t.localeName;
    final x = transfer;
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
                  const IconBadge(LucideIcons.arrowLeftRight),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${x.from.name} → ${x.to.name}',
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
                  StatusChip(
                    t.transferGroupName(x.groupName),
                    icon: LucideIcons.layers,
                  ),
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
        if (x.photoId != null) ...[
          SectionHeader(t.photo),
          GestureDetector(
            onTap: () => context.push('/photo/${x.photoId}'),
            child: ProofThumb(
              x.photoId!,
              width: MediaQuery.sizeOf(context).width - 32,
              height: 220,
            ),
          ),
        ],
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
        if (x.canEdit && !x.canDecide) ..._participantActions(context, ref),
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
            () => ref.read(transfersRepositoryProvider).approve(transfer.id),
            success: t.transferApproved,
          );
          if (ok) _refresh(ref);
        },
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
            () =>
                ref.read(transfersRepositoryProvider).reject(transfer.id, note),
            success: t.transferRejected,
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

  List<Widget> _participantActions(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return [
      OutlinedButton.icon(
        onPressed: () => _edit(context, ref, approve: false),
        icon: const Icon(LucideIcons.pencil),
        label: Text(t.transferEdit),
      ),
      if (transfer.canCancel)
        TextButton.icon(
          onPressed: () async {
            if (!await confirm(
              context,
              title: t.transferCancelAsk,
              confirmLabel: t.transferCancel,
              destructive: true,
            )) {
              return;
            }
            if (!context.mounted) return;
            final ok = await perform(
              context,
              () => ref.read(transfersRepositoryProvider).cancel(transfer.id),
              success: t.transferCancelled,
            );
            if (ok) _refresh(ref);
          },
          icon: Icon(LucideIcons.x, color: context.status.danger),
          label: Text(
            t.transferCancel,
            style: TextStyle(color: context.status.danger),
          ),
        ),
    ];
  }

  /// Change the quantities (a para, the responsable) or correct them while approving (the admin).
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    required bool approve,
  }) async {
    final t = AppLocalizations.of(context);
    final controller = QuantityController([
      for (final l in transfer.lines)
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
      builder: (context) => _LinesSheet(
        controller: controller,
        title: approve ? t.transferApproveChange : t.transferEdit,
      ),
    );
    controller.dispose();
    if (lines == null || !context.mounted) return;
    final repo = ref.read(transfersRepositoryProvider);
    final ok = await perform(
      context,
      () => approve
          ? repo.approve(transfer.id, lines: lines)
          : repo.edit(transfer.id, lines),
      success: approve ? t.transferApproved : t.transferEdited,
    );
    if (ok) _refresh(ref);
  }
}

class _LinesSheet extends StatelessWidget {
  const _LinesSheet({required this.controller, required this.title});

  final QuantityController controller;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
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
          Text(title, style: context.text.titleLarge),
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
                  ? () =>
                        Navigator.pop(context, controller.lines(skipZero: true))
                  : null,
              child: Text(t.save),
            ),
          ),
        ],
      ),
    );
  }
}
