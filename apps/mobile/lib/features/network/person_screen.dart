import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../analytics/analytics_widgets.dart' show AnalyticsButton;
import '../analytics/lens.dart' show Facet;
import '../planning/planning_repository.dart';
import '../planning/visit_widgets.dart';
import '../restock/restock_list_screen.dart' show RestockTile;
import '../restock/restock_models.dart';
import '../restock/restock_repository.dart';
import 'network_models.dart';
import 'network_repository.dart';
import 'people_widgets.dart';
import 'person_sales.dart';

/// One person, in full: who they are and what the viewer can do about the account, then what they
/// do in the network — a seller's sales, the orders a buyer, a responsable or the order manager
/// took part in, a responsable's visits with what each check-in said.
class PersonDetailScreen extends ConsumerStatefulWidget {
  const PersonDetailScreen({required this.personId, this.initial, super.key});

  final String personId;

  /// The person as the list had them: shown at once, read again after every change.
  final Person? initial;

  @override
  ConsumerState<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen> {
  late Person? _person = widget.initial;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (_person == null) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final person = await ref
          .read(networkRepositoryProvider)
          .person(widget.personId);
      if (mounted) {
        setState(() {
          _person = person;
          _error = null;
        });
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      // The account is gone (an invitation cancelled, a request refused and removed).
      if (error.status == 404 && _person != null) return context.pop();
      if (_person == null) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final person = _person;
    if (person == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error == null
            ? const Center(child: CircularProgressIndicator())
            : ErrorState(error: _error!, onRetry: _load),
      );
    }
    final manager = me.role == Role.admin || me.role == Role.responsable;
    final active = person.status == ItemStatus.active;
    final sells = person.role == Role.vendeur;
    final handlesOrders =
        person.role != Role.admin && !(sells && !person.canOrder);
    return Scaffold(
      appBar: AppBar(
        title: Text(person.name),
        actions: [
          if (sells) AnalyticsButton(facet: Facet.seller, id: person.id),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            PersonPanel(
              person: person,
              onChanged: () {
                ref.invalidate(peopleProvider);
                unawaited(_load());
              },
              // The page stays: what changed shows on it.
              onDone: () {},
            ),
            if (person.pdvId != null) ...[
              const Gap(12),
              _ParaLink(pdvId: person.pdvId!),
            ],
            // What a team member sold, and the way to correct a sale.
            if (sells && active && manager) ...[
              const Gap(20),
              PersonSales(person: person),
            ],
            if (person.role == Role.responsable &&
                active &&
                me.role == Role.admin)
              _PersonVisits(person: person),
            if (handlesOrders && active && manager)
              _PersonOrders(person: person),
          ],
        ),
      ),
    );
  }
}

/// The para a team member works in: one tap opens it.
class _ParaLink extends ConsumerWidget {
  const _ParaLink({required this.pdvId});

  final String pdvId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final pdv = ref.watch(pdvProvider(pdvId)).value;
    if (pdv == null) return const SizedBox.shrink();
    return AppCard(
      onTap: () => context.push('/pdvs/$pdvId'),
      child: Row(
        spacing: 12,
        children: [
          const Icon(LucideIcons.store),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.pointOfSale,
                  style: context.text.labelSmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
                Text(pdv.name, style: context.text.titleSmall),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: context.status.muted),
        ],
      ),
    );
  }
}

/// The latest restock orders the person took part in: asked, prepared, delivered or received.
class _PersonOrders extends ConsumerWidget {
  const _PersonOrders({required this.person});

  final Person person;

  bool _tookPart(RestockOrder o) => [
    o.requestedBy?.id,
    o.receiver?.id,
    o.proposal?.by?.id,
    o.deliveredBy?.id,
  ].contains(person.id);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    // A team member's orders are those of their para; anyone else's are looked for everywhere.
    final RestockQuery query = (
      active: null,
      status: null,
      regionId: null,
      destId: person.role.isTeam ? person.pdvId : null,
    );
    final orders = ref.watch(restocksProvider(query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.personOrders),
        AsyncBody<List<RestockOrder>>(
          value: orders,
          onRetry: () => ref.invalidate(restocksProvider(query)),
          builder: (all) {
            final mine = all.where(_tookPart).toList();
            if (mine.isEmpty) return _Nothing(t.personNoOrders);
            return Column(
              spacing: 8,
              children: [
                for (final o in mine.take(5)) RestockTile(order: o),
                if (mine.length > 5)
                  Text(
                    t.personMoreOrders(mine.length - 5),
                    style: context.text.bodySmall?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A responsable's visits around today (the last 30 days, the next 14), newest first: each shows
/// when they arrived and what the recorded position said, and opens the visit.
class _PersonVisits extends ConsumerWidget {
  const _PersonVisits({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final today = DateTime.now();
    final VisitsQuery query = (
      from: Dates.day(today.subtract(const Duration(days: 30))),
      to: Dates.day(today.add(const Duration(days: 14))),
      responsableId: person.id,
      regionId: null,
    );
    final visits = ref.watch(visitsProvider(query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          t.personVisits,
          trailing: TextButton(
            onPressed: () => context.push('/planning/overview'),
            child: Text(t.seeAll),
          ),
        ),
        AsyncBody(
          value: visits,
          onRetry: () => ref.invalidate(visitsProvider(query)),
          builder: (all) {
            if (all.isEmpty) return _Nothing(t.personNoVisits);
            final list = [...all]
              ..sort((a, b) => b.plannedStart.compareTo(a.plannedStart));
            return Column(
              spacing: 8,
              children: [
                for (final v in list.take(8))
                  VisitCard(
                    visit: v,
                    onTap: () => context.push('/planning/visits/${v.id}'),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Nothing extends StatelessWidget {
  const _Nothing(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: context.text.bodyMedium?.copyWith(color: context.status.muted),
    ),
  );
}
