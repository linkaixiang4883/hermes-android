import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralizes the TTS voice configuration so initialization and every
/// read-aloud share the same resolution path. Reading the preference fresh
/// on each read-aloud also makes setting-page changes take effect without
/// restarting the chat screen.
class TtsVoiceConfig {
  const TtsVoiceConfig._();

  /// Maps an app language code to a TTS language tag for the device-default
  /// engine. The engine itself stays whatever the system chose; only the
  /// language is matched so messages are read in the app's language when the
  /// engine provides it. Non-Chinese apps fall back to English — the app
  /// only ships en and zh locales, so this is the only other option.
  static String languageForApp(String languageCode) =>
      languageCode == 'zh' ? 'zh-CN' : 'en-US';

  /// Applies the persisted voice selection, or — when the user follows the
  /// device default and [appLanguageCode] is provided — asks the default
  /// engine for the app's language. Failures keep the engine's default
  /// voice and are never fatal.
  static Future<void> apply(
    FlutterTts tts,
    SharedPreferences prefs, {
    String? appLanguageCode,
  }) async {
    final voiceName = prefs.getString('voice_name');
    final voiceLocale = prefs.getString('voice_locale');

    if (voiceName != null && voiceName.isNotEmpty) {
      if (voiceName == voiceLocale) {
        await tts.setLanguage(voiceName);
      } else {
        await tts.setVoice({
          'name': voiceName,
          'locale': voiceLocale ?? '',
        });
      }
    } else if (appLanguageCode != null) {
      try {
        await tts.setLanguage(languageForApp(appLanguageCode));
      } catch (_) {
        // Keep the engine's default voice.
      }
    }
  }
}
