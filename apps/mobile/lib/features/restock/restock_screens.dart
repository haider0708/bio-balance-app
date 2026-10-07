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
import '../network/network_models.dart';
import '../network/network_repository.dart';
import '../shared/status_chips.dart';
import '../stock/stock_repository.dart';
import 'restock_models.dart';
import 'restock_repository.dart';

enum _Filter { open, done, all }

/// Restock orders. Every role sees the ones that concern them.
class RestocksScreen extends ConsumerStatefulWidget {
  const RestocksScreen({this.regionId, super.key});

  final String? regionId;

  @override
  ConsumerState<RestocksScreen> createState() => _RestocksScreenState();
}

class _RestocksScreenState extends ConsumerState<RestocksScreen> {
  _Filter _filter = _Filter.open;

  RestockQuery get _query => (
    active: switch (_filter) {
      _Filter.open => true,
      _ => null,
    },
    status: _filter == _Filter.done ? 'COMPLETED' : null,
    regionId: widget.regionId,
    destId: null,
  );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final orders = ref.watch(restocksProvider(_query));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          me.role == Role.grossiste ? t.ordersTitle : t.restocksTitle,
        ),
      ),
      floatingActionButton:
          me.role == Role.responsable || me.role == Role.grossiste
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () async {
                await context.push('/restocks/new');
                ref.invalidate(restocksProvider);
              },
              icon: const Icon(LucideIcons.plus),
              label: Text(t.requestRestock),
            )
          : null,
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in _Filter.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(switch (f) {
                        _Filter.open => t.filterOpen,
                        _Filter.done => t.filterDone,
                        _Filter.all => t.all,
                      }),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(restocksProvider(_query));
                await ref.read(restocksProvider(_query).future);
              },
              child: AsyncBody(
                value: orders,
                onRetry: () => ref.invalidate(restocksProvider(_query)),
                isEmpty: (list) => list.isEmpty,
                empty: ListView(
                  children: [
                    EmptyState(
                      icon: LucideIcons.truck,
                      title: t.noRestocks,
                      message: me.role == Role.responsable
                          ? t.noRestocksHint
                          : null,
                    ),
                  ],
                ),
                builder: (list) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Gap(8),
                  itemBuilder: (context, i) => RestockTile(order: list[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RestockTile extends StatelessWidget {
  const RestockTile({required this.order, super.key});

  final RestockOrder order;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppCard(
      onTap: () => context.push('/restocks/${order.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(order.number, style: context.text.titleSmall),
              ),
              RestockStatusChip(order.status),
            ],
          ),
          const Gap(6),
          Text(order.destination, style: context.text.titleMedium),
          const Gap(2),
          Text(
            [
              Dates.short(order.createdAt, t.localeName),
              t.units(
                order.status == RestockStatus.completed
                    ? order.approvedUnits
                    : order.requestedUnits,
              ),
              if (order.supplier != null) order.supplier!,
            ].join(' · '),
            style: context.text.bodySmall?.copyWith(
              color: context.status.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ask for products for a point of sale (responsable) or for the depot (grossiste).
class RequestRestockScreen extends ConsumerStatefulWidget {
  const RequestRestockScreen({this.pdvId, super.key});

  final String? pdvId;

  @override
  ConsumerState<RequestRestockScreen> createState() =>
      _RequestRestockScreenState();
}

class _RequestRestockScreenState extends ConsumerState<RequestRestockScreen> {
  final _quantities = QuantityController();
  final _note = TextEditingController();
  late String? _pdvId = widget.pdvId;

  @override
  void dispose() {
    _quantities.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref
          .read(restockRepositoryProvider)
          .create(
            destId: _pdvId,
            note: _note.text.trim(),
            lines: _quantities.lines(skipZero: true),
          ),
      success: t.restockSent,
    );
    if (ok && mounted) {
      ref.invalidate(restocksProvider);
      ref.invalidate(approvalsProvider);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final pdvs = me.role == Role.responsable
        ? ref.watch(pdvsProvider(null))
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(t.requestRestock)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (me.role == Role.responsable)
            AsyncBody(
              value: pdvs!,
              onRetry: () => ref.invalidate(pdvsProvider(null)),
              builder: (list) {
                final active = list
                    .where((p) => p.status == ItemStatus.active)
                    .toList();
                if (active.isEmpty)
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      t.noActivePdv,
                      style: context.text.bodyMedium?.copyWith(
                        color: context.status.muted,
                      ),
                    ),
                  );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: DropdownButtonFormField<String>(
                    initialValue: active.any((p) => p.id == _pdvId)
                        ? _pdvId
                        : null,
                    decoration: InputDecoration(labelText: t.deliverTo),
                    items: [
                      for (final p in active)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (v) => setState(() => _pdvId = v),
                  ),
                );
              },
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AppCard(
                child: Row(
                  children: [
                    const Icon(LucideIcons.warehouse),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        me.depot?.name ?? '',
                        style: context.text.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Text(t.productsNeeded, style: context.text.titleMedium),
          const Gap(8),
          QuantityEditor(controller: _quantities),
          const Gap(16),
          TextField(
            controller: _note,
            maxLength: 300,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(labelText: '${t.note} (${t.optional})'),
          ),
          const Gap(8),
          ListenableBuilder(
            listenable: _quantities,
            builder: (context, _) => AsyncButton(
              label: t.sendRequest,
              icon: LucideIcons.send,
              onPressed:
                  _quantities.total == 0 ||
                      (me.role == Role.responsable && _pdvId == null)
                  ? null
                  : _send,
            ),
          ),
        ],
      ),
    );
  }
}

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
                            : (o.supplier ?? t.roleGrossiste),
                      ),
                    if (o.receiver != null)
                      InfoRow(t.receivedBy, o.receiver!.name),
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
        w
          ..add(
            AsyncButton(
              label: o.toDepot ? t.sendFromBiobalance : t.assignToGrossiste,
              icon: o.toDepot ? LucideIcons.send : LucideIcons.truck,
              onPressed: () async {
                if (o.toDepot)
                  return _act(
                    () => repo.sendDirect(o.id, lines: _adjusted),
                    t.restockRouted,
                  );
                final depot = await _pickDepot(context, o.regionId);
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
        w
          ..add(
            AsyncButton(
              label: t.approveAsCounted,
              icon: LucideIcons.check,
              onPressed: () => _act(
                () => repo.approve(o.id),
                t.restockApproved,
                leave: true,
              ),
            ),
          )
          ..add(gap)
          ..add(
            AsyncButton(
              label: t.amendAndApprove,
              icon: LucideIcons.pencil,
              style: AsyncButtonStyle.outlined,
              onPressed: () async {
                final lines = await amendQuantities(
                  context,
                  title: t.amendAndApprove,
                  hint: t.amendReceiptHint,
                  items: [
                    for (final l in o.lines.where((l) => (l.shipped ?? 0) > 0))
                      QuantityItem(
                        productId: l.productId,
                        name: l.name,
                        family: l.family,
                        quantity: l.received ?? 0,
                        hint: t.shippedReceived(
                          l.shipped ?? 0,
                          l.received ?? 0,
                        ),
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

    if (me.role == Role.grossiste &&
        o.status == RestockStatus.assigned &&
        o.supplierId == me.depot?.id) {
      w.add(
        AsyncButton(
          label: t.prepareAndShip,
          icon: LucideIcons.truck,
          onPressed: () async {
            final shipped = await context.push<bool>(
              '/restocks/${o.id}/ship',
              extra: o,
            );
            if (shipped == true) _reload();
          },
        ),
      );
    }

    final isReceiver = o.receiver?.id == me.id;
    final canReceive =
        o.status == RestockStatus.shipped &&
        (isReceiver ||
            (me.role == Role.responsable && !o.toDepot) ||
            (me.role == Role.grossiste && o.toDepot));
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
              if (sent == true) _reload();
            },
          ),
        )
        ..add(gap);
    }

    if (me.role == Role.responsable && o.canChooseReceiver(me.role)) {
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

  /// Only the grossistes of the order's own region can take it.
  Future<Depot?> _pickDepot(BuildContext context, String? regionId) async {
    final depots = (await ref.read(networkRepositoryProvider).depots())
        .where((d) => regionId == null || d.regionId == regionId)
        .toList();
    if (!context.mounted) return null;
    return showModalBottomSheet<Depot>(
      context: context,
      builder: (context) => _DepotSheet(depots: depots),
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
  const _DepotSheet({required this.depots});

  final List<Depot> depots;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(t.chooseGrossiste, style: context.text.titleLarge),
          ),
          if (depots.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(t.noGrossisteYet),
            ),
          for (final d in depots)
            ListTile(
              leading: const Icon(LucideIcons.warehouse),
              title: Text(d.name),
              subtitle: Text(
                [d.grossisteName, d.city].whereType<String>().join(' · '),
              ),
              onTap: () => Navigator.pop(context, d),
            ),
          const Gap(8),
        ],
      ),
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

/// The grossiste prepares the order: what is really leaving the depot.
class ShipScreen extends ConsumerStatefulWidget {
  const ShipScreen({required this.order, super.key});

  final RestockOrder order;

  @override
  ConsumerState<ShipScreen> createState() => _ShipScreenState();
}

class _ShipScreenState extends ConsumerState<ShipScreen> {
  QuantityController? _quantities;

  @override
  void dispose() {
    _quantities?.dispose();
    super.dispose();
  }

  Future<void> _ship() async {
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref
          .read(restockRepositoryProvider)
          .ship(widget.order.id, _quantities!.lines()),
      success: t.restockShippedMessage,
    );
    if (ok && mounted) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final stock = ref.watch(stockLevelsProvider(me.depot?.id ?? ''));
    return Scaffold(
      appBar: AppBar(title: Text(t.prepareAndShip)),
      body: AsyncBody(
        value: stock,
        onRetry: () => ref.invalidate(stockLevelsProvider(me.depot?.id ?? '')),
        builder: (levels) {
          final held = {for (final i in levels.items) i.productId: i.quantity};
          _quantities ??= QuantityController([
            for (final l in widget.order.lines)
              QuantityItem(
                productId: l.productId,
                name: l.name,
                family: l.family,
                quantity: (held[l.productId] ?? 0).clamp(0, l.requested),
                max: (held[l.productId] ?? 0).clamp(0, l.requested),
                hint: t.requestedInStock(l.requested, held[l.productId] ?? 0),
              ),
          ]);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                t.shipHint(widget.order.destination),
                style: context.text.bodyMedium?.copyWith(
                  color: context.status.muted,
                ),
              ),
              const Gap(16),
              QuantityEditor(
                controller: _quantities!,
                allowAdd: false,
                allowRemove: false,
              ),
              const Gap(16),
              ListenableBuilder(
                listenable: _quantities!,
                builder: (context, _) => AsyncButton(
                  label: t.markShipped,
                  icon: LucideIcons.truck,
                  onPressed: _quantities!.total == 0 ? null : _ship,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Photograph the signed paper and count what arrived.
class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({required this.order, super.key});

  final RestockOrder order;

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  late final QuantityController _quantities = QuantityController([
    for (final l in widget.order.lines.where((l) => (l.shipped ?? 0) > 0))
      QuantityItem(
        productId: l.productId,
        name: l.name,
        family: l.family,
        quantity: l.shipped ?? 0,
        hint: null,
      ),
  ]);
  final _note = TextEditingController();
  List<String> _photoIds = const [];
  bool _photosBusy = false;

  @override
  void dispose() {
    _quantities.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref
          .read(restockRepositoryProvider)
          .receive(
            widget.order.id,
            photoIds: _photoIds,
            lines: _quantities.lines(),
            note: _note.text.trim(),
          ),
      success: t.deliverySent,
    );
    if (ok && mounted) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.confirmDelivery)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t.receiveHint,
            style: context.text.bodyMedium?.copyWith(
              color: context.status.muted,
            ),
          ),
          const Gap(16),
          PhotoSet(
            label: t.photoOfPaper,
            onChanged: (ids, busy) => setState(() {
              _photoIds = ids;
              _photosBusy = busy;
            }),
          ),
          SectionHeader(t.quantitiesReceived),
          QuantityEditor(
            controller: _quantities,
            allowAdd: false,
            allowRemove: false,
          ),
          const Gap(16),
          TextField(
            controller: _note,
            maxLength: 300,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(labelText: '${t.note} (${t.optional})'),
          ),
          const Gap(8),
          AsyncButton(
            label: t.sendToAdmin,
            icon: LucideIcons.send,
            onPressed: _photoIds.isEmpty || _photosBusy ? null : _send,
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
        ],
      ),
    );
  }
}
