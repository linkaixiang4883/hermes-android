import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/message_attachment.dart';
import 'package:hermes_android/core/widgets/message_attachment_row.dart';

import 'support/l10n_test_utils.dart';

void main() {
  const onePixelPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
      '/x8AAusB9Wl2nX0AAAAASUVORK5CYII=';

  testWidgets('renders inline image bytes without a remote client', (
    tester,
  ) async {
    final ref = MessageAttachmentRef(
      kind: MessageAttachmentKind.image,
      path: 'photo.png',
      label: 'photo.png',
      bytes: base64Decode(onePixelPng),
    );

    await tester.pumpWidget(
      testAppWithL10n(
        Scaffold(
          body: MessageAttachmentRow(attachments: [ref], filesClient: null),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('message-attachment-image')), findsOneWidget);
  });

  testWidgets('renders file chips and the remaining count', (tester) async {
    final refs = [
      for (var i = 0; i < 4; i++)
        MessageAttachmentRef(
          kind: MessageAttachmentKind.file,
          path: 'report-$i.pdf',
          label: 'report-$i.pdf',
        ),
    ];

    await tester.pumpWidget(
      testAppWithL10n(
        Scaffold(
          body: MessageAttachmentRow(attachments: refs, filesClient: null),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('message-attachment-file')), findsNWidgets(3));
    expect(find.text('+1 more'), findsOneWidget);
  });

  testWidgets('degrades an unreadable image to its file label', (tester) async {
    const ref = MessageAttachmentRef(
      kind: MessageAttachmentKind.image,
      path: '/missing/photo.png',
      label: 'photo.png',
    );

    await tester.pumpWidget(
      testAppWithL10n(
        Scaffold(
          body: MessageAttachmentRow(attachments: [ref], filesClient: null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('message-attachment-image-failed')),
      findsOneWidget,
    );
    expect(find.text('photo.png'), findsOneWidget);
  });
}
