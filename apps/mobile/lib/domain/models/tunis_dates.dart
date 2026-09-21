/// Civil expiry dates never shift with a phone's timezone. Operational
/// timestamps are shown at Tunisia's current UTC+1 offset.
class TunisDates {
  static String today([DateTime? now]) =>
      civil((now ?? DateTime.now()).toUtc().add(const Duration(hours: 1)));
  static String civil(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static String expiry(String input) {
    var value = input.trim();
    final french = RegExp(r'^(?:(\d{2})/)?(\d{2})/(\d{4})$').firstMatch(value);
    if (french != null) {
      value =
          '${french[3]}-${french[2]}${french[1] == null ? '' : '-${french[1]}'}';
    }
    final match = RegExp(r'^(\d{4})-(\d{2})(?:-(\d{2}))?$').firstMatch(value);
    if (match == null) {
      throw const FormatException(
        'Date invalide. Utilisez JJ/MM/AAAA ou MM/AAAA.',
      );
    }
    final year = int.parse(match[1]!), month = int.parse(match[2]!);
    if (year < 2000 || year > 2200 || month < 1 || month > 12) {
      throw const FormatException('Date de péremption invalide.');
    }
    final date = match[3] == null
        ? DateTime.utc(year, month + 1, 0)
        : DateTime.utc(year, month, int.parse(match[3]!));
    if (date.year != year || date.month != month) {
      throw const FormatException('Date de péremption invalide.');
    }
    return civil(date);
  }

  static String dateOnlyLabel(String value) {
    try {
      final parts = expiry(value.split('T').first).split('-');
      return '${parts[2]}/${parts[1]}/${parts[0]}';
    } on FormatException {
      return '—';
    }
  }

  static String timestampLabel(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return '—';
    final local = parsed.toUtc().add(const Duration(hours: 1));
    return '${dateOnlyLabel(civil(local))} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
