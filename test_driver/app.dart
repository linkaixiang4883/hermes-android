// QA-only entrypoint: enables the Flutter Driver extension so Dart MCP can
// tap/type/screenshot the real app. Not used by production or release builds.
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';
import 'package:hermes_android/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}
