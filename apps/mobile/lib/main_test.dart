// Development-only entry point for interactive Flutter Driver inspection.
// Development entry only; flutter_driver stays out of production dependencies.
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';

import 'main.dart' as application;

void main() {
  enableFlutterDriverExtension();
  application.main();
}
