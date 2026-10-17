import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';

/// One day's opening hours; `null` means closed all day.
class DayHours {
  const DayHours(this.open, this.close);

  factory DayHours.fromJson(Json j) => DayHours(j.str('open'), j.str('close'));

  final String open;
  final String close;

  Json toJson() => {'open': open, 'close': close};
}

/// What the admin sets for the whole application (GET/PUT /v1/settings).
class AppSettings {
  const AppSettings({
    required this.minimumIos,
    required this.minimumAndroid,
    required this.hoursEnabled,
    required this.days,
    required this.supplierChoice,
    required this.open,
    required this.nextOpening,
  });

  factory AppSettings.fromJson(Json j) {
    final minimum = j.obj('minimumBuild');
    final hours = j.obj('hours');
    return AppSettings(
      minimumIos: minimum.integer('ios'),
      minimumAndroid: minimum.integer('android'),
      hoursEnabled: hours['enabled'] == true,
      days: [
        for (final d in hours['days'] as List)
          d == null ? null : DayHours.fromJson(d as Json),
      ],
      supplierChoice: j['supplierChoice'] == true,
      open: j['open'] != false,
      nextOpening: j['nextOpening'] == null
          ? null
          : DateTime.parse(j['nextOpening'] as String).toLocal(),
    );
  }

  final int minimumIos;
  final int minimumAndroid;
  final bool hoursEnabled;

  /// Sunday first, like the server.
  final List<DayHours?> days;
  final bool supplierChoice;

  /// Whether BioBalance is open right now, by the server's clock.
  final bool open;
  final DateTime? nextOpening;
}

class AppSettingsRepository {
  AppSettingsRepository(this._ref);

  final Ref _ref;

  Future<AppSettings> load() async => AppSettings.fromJson(
    await _ref.read(apiClientProvider).get('/v1/settings') as Json,
  );

  /// Saves only the parts given.
  Future<AppSettings> save(Json patch) async => AppSettings.fromJson(
    await _ref.read(apiClientProvider).put('/v1/settings', patch) as Json,
  );
}

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  AppSettingsRepository.new,
);

final appSettingsProvider = FutureProvider.autoDispose<AppSettings>(
  (ref) => ref.watch(appSettingsRepositoryProvider).load(),
);
