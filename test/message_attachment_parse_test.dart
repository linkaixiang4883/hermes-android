import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/message_attachment.dart';

void main() {
  group('extractAttachmentContent', () {
    test('pulls trailing image refs out of text', () {
      final result = extractAttachmentContent(
        'look at this\n@image:/tmp/a.png',
      );
      expect(result.text, 'look at this');
      expect(result.attachments, hasLength(1));
      expect(result.attachments.single.kind, MessageAttachmentKind.image);
      expect(result.attachments.single.path, '/tmp/a.png');
      expect(result.hadImagePart, isTrue);
    });

    test('keeps a pure image message with empty cleaned text', () {
      final result = extractAttachmentContent('@image:/tmp/a.png');
      expect(result.text, isEmpty);
      expect(result.attachments, hasLength(1));
      expect(result.hadImagePart, isTrue);
    });

    test('extracts image parts without the legacy [Image] placeholder', () {
      final result = extractAttachmentContent([
        {'type': 'text', 'text': 'caption'},
        {
          'type': 'image_url',
          'image_url': {'url': '/tmp/a.png'},
        },
      ]);
      expect(result.text, 'caption');
      expect(result.attachments.single.kind, MessageAttachmentKind.image);
      expect(result.attachments.single.path, '/tmp/a.png');
      expect(result.text, isNot(contains('[Image]')));
    });

    test('extracts trailing file refs and strips wrapping backticks', () {
      final result = extractAttachmentContent(
        'report\n@file:`/tmp/a report.pdf`\n@file:/tmp/notes.txt',
      );
      expect(result.text, 'report');
      expect(result.attachments.map((item) => item.path), [
        '/tmp/a report.pdf',
        '/tmp/notes.txt',
      ]);
      expect(
        result.attachments.map((item) => item.kind),
        everyElement(MessageAttachmentKind.file),
      );
    });

    test('does not treat a mid-line @file mention as an attachment', () {
      final result = extractAttachmentContent('use @file:foo in prose');
      expect(result.text, 'use @file:foo in prose');
      expect(result.attachments, isEmpty);
    });

    test('deduplicates repeated refs', () {
      final result = extractAttachmentContent(
        '@image:/tmp/a.png\n@image:/tmp/a.png',
      );
      expect(result.attachments, hasLength(1));
    });

    test('normalises escaped newlines before parsing', () {
      final result = extractAttachmentContent(r'hello\n@image:/tmp/a.png');
      expect(result.text, 'hello');
      expect(result.attachments.single.path, '/tmp/a.png');
    });
  });
}
