import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/me.dart' show Region;
import '../../core/theme/app_theme.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/dashboard_repository.dart';
import '../stock/stock_repository.dart';
import 'network_models.dart';
import 'network_repository.dart';

/// Everything that shows a region's content is stale after a move: refresh it all.
void refreshAfterMove(WidgetRef ref) {
  ref
    ..invalidate(regionsOverviewProvider)
    ..invalidate(regionsProvider)
    ..invalidate(pdvsProvider)
    ..invalidate(pdvProvider)
    ..invalidate(groupsProvider)
    ..invalidate(depotsProvider)
    ..invalidate(depotProvider)
    ..invalidate(peopleProvider)
    ..invalidate(dashboardProvider)
    ..invalidate(stockLevelsProvider);
}

/// The region (and, for a store, the group of that region) a thing is moved to.
typedef MoveTarget = ({String regionId, String? groupId});

/// Ask where to move something: a region other than [currentRegionId], and for a store an
/// optional group of the new region. Returns null when dismissed.
Future<MoveTarget?> askMoveTarget(
  BuildContext context, {
  required String title,
  required String hint,
  required String currentRegionId,
  bool askGroup = false,
}) => showModalBottomSheet<MoveTarget>(
  context: context,
  isScrollControlled: true,
  builder: (context) => _MoveSheet(
    title: title,
    hint: hint,
    currentRegionId: currentRegionId,
    askGroup: askGroup,
  ),
);

class _MoveSheet extends ConsumerStatefulWidget {
  const _MoveSheet({
    required this.title,
    required this.hint,
    required this.currentRegionId,
    required this.askGroup,
  });

  final String title;
  final String hint;
  final String currentRegionId;
  final bool askGroup;

  @override
  ConsumerState<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends ConsumerState<_MoveSheet> {
  String? _regionId;
  String? _groupId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final regions = (ref.watch(regionsProvider).value ?? const <Region>[])
        .where((r) => r.id != widget.currentRegionId)
        .toList();
    final groups = widget.askGroup && _regionId != null
        ? (ref.watch(groupsProvider(_regionId)).value ?? const <Group>[])
        : const <Group>[];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: context.text.titleLarge),
          const Gap(6),
          Text(
            widget.hint,
            style: context.text.bodyMedium?.copyWith(
              color: context.status.muted,
            ),
          ),
          const Gap(16),
          DropdownButtonFormField<String>(
            initialValue: _regionId,
            decoration: InputDecoration(labelText: t.moveChooseRegion),
            items: [
              for (final r in regions)
                DropdownMenuItem(value: r.id, child: Text(r.name)),
            ],
            onChanged: (v) => setState(() {
              _regionId = v;
              _groupId = null;
            }),
          ),
          if (widget.askGroup && _regionId != null) ...[
            const Gap(12),
            DropdownButtonFormField<String?>(
              initialValue: _groupId,
              decoration: InputDecoration(labelText: t.moveGroupInNewRegion),
              items: [
                DropdownMenuItem(child: Text(t.moveNoGroup)),
                for (final g in groups)
                  DropdownMenuItem(value: g.id, child: Text(g.name)),
              ],
              onChanged: (v) => setState(() => _groupId = v),
            ),
          ],
          const Gap(20),
          FilledButton.icon(
            onPressed: _regionId == null
                ? null
                : () => Navigator.pop(context, (
                    regionId: _regionId!,
                    groupId: _groupId,
                  )),
            icon: const Icon(LucideIcons.moveRight),
            label: Text(t.moveHere),
          ),
        ],
      ),
    );
  }
}

/// Run a move; on success say so and refresh everything. Returns whether it happened.
Future<bool> _run(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() move,
) async {
  final t = AppLocalizations.of(context);
  final ok = await perform(context, move, success: t.moveDone);
  if (ok) refreshAfterMove(ref);
  return ok;
}

Future<bool> movePdvFlow(BuildContext context, WidgetRef ref, Pdv pdv) async {
  final t = AppLocalizations.of(context);
  final target = await askMoveTarget(
    context,
    title: t.moveStoreTitle(pdv.name),
    hint: t.moveStoreHint,
    currentRegionId: pdv.regionId,
    askGroup: true,
  );
  if (target == null || !context.mounted) return false;
  return _run(
    context,
    ref,
    () => ref
        .read(networkRepositoryProvider)
        .movePdv(pdv.id, target.regionId, groupId: target.groupId),
  );
}

Future<bool> moveGroupFlow(
  BuildContext context,
  WidgetRef ref,
  Group group,
) async {
  final t = AppLocalizations.of(context);
  final target = await askMoveTarget(
    context,
    title: t.moveStoreTitle(group.name),
    hint: t.moveGroupHint,
    currentRegionId: group.regionId,
  );
  if (target == null || !context.mounted) return false;
  return _run(
    context,
    ref,
    () => ref
        .read(networkRepositoryProvider)
        .moveGroup(group.id, target.regionId),
  );
}

Future<bool> moveDepotFlow(
  BuildContext context,
  WidgetRef ref,
  Depot depot,
) async {
  final t = AppLocalizations.of(context);
  final target = await askMoveTarget(
    context,
    title: t.moveStoreTitle(depot.name),
    hint: t.moveDepotHint,
    currentRegionId: depot.regionId,
  );
  if (target == null || !context.mounted) return false;
  return _run(
    context,
    ref,
    () => ref
        .read(networkRepositoryProvider)
        .moveDepot(depot.id, target.regionId),
  );
}

/// Move a responsable to [regionId]. A region has one responsable: when it is taken, the admin is
/// asked to swap the two, and the swap is only done after they agree.
Future<bool> moveResponsableTo(
  BuildContext context,
  WidgetRef ref,
  Person responsable,
  String regionId,
) async {
  final t = AppLocalizations.of(context);
  final repo = ref.read(networkRepositoryProvider);
  try {
    await repo.moveResponsable(responsable.id, regionId);
  } on ApiException catch (error) {
    if (error.code != 'REGION_HAS_RESPONSABLE') {
      if (context.mounted) showError(context, error);
      return false;
    }
    final regions = await ref.read(regionsOverviewProvider.future);
    final target = regions.where((r) => r.id == regionId).firstOrNull;
    final from = regions.where((r) => r.id == responsable.regionId).firstOrNull;
    final other = target?.responsable;
    if (!context.mounted || target == null || from == null || other == null) {
      return false;
    }
    final yes = await confirm(
      context,
      title: t.moveSwapTitle,
      message:
          '${t.moveSwapBody(responsable.name, other.name, target.name, from.name)}\n${t.moveResponsableHint}',
      confirmLabel: t.moveSwap,
    );
    if (!yes || !context.mounted) return false;
    return _run(
      context,
      ref,
      () => repo.moveResponsable(responsable.id, regionId, swap: true),
    );
  }
  if (context.mounted) showMessage(context, t.moveDone);
  refreshAfterMove(ref);
  return true;
}

/// From a responsable's page: choose the region they go to.
Future<bool> moveResponsableFlow(
  BuildContext context,
  WidgetRef ref,
  Person responsable,
) async {
  final t = AppLocalizations.of(context);
  final target = await askMoveTarget(
    context,
    title: t.moveStoreTitle(responsable.name),
    hint: t.moveResponsableHint,
    currentRegionId: responsable.regionId ?? '',
  );
  if (target == null || !context.mounted) return false;
  return moveResponsableTo(context, ref, responsable, target.regionId);
}
