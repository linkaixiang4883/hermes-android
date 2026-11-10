import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/app_update_service.dart';

void main() {
  test('parses only fork-hosted ABI APK assets', () {
    final release = AppUpdateService.parseRelease('''
    {
      "tag_name": "v3.2.7",
      "html_url": "https://github.com/linkaixiang4883/hermes-android/releases/tag/v3.2.7",
      "draft": false,
      "prerelease": false,
      "assets": [
        {
          "name": "app-arm64-v8a-release.apk",
          "size": 64792569,
          "state": "uploaded",
          "digest": "sha256:2b92567996ca5d2856d3d6e9b949ce1232e205959c39e8a4018f6a23f9c40002",
          "browser_download_url": "https://github.com/linkaixiang4883/hermes-android/releases/download/v3.2.7/app-arm64-v8a-release.apk"
        },
        {
          "name": "README.md",
          "size": 10,
          "state": "uploaded",
          "digest": "sha256:0000000000000000000000000000000000000000000000000000000000000000",
          "browser_download_url": "https://github.com/linkaixiang4883/hermes-android/releases/download/v3.2.7/README.md"
        }
      ]
    }
    ''');
    expect(release, isNotNull);
    expect(release!.apkAssets, hasLength(1));
    expect(release.apkAssets.single.abi, 'arm64-v8a');
    expect(release.apkForAbis(['arm64-v8a'])?.name, 'app-arm64-v8a-release.apk');
  });

  test('rejects an asset hosted by the upstream author', () {
    final release = AppUpdateService.parseRelease('''
    {
      "tag_name": "v3.2.7",
      "html_url": "https://github.com/linkaixiang4883/hermes-android/releases/tag/v3.2.7",
      "draft": false,
      "assets": [{
        "name": "app-arm64-v8a-release.apk",
        "size": 10,
        "state": "uploaded",
        "digest": "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        "browser_download_url": "https://github.com/rusty4444/hermes-android/releases/download/v3.2.7/app-arm64-v8a-release.apk"
      }]
    }
    ''');
    expect(release, isNotNull);
    expect(release!.apkAssets, isEmpty);
  });
}
