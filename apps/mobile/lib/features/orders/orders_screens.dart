import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/home_scaffold.dart';
import '../notifications/notifications_repository.dart';
import '../restock/restock_models.dart';
import '../shared/status_chips.dart';
import 'orders_models.dart';
import 'orders_repository.dart';

Tone _tone(ParaLevel l) => switch (l) {
  ParaLevel.out => Tone.danger,
  ParaLevel.low => Tone.warning,
  ParaLevel.ok => Tone.success,
};

String _levelLabel(AppLocalizations t, ParaLevel l) => switch (l) {
  ParaLevel.out => t.paraOut,
  ParaLevel.low => t.paraLow,
  ParaLevel.ok => t.paraStockOk,
};

/// The order manager's home: what waits in the orders and which paras are getting low.
class OrdersHome extends ConsumerWidget {
  const OrdersHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final data = ref.watch(ordersOverviewProvider);
    return HomeScaffold(
      title: t.helloName(me.name.split(' ').first),
      subtitle: t.roleOrders,
      onRefresh: () async {
        ref.invalidate(ordersOverviewProvider);
        unawaited(ref.read(unreadCountProvider.notifier).refresh());
        await ref.read(ordersOverviewProvider.future);
      },
      body: AsyncBody<OrdersOverview>(
        value: data,
        onRetry: () => ref.invalidate(ordersOverviewProvider),
        builder: (d) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            AutoGrid(
              minItemWidth: 150,
              children: [
                StatTile(
                  label: t.ordersToPrepare,
                  value: '${d.orders.requested}',
                  icon: LucideIcons.clipboardList,
                  tone: d.orders.requested > 0 ? Tone.warning : Tone.neutral,
                  onTap: () => context.go('/restocks'),
                ),
                StatTile(
                  label: t.ordersProposed,
                  value: '${d.orders.proposed}',
                  icon: LucideIcons.hourglass,
                  onTap: () => context.go('/restocks'),
                ),
                StatTile(
                  label: t.ordersToShip,
                  value: '${d.orders.toShip}',
                  icon: LucideIcons.packageCheck,
                  tone: d.orders.toShip > 0 ? Tone.info : Tone.neutral,
                  onTap: () => context.go('/restocks'),
                ),
                StatTile(
                  label: t.ordersOnTheRoad,
                  value: '${d.orders.onTheRoad}',
                  icon: LucideIcons.truck,
                  onTap: () => context.go('/restocks'),
                ),
                StatTile(
                  label: t.ordersDelivered,
                  value: '${d.orders.delivered}',
                  icon: LucideIcons.circleCheck,
                  onTap: () => context.go('/restocks'),
                ),
                StatTile(
                  label: t.ordersToApprove,
                  value: '${d.orders.toApprove}',
                  icon: LucideIcons.shieldCheck,
                  hint: t.ordersToApproveHint,
                ),
              ],
            ),
            SectionHeader(
              t.ordersAttention,
              trailing: TextButton(
                onPressed: () => context.go('/paras'),
                child: Text(t.seeAll),
              ),
            ),
            if (d.attention.isEmpty)
              EmptyState(
                icon: LucideIcons.circleCheck,
                title: t.ordersAttentionNone,
              )
            else
              Column(
                spacing: 12,
                children: [
                  for (final p in d.attention)
                    ParaCard(
                      para: p,
                      onTap: () => context.push('/paras/${p.id}'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A para with how its stock stands: the worst first on the board.
class ParaCard extends StatelessWidget {
  const ParaCard({required this.para, required this.onTap, super.key});

  final ParaRow para;
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
          IconBadge(LucideIcons.store, size: 44, tone: _tone(para.level)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  para.name,
                  style: context.text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [
                    para.city,
                    para.region,
                    ?para.group,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    StatusChip(
                      _levelLabel(t, para.level),
                      tone: _tone(para.level),
                    ),
                    if (para.out > 0)
                      StatusChip(t.paraOutCount(para.out), tone: Tone.danger),
                    if (para.low > 0)
                      StatusChip(t.paraLowCount(para.low), tone: Tone.warning),
                    if (para.openOrders > 0)
                      StatusChip(
                        t.paraOpenOrders(para.openOrders),
                        tone: Tone.info,
                        icon: LucideIcons.truck,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 16, color: context.status.muted),
        ],
      ),
    );
  }
}

/// Every para, the lowest first; search by name, or keep only those low or out.
class ParasScreen extends ConsumerStatefulWidget {
  const ParasScreen({super.key});

  @override
  ConsumerState<ParasScreen> createState() => _ParasScreenState();
}

class _ParasScreenState extends ConsumerState<ParasScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';
  bool _lowOnly = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _typed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _q = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final query = (q: _q, lowOnly: _lowOnly);
    final paras = ref.watch(parasProvider(query));
    return Scaffold(
      appBar: AppBar(title: Text(t.parasTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(parasProvider(query));
          await ref.read(parasProvider(query).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            TextField(
              controller: _search,
              onChanged: _typed,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: t.parasSearch,
                prefixIcon: const Icon(LucideIcons.search, size: 18),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(t.parasAll),
                  selected: !_lowOnly,
                  onSelected: (_) => setState(() => _lowOnly = false),
                ),
                ChoiceChip(
                  label: Text(t.parasLowOnly),
                  selected: _lowOnly,
                  onSelected: (_) => setState(() => _lowOnly = true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AsyncBody<List<ParaRow>>(
              value: paras,
              onRetry: () => ref.invalidate(parasProvider(query)),
              builder: (rows) {
                if (rows.isEmpty) {
                  return EmptyState(
                    icon: LucideIcons.store,
                    title: t.parasNone,
                  );
                }
                return Column(
                  spacing: 12,
                  children: [
                    for (final p in rows)
                      ParaCard(
                        para: p,
                        onTap: () => context.push('/paras/${p.id}'),
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

/// One para: its stock with how fast each product sells, what is on order, and who to call.
class ParaDetailScreen extends ConsumerWidget {
  const ParaDetailScreen({required this.paraId, super.key});

  final String paraId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final detail = ref.watch(paraDetailProvider(paraId));
    final canAsk = ref.watch(meProvider).role == Role.orders;
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.row.name ?? t.parasTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(paraDetailProvider(paraId));
          await ref.read(paraDetailProvider(paraId).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            AsyncBody<ParaDetail>(
              value: detail,
              onRetry: () => ref.invalidate(paraDetailProvider(paraId)),
              builder: (d) => _DetailBody(detail: d, canAsk: canAsk),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail, required this.canAsk});

  final ParaDetail detail;
  final bool canAsk;

  Future<void> _ask(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final note = await askNote(
      context,
      title: t.paraAskTitle,
      confirmLabel: t.paraAskSend,
      hint: t.paraAskHint,
      required: false,
    );
    if (note == null || !context.mounted) return;
    final done = await perform(
      context,
      () =>
          ref.read(ordersRepositoryProvider).ask(detail.row.id, message: note),
      success: t.paraAsked,
    );
    if (done) ref.invalidate(paraDetailProvider(detail.row.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final row = detail.row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  StatusChip(_levelLabel(t, row.level), tone: _tone(row.level)),
                  StatusChip(t.paraSold7(row.sold7Days), tone: Tone.info),
                ],
              ),
              InfoRow(t.paraRegion, row.region),
              if (row.group != null) InfoRow(t.paraGroup, row.group!),
              if ((row.address ?? '').isNotEmpty)
                InfoRow(t.paraAddress, '${row.address}, ${row.city}'),
              InfoRow(t.paraStockUnits, '${row.units}'),
            ],
          ),
        ),
        if (canAsk)
          AsyncButton(
            label: t.paraAsk,
            icon: LucideIcons.messageCircleQuestionMark,
            onPressed: () async => _ask(context, ref),
          ),
        AsyncButton(
          label: t.paraOrderFor,
          icon: LucideIcons.truck,
          style: AsyncButtonStyle.outlined,
          onPressed: () async => context.push('/restocks/new', extra: row.id),
        ),
        if (detail.lastAskedAt != null)
          Text(
            t.paraAskedAt(Dates.dateTime(detail.lastAskedAt!, t.localeName)),
            style: context.text.bodySmall?.copyWith(
              color: context.status.muted,
            ),
          ),
        if (detail.contacts.isNotEmpty) ...[
          SectionHeader(t.paraContacts),
          for (final c in detail.contacts) _ContactTile(contact: c),
        ],
        if (detail.orders.isNotEmpty) ...[
          SectionHeader(t.paraOrders),
          for (final o in detail.orders)
            AppCard(
              onTap: () => context.push('/restocks/${o.id}'),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(o.number, style: context.text.titleSmall),
                        Text(
                          t.units(o.units),
                          style: context.text.bodySmall?.copyWith(
                            color: context.status.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  RestockStatusChip(RestockStatus.parse(o.status)),
                ],
              ),
            ),
        ],
        SectionHeader(t.paraStockTitle),
        if (detail.lines.isEmpty)
          EmptyState(icon: LucideIcons.package, title: t.paraNoStock)
        else
          for (final l in detail.lines) _StockLine(line: l),
      ],
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact});

  final ParaContact contact;

  /// The number as WhatsApp wants it: digits only, with the country code (Tunisia's when it has none).
  static String whatsappNumber(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length == 8 ? '216$digits' : digits;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final phone = contact.phone;
    return AppCard(
      child: Row(
        spacing: 12,
        children: [
          Avatar(_initials(contact.name)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name, style: context.text.titleSmall),
                Text(
                  contact.role == 'RESPONSABLE'
                      ? t.roleResponsable
                      : t.roleVendeur,
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              ],
            ),
          ),
          if (phone != null && phone.isNotEmpty) ...[
            IconButton(
              tooltip: t.paraCall,
              icon: const Icon(LucideIcons.phone),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
            ),
            IconButton(
              tooltip: t.paraWhatsapp,
              icon: const Icon(LucideIcons.messageCircle),
              onPressed: () => launchUrl(
                Uri.parse('https://wa.me/${whatsappNumber(phone)}'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StockLine extends StatelessWidget {
  const _StockLine({required this.line});

  final ParaStockLine line;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cover = line.coverDays;
    return AppCard(
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  line.name,
                  style: context.text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  line.sold7Days == 0
                      ? t.paraNoSales
                      : [
                          t.paraSold7(line.sold7Days),
                          if (cover != null) t.paraCover(cover),
                        ].join(' · '),
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              ],
            ),
          ),
          StatusChip('${line.quantity}', tone: _tone(line.level)),
        ],
      ),
    );
  }
}
