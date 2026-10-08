import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/util/money.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/paged_list.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../network/network_repository.dart';
import '../stock/stock_repository.dart';
import '../wallet/wallet_repository.dart';
import 'approvals_repository.dart';

/// The admin's inbox: everything waiting for a decision, from every region, in one place.
class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen> {
  ApprovalType? _type;
  String? _regionId;
  bool _history = false;

  void _reload() {
    ref.invalidate(approvalsProvider);
    ref.invalidate(pdvsProvider);
    ref.invalidate(groupsProvider);
    ref.invalidate(peopleProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final regions = ref.watch(regionsProvider).value ?? const [];
    final data = ref.watch(approvalsProvider(_regionId));
    return Scaffold(
      appBar: AppBar(title: Text(t.approvalsTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(
                    '${t.pendingTab}${(data.value?.total ?? 0) > 0 ? ' ${data.value!.total}' : ''}',
                  ),
                ),
                ButtonSegment(value: true, label: Text(t.historyTab)),
              ],
              selected: {_history},
              onSelectionChanged: (s) => setState(() => _history = s.first),
            ),
          ),
          if (_history)
            Expanded(child: _History(key: ValueKey(_type)))
          else ...[
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(t.allRegions),
                      selected: _regionId == null,
                      onSelected: (_) => setState(() => _regionId = null),
                    ),
                  ),
                  for (final r in regions)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(r.name),
                        selected: _regionId == r.id,
                        onSelected: (_) => setState(() => _regionId = r.id),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text('${t.all} ${data.value?.total ?? ''}'.trim()),
                      selected: _type == null,
                      onSelected: (_) => setState(() => _type = null),
                    ),
                  ),
                  for (final type in ApprovalType.values)
                    if ((data.value?.counts[type] ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(
                            '${_typeLabel(t, type)} ${data.value!.counts[type]}',
                          ),
                          selected: _type == type,
                          onSelected: (_) => setState(
                            () => _type = _type == type ? null : type,
                          ),
                        ),
                      ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  _reload();
                  await ref.read(approvalsProvider(_regionId).future);
                },
                child: AsyncBody(
                  value: data,
                  onRetry: _reload,
                  builder: (a) {
                    final items = a.items
                        .where((i) => _type == null || i.type == _type)
                        .toList();
                    if (items.isEmpty)
                      return ListView(
                        children: [
                          EmptyState(
                            icon: LucideIcons.circleCheck,
                            title: t.nothingToApprove,
                            message: t.allCaughtUp,
                          ),
                        ],
                      );
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Gap(8),
                      itemBuilder: (context, i) =>
                          _ApprovalTile(item: items[i], onDone: _reload),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _typeLabel(AppLocalizations t, ApprovalType type) => switch (type) {
  ApprovalType.group => t.typeGroup,
  ApprovalType.pdv => t.typePdv,
  ApprovalType.member => t.typeMember,
  ApprovalType.stock => t.typeStock,
  ApprovalType.receipt => t.typeReceipt,
  ApprovalType.restockRequest => t.typeRestockRequest,
  ApprovalType.payout => t.typePayout,
  ApprovalType.recount => t.typeRecount,
};

IconData _typeIcon(ApprovalType type) => switch (type) {
  ApprovalType.group => LucideIcons.layers,
  ApprovalType.pdv => LucideIcons.store,
  ApprovalType.member => LucideIcons.userRound,
  ApprovalType.stock => LucideIcons.boxes,
  ApprovalType.receipt => LucideIcons.packageCheck,
  ApprovalType.restockRequest => LucideIcons.truck,
  ApprovalType.payout => LucideIcons.banknote,
  ApprovalType.recount => LucideIcons.rotateCcw,
};

class _ApprovalTile extends ConsumerWidget {
  const _ApprovalTile({required this.item, required this.onDone});

  final ApprovalItem item;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final subtitle = <String>[
      if (item.by != null) t.byName(item.by!),
      if (item.region != null) item.region!,
      switch (item.type) {
        ApprovalType.pdv => item.meta.str('city'),
        ApprovalType.member => item.meta.str('pdv'),
        ApprovalType.stock => t.units(item.meta.integer('units')),
        ApprovalType.receipt || ApprovalType.restockRequest =>
          '${item.meta.str('number')} · ${t.units(item.meta.integer('units'))}',
        ApprovalType.payout => Money.format(
          item.meta.integer('amountMillimes'),
          t.localeName,
        ),
        ApprovalType.group => '',
        ApprovalType.recount => item.meta.str('reason'),
      },
    ].where((s) => s.isNotEmpty).toList();
    return AppCard(
      onTap: () => _open(context, ref),
      child: Row(
        children: [
          IconBadge(_typeIcon(item.type), size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: context.text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _typeLabel(t, item.type),
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle.join(' · '),
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
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: context.status.muted),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    switch (item.type) {
      case ApprovalType.pdv:
        await context.push('/pdvs/${item.id}');
      case ApprovalType.stock:
        await context.push('/stock/declarations/${item.id}');
      case ApprovalType.receipt || ApprovalType.restockRequest:
        await context.push('/restocks/${item.id}');
      case ApprovalType.payout:
        await context.push('/payouts');
      case ApprovalType.recount:
        final approve = await showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.approveRecountTitle, style: context.text.titleMedium),
                  const Gap(6),
                  Text(
                    '${item.name} · ${item.by ?? ''}',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
                  const Gap(14),
                  Text(t.recountReasonLabel, style: context.text.labelMedium),
                  Text(item.meta.str('reason'), style: context.text.bodyLarge),
                  const Gap(20),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(t.allowRecount),
                  ),
                  const Gap(8),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(t.reject),
                  ),
                ],
              ),
            ),
          ),
        );
        if (approve == null || !context.mounted) return;
        String? note;
        if (!approve) {
          note = await askNote(
            context,
            title: t.rejectReasonTitle,
            confirmLabel: t.reject,
            hint: t.rejectReasonHint,
          );
          if (note == null || !context.mounted) return;
        }
        await perform(
          context,
          () => ref
              .read(stockRepositoryProvider)
              .decideRecount(item.id, approve: approve, note: note),
          success: approve ? t.approved : t.rejected,
        );
      case ApprovalType.group:
        final note = await confirm(
          context,
          title: t.approveGroupTitle(item.name),
          confirmLabel: t.approve,
        );
        if (!note || !context.mounted) return;
        await perform(
          context,
          () => ref
              .read(networkRepositoryProvider)
              .decideGroup(item.id, 'approve'),
          success: t.approved,
        );
      case ApprovalType.member:
        final people = await ref
            .read(networkRepositoryProvider)
            .people(status: 'PENDING');
        final person = people.where((p) => p.id == item.id).firstOrNull;
        if (person == null || !context.mounted) return;
        await context.push('/people/${person.id}', extra: person);
    }
    onDone();
    ref.invalidate(myPayoutsProvider);
  }
}

/// What was decided before: date, who decided, the outcome and the reason.
class _History extends ConsumerStatefulWidget {
  const _History({super.key});

  @override
  ConsumerState<_History> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<_History> {
  ApprovalType? _type;
  late PagedController<HistoryItem> _paged = _make();

  PagedController<HistoryItem> _make() =>
      PagedController<HistoryItem>((cursor) async {
        final page = await fetchApprovalHistory(
          ref.read(apiClientProvider),
          before: cursor,
          type: _type,
        );
        return PageResult(page.items, page.next);
      });

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(t.all),
                  selected: _type == null,
                  onSelected: (_) => setState(() {
                    _type = null;
                    _paged.dispose();
                    _paged = _make();
                  }),
                ),
              ),
              for (final type in ApprovalType.values)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(_typeLabel(t, type)),
                    selected: _type == type,
                    onSelected: (_) => setState(() {
                      _type = _type == type ? null : type;
                      _paged.dispose();
                      _paged = _make();
                    }),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: PagedList<HistoryItem>(
            controller: _paged,
            empty: EmptyState(icon: LucideIcons.history, title: t.noHistoryYet),
            itemBuilder: (context, item, index) {
              final tone = switch (item.outcome) {
                'APPROVED' => Tone.success,
                'REJECTED' => Tone.danger,
                _ => Tone.muted,
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_typeIcon(item.type), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.name,
                              style: context.text.titleSmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          StatusChip(switch (item.outcome) {
                            'APPROVED' => t.statusApproved,
                            'REJECTED' => t.statusRejected,
                            _ => t.deactivated,
                          }, tone: tone),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_typeLabel(t, item.type)}${item.region != null ? ' · ${item.region}' : ''}',
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        [
                          Dates.dateTime(item.decidedAt, t.localeName),
                          if (item.decidedBy != null) t.byName(item.decidedBy!),
                        ].join(' · '),
                        style: context.text.bodySmall?.copyWith(
                          color: context.status.muted,
                        ),
                      ),
                      if (item.note != null && item.note!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('“${item.note}”', style: context.text.bodyMedium),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
