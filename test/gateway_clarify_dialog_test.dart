import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_clarify.dart';
import 'package:hermes_android/core/widgets/gateway_clarify_dialog.dart';

import 'support/l10n_test_utils.dart';

/// Regression: answering the last question of a `clarify.lock` flow makes the
/// gateway layer synthesize `clarify.remaining` with an empty list. The chat
/// screen's reconcile handler pops the dialog route in that same turn; the
/// dialog's own completion used to pop a second time, dismissing the chat
/// screen underneath and dropping the user back to the session list.
void main() {
  testWidgets(
    'does not pop again when its route was already dismissed while responding',
    (tester) async {
      final responder = Completer<void>();
      late BuildContext screenContext;

      await tester.pumpWidget(
        testAppWithL10n(
          Builder(
            builder: (context) {
              screenContext = context;
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog<bool>(
                        context: context,
                        builder: (_) => GatewayClarifyDialog(
                          request: const GatewayClarifyRequest(
                            requestId: 'srq-test',
                            questionId: 'q1',
                            question: 'Ready to continue?',
                            choices: ['Yes', 'No'],
                            multiSelect: false,
                          ),
                          onRespond: (_) => responder.future,
                        ),
                      );
                    },
                    child: const Text('open-dialog'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open-dialog'));
      await tester.pumpAndSettle();
      expect(find.byType(GatewayClarifyDialog), findsOneWidget);

      // Pick a choice and submit; the responder stays pending, mimicking the
      // clarify.lock round-trip still being in flight.
      await tester.tap(find.text('Yes'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('clarify-continue')));
      await tester.pump();

      // The reconcile handler wins the race and dismisses the dialog route
      // first (this is what the chat screen does for `clarify.remaining`).
      Navigator.of(screenContext, rootNavigator: true).pop(false);
      await tester.pump();

      // The lock response now arrives; the dialog's continuation must not pop
      // a second route.
      responder.complete();
      await tester.pumpAndSettle();

      // The screen underneath survived its dialog being dismissed.
      expect(find.text('open-dialog'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
