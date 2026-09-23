import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/money.dart';
import '../../../domain/models/sales_trend.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/design.dart';

class SalesTrendChart extends StatefulWidget {
  final List<SalesTrendPoint> points;
  final ValueChanged<SalesTrendPoint> onOpenDay;
  const SalesTrendChart({
    super.key,
    required this.points,
    required this.onOpenDay,
  });

  @override
  State<SalesTrendChart> createState() => _SalesTrendChartState();
}

class _SalesTrendChartState extends State<SalesTrendChart> {
  String? selectedDay;

  int get selectedIndex {
    final selected = widget.points.indexWhere((p) => p.day == selectedDay);
    if (selected >= 0) return selected;
    final lastActive = widget.points.lastIndexWhere((p) => p.saleCount > 0);
    return lastActive >= 0 ? lastActive : widget.points.length - 1;
  }

  void select(int index) {
    if (index < 0 || index >= widget.points.length) return;
    final day = widget.points[index].day;
    if (selectedDay != day) setState(() => selectedDay = day);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) return const SizedBox.shrink();
    final points = widget.points, selected = selectedIndex;
    final current = points[selected];
    final textScale = MediaQuery.textScalerOf(context);
    final values = [for (final p in points) p.netMillimes / 1000];
    final peak = values.reduce(math.max);
    final target = (peak > 0 ? peak : 1) / 4;
    final magnitude = math.pow(10, (math.log(target) / math.ln10).floor());
    final fraction = target / magnitude;
    final step = math.max(
      .001,
      (fraction <= 1
              ? 1
              : fraction <= 2
              ? 2
              : fraction <= 5
              ? 5
              : 10) *
          magnitude,
    );
    final top = ((peak / step).floor() + 1) * step;
    final spots = [
      for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), values[i]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Ventes nettes · TND',
          style: TextStyle(fontSize: 14, color: muted),
        ),
        const SizedBox(height: 12),
        ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, bounds) {
              final labelCount = (bounds.maxWidth / textScale.scale(85))
                  .floor()
                  .clamp(2, 5);
              final interval = ((points.length - 1) / (labelCount - 1))
                  .ceil()
                  .clamp(1, 366)
                  .toDouble();
              return SizedBox(
                key: const ValueKey('sales-trend-plot'),
                height: textScale.scale(14) > 20 ? 260 : 220,
                child: LineChart(
                  LineChartData(
                    minX: points.length == 1 ? -.5 : 0,
                    maxX: points.length == 1
                        ? .5
                        : (points.length - 1).toDouble(),
                    minY: 0,
                    maxY: top.toDouble(),
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: step.toDouble(),
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: Color(0xFFE5EDE8),
                        strokeWidth: 1,
                        dashArray: [4, 4],
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: textScale.scale(48),
                          interval: step.toDouble(),
                          getTitlesWidget: (value, meta) => SideTitleWidget(
                            meta: meta,
                            space: 8,
                            child: Text(
                              _axisAmount(value),
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: textScale.scale(14) + 18,
                          interval: interval,
                          getTitlesWidget: (value, meta) {
                            final index = value.round();
                            if ((value - index).abs() > .01 ||
                                index < 0 ||
                                index >= points.length) {
                              return const SizedBox.shrink();
                            }
                            final edge =
                                index == 0 || index == points.length - 1;
                            if (!edge &&
                                (index < interval / 2 ||
                                    points.length - 1 - index < interval / 2)) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              meta: meta,
                              space: 10,
                              fitInside: SideTitleFitInsideData(
                                enabled: true,
                                axisPosition: meta.axisPosition,
                                parentAxisSize: meta.parentAxisSize,
                                distanceFromEdge: 0,
                              ),
                              child: Text(
                                TunisDates.dateOnlyLabel(points[index].day)
                                    .substring(0, 5),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    extraLinesData: ExtraLinesData(
                      verticalLines: [
                        VerticalLine(
                          x: selected.toDouble(),
                          color: darkGreen.withValues(alpha: .35),
                          strokeWidth: 1,
                          dashArray: [4, 4],
                        ),
                      ],
                    ),
                    lineTouchData: LineTouchData(
                      handleBuiltInTouches: false,
                      distanceCalculator: (touch, spot) =>
                          (touch.dx - spot.dx).abs(),
                      touchSpotThreshold: double.infinity,
                      touchCallback: (event, response) {
                        if (!event.isInterestedForInteractions) return;
                        final spot = response?.lineBarSpots?.firstOrNull;
                        if (spot != null) select(spot.spotIndex);
                      },
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: false,
                        color: darkGreen,
                        barWidth: 2.5,
                        isStrokeCapRound: true,
                        dotData: FlDotData(
                          checkToShowDot: (spot, _) =>
                              points.length <= 45 ||
                              spot.x.toInt() == selected ||
                              spot.x.toInt() % (points.length / 40).ceil() == 0,
                          getDotPainter: (spot, _, _, index) =>
                              FlDotCirclePainter(
                                radius: index == selected ? 5 : 2.5,
                                color: index == selected
                                    ? darkGreen
                                    : Colors.white,
                                strokeColor: index == selected
                                    ? Colors.white
                                    : darkGreen,
                                strokeWidth: index == selected ? 2.5 : 1.5,
                              ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              darkGreen.withValues(alpha: .12),
                              const Color(0xFFF1F8F4).withValues(alpha: .25),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  duration: Duration.zero,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Touchez un point ou faites glisser pour explorer les jours.',
          style: TextStyle(fontSize: 14, color: muted),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF1F8F4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        TunisDates.dateOnlyLabel(current.day),
                        key: const ValueKey('sales-trend-date'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Jour précédent',
                      onPressed: selected > 0
                          ? () => select(selected - 1)
                          : null,
                      icon: const Icon(AppIcons.chevronLeft),
                    ),
                    IconButton(
                      tooltip: 'Jour suivant',
                      onPressed: selected < points.length - 1
                          ? () => select(selected + 1)
                          : null,
                      icon: const Icon(AppIcons.chevronRight),
                    ),
                  ],
                ),
                Semantics(
                  liveRegion: true,
                  excludeSemantics: true,
                  label:
                      '${TunisDates.dateOnlyLabel(current.day)}, ${Money(current.netMillimes).formatted}, ${current.netUnits} unités nettes, ${current.saleCount} ventes enregistrées',
                  child: Text(
                    Money(current.netMillimes).formatted,
                    key: const ValueKey('sales-trend-value'),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${current.netUnits} unités nettes · ${current.saleCount} ventes enregistrées',
                  style: const TextStyle(fontSize: 14, color: muted),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('sales-trend-open-day'),
                    onPressed: () => widget.onOpenDay(current),
                    icon: const Icon(AppIcons.receiptLongOutlined, size: 18),
                    label: const Text('Voir les ventes de ce jour'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => Navigator.push(
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
                  ),
                ),
              ),
            ),
            child: const Text('Voir toutes les données'),
          ),
        ),
      ],
    );
  }
}

String _axisAmount(double amount) {
  final (scaled, suffix) = amount >= 1000000
      ? (amount / 1000000, ' M')
      : amount >= 1000
      ? (amount / 1000, ' k')
      : (amount, '');
  final label = scaled
      .toStringAsFixed(suffix.isEmpty ? 3 : 1)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return '${label.replaceAll('.', ',')}$suffix';
}
