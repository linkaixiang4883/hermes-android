import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/app_update_policy.dart';

void main() {
  test('in-app installer is disabled in production', () {
    expect(AppUpdatePolicy.inAppInstallerEnabled, isFalse);
  });
}
