/// Firebase push on Android phones; the web build gets an inert stand-in.
library;

export 'fcm_stub.dart' if (dart.library.io) 'fcm_io.dart';
