import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/money.dart';
import '../../../domain/models/sales_trend.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/design.dart';

/// Presentation choices over the same accepted daily records; no extra reads.
enum SalesTrendMetric {
  amount('Montant', 'Ventes nettes', 'TND'),
  units('Unités', 'Unités nettes', 'unités'),
  sales('Ventes', 'Ventes enregistrées', 'ventes');

  final String label, description, unit;
  const SalesTrendMetric(this.label, this.description, this.unit);

  int rawValue(SalesTrendPoint point) => switch (this) {
    amount => point.netMillimes,
    units => point.netUnits,
    sales => point.saleCount,
  };

  double value(SalesTrendPoint point) =>
      rawValue(point) / (this == amount ? 1000 : 1);

  String display(SalesTrendPoint point) => this == amount
      ? Money(point.netMillimes).formatted.replaceFirstMapped(
          RegExp(r'^\d+'),
          (match) => match[0]!.replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
            (digit) => '${digit[1]}\u202f',
          ),
        )
      : '${rawValue(point)} $unit';

  double average(List<SalesTrendPoint> points) => points.isEmpty
      ? 0
      : points.fold<double>(0, (sum, point) => sum + value(point)) /
            points.length;

  String averageLabel(List<SalesTrendPoint> points) {
    final mean = average(points);
    final decimals = this == amount ? 3 : 2;
    final rounded = mean.toStringAsFixed(decimals);
    final approximate = (double.parse(rounded) - mean).abs() > 1e-9;
    return '${approximate ? '≈ ' : ''}${rounded.replaceAll('.', ',')} $unit';
  }
}

class SalesTrendPlot extends StatelessWidget {
  final List<SalesTrendPoint> points;
  final SalesTrendMetric metric;
  final int selected;
  final bool showTooltip, expanded;
  final ValueChanged<int> onSelect;
  const SalesTrendPlot({
    super.key,
    required this.points,
    required this.metric,
    required this.selected,
    required this.onSelect,
    required this.showTooltip,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final scaler = MediaQuery.textScalerOf(context);
      final values = points.map(metric.value).toList(growable: false);
      final peak = values.reduce(math.max);
      final step = _niceStep(
        peak,
        fractional: metric == SalesTrendMetric.amount,
      );
      final height = expanded
          ? (MediaQuery.sizeOf(context).height * .48).clamp(260.0, 440.0)
          : scaler.scale(14) > 20
          ? 280.0
          : 230.0;
      // The same exact values stay in the accessible readout above the plot.
      // Large text should not turn a duplicate canvas tooltip into an overlay
      // covering most of the data.
      final showBubble = scaler.scale(14) <= 21;
      // Reserve space before interaction, so a tooltip never causes the data
      // to rescale while scrubbing. It includes the date, value and padding.
      final tooltipFraction = showBubble
          ? ((scaler.scale(42) + 36) / (height - scaler.scale(14) - 18)).clamp(
              0.0,
              .72,
            )
          : .18;
      final top = math.max(
        step * 3,
        (peak / (1 - tooltipFraction) / step).ceil() * step,
      );
      final mean = metric.average(points);
      const axisStyle = TextStyle(fontSize: 12, color: muted);
      final measure = TextPainter(
        text: TextSpan(text: _axisAmount(top), style: axisStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final rightWidth = math.min(measure.width + 14, bounds.maxWidth * .35);
      measure.dispose();
      final plotWidth = math.max(1.0, bounds.maxWidth - rightWidth);
      final labelCount = (plotWidth / scaler.scale(70)).floor().clamp(2, 6);
      final interval = ((points.length - 1) / (labelCount - 1))
          .ceil()
          .clamp(1, 366)
          .toDouble();
      final spots = [
        for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), values[i]),
      ];
      final bar = LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: .16,
        preventCurveOverShooting: true,
        preventCurveOvershootingThreshold: 0,
        color: darkGreen,
        barWidth: 3,
        isStrokeCapRound: true,
        dotData: FlDotData(
          checkToShowDot: (spot, _) =>
              points.length <= 31 ||
              spot.x.toInt() == selected ||
              spot.x.toInt() % (points.length / 25).ceil() == 0,
          getDotPainter: (_, _, _, index) => index == selected
              ? _FocusDot()
              : FlDotCirclePainter(
                  radius: 2.5,
                  color: Colors.white,
                  strokeColor: darkGreen,
                  strokeWidth: 1.5,
                ),
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF30A46C).withValues(alpha: .22),
              const Color(0xFF30A46C).withValues(alpha: .025),
            ],
          ),
        ),
      );
      return RepaintBoundary(
        child: SizedBox(
          key: const ValueKey('sales-trend-plot'),
          height: height,
          child: LineChart(
            LineChartData(
              minX: points.length == 1 ? -.5 : 0,
              maxX: points.length == 1 ? .5 : (points.length - 1).toDouble(),
              minY: 0,
              maxY: top,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: step,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: Color(0xFFE8EFEB),
                  strokeWidth: 1,
                  dashArray: [3, 5],
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: rightWidth,
                    interval: step,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      space: 10,
                      child: Text(_axisAmount(value), style: axisStyle),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: scaler.scale(14) + 18,
                    interval: interval,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if ((value - index).abs() > .01 ||
                          index < 0 ||
                          index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      final edge = index == 0 || index == points.length - 1;
                      if (!edge &&
                          (index % interval != 0 ||
                              index < interval / 2 ||
                              points.length - 1 - index < interval / 2)) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 12,
                        fitInside: SideTitleFitInsideData(
                          enabled: true,
                          axisPosition: meta.axisPosition,
                          parentAxisSize: meta.parentAxisSize,
                          distanceFromEdge: 0,
                        ),
                        child: Text(
                          TunisDates.dateOnlyLabel(points[index].day)
                              .substring(0, 5),
                          style: axisStyle,
                        ),
                      );
                    },
                  ),
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (mean > 0)
                    HorizontalLine(
                      y: mean,
                      color: const Color(0xFF759786),
                      strokeWidth: 1.2,
                      dashArray: [6, 5],
                    ),
                ],
                verticalLines: [
                  VerticalLine(
                    x: selected.toDouble(),
                    color: darkGreen.withValues(alpha: .3),
                    strokeWidth: 1,
                    dashArray: [3, 4],
                  ),
                ],
              ),
              showingTooltipIndicators: [
                if (showTooltip && showBubble)
                  ShowingTooltipIndicators([
                    LineBarSpot(bar, 0, spots[selected]),
                  ]),
              ],
              lineTouchData: LineTouchData(
                handleBuiltInTouches: false,
                distanceCalculator: (touch, spot) => (touch.dx - spot.dx).abs(),
                touchSpotThreshold: double.infinity,
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions) return;
                  final spot = response?.lineBarSpots?.firstOrNull;
                  if (spot != null) onSelect(spot.spotIndex);
                },
                touchTooltipData: LineTouchTooltipData(
                  tooltipBorderRadius: BorderRadius.circular(10),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  tooltipMargin: 16,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  maxContentWidth: math.max(40, plotWidth - 30),
                  getTooltipColor: (_) => ink,
                  getTooltipItems: (spots) => [
                    for (final spot in spots)
                      LineTooltipItem(
                        '${TunisDates.dateOnlyLabel(points[spot.spotIndex].day)}\n',
                        const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: Color(0xFFCCE2D5),
                          height: 1.5,
                        ),
                        children: [
                          TextSpan(
                            text: metric.display(points[spot.spotIndex]),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              lineBarsData: [bar],
            ),
            // Scrubbing and background refreshes must not animate the data away
            // from the finger or replay a chart transition.
            duration: Duration.zero,
          ),
        ),
      );
    },
  );
}

class _FocusDot extends FlDotCirclePainter {
  _FocusDot()
    : super(
        radius: 5,
        color: darkGreen,
        strokeColor: Colors.white,
        strokeWidth: 2.5,
      );
  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    canvas.drawCircle(
      offsetInCanvas,
      12,
      Paint()..color = darkGreen.withValues(alpha: .12),
    );
    super.draw(canvas, spot, offsetInCanvas);
  }

  @override
  Size getSize(FlSpot spot) => const Size.square(24);
}

double _niceStep(double peak, {required bool fractional}) {
  final target = (peak > 0 ? peak : 1) / 3;
  final magnitude = math.pow(10, (math.log(target) / math.ln10).floor());
  final fraction = target / magnitude;
  return math
      .max(
        fractional ? .001 : 1.0,
        (fraction <= 1
                ? 1
                : fraction <= 2
                ? 2
                : fraction <= 5
                ? 5
                : 10) *
            magnitude,
      )
      .toDouble();
}

String _axisAmount(double amount) {
  final (scaled, suffix) = amount >= 1000000000
      ? (amount / 1000000000, ' Md')
      : amount >= 1000000
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
