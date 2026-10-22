import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../shared/status_chips.dart';
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
      appBar: AppBar(title: Text(t.restocksTitle)),
      floatingActionButton: me.role != Role.vendeur
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () async {
                await context.push('/restocks/new');
                ref.invalidate(restocksProvider);
              },
              icon: const Icon(LucideIcons.plus),
              label: Text(
                me.role == Role.admin ? t.newOrder : t.requestRestock,
              ),
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
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
            spacing: 8,
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
          if (order.status != RestockStatus.cancelled) ...[
            const Gap(12),
            _Steps(order.status),
          ],
        ],
      ),
    );
  }
}

/// Where an order is on its way: requested, on the road, counted, done.
class _Steps extends StatelessWidget {
  const _Steps(this.status);

  final RestockStatus status;

  @override
  Widget build(BuildContext context) {
    final reached = switch (status) {
      RestockStatus.requested => 1,
      RestockStatus.assigned => 2,
      RestockStatus.shipped => 3,
      RestockStatus.received => 4,
      _ => 5,
    };
    return Row(
      children: [
        for (var i = 1; i <= 5; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 5,
              decoration: BoxDecoration(
                color: i <= reached
                    ? context.colors.primary
                    : context.status.mutedSoft,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (i < 5) const SizedBox(width: 4),
        ],
      ],
    );
  }
}
