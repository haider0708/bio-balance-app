import 'package:intl/intl.dart';

/// Dates shown to people use their language; dates sent to the server are `YYYY-MM-DD` (Tunis).
class Dates {
  const Dates._();

  static String day(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  static DateTime parseDay(String day) => DateTime.parse(day);

  static String short(DateTime date, String locale) =>
      DateFormat.MMMd(locale).format(date);

  static String full(DateTime date, String locale) =>
      DateFormat.yMMMd(locale).format(date);

  static String dateTime(DateTime date, String locale) =>
      DateFormat.yMMMd(locale).add_Hm().format(date);

  static String time(DateTime date, String locale) =>
      DateFormat.Hm(locale).format(date);

  /// "Today", "Yesterday", or the date: callers pass the localised words.
  static String relativeDay(
    DateTime date,
    String locale, {
    required String today,
    required String yesterday,
  }) {
    final now = DateTime.now();
    final d = DateTime(date.year, date.month, date.day);
    final t = DateTime(now.year, now.month, now.day);
    final diff = t.difference(d).inDays;
    if (diff == 0) return today;
    if (diff == 1) return yesterday;
    return DateFormat.MMMEd(locale).format(date);
  }
}
