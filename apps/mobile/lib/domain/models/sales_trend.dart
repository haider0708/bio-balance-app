import 'dashboard.dart';
import 'models.dart';
import 'tunis_dates.dart';

/// Exact daily reporting values. Only the chart converts millimes to doubles.
class SalesTrendPoint {
  final String day;
  final int netMillimes, netUnits, saleCount;
  const SalesTrendPoint({
    required this.day,
    this.netMillimes = 0,
    this.netUnits = 0,
    this.saleCount = 0,
  });

  DashboardPeriod get period =>
      DashboardPeriod(day, day, TunisDates.dateOnlyLabel(day));

  static List<SalesTrendPoint> forPeriod(
    List<Json> series,
    DashboardPeriod period,
  ) {
    // UTC arithmetic keeps civil days independent of phone timezone / DST.
    final start = DateTime.parse('${period.from}T00:00:00Z');
    final end = DateTime.parse('${period.to}T00:00:00Z');
    final days = end.difference(start).inDays;
    if (days < 0 || days > 365) {
      throw const FormatException('Période de 1 à 366 jours requise.');
    }
    final byDay = {for (final row in series) row['day']: row};
    return List.unmodifiable([
      for (var i = 0; i <= days; i++)
        _point(TunisDates.civil(start.add(Duration(days: i))), byDay),
    ]);
  }

  static SalesTrendPoint _point(String day, Map<dynamic, Json> byDay) {
    final row = byDay[day];
    return SalesTrendPoint(
      day: day,
      netMillimes: integer(row?['netMillimes']),
      netUnits: integer(row?['netUnits']),
      saleCount: integer(row?['saleCount']),
    );
  }
}
