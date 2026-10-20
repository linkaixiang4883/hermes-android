import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// Saves downloaded media bytes into the system Downloads collection.
///
/// The Android side writes through MediaStore (API 29+, no storage
/// permission required); releases before that return null and the caller
/// keeps the pre-existing delivery — the system share sheet
/// (`com.hermesagent.hermes_android/downloads#saveToDownloads`, see
/// `MainActivity.saveToDownloads`).
class MediaDownloadSaver {
  @visibleForTesting
  static const MethodChannel channel = MethodChannel(
    'com.hermesagent.hermes_android/downloads',
  );

  /// Returns the save outcome, or null when the platform cannot save
  /// natively (older Android, or no plugin in the host process). A platform
  /// failure throws so the card can surface it instead of a fake success.
  static Future<MediaDownloadSaveResult?> save({
    required Uint8List bytes,
    required String filename,
    String? mimeType,
    bool installAfterSave = false,
  }) async {
    try {
      final raw = await channel.invokeMethod<dynamic>('saveToDownloads', {
        'bytes': bytes,
        'filename': filename,
        'mimeType': mimeType,
        'installAfterSave': installAfterSave,
      });
      if (raw is String) {
        // Older platform builds answered with the saved name only.
        return MediaDownloadSaveResult(filename: raw, installStatus: 'none');
      }
      if (raw is Map) {
        final saved = raw['filename']?.toString() ?? '';
        if (saved.isEmpty) return null;
        return MediaDownloadSaveResult(
          filename: saved,
          installStatus: raw['install']?.toString() ?? 'none',
        );
      }
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Outcome of [MediaDownloadSaver.save].
class MediaDownloadSaveResult {
  /// The display name the platform saved under.
  final String filename;

  /// `launched` — the system installer was started; `permission` — this app
  /// may not install yet and the platform opened the "install unknown apps"
  /// settings page; `failed` — the installer could not be prepared; `none` —
  /// the save was not an install request.
  final String installStatus;

  const MediaDownloadSaveResult({
    required this.filename,
    required this.installStatus,
  });

  bool get installLaunched => installStatus == 'launched';

  bool get installPermissionMissing => installStatus == 'permission';
}
