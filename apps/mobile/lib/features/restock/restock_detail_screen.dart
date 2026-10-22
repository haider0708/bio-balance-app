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
import '../../l10n/app_localizations.dart';
import '../approvals/approvals_repository.dart';
import '../network/network_models.dart';
import '../network/network_repository.dart';
import '../shared/status_chips.dart';
import 'restock_models.dart';
import 'restock_repository.dart';

/// One order: what was asked, what happened since, and the actions this person may take.
class RestockDetailScreen extends ConsumerStatefulWidget {
  const RestockDetailScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<RestockDetailScreen> createState() =>
      _RestockDetailScreenState();
}

class _RestockDetailScreenState extends ConsumerState<RestockDetailScreen> {
  /// Quantities the admin changed before routing the order.
  List<Map<String, Object>>? _adjusted;

  void _reload() {
    ref.invalidate(restockProvider(widget.orderId));
    ref.invalidate(restocksProvider);
    ref.invalidate(approvalsProvider);
  }

  Future<void> _act(
    Future<void> Function() action,
    String success, {
    bool leave = false,
  }) async {
    final ok = await perform(context, action, success: success);
    if (!ok) return;
    _reload();
    if (leave && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final order = ref.watch(restockProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(title: Text(order.value?.number ?? t.restock)),
      body: AsyncBody(
        value: order,
        onRetry: () => ref.invalidate(restockProvider(widget.orderId)),
        builder: (o) => RefreshIndicator(
          onRefresh: () async {
            _reload();
            await ref.read(restockProvider(widget.orderId).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      spacing: 8,
                      children: [
                        Expanded(
                          child: Text(
                            o.destination,
                            style: context.text.titleMedium,
                          ),
                        ),
                        RestockStatusChip(o.status),
                      ],
                    ),
                    const Gap(8),
                    if (o.requestedBy != null)
                      InfoRow(t.requestedBy, o.requestedBy!.name),
                    InfoRow(t.date, Dates.dateTime(o.createdAt, t.localeName)),
                    if (o.source != null)
                      InfoRow(
                        t.sentFrom,
                        o.source == 'BIOBALANCE'
                            ? 'BioBalance'
                            : (o.supplier ?? t.grossisteLabel),
                      ),
                    if (o.suggestedSupplier != null &&
                        o.status == RestockStatus.requested)
                      InfoRow(t.suggestedSupplier, o.suggestedSupplier!.name),
                    if (o.receiver != null)
                      InfoRow(t.receivedBy, o.receiver!.name),
                    if (o.receiptNote != null)
                      InfoRow(t.receiverNote, o.receiptNote!),
                    if (o.note != null) InfoRow(t.note, o.note!),
                    if (o.decisionNote != null)
                      InfoRow(t.decision, o.decisionNote!),
                    if (o.cancelReason != null)
                      InfoRow(t.cancelReason, o.cancelReason!),
                  ],
                ),
              ),
              SectionHeader(t.products),
              _Lines(order: o, adjusted: _adjusted),
              if (o.receiptPhotoIds.isNotEmpty || o.receiptPhotoId != null) ...[
                SectionHeader(t.deliveryPaper),
                PhotoStrip(
                  ids: o.receiptPhotoIds.isNotEmpty
                      ? o.receiptPhotoIds
                      : [?o.receiptPhotoId],
                ),
              ],
              const Gap(20),
              ..._actions(context, me, o),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, Me me, RestockOrder o) {
    final t = AppLocalizations.of(context);
    final repo = ref.read(restockRepositoryProvider);
    const gap = Gap(8);
    final w = <Widget>[];

    if (me.role == Role.admin) {
      if (o.status == RestockStatus.requested) {
        final suggested = o.toDepot ? null : o.suggestedSupplier;
        // The responsable suggested a grossiste: one tap approves it as suggested.
        if (suggested != null) {
          w
            ..add(
              AsyncButton(
                label: t.assignToSuggested(suggested.name),
                icon: LucideIcons.check,
                onPressed: () => _act(
                  () => repo.assign(
                    o.id,
                    depotId: suggested.id,
                    lines: _adjusted,
                  ),
                  t.restockRouted,
                ),
              ),
            )
            ..add(gap);
        }
        w
          ..add(
            AsyncButton(
              label: o.toDepot ? t.sendFromBiobalance : t.assignToGrossiste,
              icon: o.toDepot ? LucideIcons.send : LucideIcons.truck,
              style: suggested != null
                  ? AsyncButtonStyle.outlined
                  : AsyncButtonStyle.filled,
              onPressed: () async {
                if (o.toDepot)
                  return _act(
                    () => repo.sendDirect(o.id, lines: _adjusted),
                    t.restockRouted,
                  );
                final depot = await _pickDepot(context, o);
                if (depot == null) return;
                await _act(
                  () => repo.assign(o.id, depotId: depot.id, lines: _adjusted),
                  t.restockRouted,
                );
              },
            ),
          )
          ..add(gap);
        if (!o.toDepot) {
          w
            ..add(
              AsyncButton(
                label: t.sendFromBiobalance,
                icon: LucideIcons.send,
                style: AsyncButtonStyle.outlined,
                onPressed: () => _act(
                  () => repo.sendDirect(o.id, lines: _adjusted),
                  t.restockRouted,
                ),
              ),
            )
            ..add(gap);
        }
        w.add(
          AsyncButton(
            label: t.adjustQuantities,
            icon: LucideIcons.pencil,
            style: AsyncButtonStyle.text,
            onPressed: () async {
              final lines = await amendQuantities(
                context,
                title: t.adjustQuantities,
                hint: t.adjustQuantitiesHint,
                allowAdd: true,
                items: [
                  for (final l in o.lines)
                    QuantityItem(
                      productId: l.productId,
                      name: l.name,
                      family: l.family,
                      quantity: l.requested,
                      hint: t.requestedQuantity(l.requested),
                    ),
                ],
              );
              if (lines != null) setState(() => _adjusted = lines);
            },
          ),
        );
      }
      if (o.status == RestockStatus.received) {
        // The receiver sent the paper; the admin enters what arrived (from what was sent, or what
        // an older app counted at the store) and approves: the stock goes into the store.
        w
          ..add(
            AsyncButton(
              label: t.approveAsCounted,
              icon: LucideIcons.check,
              onPressed: () async {
                final lines = await amendQuantities(
                  context,
                  title: t.approveAsCounted,
                  hint: t.amendReceiptHint,
                  items: [
                    for (final l in o.lines.where((l) => (l.shipped ?? 0) > 0))
                      QuantityItem(
                        productId: l.productId,
                        name: l.name,
                        family: l.family,
                        quantity: l.received ?? l.shipped ?? 0,
                        hint: l.received == null
                            ? t.sentQuantity(l.shipped ?? 0)
                            : t.shippedReceived(l.shipped ?? 0, l.received!),
                      ),
                  ],
                );
                if (lines == null) return;
                await _act(
                  () => repo.approve(o.id, lines: lines),
                  t.restockApproved,
                  leave: true,
                );
              },
            ),
          )
          ..add(gap)
          ..add(
            AsyncButton(
              label: t.askRecount,
              icon: LucideIcons.rotateCcw,
              style: AsyncButtonStyle.text,
              onPressed: () async {
                final note = await askNote(
                  context,
                  title: t.askRecount,
                  confirmLabel: t.send,
                  hint: t.recountReasonHint,
                );
                if (note == null) return;
                await _act(
                  () => repo.rejectReceipt(o.id, note),
                  t.recountAsked,
                );
              },
            ),
          );
      }
    }

    // The responsable of the region (or the admin) ships from the grossiste.
    final shipsIt =
        me.role == Role.admin ||
        (me.role == Role.responsable && o.supplierRegionId == me.region?.id);
    if (o.status == RestockStatus.assigned &&
        o.supplierId != null &&
        !shipsIt) {
      // Another region's grossiste supplies it: that region's team ships, here we only follow.
      w
        ..add(
          StatusChip(
            t.shipByRegionTeam(o.supplier ?? ''),
            tone: Tone.info,
            icon: LucideIcons.truck,
          ),
        )
        ..add(gap);
    }
    if (shipsIt && o.status == RestockStatus.assigned && o.supplierId != null) {
      w.add(
        AsyncButton(
          label: t.prepareAndShip,
          icon: LucideIcons.truck,
          onPressed: () async {
            final shipped = await context.push<bool>(
              '/restocks/${o.id}/ship',
              extra: o,
            );
            if (shipped ?? false) _reload();
          },
        ),
      );
    }

    final isReceiver = o.receiver?.id == me.id;
    final canReceive =
        o.status == RestockStatus.shipped &&
        (isReceiver ||
            (me.role == Role.responsable && o.regionId == me.region?.id) ||
            (me.role == Role.admin && o.toDepot));
    if (canReceive) {
      w
        ..add(
          AsyncButton(
            label: t.confirmDelivery,
            icon: LucideIcons.packageCheck,
            onPressed: () async {
              final sent = await context.push<bool>(
                '/restocks/${o.id}/receive',
                extra: o,
              );
              if (sent ?? false) _reload();
            },
          ),
        )
        ..add(gap);
    }

    if (o.canChooseReceiver(me)) {
      w
        ..add(
          AsyncButton(
            label: o.receiver == null ? t.chooseReceiver : t.changeReceiver,
            icon: LucideIcons.userRoundCheck,
            style: AsyncButtonStyle.outlined,
            onPressed: () async {
              final pdvTeam = await ref
                  .read(networkRepositoryProvider)
                  .people(
                    role: 'VENDEUR',
                    pdvId: o.destinationId,
                    status: 'ACTIVE',
                  );
              if (!context.mounted) return;
              final chosen = await showModalBottomSheet<String?>(
                context: context,
                builder: (context) => _ReceiverSheet(
                  team: pdvTeam.where((p) => p.activated).toList(),
                  current: o.receiver?.id,
                ),
              );
              // `chosen == null` means the sheet was dismissed; the empty string means "me".
              if (chosen == null) return;
              await _act(
                () => repo.setReceiver(o.id, chosen.isEmpty ? null : chosen),
                t.receiverSaved,
              );
            },
          ),
        )
        ..add(gap);
    }

    final canCancel = me.role == Role.admin
        ? o.status.open && o.status != RestockStatus.received
        : (me.role == Role.responsable && o.status == RestockStatus.requested);
    if (canCancel) {
      w.add(
        AsyncButton(
          label: t.cancelRestock,
          icon: LucideIcons.ban,
          style: AsyncButtonStyle.text,
          onPressed: () async {
            final note = await askNote(
              context,
              title: t.cancelRestock,
              confirmLabel: t.cancelRestock,
              hint: t.cancelReasonHint,
            );
            if (note == null) return;
            await _act(
              () => repo.cancel(o.id, note),
              t.restockCancelled,
              leave: true,
            );
          },
        ),
      );
    }
    return w;
  }

  /// Any active grossiste can supply the order, in its region or another. Each one shows what it
  /// holds of the order's products (with the quantities as adjusted), so the admin picks one that
  /// has them: those holding everything first, then the order's own region.
  Future<SupplierOption?> _pickDepot(
    BuildContext context,
    RestockOrder order,
  ) async {
    final suppliers = await ref
        .read(restockRepositoryProvider)
        .suppliers(order.id);
    final wanted = {
      for (final l
          in _adjusted ??
              [
                for (final l in order.lines)
                  {'productId': l.productId, 'quantity': l.requested},
              ])
        l['productId']! as String: l['quantity']! as int,
    };
    final names = {for (final l in order.lines) l.productId: l.name};
    suppliers.sort((a, b) {
      // The one the responsable suggested comes first.
      final suggestedId = order.suggestedSupplier?.id;
      if (suggestedId != null &&
          (a.id == suggestedId) != (b.id == suggestedId)) {
        return a.id == suggestedId ? -1 : 1;
      }
      final byMissing = a.missing(wanted).compareTo(b.missing(wanted));
      if (byMissing != 0) return byMissing;
      final byRegion = (a.regionId == order.regionId ? 0 : 1).compareTo(
        b.regionId == order.regionId ? 0 : 1,
      );
      return byRegion != 0 ? byRegion : a.name.compareTo(b.name);
    });
    if (!context.mounted) return null;
    return showModalBottomSheet<SupplierOption>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DepotSheet(
        suppliers: suppliers,
        wanted: wanted,
        names: names,
        suggestedId: order.suggestedSupplier?.id,
      ),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({required this.order, this.adjusted});

  final RestockOrder order;
  final List<Map<String, Object>>? adjusted;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final showShipped = order.lines.any((l) => l.shipped != null);
    final showReceived = order.lines.any((l) => l.received != null);
    final showApproved = order.lines.any((l) => l.approved != null);
    Widget cell(String label, int? value, {bool strong = false}) => Padding(
      padding: const EdgeInsetsDirectional.only(start: 14),
      child: Column(
        children: [
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: context.status.muted,
            ),
          ),
          Text(
            '${value ?? '–'}',
            style: strong ? context.text.titleMedium : context.text.bodyLarge,
          ),
        ],
      ),
    );
    return Column(
      children: [
        if (adjusted != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StatusChip(
              t.quantitiesAdjusted,
              tone: Tone.info,
              icon: LucideIcons.pencil,
            ),
          ),
        for (final l in order.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                spacing: 8,
                children: [
                  Expanded(child: Text(l.name, style: context.text.titleSmall)),
                  cell(t.colRequested, l.requested),
                  if (showShipped) cell(t.colShipped, l.shipped),
                  if (showReceived) cell(t.colReceived, l.received),
                  if (showApproved)
                    cell(t.colApproved, l.approved, strong: true),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DepotSheet extends StatelessWidget {
  const _DepotSheet({
    required this.suppliers,
    required this.wanted,
    required this.names,
    this.suggestedId,
  });

  /// The grossiste the responsable suggested, if any.
  final String? suggestedId;

  final List<SupplierOption> suppliers;

  /// The quantities the order asks for, by product.
  final Map<String, int> wanted;

  /// Product names, by id.
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(t.chooseGrossiste, style: context.text.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                t.chooseGrossisteOtherRegions,
                style: context.text.bodyMedium?.copyWith(
                  color: context.status.muted,
                ),
              ),
            ),
            if (suppliers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(t.noGrossisteYet),
              ),
            for (final d in suppliers) _supplier(context, t, d),
          ],
        ),
      ),
    );
  }

  Widget _supplier(BuildContext context, AppLocalizations t, SupplierOption d) {
    final missing = d.missing(wanted);
    // What it is short of: "Serum C 2/6", so the admin sees how far it is.
    final short = [
      for (final e in wanted.entries)
        if ((d.held[e.key] ?? 0) < e.value)
          '${names[e.key] ?? ''} ${d.held[e.key] ?? 0}/${e.value}',
    ].join(' · ');
    return ListTile(
      leading: const Icon(LucideIcons.warehouse),
      title: Text(d.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${d.city} · ${d.regionName}'),
          const Gap(6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (d.id == suggestedId)
                StatusChip(
                  t.suggestedTag,
                  tone: Tone.info,
                  icon: LucideIcons.star,
                ),
              StatusChip(
                missing == 0 ? t.supplierHasAll : t.supplierMissing(missing),
                tone: missing == 0 ? Tone.success : Tone.warning,
              ),
            ],
          ),
          if (missing > 0) ...[
            const Gap(4),
            Text(
              short,
              style: context.text.bodySmall?.copyWith(
                color: context.status.warning,
              ),
            ),
          ],
        ],
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        size: 18,
        color: context.status.muted,
      ),
      onTap: () => Navigator.pop(context, d),
    );
  }
}

class _ReceiverSheet extends StatelessWidget {
  const _ReceiverSheet({required this.team, required this.current});

  final List<Person> team;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(t.whoCountsTheGoods, style: context.text.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              t.whoCountsHint,
              style: context.text.bodyMedium?.copyWith(
                color: context.status.muted,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(LucideIcons.user),
            title: Text(t.me),
            trailing: current == null ? const Icon(LucideIcons.check) : null,
            onTap: () => Navigator.pop(context, ''),
          ),
          for (final p in team)
            ListTile(
              leading: Avatar(p.initials, size: 36),
              title: Text(p.name),
              trailing: current == p.id ? const Icon(LucideIcons.check) : null,
              onTap: () => Navigator.pop(context, p.id),
            ),
          const Gap(8),
        ],
      ),
    );
  }
}
