import 'package:intl/intl.dart';

/// Amounts travel as whole millimes (1 TND = 1000 millimes), so sums are always exact.
class Money {
  const Money._();

  static String format(
    int millimes,
    String locale, {
    bool unit = true,
    bool sign = false,
  }) {
    final formatter = NumberFormat('#,##0.000', locale);
    final text = formatter.format(millimes.abs() / 1000);
    final prefix = millimes < 0 ? '−' : (sign && millimes > 0 ? '+' : '');
    return unit ? '$prefix$text TND' : '$prefix$text';
  }

  /// "12,5" or "12.500" typed by a person → millimes. Null when it is not a valid amount.
  static int? parse(String input) {
    final cleaned = input.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || value < 0 || value > 1000000) return null;
    return (value * 1000).round();
  }
}
