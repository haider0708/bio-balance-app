import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/amend_sheet.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/photo_set.dart';
import '../../core/widgets/quantity_editor.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../approvals/approvals_repository.dart';
import '../media/media_repository.dart';
import '../shared/status_chips.dart';
import 'stock_models.dart';
import 'stock_repository.dart';

/// What a place holds. A responsable opens it for a point of sale, a grossiste for the depot.
class StockScreen extends ConsumerWidget {
  const StockScreen({
    required this.locationId,
    this.title,
    this.embedded = false,
    super.key,
  });

  final String locationId;
  final String? title;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final levels = ref.watch(stockLevelsProvider(locationId));
    final declarations = ref.watch(declarationsProvider(locationId));
    final canDeclare = me.role == Role.responsable || me.role == Role.grossiste;
    final pending = declarations.value
        ?.where(
          (d) =>
              d.status == DeclarationStatus.pending ||
              d.status == DeclarationStatus.review,
        )
        .firstOrNull;
    final recounts = canDeclare
        ? (ref.watch(recountsProvider(locationId)).value ??
              const <RecountRequest>[])
        : const <RecountRequest>[];
    final allowed = recounts.any((r) => r.allowed);
    final asked = recounts.any((r) => r.waiting);
    // The stock is counted once: only a place with no count waiting or approved can declare.
    final counted =
        declarations.value?.any(
          (d) => d.status != DeclarationStatus.rejected,
        ) ??
        true;
    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? levels.value?.location.name ?? t.stockTitle),
      ),
      floatingActionButton:
          canDeclare && (!counted || (allowed && pending == null))
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () async {
                await context.push(
                  '/stock/$locationId/declare',
                  extra: levels.value?.location.name,
                );
                ref.invalidate(stockLevelsProvider(locationId));
                ref.invalidate(declarationsProvider(locationId));
              },
              icon: const Icon(LucideIcons.camera),
              label: Text(counted ? t.recountStock : t.declareStock),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(stockLevelsProvider(locationId));
          ref.invalidate(declarationsProvider(locationId));
          await ref.read(stockLevelsProvider(locationId).future);
        },
        child: AsyncBody(
          value: levels,
          onRetry: () => ref.invalidate(stockLevelsProvider(locationId)),
          builder: (data) {
            final recent =
                declarations.value?.take(3).toList() ??
                const <StockDeclaration>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (pending != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      color: context.status.warningSoft,
                      borderColor: Colors.transparent,
                      onTap: () =>
                          context.push('/stock/declarations/${pending.id}'),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.clock,
                            color: context.status.warning,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              pending.status == DeclarationStatus.review
                                  ? t.declarationWaitingResponsable
                                  : t.declarationWaiting,
                              style: context.text.bodyMedium?.copyWith(
                                color: context.status.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (canDeclare && counted && pending == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: asked
                        ? AppCard(
                            color: context.status.infoSoft,
                            borderColor: Colors.transparent,
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.clock,
                                  color: context.status.info,
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(t.recountAsked2)),
                              ],
                            ),
                          )
                        : allowed
                        ? AppCard(
                            color: context.status.successSoft,
                            borderColor: Colors.transparent,
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.circleCheck,
                                  color: context.status.success,
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(t.recountAllowed)),
                              ],
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: () async {
                              final reason = await askNote(
                                context,
                                title: t.recountRequestTitle,
                                confirmLabel: t.recountRequestSend,
                                hint: t.recountRequestHint,
                              );
                              if (reason == null || !context.mounted) return;
                              if (await perform(
                                context,
                                () => ref
                                    .read(stockRepositoryProvider)
                                    .requestRecount(locationId, reason),
                                success: t.recountRequested,
                              )) {
                                ref.invalidate(recountsProvider(locationId));
                              }
                            },
                            icon: const Icon(LucideIcons.rotateCcw),
                            label: Text(t.recountRequestTitle),
                          ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        icon: LucideIcons.boxes,
                        label: t.totalUnits,
                        value: '${data.units}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatTile(
                        icon: LucideIcons.package,
                        label: t.products,
                        value: '${data.items.length}',
                      ),
                    ),
                  ],
                ),
                const Gap(8),
                if (data.items.isEmpty)
                  EmptyState(
                    icon: LucideIcons.boxes,
                    title: t.noStockYet,
                    message: canDeclare ? t.noStockYetHint : null,
                  )
                else ...[
                  SectionHeader(t.stockLevels),
                  for (final item in data.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: StockTile(item: item),
                    ),
                ],
                if (recent.isNotEmpty) ...[
                  SectionHeader(t.declarations),
                  for (final d in recent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        onTap: () =>
                            context.push('/stock/declarations/${d.id}'),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.initial ? t.initialStock : t.recount,
                                    style: context.text.titleSmall,
                                  ),
                                  Text(
                                    '${Dates.dateTime(d.createdAt, t.localeName)} · ${t.units(d.units)}',
                                    style: context.text.bodySmall?.copyWith(
                                      color: context.status.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DeclarationStatusChip(d.status),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class StockTile extends StatelessWidget {
  const StockTile({required this.item, super.key});

  final StockItem item;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (tone, label) = switch (item.level) {
      StockLevel.negative => (Tone.danger, t.stockNegative),
      StockLevel.low => (Tone.warning, t.stockLow),
      StockLevel.ok => (Tone.success, ''),
    };
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          AuthImage(
            item.imageId,
            width: 48,
            height: 48,
            radius: 10,
            placeholderIcon: LucideIcons.package,
          ),
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
                  item.family,
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              ],
            ),
          ),
          if (label.isNotEmpty) ...[
            StatusChip(label, tone: tone),
            const SizedBox(width: 8),
          ],
          Text(
            '${item.quantity}',
            style: context.text.titleMedium?.copyWith(
              color: item.level == StockLevel.negative
                  ? context.status.danger
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Count the stock, photograph it, send it to the admin.
class DeclareStockScreen extends ConsumerStatefulWidget {
  const DeclareStockScreen({
    required this.locationId,
    this.locationName,
    super.key,
  });

  final String locationId;
  final String? locationName;

  @override
  ConsumerState<DeclareStockScreen> createState() => _DeclareStockScreenState();
}

class _DeclareStockScreenState extends ConsumerState<DeclareStockScreen> {
  final _quantities = QuantityController();
  final _note = TextEditingController();
  List<String> _photoIds = const [];
  bool _photosBusy = false;
  bool _seeded = false;

  @override
  void dispose() {
    _quantities.dispose();
    _note.dispose();
    super.dispose();
  }

  /// A recount starts from what the system believes the place holds.
  void _seed(StockLevels levels) {
    if (_seeded) return;
    _seeded = true;
    for (final i in levels.items) {
      _quantities.addItem(
        QuantityItem(
          productId: i.productId,
          name: i.name,
          family: i.family,
          imageId: i.imageId,
          quantity: i.quantity < 0 ? 0 : i.quantity,
        ),
      );
    }
  }

  Future<void> _declareEmpty() async {
    final t = AppLocalizations.of(context);
    final yes = await confirm(
      context,
      title: t.noStockTitle,
      message: t.noStockBody,
      confirmLabel: t.sendToAdmin,
    );
    if (!yes || !mounted) return;
    await _submit(empty: true);
  }

  Future<void> _submit({bool empty = false}) async {
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref
          .read(stockRepositoryProvider)
          .declare(
            locationId: widget.locationId,
            photoIds: empty ? const [] : _photoIds,
            lines: empty ? const [] : _quantities.lines(),
            note: _note.text.trim(),
          ),
      success: t.declarationSent,
    );
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final levels = ref.watch(stockLevelsProvider(widget.locationId));
    return Scaffold(
      appBar: AppBar(title: Text(widget.locationName ?? t.declareStock)),
      body: AsyncBody(
        value: levels,
        onRetry: () => ref.invalidate(stockLevelsProvider(widget.locationId)),
        builder: (data) {
          _seed(data);
          final first = data.items.isEmpty;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                first ? t.declareFirstHint : t.recountHint,
                style: context.text.bodyMedium?.copyWith(
                  color: context.status.muted,
                ),
              ),
              const Gap(16),
              PhotoSet(
                label: t.photoOfStock,
                onChanged: (ids, busy) => setState(() {
                  _photoIds = ids;
                  _photosBusy = busy;
                }),
              ),
              SectionHeader(t.countedProducts),
              QuantityEditor(controller: _quantities, addLabel: t.addProduct),
              const Gap(16),
              TextField(
                controller: _note,
                maxLength: 300,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: '${t.note} (${t.optional})',
                ),
              ),
              const Gap(8),
              ListenableBuilder(
                listenable: _quantities,
                builder: (context, _) => AsyncButton(
                  label: t.sendToAdmin,
                  icon: LucideIcons.send,
                  onPressed:
                      _photoIds.isEmpty || _photosBusy || _quantities.isEmpty
                      ? null
                      : _submit,
                ),
              ),
              if (_photoIds.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    t.photoRequiredHint,
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
                ),
              const Gap(8),
              TextButton.icon(
                onPressed: _declareEmpty,
                icon: const Icon(LucideIcons.packageOpen),
                label: Text(t.noStockHere),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Review a declaration: the photo next to the numbers. The admin approves, corrects or rejects.
class DeclarationScreen extends ConsumerWidget {
  const DeclarationScreen({required this.declarationId, super.key});

  final String declarationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final declaration = ref.watch(declarationProvider(declarationId));
    return Scaffold(
      appBar: AppBar(title: Text(t.declaration)),
      body: AsyncBody(
        value: declaration,
        onRetry: () => ref.invalidate(declarationProvider(declarationId)),
        builder: (d) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          d.location.name,
                          style: context.text.titleMedium,
                        ),
                      ),
                      DeclarationStatusChip(d.status),
                    ],
                  ),
                  const Gap(8),
                  InfoRow(t.kind, d.initial ? t.initialStock : t.recount),
                  InfoRow(t.sentBy, d.createdBy),
                  InfoRow(t.date, Dates.dateTime(d.createdAt, t.localeName)),
                  InfoRow(t.totalUnits, t.units(d.units)),
                  if (d.note != null) InfoRow(t.note, d.note!),
                  if (d.decisionNote != null)
                    InfoRow(t.decision, d.decisionNote!),
                ],
              ),
            ),
            const Gap(12),
            PhotoStrip(ids: d.photoIds.isNotEmpty ? d.photoIds : [?d.photoId]),
            SectionHeader(t.countedProducts),
            for (final l in d.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(l.name, style: context.text.titleSmall),
                      ),
                      if (l.approvedQuantity != null &&
                          l.approvedQuantity != l.quantity) ...[
                        Text(
                          '${l.quantity}',
                          style: context.text.bodyMedium?.copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: context.status.muted,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        '${l.approvedQuantity ?? l.quantity}',
                        style: context.text.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            if (me.role == Role.admin &&
                d.status == DeclarationStatus.pending) ...[
              const Gap(16),
              _DecisionBar(declaration: d),
            ],
            if (me.role == Role.responsable &&
                d.status == DeclarationStatus.review) ...[
              const Gap(16),
              _ReviewBar(declaration: d),
            ],
          ],
        ),
      ),
    );
  }
}

class _DecisionBar extends ConsumerWidget {
  const _DecisionBar({required this.declaration});

  final StockDeclaration declaration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    Future<void> done() async {
      ref.invalidate(declarationProvider(declaration.id));
      ref.invalidate(approvalsProvider(null));
      if (context.mounted) context.pop();
    }

    return Column(
      children: [
        AsyncButton(
          label: t.approve,
          icon: LucideIcons.check,
          onPressed: () async {
            if (await perform(
              context,
              () => ref.read(stockRepositoryProvider).approve(declaration.id),
              success: t.approved,
            ))
              await done();
          },
        ),
        const Gap(8),
        AsyncButton(
          label: t.amendAndApprove,
          icon: LucideIcons.pencil,
          style: AsyncButtonStyle.outlined,
          onPressed: () async {
            final lines = await amendQuantities(
              context,
              title: t.amendAndApprove,
              hint: t.amendStockHint,
              items: [
                for (final l in declaration.lines)
                  QuantityItem(
                    productId: l.productId,
                    name: l.name,
                    family: l.family,
                    quantity: l.quantity,
                    hint: t.declaredQuantity(l.quantity),
                  ),
              ],
            );
            if (lines == null || !context.mounted) return;
            if (await perform(
              context,
              () => ref
                  .read(stockRepositoryProvider)
                  .approve(declaration.id, lines: lines),
              success: t.approved,
            ))
              await done();
          },
        ),
        const Gap(8),
        AsyncButton(
          label: t.reject,
          icon: LucideIcons.x,
          style: AsyncButtonStyle.text,
          onPressed: () async {
            final note = await askNote(
              context,
              title: t.rejectReasonTitle,
              confirmLabel: t.reject,
              hint: t.rejectReasonHint,
            );
            if (note == null || !context.mounted) return;
            if (await perform(
              context,
              () => ref
                  .read(stockRepositoryProvider)
                  .reject(declaration.id, note),
              success: t.rejected,
            ))
              await done();
          },
        ),
      ],
    );
  }
}

/// The responsable checks a grossiste's count: photos and numbers, then on to the admin or back.
class _ReviewBar extends ConsumerWidget {
  const _ReviewBar({required this.declaration});

  final StockDeclaration declaration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    Future<void> done() async {
      ref.invalidate(declarationProvider(declaration.id));
      ref.invalidate(countsToReviewProvider);
      ref.invalidate(declarationsProvider);
      if (context.mounted) context.pop();
    }

    return Column(
      children: [
        Text(
          t.reviewHint,
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(color: context.status.muted),
        ),
        const Gap(10),
        AsyncButton(
          label: t.sendToAdmin,
          icon: LucideIcons.send,
          onPressed: () async {
            if (await perform(
              context,
              () => ref
                  .read(stockRepositoryProvider)
                  .review(declaration.id, approve: true),
              success: t.sentToAdmin,
            )) {
              await done();
            }
          },
        ),
        const Gap(8),
        AsyncButton(
          label: t.sendBack,
          icon: LucideIcons.undo2,
          style: AsyncButtonStyle.text,
          onPressed: () async {
            final note = await askNote(
              context,
              title: t.rejectReasonTitle,
              confirmLabel: t.sendBack,
              hint: t.rejectReasonHint,
            );
            if (note == null || !context.mounted) return;
            if (await perform(
              context,
              () => ref
                  .read(stockRepositoryProvider)
                  .review(declaration.id, approve: false, note: note),
              success: t.sentBack,
            )) {
              await done();
            }
          },
        ),
      ],
    );
  }
}

/// Grossiste counts waiting for the responsable.
class CountsToReviewScreen extends ConsumerWidget {
  const CountsToReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final rows = ref.watch(countsToReviewProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.countsToCheck)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(countsToReviewProvider);
          await ref.read(countsToReviewProvider.future);
        },
        child: AsyncBody(
          value: rows,
          onRetry: () => ref.invalidate(countsToReviewProvider),
          isEmpty: (l) => l.isEmpty,
          empty: ListView(
            children: [
              EmptyState(
                icon: LucideIcons.circleCheck,
                title: t.nothingToCheck,
              ),
            ],
          ),
          builder: (list) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Gap(8),
            itemBuilder: (context, i) {
              final d = list[i];
              return AppCard(
                onTap: () async {
                  await context.push('/stock/declarations/${d.id}');
                  ref.invalidate(countsToReviewProvider);
                },
                child: Row(
                  children: [
                    const Icon(LucideIcons.warehouse),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.location.name, style: context.text.titleSmall),
                          Text(
                            '${d.createdBy} · ${t.units(d.units)} · ${Dates.dateTime(d.createdAt, t.localeName)}',
                            style: context.text.bodySmall?.copyWith(
                              color: context.status.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DeclarationStatusChip(d.status),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The admin corrects the quantities of a place, with a reason that is kept in the history.
class AdjustStockScreen extends ConsumerStatefulWidget {
  const AdjustStockScreen({
    required this.locationId,
    this.locationName,
    super.key,
  });

  final String locationId;
  final String? locationName;

  @override
  ConsumerState<AdjustStockScreen> createState() => _AdjustStockScreenState();
}

class _AdjustStockScreenState extends ConsumerState<AdjustStockScreen> {
  final _quantities = QuantityController();
  final _reason = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _quantities.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _seed(StockLevels levels) {
    if (_seeded) return;
    _seeded = true;
    for (final i in levels.items) {
      _quantities.addItem(
        QuantityItem(
          productId: i.productId,
          name: i.name,
          family: i.family,
          imageId: i.imageId,
          quantity: i.quantity < 0 ? 0 : i.quantity,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final levels = ref.watch(stockLevelsProvider(widget.locationId));
    return Scaffold(
      appBar: AppBar(title: Text(t.adjustStock)),
      body: AsyncBody(
        value: levels,
        onRetry: () => ref.invalidate(stockLevelsProvider(widget.locationId)),
        builder: (data) {
          _seed(data);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                widget.locationName ?? data.location.name,
                style: context.text.titleLarge,
              ),
              const Gap(4),
              Text(
                t.adjustStockHint,
                style: context.text.bodyMedium?.copyWith(
                  color: context.status.muted,
                ),
              ),
              const Gap(16),
              QuantityEditor(controller: _quantities, addLabel: t.addProduct),
              const Gap(16),
              TextField(
                controller: _reason,
                maxLength: 300,
                minLines: 1,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: t.adjustReason),
              ),
              const Gap(8),
              AsyncButton(
                label: t.save,
                icon: LucideIcons.save,
                onPressed: _reason.text.trim().length < 3
                    ? null
                    : () async {
                        if (await perform(
                          context,
                          () => ref
                              .read(stockRepositoryProvider)
                              .adjust(
                                locationId: widget.locationId,
                                reason: _reason.text.trim(),
                                lines: _quantities.lines(),
                              ),
                          success: t.stockAdjusted,
                        )) {
                          ref.invalidate(
                            stockLevelsProvider(widget.locationId),
                          );
                          if (context.mounted) context.pop();
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }
}
