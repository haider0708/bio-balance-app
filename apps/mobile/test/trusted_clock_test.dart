import 'package:biobalance/domain/trusted_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(TrustedClock.reset);

  test('follows the server, not the phone, once anchored', () {
    final server = DateTime.utc(2020, 1, 1, 12);
    TrustedClock.sync(server);
    final now = TrustedClock.now();
    // The phone says 2026; the sale is dated by the server's clock plus the
    // time elapsed since, so a phone set back or forward changes nothing.
    expect(now.difference(server).inSeconds, inInclusiveRange(0, 2));
  });

  test('never runs backwards between two readings', () {
    TrustedClock.sync(DateTime.utc(2026, 10, 1, 12));
    final first = TrustedClock.now();
    final second = TrustedClock.now();
    expect(second.isBefore(first), isFalse);
  });

  test('uses the phone clock only until the first answer from the server', () {
    final before = DateTime.now().toUtc();
    final now = TrustedClock.now();
    expect(now.difference(before).inSeconds.abs(), lessThan(2));
  });
}
