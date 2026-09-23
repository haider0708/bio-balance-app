import 'models.dart';
import 'tunis_dates.dart';

class DashboardPeriod {
  final String from, to, label;
  const DashboardPeriod(this.from, this.to, this.label);
  factory DashboardPeriod.today() {
    final d = TunisDates.today();
    return DashboardPeriod(d, d, 'Aujourd’hui');
  }
  factory DashboardPeriod.month() {
    final d = TunisDates.today();
    return DashboardPeriod('${d.substring(0, 8)}01', d, 'Ce mois-ci');
  }
  factory DashboardPeriod.week() {
    final d = TunisDates.today();
    return DashboardPeriod(
      TunisDates.civil(
        DateTime.parse('${d}T00:00:00Z').subtract(const Duration(days: 6)),
      ),
      d,
      '7 derniers jours',
    );
  }
  String get key => '$from:$to';
}

class DashboardData {
  final Json raw;
  final bool cached;
  DashboardData(Json value, {this.cached = false})
    : raw = Map.unmodifiable(value);
  int get netMillimes => integer(raw['netMillimes']);
  int get netUnits => integer(raw['netUnits']);
  int get saleCount => integer(raw['saleCount']);
  Json get current => Map<String, dynamic>.from(raw['current'] ?? {});
  List<Json> list(String key) => objects(raw[key]);
}
