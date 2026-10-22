import 'package:biobalance/core/util/phone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every way of writing a Tunisian number reads the same', () {
    for (final input in [
      '21345678',
      '21 345 678',
      '21.345.678',
      '21-345-678',
      '+216 21 345 678',
      '+21621345678',
      '00216 21345678',
      '0021621345678',
      '216 21 345 678',
      '21621345678',
      '(+216) 21 345 678',
      '  +216-21-345-678  ',
    ]) {
      expect(normalizeTunisianPhone(input), '+21621345678', reason: input);
    }
  });

  test('anything else is refused', () {
    for (final input in [
      '',
      '2134567',
      '213456789',
      '+216 2134567',
      '+33 6 12 34 56 78',
      'abc',
      '01234567',
      '11345678',
      '21 345 678 9',
    ]) {
      expect(normalizeTunisianPhone(input), isNull, reason: input);
    }
  });

  test('a number is shown back readably', () {
    expect(formatPhone('+21621345678'), '+216 21 345 678');
  });
}
