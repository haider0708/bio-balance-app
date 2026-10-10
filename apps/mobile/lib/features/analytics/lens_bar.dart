import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/json.dart';
import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../catalog/catalog_repository.dart';
import '../network/network_models.dart';
import '../network/network_repository.dart';
import 'lens.dart';

String presetLabel(AppLocalizations t, PeriodPreset p) => switch (p) {
  PeriodPreset.today => t.today,
  PeriodPreset.yesterday => t.yesterday,
  PeriodPreset.last7 => t.period7,
  PeriodPreset.last30 => t.period30,
  PeriodPreset.thisMonth => t.thisMonth,
  PeriodPreset.lastMonth => t.lastMonth,
  PeriodPreset.last90 => t.period90,
};

/// Pick a period: one tap for the usual ones, a calendar for anything else. The chosen one
/// is scrolled into view, so a narrow screen always shows which period is on.
class PeriodChips extends StatefulWidget {
  const PeriodChips({
    required this.from,
    required this.to,
    required this.onChanged,
    super.key,
  });

  final String from;
  final String to;
  final void Function(String from, String to) onChanged;

  @override
  State<PeriodChips> createState() => _PeriodChipsState();
}

class _PeriodChipsState extends State<PeriodChips> {
  final _selected = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void didUpdateWidget(PeriodChips old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  void _reveal() {
    final chip = _selected.currentContext;
    if (chip != null && chip.mounted) {
      Scrollable.ensureVisible(
        chip,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final from = widget.from;
    final to = widget.to;
    final onChanged = widget.onChanged;
    final current = PeriodPreset.of(Lens(from: from, to: to));
    final custom = current == null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in PeriodPreset.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                key: current == p ? _selected : null,
                label: Text(presetLabel(t, p)),
                selected: current == p,
                onSelected: (_) {
                  final r = p.range();
                  onChanged(r.from, r.to);
                },
              ),
            ),
          ChoiceChip(
            key: custom ? _selected : null,
            avatar: const Icon(LucideIcons.calendarRange, size: 16),
            label: Text(
              custom
                  ? from == to
                        ? Dates.full(Dates.parseDay(from), t.localeName)
                        : '${Dates.short(Dates.parseDay(from), t.localeName)} – ${Dates.full(Dates.parseDay(to), t.localeName)}'
                  : t.customPeriod,
            ),
            selected: custom,
            onSelected: (_) async {
              final today = Dates.parseDay(tunisToday());
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2026),
                lastDate: today,
                initialDateRange: DateTimeRange(
                  start: Dates.parseDay(from),
                  end: Dates.parseDay(to).isAfter(today)
                      ? today
                      : Dates.parseDay(to),
                ),
              );
              if (picked == null) return;
              // The server reads at most 400 days at once.
              final start = picked.end.difference(picked.start).inDays > 399
                  ? picked.end.subtract(const Duration(days: 399))
                  : picked.start;
              onChanged(Dates.day(start), Dates.day(picked.end));
            },
          ),
        ],
      ),
    );
  }
}

/// The period and the narrowing of a lens: each narrowing is a chip that can be removed, and
/// "Filter" adds one.
class LensBar extends ConsumerWidget {
  const LensBar({
    required this.lens,
    required this.subject,
    required this.onChange,
    super.key,
  });

  final Lens lens;
  final Json subject;
  final ValueChanged<Lens> onChange;

  String _name(AppLocalizations t, Facet f) =>
      switch (f) {
        Facet.region => subject.objOrNull('region')?.str('name'),
        Facet.group => subject.objOrNull('group')?.str('name'),
        Facet.pdv => subject.objOrNull('pdv')?.str('name'),
        Facet.seller => subject.objOrNull('seller')?.str('name'),
        Facet.product => subject.objOrNull('product')?.str('name'),
        Facet.family => subject.strOrNull('family'),
      } ??
      '…';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final admin = ref.watch(meProvider).role == Role.admin;
    final available = [
      for (final f in Facet.values)
        if (lens.value(f) == null && (f != Facet.region || admin)) f,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PeriodChips(
          from: lens.from,
          to: lens.to,
          onChanged: (from, to) => onChange(lens.copyWith(from: from, to: to)),
        ),
        const Gap(6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final f in lens.facets)
              InputChip(
                avatar: Icon(facetIcon(f), size: 16),
                label: Text(t.facetChip(facetLabel(t, f), _name(t, f))),
                onDeleted: () => onChange(lens.withFacet(f, null)),
                deleteButtonTooltipMessage: t.removeFilter,
              ),
            if (available.isNotEmpty)
              ActionChip(
                avatar: const Icon(LucideIcons.listFilter, size: 16),
                label: Text(t.addFilter),
                onPressed: () async {
                  final picked = await pickFacet(context, ref, lens, available);
                  if (picked != null) onChange(picked);
                },
              ),
          ],
        ),
      ],
    );
  }
}

IconData facetIcon(Facet f) => switch (f) {
  Facet.region => LucideIcons.map,
  Facet.group => LucideIcons.layers,
  Facet.pdv => LucideIcons.store,
  Facet.seller => LucideIcons.user,
  Facet.product => LucideIcons.package,
  Facet.family => LucideIcons.tags,
};

String facetLabel(AppLocalizations t, Facet f) => switch (f) {
  Facet.region => t.facetRegion,
  Facet.group => t.facetGroup,
  Facet.pdv => t.facetStore,
  Facet.seller => t.facetSeller,
  Facet.product => t.facetProduct,
  Facet.family => t.facetFamily,
};

class _Option {
  const _Option(this.id, this.title, [this.subtitle]);

  final String id;
  final String title;
  final String? subtitle;
}

/// Choose what to narrow to (a store, a product…) and which one; null when cancelled.
Future<Lens?> pickFacet(
  BuildContext context,
  WidgetRef ref,
  Lens lens,
  List<Facet> available,
) async {
  final t = AppLocalizations.of(context);
  final facet = available.length == 1
      ? available.single
      : await showModalBottomSheet<Facet>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(t.filterBy, style: context.text.titleLarge),
                ),
                for (final f in available)
                  ListTile(
                    leading: Icon(facetIcon(f)),
                    title: Text(facetLabel(t, f)),
                    trailing: const Icon(LucideIcons.chevronRight, size: 18),
                    onTap: () => Navigator.pop(context, f),
                  ),
                const Gap(8),
              ],
            ),
          ),
        );
  if (facet == null || !context.mounted) return null;
  Future<List<_Option>> load() async {
    switch (facet) {
      case Facet.region:
        return [
          for (final r in await ref.read(regionsProvider.future))
            _Option(r.id, r.name),
        ];
      case Facet.group:
        return [
          for (final g in await ref.read(groupsProvider(lens.regionId).future))
            if (g.status == ItemStatus.active)
              _Option(g.id, g.name, t.pdvCount(g.pdvCount)),
        ];
      case Facet.pdv:
        return [
          for (final p in await ref.read(pdvsProvider(lens.regionId).future))
            if (lens.groupId == null || p.groupId == lens.groupId)
              _Option(p.id, p.name, [p.city, ?p.groupName].join(' · ')),
        ];
      case Facet.seller:
        return [
          for (final p in await ref.read(
            peopleProvider((
              role: 'VENDEUR',
              pdvId: lens.pdvId,
              regionId: lens.regionId,
              status: null,
            )).future,
          ))
            _Option(p.id, p.name, p.email),
        ];
      case Facet.product:
        return [
          for (final p in await ref.read(allProductsProvider.future))
            if (lens.family == null || p.family == lens.family)
              _Option(p.id, p.name, [p.reference, p.family].join(' · ')),
        ];
      case Facet.family:
        final families = {
          for (final p in await ref.read(allProductsProvider.future))
            if (p.family.isNotEmpty) p.family,
        }.toList()..sort();
        return [for (final f in families) _Option(f, f)];
    }
  }

  final id = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _OptionSheet(title: facetLabel(t, facet), load: load),
  );
  return id == null ? null : lens.withFacet(facet, id);
}

class _OptionSheet extends StatefulWidget {
  const _OptionSheet({required this.title, required this.load});

  final String title;
  final Future<List<_Option>> Function() load;

  @override
  State<_OptionSheet> createState() => _OptionSheetState();
}

class _OptionSheetState extends State<_OptionSheet> {
  late final Future<List<_Option>> _options = widget.load();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(widget.title, style: context.text.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(LucideIcons.search),
                hintText: t.search,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_Option>>(
              future: _options,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorState(error: snap.error!);
                }
                if (!snap.hasData) return const LoadingState();
                final shown = snap.data!
                    .where(
                      (o) =>
                          _query.isEmpty ||
                          o.title.toLowerCase().contains(_query) ||
                          (o.subtitle?.toLowerCase().contains(_query) ?? false),
                    )
                    .toList();
                if (shown.isEmpty) {
                  return EmptyState(
                    icon: LucideIcons.searchX,
                    title: t.noResults,
                  );
                }
                return ListView.builder(
                  controller: scroll,
                  itemCount: shown.length,
                  itemBuilder: (context, i) => ListTile(
                    title: Text(shown[i].title),
                    subtitle:
                        shown[i].subtitle == null || shown[i].subtitle!.isEmpty
                        ? null
                        : Text(shown[i].subtitle!),
                    onTap: () => Navigator.pop(context, shown[i].id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
