import 'package:biobalance/features/auth/auth_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the code is shaped like ABCD-2345 whatever was typed or pasted', () {
    expect(CodeField.pretty('abcd2345'), 'ABCD-2345');
    expect(CodeField.pretty(' ab cd-23 45 xyz'), 'ABCD-2345');
    expect(CodeField.pretty('abc'), 'ABC');
    expect(
      CodeField.extract('Activation code : ABCD-2345 (valid 72 h)'),
      'ABCD-2345',
    );
    expect(CodeField.extract('abcd 2345'), 'ABCD-2345');
    expect(CodeField.extract('hello'), isNull);
  });
}
