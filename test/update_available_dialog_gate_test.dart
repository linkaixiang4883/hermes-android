import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/app_update_service.dart';
import 'package:hermes_android/core/widgets/update_available_dialog.dart';

import 'support/l10n_test_utils.dart';

final _release = AppReleaseInfo(
  version: '3.2.7',
  tagName: 'v3.2.7',
  releaseUrl: 'https://github.com/linkaixiang4883/hermes-android/releases/tag/v3.2.7',
  apkAssets: [
    AppReleaseApk(
      abi: 'arm64-v8a',
      name: 'app-arm64-v8a-release.apk',
      url: Uri.parse(
        'https://github.com/linkaixiang4883/hermes-android/releases/download/v3.2.7/app-arm64-v8a-release.apk',
      ),
      sha256: '2b92567996ca5d2856d3d6e9b949ce1232e205959c39e8a4018f6a23f9c40002',
      size: 64792569,
    ),
  ],
);

void main() {
  testWidgets('default policy hides install controls even with an APK asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      testAppWithL10n(UpdateAvailableDialog(release: _release)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Update now'), findsNothing);
    expect(find.text('Install update'), findsNothing);
    expect(find.text('View release'), findsOneWidget);
  });
}
