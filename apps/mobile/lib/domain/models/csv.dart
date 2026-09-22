/// Preserve exported text and prevent spreadsheet programs interpreting formulas.
String csvCell(Object? value) {
  final text = (value ?? '').toString();
  final formula =
      RegExp(r'^[\s\u0000-\u001f]*[=+@-]').hasMatch(text) ||
      RegExp(r'^[\t\r\n]').hasMatch(text);
  final safe = formula ? "'$text" : text;
  return '"${safe.replaceAll('"', '""')}"';
}
