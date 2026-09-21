import 'dart:math';
import 'dart:io';

class RetryPolicy {
  final double Function() random;
  RetryPolicy({double Function()? random})
    : random = random ?? Random().nextDouble;
  Duration delay(int attempt, DateTime now, {String? retryAfter}) {
    var milliseconds =
        (min(300000, 1000 * pow(2, min(attempt - 1, 18))) *
                (0.5 + random() * 0.5))
            .round();
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter);
      DateTime? date;
      if (seconds == null) {
        try {
          date = HttpDate.parse(retryAfter);
        } on FormatException {
          /* Ignore invalid server header. */
        }
      }
      final requested = seconds == null
          ? date?.difference(now).inMilliseconds
          : seconds * 1000;
      if (requested != null) milliseconds = max(milliseconds, requested);
    }
    return Duration(milliseconds: milliseconds.clamp(0, 300000));
  }
}
