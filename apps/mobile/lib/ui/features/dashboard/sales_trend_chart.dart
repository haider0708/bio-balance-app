import 'package:flutter/material.dart';

import '../../../domain/models/money.dart';
import '../../../domain/models/sales_trend.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/design.dart';
import 'sales_trend_plot.dart';

typedef _Selection = ({String? day, SalesTrendMetric metric});

class SalesTrendChart extends StatefulWidget {
  final List<SalesTrendPoint> points;
  final ValueChanged<SalesTrendPoint> onOpenDay;
  final String? scopeLabel;
  final bool _expanded;
  final _Selection? _initialSelection;
  final ValueChanged<_Selection>? _onSelection;
  const SalesTrendChart({
    super.key,
    required this.points,
    required this.onOpenDay,
    this.scopeLabel,
  }) : _expanded = false,
       _initialSelection = null,
       _onSelection = null;

  const SalesTrendChart._expanded(
    this._initialSelection,
    this._onSelection, {
    required this.points,
    required this.onOpenDay,
    required this.scopeLabel,
  }) : _expanded = true;

  @override
  State<SalesTrendChart> createState() => _SalesTrendChartState();
}

class _SalesTrendChartState extends State<SalesTrendChart> {
  late String? selectedDay = widget._initialSelection?.day;
  late SalesTrendMetric metric =
      widget._initialSelection?.metric ?? SalesTrendMetric.amount;
  bool showTooltip = false, expanding = false;

  int get selectedIndex {
    final selected = widget.points.indexWhere((p) => p.day == selectedDay);
    if (selected >= 0) return selected;
    final lastActive = widget.points.lastIndexWhere((p) => p.saleCount > 0);
    return lastActive >= 0 ? lastActive : widget.points.length - 1;
  }

  void select(int index, {bool fromPlot = false}) {
    if (index < 0 || index >= widget.points.length) return;
    final day = widget.points[index].day;
    if (selectedDay == day && showTooltip == fromPlot) return;
    setState(() {
      selectedDay = day;
      showTooltip = fromPlot;
    });
    widget._onSelection?.call((day: day, metric: metric));
  }

  void changeMetric(SalesTrendMetric next) {
    if (metric == next) return;
    setState(() {
      metric = next;
      showTooltip = false;
    });
    widget._onSelection?.call((
      day: widget.points[selectedIndex].day,
      metric: metric,
    ));
  }

  Future<void> expand() async {
    if (expanding) return;
    setState(() => expanding = true);
    _Selection selection = (
      day: widget.points[selectedIndex].day,
      metric: metric,
    );
    final points = widget.points;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Évolution des ventes')),
            body: Content(
              maxWidth: 1200,
              children: [
                Wrap(
                  spacing: 24,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.scopeLabel != null)
                      Text(
                        widget.scopeLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    Text(
                      '${TunisDates.dateOnlyLabel(points.first.day)} – ${TunisDates.dateOnlyLabel(points.last.day)}',
                      style: const TextStyle(fontSize: 14, color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SalesTrendChart._expanded(
                  selection,
                  (value) => selection = value,
                  points: points,
                  scopeLabel: widget.scopeLabel,
                  onOpenDay: widget.onOpenDay,
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          expanding = false;
          selectedDay = selection.day;
          metric = selection.metric;
          showTooltip = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) return const SizedBox.shrink();
    final points = widget.points, selected = selectedIndex;
    final current = points[selected];
    var peak = 0;
    for (var i = 1; i < points.length; i++) {
      if (metric.rawValue(points[i]) > metric.rawValue(points[peak])) peak = i;
    }
    final hasActivity = points.any((p) => p.saleCount > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, current, selected),
        const SizedBox(height: 16),
        ExcludeSemantics(
          child: SalesTrendPlot(
            points: points,
            metric: metric,
            selected: selected,
            showTooltip: showTooltip,
            expanded: widget._expanded,
            onSelect: (index) => select(index, fromPlot: true),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        const Padding(
                          padding: EdgeInsets.only(right: 3),
                          child: SizedBox(
                            width: 4,
                            height: 2,
                            child: ColoredBox(color: Color(0xFF759786)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Moyenne/jour · ${metric.averageLabel(points)}',
                    key: const ValueKey('sales-trend-average'),
                    style: const TextStyle(fontSize: 14, color: muted),
                  ),
                ),
              ],
            ),
            if (hasActivity)
              TextButton.icon(
                key: const ValueKey('sales-trend-peak'),
                onPressed: () => select(peak, fromPlot: true),
                icon: const Icon(AppIcons.trendingUp, size: 18),
                label: const Text('Meilleur jour'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
          ],
        ),
        if (!hasActivity)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Aucune vente enregistrée sur cette période.',
              style: TextStyle(fontSize: 14, color: muted),
            ),
          ),
        const Divider(height: 20),
        Text(
          '${current.netUnits} unités nettes · ${current.saleCount} ventes enregistrées',
          style: const TextStyle(fontSize: 14, color: muted),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [
            TextButton.icon(
              key: const ValueKey('sales-trend-open-day'),
              onPressed: () => widget.onOpenDay(current),
              icon: const Icon(AppIcons.receiptLongOutlined, size: 18),
              label: const Text('Ventes du jour'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
            ),
            TextButton.icon(
              onPressed: showData,
              icon: const Icon(AppIcons.table, size: 18),
              label: const Text('Toutes les données'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: muted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _header(BuildContext context, SalesTrendPoint current, int selected) {
    final animation = AnimationStyle(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
    );
    final controls = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final option in SalesTrendMetric.values)
                ChoiceChip(
                  key: ValueKey('sales-trend-metric:${option.name}'),
                  label: Text(option.label),
                  selected: metric == option,
                  onSelected: (_) => changeMetric(option),
                  showCheckmark: false,
                  selectedColor: darkGreen,
                  backgroundColor: const Color(0xFFF1F8F4),
                  side: BorderSide.none,
                  labelStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: metric == option ? Colors.white : muted,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  chipAnimationStyle: ChipAnimationStyle(
                    selectAnimation: animation,
                    enableAnimation: animation,
                  ),
                ),
            ],
          ),
        ),
        if (!widget._expanded)
          IconButton(
            tooltip: 'Agrandir le graphique',
            onPressed: expanding ? null : expand,
            icon: const Icon(AppIcons.expand, size: 20),
          ),
      ],
    );
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                TunisDates.dateOnlyLabel(current.day),
                key: const ValueKey('sales-trend-date'),
                style: const TextStyle(fontSize: 14, color: muted),
              ),
            ),
            IconButton(
              tooltip: 'Jour précédent',
              onPressed: selected > 0 ? () => select(selected - 1) : null,
              icon: const Icon(AppIcons.chevronLeft, size: 20),
            ),
            IconButton(
              tooltip: 'Jour suivant',
              onPressed: selected < widget.points.length - 1
                  ? () => select(selected + 1)
                  : null,
              icon: const Icon(AppIcons.chevronRight, size: 20),
            ),
          ],
        ),
        Semantics(
          liveRegion: true,
          excludeSemantics: true,
          label:
              '${TunisDates.dateOnlyLabel(current.day)}, ${Money(current.netMillimes).formatted}, ${current.netUnits} unités nettes, ${current.saleCount} ventes enregistrées',
          child: Text(
            metric.display(current),
            key: const ValueKey('sales-trend-value'),
            style: const TextStyle(
              fontSize: 28,
              height: 1.25,
              fontWeight: FontWeight.w700,
              letterSpacing: -.6,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(
          metric.description,
          style: const TextStyle(fontSize: 14, color: muted),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth >= 600) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    controls,
                    const SizedBox(height: 8),
                    const Text(
                      'Touchez ou glissez pour explorer.',
                      style: TextStyle(fontSize: 14, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(child: summary),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [controls, const SizedBox(height: 8), summary],
        );
      },
    );
  }

  void showData() {
    final points = widget.points;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Données du graphique')),
          body: Content.builder(
            itemCount: points.length,
            itemBuilder: (_, index) {
              final point = points[index];
              return CompactRow(
                title: TunisDates.dateOnlyLabel(point.day),
                value: Money(point.netMillimes).formatted,
                subtitle:
                    '${point.netUnits} unités nettes · ${point.saleCount} ventes enregistrées',
                onTap: () => widget.onOpenDay(point),
              );
            },
            children: [
              if (widget.scopeLabel != null) SectionTitle(widget.scopeLabel!),
            ],
          ),
        ),
      ),
    );
  }
}
