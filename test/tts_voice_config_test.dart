import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hermes_android/core/services/tts_voice_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTts extends FlutterTts {
  final List<String> languageCalls = [];
  final List<Map<String, String>> voiceCalls = [];
  bool throwOnSetLanguage = false;

  @override
  Future<dynamic> setLanguage(String language) async {
    if (throwOnSetLanguage) {
      throw PlatformException(code: 'unsupported_language');
    }
    languageCalls.add(language);
    return 1;
  }

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {
    voiceCalls.add(voice);
    return 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('languageForApp maps zh to zh-CN and everything else to en-US', () {
    expect(TtsVoiceConfig.languageForApp('zh'), 'zh-CN');
    expect(TtsVoiceConfig.languageForApp('en'), 'en-US');
    expect(TtsVoiceConfig.languageForApp('fr'), 'en-US');
    expect(TtsVoiceConfig.languageForApp('ja'), 'en-US');
  });

  test('apply matches the app language when following the device default',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final tts = _FakeTts();

    await TtsVoiceConfig.apply(tts, prefs, appLanguageCode: 'zh');

    expect(tts.languageCalls, ['zh-CN']);
    expect(tts.voiceCalls, isEmpty);
  });

  test('apply leaves the engine untouched when no language is provided', () async {
    final prefs = await SharedPreferences.getInstance();
    final tts = _FakeTts();

    await TtsVoiceConfig.apply(tts, prefs);

    expect(tts.languageCalls, isEmpty);
    expect(tts.voiceCalls, isEmpty);
  });

  test('apply prefers the persisted voice over the app language', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'voice_name': 'cmn-cn-x-ssa-language',
      'voice_locale': 'cmn-CN',
    });
    final prefs = await SharedPreferences.getInstance();
    final tts = _FakeTts();

    await TtsVoiceConfig.apply(tts, prefs, appLanguageCode: 'en');

    expect(tts.languageCalls, isEmpty);
    expect(tts.voiceCalls, [
      {'name': 'cmn-cn-x-ssa-language', 'locale': 'cmn-CN'},
    ]);
  });

  test('apply uses setLanguage when the persisted voice equals its locale',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'voice_name': 'zh-CN',
      'voice_locale': 'zh-CN',
    });
    final prefs = await SharedPreferences.getInstance();
    final tts = _FakeTts();

    await TtsVoiceConfig.apply(tts, prefs, appLanguageCode: 'zh');

    expect(tts.languageCalls, ['zh-CN']);
    expect(tts.voiceCalls, isEmpty);
  });

  test('apply swallows language failures and keeps the engine default',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final tts = _FakeTts()..throwOnSetLanguage = true;

    await TtsVoiceConfig.apply(tts, prefs, appLanguageCode: 'zh');

    expect(tts.languageCalls, isEmpty);
    expect(tts.voiceCalls, isEmpty);
  });
}
