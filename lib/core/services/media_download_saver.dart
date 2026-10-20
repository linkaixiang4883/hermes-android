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

  /// Returns the saved display name, or null when the platform cannot save
  /// natively (older Android, or no plugin in the host process). A platform
  /// failure throws so the card can surface it instead of a fake success.
  static Future<String?> save({
    required Uint8List bytes,
    required String filename,
    String? mimeType,
    bool installAfterSave = false,
  }) async {
    try {
      return await channel.invokeMethod<String>('saveToDownloads', {
        'bytes': bytes,
        'filename': filename,
        'mimeType': mimeType,
        'installAfterSave': installAfterSave,
      });
    } on MissingPluginException {
      return null;
    }
  }
}
