String dateLabel(String date) {
  final parts = date.substring(0, 10).split('-');
  return '${parts[2]}/${parts[1]}/${parts[0]}';
}
