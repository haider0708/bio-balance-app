import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import 'network_models.dart';
import 'network_repository.dart';
import 'people_widgets.dart' show askText;
import 'region_moves.dart';

/// Rename a region (admin); true when it was saved.
Future<bool> renameRegionFlow(
  BuildContext context,
  WidgetRef ref,
  String id,
  String current,
) async {
  final t = AppLocalizations.of(context);
  final name = await askText(
    context,
    title: t.regionRename,
    label: t.regionName,
    confirmLabel: t.save,
    initial: current,
  );
  if (name == null || !context.mounted) return false;
  final ok = await perform(
    context,
    () => ref.read(networkRepositoryProvider).renameRegion(id, name),
    success: t.regionSaved,
  );
  if (ok) refreshAfterMove(ref);
  return ok;
}

/// Delete an empty region (admin); true when it is gone.
Future<bool> deleteRegionFlow(
  BuildContext context,
  WidgetRef ref,
  RegionInfo region,
) async {
  final t = AppLocalizations.of(context);
  final yes = await confirm(
    context,
    title: t.regionDeleteTitle(region.name),
    message: t.regionDeleteBody,
    confirmLabel: t.regionDelete,
    destructive: true,
  );
  if (!yes || !context.mounted) return false;
  final ok = await perform(
    context,
    () => ref.read(networkRepositoryProvider).deleteRegion(region.id),
    success: t.regionDeleted,
  );
  if (ok) refreshAfterMove(ref);
  return ok;
}

/// The regions of the network: who looks after each and what it holds. The admin names them,
/// adds and deletes them (only when empty), and opens one to change its responsable.
class RegionsScreen extends ConsumerWidget {
  const RegionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final regions = ref.watch(regionsOverviewProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.regions)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () async {
          final name = await askText(
            context,
            title: t.regionNew,
            label: t.regionName,
            confirmLabel: t.save,
          );
          if (name == null || !context.mounted) return;
          if (await perform(
            context,
            () => ref.read(networkRepositoryProvider).createRegion(name),
            success: t.regionSaved,
          )) {
            refreshAfterMove(ref);
          }
        },
        icon: const Icon(LucideIcons.plus),
        label: Text(t.regionNew),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(regionsOverviewProvider);
          await ref.read(regionsOverviewProvider.future);
        },
        child: AsyncBody(
          value: regions,
          onRetry: () => ref.invalidate(regionsOverviewProvider),
          isEmpty: (l) => l.isEmpty,
          empty: ListView(
            children: [
              EmptyState(
                icon: LucideIcons.map,
                title: t.regionNoneYet,
                message: t.regionNoneYetHint,
              ),
            ],
          ),
          builder: (list) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              AutoGrid(
                minItemWidth: 320,
                maxColumns: 3,
                spacing: 12,
                children: [for (final r in list) _RegionCard(region: r)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionCard extends ConsumerWidget {
  const _RegionCard({required this.region});

  final RegionInfo region;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final boss = region.responsable;
    return AppCard(
      onTap: () => context.push('/regions/${region.id}', extra: region.name),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(LucideIcons.mapPin),
              const SizedBox(width: 12),
              Expanded(
                child: Text(region.name, style: context.text.titleMedium),
              ),
              PopupMenuButton<String>(
                tooltip: '',
                onSelected: (action) async {
                  if (action == 'rename') {
                    await renameRegionFlow(
                      context,
                      ref,
                      region.id,
                      region.name,
                    );
                  } else if (action == 'delete') {
                    await deleteRegionFlow(context, ref, region);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'rename', child: Text(t.regionRename)),
                  if (region.deletable)
                    PopupMenuItem(value: 'delete', child: Text(t.regionDelete)),
                ],
              ),
            ],
          ),
          const Gap(12),
          Row(
            children: [
              if (boss != null) ...[
                Avatar(boss.initials, size: 28),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  boss?.name ?? t.regionNoResponsable,
                  style: context.text.bodyMedium?.copyWith(
                    color: boss == null ? context.status.warning : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const Gap(8),
          Text(
            t.regionHolds(region.pdvs, region.groups, region.grossistes),
            style: context.text.bodySmall?.copyWith(
              color: context.status.muted,
            ),
          ),
          if (region.deletable) ...[
            const Gap(8),
            StatusChip(t.regionEmpty, tone: Tone.muted),
          ],
        ],
      ),
    );
  }
}
