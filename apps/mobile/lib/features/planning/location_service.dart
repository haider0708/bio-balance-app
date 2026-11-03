import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'planning_repository.dart';

enum LocationFailure { denied, deniedForever, serviceOff, unavailable }

class LocationException implements Exception {
  const LocationException(this.failure);

  final LocationFailure failure;

  @override
  String toString() => 'LocationException($failure)';
}

/// Where the phone is, read once when the person taps "I'm here" (never followed in the background).
abstract class LocationService {
  /// The best reading within a few seconds. Throws [LocationException] when there is none.
  Future<Fix> current();

  /// Opens the phone's settings for this app (after the permission was refused for good).
  Future<void> openSettings();
}

class DeviceLocation implements LocationService {
  const DeviceLocation();

  /// A reading this precise (metres) is taken at once.
  static const _good = 25.0;
  static const _wait = Duration(seconds: 12);

  @override
  Future<Fix> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(LocationFailure.serviceOff);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(LocationFailure.deniedForever);
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationException(LocationFailure.denied);
    }
    Position? best;
    final done = Completer<void>();
    final subscription =
        Geolocator.getPositionStream(locationSettings: const LocationSettings())
            .listen(
              (p) {
                if (best == null || p.accuracy < best!.accuracy) best = p;
                if (p.accuracy <= _good && !done.isCompleted) done.complete();
              },
              onError: (Object error) {
                if (!done.isCompleted) done.completeError(error);
              },
            );
    final timer = Timer(_wait, () {
      if (!done.isCompleted) done.complete();
    });
    try {
      await done.future;
    } on Object {
      throw const LocationException(LocationFailure.unavailable);
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
    final reading = best;
    if (reading == null) {
      throw const LocationException(LocationFailure.unavailable);
    }
    return Fix(
      latitude: reading.latitude,
      longitude: reading.longitude,
      accuracyMeters: reading.accuracy,
      mocked: reading.isMocked,
    );
  }

  @override
  Future<void> openSettings() => Geolocator.openAppSettings();
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => const DeviceLocation(),
);
