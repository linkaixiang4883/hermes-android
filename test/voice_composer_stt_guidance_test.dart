import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/voice_composer_controller.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/l10n_test_utils.dart';

void main() {
  testWidgets('no-service error is localized to keyboard hint (zh)', (tester) async {
    final editor = TextEditingController();
    final adapter = FakeVoiceComposerAdapter();
    final controller = VoiceComposerController(textController: editor, adapter: adapter);
    addTearDown(controller.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nTestDelegates,
        supportedLocales: l10nTestSupportedLocales,
        locale: const Locale('zh'),
        home: Builder(builder: (context) {
          controller.l10n = AppLocalizations.of(context);
          return const SizedBox();
        }),
      ),
    );
    await tester.pump();

    await controller.start();
    adapter.emitError('bind to recognition service failed');
    await tester.pump();

    expect(controller.listening, isFalse);
    expect(controller.status, '语音识别服务不可用，请使用输入法键盘上的语音按钮');
  });

  testWidgets('no-service error is localized to keyboard hint (en)', (tester) async {
    final editor = TextEditingController();
    final adapter = FakeVoiceComposerAdapter();
    final controller = VoiceComposerController(textController: editor, adapter: adapter);
    addTearDown(controller.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nTestDelegates,
        supportedLocales: l10nTestSupportedLocales,
        locale: const Locale('en'),
        home: Builder(builder: (context) {
          controller.l10n = AppLocalizations.of(context);
          return const SizedBox();
        }),
      ),
    );
    await tester.pump();

    await controller.start();
    adapter.emitError('Speech recognition is unavailable');
    await tester.pump();

    expect(controller.status, "Speech recognition service unavailable — use the keyboard's voice input instead");
  });

  testWidgets('unrelated error is not rewritten', (tester) async {
    final editor = TextEditingController();
    final adapter = FakeVoiceComposerAdapter();
    final controller = VoiceComposerController(textController: editor, adapter: adapter);
    controller.l10n = null;
    addTearDown(controller.dispose);
    addTearDown(editor.dispose);

    await controller.start();
    adapter.emitError('network timeout');

    expect(controller.status, 'network timeout');
  });

  testWidgets('initialize failure shows keyboard hint when l10n is zh', (tester) async {
    final editor = TextEditingController();
    final adapter = FakeVoiceComposerAdapter(initializationSucceeds: false);
    final controller = VoiceComposerController(textController: editor, adapter: adapter);
    addTearDown(controller.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: l10nTestDelegates,
        supportedLocales: l10nTestSupportedLocales,
        locale: const Locale('zh'),
        home: Builder(builder: (context) {
          controller.l10n = AppLocalizations.of(context);
          return const SizedBox();
        }),
      ),
    );
    await tester.pump();

    final ok = await controller.initialize();
    expect(ok, isFalse);
    expect(controller.status, '语音识别服务不可用，请使用输入法键盘上的语音按钮');
  });

  testWidgets('successful recognition keeps Google path unaffected', (tester) async {
    final editor = TextEditingController(text: 'hi ');
    final adapter = FakeVoiceComposerAdapter();
    final controller = VoiceComposerController(textController: editor, adapter: adapter);
    addTearDown(controller.dispose);
    addTearDown(editor.dispose);

    await controller.start();
    adapter.emitPartial('hello');
    expect(editor.text, 'hi hello');
    expect(controller.listening, isTrue);

    adapter.emitFinal('hello world');
    await tester.pump();
    expect(editor.text, 'hi hello world');
    expect(controller.listening, isFalse);
  });
}
