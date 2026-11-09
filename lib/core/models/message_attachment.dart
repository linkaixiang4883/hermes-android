import 'dart:typed_data';

/// One user-visible attachment carried by a chat message.
///
/// Historical messages reference gateway-side files. A locally submitted
/// message may additionally carry the sanitized bytes it already uploaded, so
/// the optimistic bubble can render immediately even though the upload service
/// deletes its temporary cache file after `file.attach` / `image.attach_bytes`.
class MessageAttachmentRef {
  final MessageAttachmentKind kind;
  final String path;
  final String label;
  final Uint8List? bytes;

  /// True for an optimistic composer snapshot. Such a ref has no gateway path;
  /// when its bytes are unavailable it must degrade locally instead of asking
  /// `/api/media` for a phone-local filename.
  final bool isLocal;

  const MessageAttachmentRef({
    required this.kind,
    required this.path,
    this.label = '',
    this.bytes,
    this.isLocal = false,
  });

  bool get isImage => kind == MessageAttachmentKind.image;
  bool get hasInlineBytes => bytes != null && bytes!.isNotEmpty;
  bool get isDataUrl => path.startsWith('data:');

  String get displayLabel {
    if (label.trim().isNotEmpty) return label;
    if (isImage) return 'Image';
    final name = path.split(RegExp(r'[/\\]')).last;
    return name.isEmpty ? 'Attachment' : name;
  }
}

enum MessageAttachmentKind { image, file }

class ExtractedAttachmentContent {
  final String text;
  final List<MessageAttachmentRef> attachments;
  final bool hadImagePart;

  const ExtractedAttachmentContent({
    required this.text,
    required this.attachments,
    required this.hadImagePart,
  });
}

/// Extract image/file references from a user message without changing the
/// legacy [messageContentToText] behaviour used elsewhere.
///
/// Hermes persists images as `@image:<gateway path>` lines and files as
/// `@file:<workspace-relative path>` lines. The app also appends refs at the
/// end of its prompt, so both leading and trailing blocks are supported. A
/// line is only treated as a reference when the whole line is the marker;
/// prose that merely mentions `@file:` stays untouched.
ExtractedAttachmentContent extractAttachmentContent(dynamic content) {
  if (content is String) {
    return _extractText(content);
  }

  if (content is List) {
    final textParts = <String>[];
    final attachments = <MessageAttachmentRef>[];
    var hadImagePart = false;
    for (final part in content) {
      if (part == null) continue;
      if (part is String) {
        final extracted = _extractText(part);
        if (extracted.text.isNotEmpty) textParts.add(extracted.text);
        attachments.addAll(extracted.attachments);
        hadImagePart = hadImagePart || extracted.hadImagePart;
        continue;
      }
      if (part is! Map) {
        final text = part.toString().trim();
        if (text.isNotEmpty) textParts.add(text);
        continue;
      }

      final text = part['text'];
      if (text is String && text.trim().isNotEmpty) {
        final extracted = _extractText(text);
        if (extracted.text.isNotEmpty) textParts.add(extracted.text);
        attachments.addAll(extracted.attachments);
        hadImagePart = hadImagePart || extracted.hadImagePart;
        continue;
      }

      final imageUrl = _imageUrlFromPart(part);
      if (imageUrl != null && imageUrl.isNotEmpty) {
        hadImagePart = true;
        attachments.add(
          MessageAttachmentRef(
            kind: MessageAttachmentKind.image,
            path: imageUrl,
          ),
        );
        continue;
      }

      final filePath = _filePathFromPart(part);
      if (filePath != null && filePath.isNotEmpty) {
        attachments.add(
          MessageAttachmentRef(
            kind: MessageAttachmentKind.file,
            path: filePath,
          ),
        );
      }
    }

    return ExtractedAttachmentContent(
      text: _joinTextParts(textParts),
      attachments: _dedupe(attachments),
      hadImagePart: hadImagePart,
    );
  }

  if (content == null) {
    return const ExtractedAttachmentContent(
      text: '',
      attachments: [],
      hadImagePart: false,
    );
  }

  return _extractText(content.toString());
}

ExtractedAttachmentContent _extractText(String raw) {
  final lines = normaliseDisplayTextForAttachments(raw).split('\n');
  final kept = <String>[];
  final attachments = <MessageAttachmentRef>[];
  var hadImagePart = false;

  for (final line in lines) {
    final trimmed = line.trim();
    final marker = _referenceMarker(trimmed);
    if (marker != null) {
      final path = _cleanReferencePath(trimmed.substring(marker.length));
      if (path.isNotEmpty) {
        if (marker == '@image:') hadImagePart = true;
        attachments.add(
          MessageAttachmentRef(
            kind: marker == '@image:'
                ? MessageAttachmentKind.image
                : MessageAttachmentKind.file,
            path: path,
          ),
        );
        continue;
      }
    }
    kept.add(line);
  }

  return ExtractedAttachmentContent(
    text: _joinTextParts(kept),
    attachments: _dedupe(attachments),
    hadImagePart: hadImagePart,
  );
}

String? _referenceMarker(String line) {
  if (line.startsWith('@image:')) return '@image:';
  if (line.startsWith('@file:')) return '@file:';
  return null;
}

String _cleanReferencePath(String raw) {
  var value = raw.trim();
  if (value.length >= 2) {
    final first = value[0];
    final last = value[value.length - 1];
    if ((first == '`' && last == '`') ||
        (first == '"' && last == '"') ||
        (first == "'" && last == "'")) {
      value = value.substring(1, value.length - 1).trim();
    }
  }
  return value;
}

String _joinTextParts(Iterable<String> parts) {
  return parts
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .join('\n')
      .trim();
}

List<MessageAttachmentRef> _dedupe(List<MessageAttachmentRef> refs) {
  final seen = <String>{};
  final result = <MessageAttachmentRef>[];
  for (final ref in refs) {
    final key = '${ref.kind.name}\u0000${ref.path}';
    if (!seen.add(key)) continue;
    result.add(ref);
  }
  return result;
}

String? _imageUrlFromPart(Map part) {
  final imageUrl = part['image_url'];
  if (imageUrl is Map) {
    final url = imageUrl['url'];
    if (url is String && url.trim().isNotEmpty) return url.trim();
  }
  if (imageUrl is String && imageUrl.trim().isNotEmpty) {
    return imageUrl.trim();
  }
  final type = part['type']?.toString().toLowerCase() ?? '';
  if (type.contains('image')) {
    final url = part['url'];
    if (url is String && url.trim().isNotEmpty) return url.trim();
    final source = part['source'];
    if (source is Map) {
      final sourceUrl = source['url'];
      if (sourceUrl is String && sourceUrl.trim().isNotEmpty) {
        return sourceUrl.trim();
      }
    }
  }
  return null;
}

String? _filePathFromPart(Map part) {
  final file = part['file'];
  if (file is Map) {
    final path = file['path'] ?? file['name'];
    if (path is String && path.trim().isNotEmpty) return path.trim();
  }
  final type = part['type']?.toString().toLowerCase() ?? '';
  if (type.contains('file')) {
    final path = part['path'] ?? part['name'];
    if (path is String && path.trim().isNotEmpty) return path.trim();
  }
  return null;
}

/// The attachment parser needs the same escaped-newline cleanup the chat
/// renderer already applies, but the legacy helper lives in this utility's
/// sibling. Keep the small local copy to avoid importing the renderer.
String normaliseDisplayTextForAttachments(String text) {
  if (!text.contains(r'\n') && !text.contains(r'\r')) return text;
  return text
      .replaceAll(r'\r\n', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\n');
}
