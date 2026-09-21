class Money {
  final int millimes;
  const Money._(this.millimes);
  factory Money(int value) {
    if (value < 0 || value > 999999999999999) {
      throw const FormatException('Montant hors limites.');
    }
    return Money._(value);
  }
  factory Money.parse(String text) {
    final normalized = text.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(normalized)) {
      throw const FormatException(
        'Saisissez un montant avec au plus trois décimales.',
      );
    }
    final parts = normalized.split('.');
    return Money(
      int.parse(parts[0]) * 1000 +
          int.parse(parts.length == 2 ? parts[1].padRight(3, '0') : '0'),
    );
  }
  String get formatted =>
      '${millimes ~/ 1000},${(millimes % 1000).toString().padLeft(3, '0')} TND';
  String get input => formatted.replaceAll(' TND', '');
  Money times(int quantity) {
    if (quantity < 1 || quantity > 1000000) {
      throw const FormatException('Quantité invalide.');
    }
    return Money(millimes * quantity);
  }

  Map<String, dynamic> toJson() => {
    'currency': 'TND',
    'millimes': millimes.toString(),
  };
}
