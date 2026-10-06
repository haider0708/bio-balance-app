import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../shared/status_chips.dart';
import 'network_models.dart';
import 'network_repository.dart';
import 'people_widgets.dart';

/// The network: points of sale, groups and people. A responsable sees their region; the admin picks one.
class NetworkScreen extends ConsumerStatefulWidget {
  const NetworkScreen({super.key});

  @override
  ConsumerState<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends ConsumerState<NetworkScreen> {
  String? _regionId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final admin = me.role == Role.admin;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            admin ? t.networkTitle : t.myRegion(me.region?.name ?? ''),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: t.tabPdvs),
              Tab(text: t.tabGroups),
              Tab(text: t.tabPeople),
            ],
          ),
        ),
        floatingActionButton: _fab(context, me),
        body: Column(
          children: [
            if (admin)
              _RegionFilter(
                selected: _regionId,
                onChanged: (id) => setState(() => _regionId = id),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _PdvList(regionId: _regionId),
                  _GroupList(regionId: _regionId),
                  PeopleList(regionId: _regionId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _fab(BuildContext context, Me me) {
    final t = AppLocalizations.of(context);
    if (me.role == Role.responsable) {
      return Builder(
        builder: (context) => FloatingActionButton.extended(
          heroTag: null,
          onPressed: () =>
              _addForTab(context, DefaultTabController.of(context).index),
          icon: const Icon(LucideIcons.plus),
          label: Text(t.add),
        ),
      );
    }
    if (me.role == Role.admin) {
      return Builder(
        builder: (context) => FloatingActionButton.extended(
          heroTag: null,
          onPressed: () async {
            await context.push('/people/new');
            ref.invalidate(peopleProvider);
          },
          icon: const Icon(LucideIcons.userPlus),
          label: Text(t.newAccount),
        ),
      );
    }
    return null;
  }

  Future<void> _addForTab(BuildContext context, int tab) async {
    final t = AppLocalizations.of(context);
    switch (tab) {
      case 1:
        await _newGroup(context);
      case 2:
        showMessage(context, t.addMemberFromPdv);
      default:
        await context.push<void>('/pdvs/new');
    }
    ref.invalidate(pdvsProvider);
    ref.invalidate(groupsProvider);
  }

  Future<void> _newGroup(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final name = await askText(
      context,
      title: t.newGroup,
      label: t.groupName,
      confirmLabel: t.create,
    );
    if (name == null || !context.mounted) return;
    await perform(
      context,
      () => ref.read(networkRepositoryProvider).createGroup(name),
      success: t.groupCreated,
    );
  }
}

class _RegionFilter extends ConsumerWidget {
  const _RegionFilter({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final regions = ref.watch(regionsProvider).value ?? const [];
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: ChoiceChip(
              label: Text(t.allRegions),
              selected: selected == null,
              onSelected: (_) => onChanged(null),
            ),
          ),
          for (final r in regions)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(r.name),
                selected: selected == r.id,
                onSelected: (_) => onChanged(r.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _PdvList extends ConsumerWidget {
  const _PdvList({required this.regionId});

  final String? regionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final pdvs = ref.watch(pdvsProvider(regionId));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(pdvsProvider(regionId));
        await ref.read(pdvsProvider(regionId).future);
      },
      child: AsyncBody(
        value: pdvs,
        onRetry: () => ref.invalidate(pdvsProvider(regionId)),
        isEmpty: (l) => l.isEmpty,
        empty: ListView(
          children: [
            EmptyState(
              icon: LucideIcons.store,
              title: t.noPdvs,
              message: me.role == Role.responsable ? t.noPdvsHint : null,
            ),
          ],
        ),
        builder: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Gap(8),
          itemBuilder: (context, i) => PdvTile(pdv: list[i]),
        ),
      ),
    );
  }
}

class PdvTile extends StatelessWidget {
  const PdvTile({required this.pdv, super.key});

  final Pdv pdv;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppCard(
      onTap: () => context.push('/pdvs/${pdv.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(pdv.name, style: context.text.titleMedium)),
              ItemStatusChip(pdv.status),
            ],
          ),
          const Gap(4),
          Text(
            [pdv.city, if (pdv.groupName != null) pdv.groupName!].join(' · '),
            style: context.text.bodySmall?.copyWith(
              color: context.status.muted,
            ),
          ),
          const Gap(10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusChip(
                t.teamCount(pdv.memberCount),
                tone: Tone.muted,
                icon: LucideIcons.users,
              ),
              StatusChip(
                switch (pdv.initialStock) {
                  'APPROVED' => t.stockApproved,
                  'PENDING' => t.stockWaiting,
                  'REJECTED' => t.stockRejected,
                  _ => t.stockMissing,
                },
                tone: switch (pdv.initialStock) {
                  'APPROVED' => Tone.success,
                  'PENDING' => Tone.warning,
                  'REJECTED' => Tone.danger,
                  _ => Tone.muted,
                },
                icon: LucideIcons.boxes,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupList extends ConsumerWidget {
  const _GroupList({required this.regionId});

  final String? regionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final groups = ref.watch(groupsProvider(regionId));
    return AsyncBody(
      value: groups,
      onRetry: () => ref.invalidate(groupsProvider(regionId)),
      isEmpty: (l) => l.isEmpty,
      empty: EmptyState(
        icon: LucideIcons.layers,
        title: t.noGroups,
        message: me.role == Role.responsable ? t.noGroupsHint : null,
      ),
      builder: (list) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: list.length,
        separatorBuilder: (_, _) => const Gap(8),
        itemBuilder: (context, i) {
          final g = list[i];
          return AppCard(
            child: Row(
              children: [
                const Icon(LucideIcons.layers),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.name, style: context.text.titleSmall),
                      Text(
                        t.pdvCount(g.pdvCount),
                        style: context.text.bodySmall?.copyWith(
                          color: context.status.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                ItemStatusChip(g.status),
                if (me.role == Role.admin && g.status == ItemStatus.pending)
                  IconButton(
                    tooltip: t.approve,
                    icon: Icon(
                      LucideIcons.check,
                      color: context.status.success,
                    ),
                    onPressed: () async {
                      if (await perform(
                        context,
                        () => ref
                            .read(networkRepositoryProvider)
                            .decideGroup(g.id, 'approve'),
                        success: t.approved,
                      ))
                        ref.invalidate(groupsProvider);
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
