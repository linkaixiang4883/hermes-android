// QA-only entrypoint for the MEDIA card APK save/install path. It mounts the
// real card with a local fake file source (the signed APK is copied into this
// app's cache with `run-as`), so the native MediaStore + installer code is
// exercised without needing a gateway session. Not part of the app.
import 'dart:io';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/utils/media_tags.dart';
import 'package:hermes_android/core/widgets/media_artifact_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

class _CacheApk implements RemoteFilesDataSource {
  static const _path =
      '/data/user/0/com.hermesagent.hermes_android.dev/cache/qa.apk';

  @override
  Future<RemoteFileDownload> download(String path) async {
    final bytes = await File(_path).readAsBytes();
    return RemoteFileDownload(filename: 'qa.apk', bytes: bytes);
  }

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
  enableFlutterDriverExtension();
  runApp(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: MediaArtifactCard(
              ref: const MediaTagRef(path: 'qa.apk'),
              filesClient: _CacheApk.new,
            ),
          ),
        ),
      ),
    ),
  );
}
