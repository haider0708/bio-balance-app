import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../transfers/transfer_widgets.dart';
import 'return_models.dart';
import 'returns_repository.dart';

String actionLabel(AppLocalizations t, StockReturn r) => switch (r.action) {
  ReturnAction.remove => t.returnTakenOut,
  ReturnAction.move => t.returnMovedTo(r.to?.name ?? ''),
  ReturnAction.add => t.returnAdded,
};

/// The returns a person may see: what waits for the admin, and what was decided.
class ReturnsScreen extends ConsumerStatefulWidget {
  const ReturnsScreen({super.key});

  @override
  ConsumerState<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends ConsumerState<ReturnsScreen> {
  bool _waiting = true;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final returns = ref.watch(returnsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.returnsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () async {
          await context.push('/returns/new');
          ref.invalidate(returnsProvider);
        },
        icon: const Icon(LucideIcons.plus),
        label: Text(t.returnNew),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(returnsProvider);
          await ref.read(returnsProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(t.transferWaitingTab),
                  selected: _waiting,
                  onSelected: (_) => setState(() => _waiting = true),
                ),
                ChoiceChip(
                  label: Text(t.transferDecidedTab),
                  selected: !_waiting,
                  onSelected: (_) => setState(() => _waiting = false),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AsyncBody<List<StockReturn>>(
              value: returns,
              onRetry: () => ref.invalidate(returnsProvider),
              builder: (all) {
                final shown = all.where((x) => x.pending == _waiting).toList();
                if (shown.isEmpty) {
                  return EmptyState(
                    icon: LucideIcons.undo2,
                    title: t.returnNone,
                    message: t.returnNoneHint,
                  );
                }
                return Column(
                  spacing: 12,
                  children: [
                    for (final x in shown)
                      _ReturnCard(
                        item: x,
                        onTap: () async {
                          await context.push('/returns/${x.id}');
                          ref.invalidate(returnsProvider);
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReturnCard extends StatelessWidget {
  const _ReturnCard({required this.item, required this.onTap});

  final StockReturn item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          const IconBadge(LucideIcons.undo2, size: 44),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  item.action == ReturnAction.move
                      ? '${item.para.name} → ${item.to?.name ?? ''}'
                      : item.para.name,
                  style: context.text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${item.number} · ${t.units(item.units)} · ${t.byName(item.createdBy)}',
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
                Text(
                  Dates.dateTime(item.createdAt, t.localeName),
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusChip(item.status.label(t), tone: item.status.tone),
                    if (item.action != ReturnAction.remove)
                      StatusChip(actionLabel(t, item), tone: Tone.info),
                  ],
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: context.status.muted),
        ],
      ),
    );
  }
}
