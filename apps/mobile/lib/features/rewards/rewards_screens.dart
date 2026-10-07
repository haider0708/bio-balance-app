import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/json.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/util/money.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/quantity_editor.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../catalog/catalog_repository.dart';
import '../media/media_repository.dart';
import 'rewards_models.dart';
import 'rewards_repository.dart';

/// What each product pays per unit sold. The admin sets it per family or per product, for a period.
class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.rewardsTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: t.paysToday),
              Tab(text: t.periods),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: null,
          onPressed: () async {
            await context.push('/rewards/new');
            ref.invalidate(rewardRulesProvider);
            ref.invalidate(effectiveRewardsProvider);
          },
          icon: const Icon(LucideIcons.plus),
          label: Text(t.setReward),
        ),
        body: const TabBarView(children: [_Today(), _Periods()]),
      ),
    );
  }
}

class _Today extends ConsumerStatefulWidget {
  const _Today();

  @override
  ConsumerState<_Today> createState() => _TodayState();
}

class _TodayState extends ConsumerState<_Today> {
  String _query = '';

  Future<void> _set(RewardPreset preset) async {
    await context.push('/rewards/new', extra: preset);
    ref.invalidate(rewardRulesProvider);
    ref.invalidate(effectiveRewardsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final day = Dates.day(DateTime.now());
    final effective = ref.watch(effectiveRewardsProvider(day));
    return AsyncBody(
      value: effective,
      onRetry: () => ref.invalidate(effectiveRewardsProvider(day)),
      isEmpty: (l) => l.isEmpty,
      empty: EmptyState(
        icon: LucideIcons.banknote,
        title: t.noRewardsYet,
        message: t.noRewardsYetHint,
      ),
      builder: (list) {
        final shown = list
            .where(
              (r) =>
                  _query.isEmpty ||
                  r.name.toLowerCase().contains(_query) ||
                  r.family.toLowerCase().contains(_query),
            )
            .toList();
        final byFamily = <String, List<EffectiveReward>>{};
        for (final r in shown) {
          byFamily.putIfAbsent(r.family, () => []).add(r);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: t.searchProducts,
                prefixIcon: const Icon(LucideIcons.search, size: 20),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            for (final family in byFamily.keys.toList()..sort())
              _FamilyCard(
                family: family,
                rewards: byFamily[family]!,
                onSetFamily: () => _set(RewardPreset.family(family)),
                onSetProduct: (r) =>
                    _set(RewardPreset.product(r.productId, r.name)),
              ),
            if (shown.isEmpty)
              EmptyState(
                icon: LucideIcons.packageSearch,
                title: t.noProductsFound,
              ),
          ],
        );
      },
    );
  }
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({
    required this.family,
    required this.rewards,
    required this.onSetFamily,
    required this.onSetProduct,
  });

  final String family;
  final List<EffectiveReward> rewards;
  final VoidCallback onSetFamily;
  final ValueChanged<EffectiveReward> onSetProduct;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // The family rate is what the products without their own rate earn.
    final familyRate = rewards
        .where((r) => r.source == RewardSource.family)
        .map((r) => r.amountMillimes)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            InkWell(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              onTap: onSetFamily,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: context.colors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        LucideIcons.layers,
                        size: 20,
                        color: context.colors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(family, style: context.text.titleSmall),
                          if (familyRate != null)
                            Text(
                              t.familyRate(
                                Money.format(familyRate, t.localeName),
                              ),
                              style: context.text.bodySmall?.copyWith(
                                color: context.status.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      LucideIcons.pencil,
                      size: 18,
                      color: context.status.muted,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            for (final r in rewards)
              InkWell(
                onTap: () => onSetProduct(r),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      AuthImage(
                        r.imageId,
                        width: 44,
                        height: 44,
                        radius: 10,
                        placeholderIcon: LucideIcons.package,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.name,
                              style: context.text.bodyMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            switch (r.source) {
                              RewardSource.product => StatusChip(
                                t.ownRate,
                                tone: Tone.success,
                              ),
                              RewardSource.family => Text(
                                t.followsFamily,
                                style: context.text.bodySmall?.copyWith(
                                  color: context.status.muted,
                                ),
                              ),
                              RewardSource.none => const SizedBox.shrink(),
                            },
                          ],
                        ),
                      ),
                      Text(
                        r.source == RewardSource.none
                            ? '—'
                            : Money.format(r.amountMillimes, t.localeName),
                        style: context.text.titleMedium?.copyWith(
                          color: r.source == RewardSource.none
                              ? context.status.muted
                              : context.colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A starting point for the reward form, when it is opened from a family or a product.
class RewardPreset {
  const RewardPreset.family(String this.family)
    : productId = null,
      productName = null;
  const RewardPreset.product(String this.productId, this.productName)
    : family = null;

  final String? family;
  final String? productId;
  final String? productName;
}

class _Periods extends ConsumerStatefulWidget {
  const _Periods();

  @override
  ConsumerState<_Periods> createState() => _PeriodsState();
}

class _PeriodsState extends ConsumerState<_Periods> {
  String _when = 'current';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final rules = ref.watch(rewardRulesProvider(_when));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'current', label: Text(t.current)),
              ButtonSegment(value: 'upcoming', label: Text(t.upcoming)),
              ButtonSegment(value: 'past', label: Text(t.past)),
            ],
            selected: {_when},
            onSelectionChanged: (s) => setState(() => _when = s.first),
          ),
        ),
        Expanded(
          child: AsyncBody(
            value: rules,
            onRetry: () => ref.invalidate(rewardRulesProvider(_when)),
            isEmpty: (l) => l.isEmpty,
            empty: EmptyState(
              icon: LucideIcons.calendarRange,
              title: t.noRulesHere,
            ),
            builder: (list) => ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Gap(8),
              itemBuilder: (context, i) {
                final r = list[i];
                final range = r.endsOn == null
                    ? t.fromDate(Dates.full(r.startsOn, t.localeName))
                    : t.dateRange(
                        Dates.full(r.startsOn, t.localeName),
                        Dates.full(r.endsOn!, t.localeName),
                      );
                return AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: context.colors.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              r.byProduct
                                  ? LucideIcons.package
                                  : LucideIcons.layers,
                              color: context.colors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.targetName,
                                  style: context.text.titleSmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                StatusChip(
                                  r.byProduct ? t.byProduct : t.byFamily,
                                  tone: r.byProduct ? Tone.success : Tone.muted,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                Money.format(r.amountMillimes, t.localeName),
                                style: context.text.titleLarge?.copyWith(
                                  color: context.colors.primary,
                                ),
                              ),
                              Text(
                                t.perUnit,
                                style: context.text.bodySmall?.copyWith(
                                  color: context.status.muted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            LucideIcons.calendarRange,
                            size: 16,
                            color: context.status.muted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(range, style: context.text.bodyMedium),
                          ),
                          if (_when != 'past')
                            TextButton.icon(
                              onPressed: () async {
                                if (await confirm(
                                      context,
                                      title: t.cancelRuleTitle,
                                      message: t.cancelRuleBody,
                                      confirmLabel: t.cancelRule,
                                      destructive: true,
                                    ) &&
                                    context.mounted) {
                                  if (await perform(
                                    context,
                                    () => ref
                                        .read(rewardsRepositoryProvider)
                                        .cancel(r.id),
                                    success: t.ruleCancelled,
                                  )) {
                                    ref.invalidate(rewardRulesProvider);
                                    ref.invalidate(effectiveRewardsProvider);
                                  }
                                }
                              },
                              icon: Icon(
                                LucideIcons.trash2,
                                size: 16,
                                color: context.status.danger,
                              ),
                              label: Text(
                                t.cancelRule,
                                style: TextStyle(color: context.status.danger),
                              ),
                            ),
                        ],
                      ),
                      if (r.note != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          r.note!,
                          style: context.text.bodySmall?.copyWith(
                            color: context.status.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Set an amount for a family or a product, for a period.
class RewardFormScreen extends ConsumerStatefulWidget {
  const RewardFormScreen({this.preset, super.key});

  final RewardPreset? preset;

  @override
  ConsumerState<RewardFormScreen> createState() => _RewardFormScreenState();
}

class _RewardFormScreenState extends ConsumerState<RewardFormScreen> {
  bool _byProduct = false;
  String? _family;
  String? _productId;
  String? _productName;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _start = DateTime.now();
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final preset = widget.preset;
    if (preset != null) {
      _byProduct = preset.productId != null;
      _family = preset.family;
      _productId = preset.productId;
      _productName = preset.productName;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _valid =>
      (_byProduct ? _productId != null : _family != null) &&
      Money.parse(_amount.text) != null &&
      (_end == null || !_end!.isBefore(_start));

  Future<void> _save({bool replace = false}) async {
    final t = AppLocalizations.of(context);
    final repo = ref.read(rewardsRepositoryProvider);
    final body = <String, Object?>{
      'scope': _byProduct ? 'PRODUCT' : 'FAMILY',
      if (_byProduct) 'productId': _productId else 'family': _family,
      'amountMillimes': Money.parse(_amount.text),
      'startsOn': Dates.day(_start),
      'endsOn': _end == null ? null : Dates.day(_end!),
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      if (replace) 'replaceOverlap': true,
    };
    try {
      await repo.create(body);
      if (!mounted) return;
      showMessage(context, t.rewardSaved);
      context.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'RULE_OVERLAP') {
        final existing =
            ((error.details as Json?)?['existing'] as List<dynamic>? ??
                    const [])
                .cast<Json>();
        final replace = await confirm(
          context,
          title: t.overlapTitle,
          message: t.overlapBody(
            existing
                .map(
                  (e) =>
                      '${e.str('startsOn')} → ${e.strOrNull('endsOn') ?? '∞'} (${Money.format(e.integer('amountMillimes'), t.localeName)})',
                )
                .join('\n'),
          ),
          confirmLabel: t.replaceValue,
        );
        if (replace && mounted) await _save(replace: true);
        return;
      }
      showError(context, error);
    }
  }

  Future<void> _pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : (_end ?? _start),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => start ? _start = picked : _end = picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final products = ref.watch(productsProvider).value ?? const [];
    final families = {for (final p in products) p.family}.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text(t.setReward)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(t.byFamily),
                icon: const Icon(LucideIcons.layers),
              ),
              ButtonSegment(
                value: true,
                label: Text(t.byProduct),
                icon: const Icon(LucideIcons.package),
              ),
            ],
            selected: {_byProduct},
            onSelectionChanged: (s) => setState(() => _byProduct = s.first),
          ),
          const Gap(16),
          if (!_byProduct)
            DropdownButtonFormField<String>(
              initialValue: _family,
              decoration: InputDecoration(labelText: t.family),
              items: [
                for (final f in families)
                  DropdownMenuItem(value: f, child: Text(f)),
              ],
              onChanged: (v) => setState(() => _family = v),
            )
          else
            AppCard(
              onTap: () async {
                final picked = await ProductPickerSheet.show(
                  context,
                  single: true,
                );
                if (picked != null)
                  setState(() {
                    _productId = picked.first.id;
                    _productName = picked.first.name;
                  });
              },
              child: Row(
                children: [
                  const Icon(LucideIcons.package),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _productName ?? t.chooseProduct,
                      style: context.text.titleSmall,
                    ),
                  ),
                  const Icon(LucideIcons.chevronRight, size: 18),
                ],
              ),
            ),
          const Gap(16),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: t.amountPerUnit,
              suffixText: 'TND',
              helperText: t.amountPerUnitHint,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const Gap(16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(true),
                  icon: const Icon(LucideIcons.calendar),
                  label: Text(t.startsOn(Dates.full(_start, t.localeName))),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            ],
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(false),
                  icon: const Icon(LucideIcons.calendarCheck),
                  label: Text(
                    _end == null
                        ? t.noEndDate
                        : t.endsOn(Dates.full(_end!, t.localeName)),
                  ),
                ),
              ),
              if (_end != null)
                IconButton(
                  onPressed: () => setState(() => _end = null),
                  icon: const Icon(LucideIcons.x),
                ),
            ],
          ),
          const Gap(16),
          TextField(
            controller: _note,
            maxLength: 300,
            decoration: InputDecoration(labelText: '${t.note} (${t.optional})'),
          ),
          const Gap(8),
          AsyncButton(label: t.saveReward, onPressed: _valid ? _save : null),
        ],
      ),
    );
  }
}
