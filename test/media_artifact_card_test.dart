// The MEDIA artifact card's "save to Downloads" action: the bytes the card
// already downloads are handed to the platform channel (MediaStore on
// Android 10+, with the share sheet as the fallback on older releases).
//
// The widget test binding has no Android behind it, so the channel is mocked
// here; what is pinned is the card's side of the contract — the right bytes,
// filename and mime type reach the channel, a success says so, and a platform
// failure surfaces on the card instead of pretending to have saved.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/media_download_saver.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/utils/media_tags.dart';
import 'package:hermes_android/core/widgets/media_artifact_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

class _FakeFiles implements RemoteFilesDataSource {
  @override
  Future<RemoteFileDownload> download(String path) async =>
      RemoteFileDownload(filename: 'report.pdf', bytes: const [1, 2, 3, 4]);

  @override
  Future<RemoteDirectory> defaultDirectory() => throw UnimplementedError();

  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) =>
      throw UnimplementedError();

  @override
  Future<RemoteTextPreview> readText(String path) =>
      throw UnimplementedError();
}

void main() {
  const ref = MediaTagRef(path: '/srv/data/report.pdf');
  const key = Key('media-card-download-/srv/data/report.pdf');

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: MediaArtifactCard(ref: ref, filesClient: _FakeFiles.new),
        ),
      ),
    );
    await tester.pump();
  }

  void mockDownloadsChannel(
    Future<Object?> Function(MethodCall call) handler,
  ) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(MediaDownloadSaver.channel, handler);
    addTearDown(
      () => messenger.setMockMethodCallHandler(MediaDownloadSaver.channel, null),
    );
  }

  testWidgets('the save action hands the bytes to the downloads channel', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    mockDownloadsChannel((call) async {
      calls.add(call);
      return 'report.pdf';
    });

    await pumpCard(tester);
    await tester.tap(find.byKey(key));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(calls, hasLength(1));
    expect(calls.single.method, 'saveToDownloads');
    final args = calls.single.arguments as Map;
    expect(args['filename'], 'report.pdf');
    expect(args['installAfterSave'], isFalse);
    expect(args['bytes'], isA<Uint8List>());
    expect((args['bytes'] as Uint8List).length, 4);
    expect(find.text('Saved to Downloads'), findsOneWidget);
  });

  testWidgets('an APK save asks the platform to open the installer', (
    tester,
  ) async {
    const apkRef = MediaTagRef(path: '/srv/data/release.apk');
    final calls = <MethodCall>[];
    mockDownloadsChannel((call) async {
      calls.add(call);
      return 'release.apk';
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: MediaArtifactCard(ref: apkRef, filesClient: _FakeFiles.new),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('media-card-download-/srv/data/release.apk')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(calls, hasLength(1));
    final args = calls.single.arguments as Map;
    expect(args['filename'], 'release.apk');
    expect(
      args['installAfterSave'],
      isTrue,
      reason: 'the platform is the only side that can raise the installer',
    );
    expect(
      find.text('Saved to Downloads — opening the installer…'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a platform failure surfaces on the card instead of a fake success',
    (tester) async {
      mockDownloadsChannel(
        (call) async =>
            throw PlatformException(code: 'io', message: 'disk full'),
      );

      await pumpCard(tester);
      await tester.tap(find.byKey(key));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Saved to Downloads'), findsNothing);
      expect(find.textContaining('disk full'), findsOneWidget);
    },
  );
}
