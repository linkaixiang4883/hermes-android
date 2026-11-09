import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/message_attachment.dart';
import '../services/remote_files_client.dart';

/// Attachment previews below a message bubble.
///
/// Images use inline bytes when the sender still has them, then a data URL,
/// then the authenticated gateway `/api/media` route for historical refs.
/// A fetch failure degrades to a file chip; it never hides the message or
/// renders a broken network image.
class MessageAttachmentRow extends StatelessWidget {
  final List<MessageAttachmentRef> attachments;
  final RemoteMediaDataSource? filesClient;

  const MessageAttachmentRow({
    super.key,
    required this.attachments,
    this.filesClient,
  });

  static const _visibleLimit = 3;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final visible = attachments.take(_visibleLimit).toList(growable: false);
    final hidden = attachments.length - visible.length;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final attachment in visible)
                _AttachmentTile(
                  attachment: attachment,
                  filesClient: filesClient,
                ),
            ],
          ),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.l10n.attachments_more(hidden),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatefulWidget {
  final MessageAttachmentRef attachment;
  final RemoteMediaDataSource? filesClient;

  const _AttachmentTile({required this.attachment, this.filesClient});

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  Future<Uint8List?>? _imageFuture;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.isImage) {
      _imageFuture = _loadImage();
    }
  }

  Future<Uint8List?> _loadImage() async {
    final inline = widget.attachment.bytes;
    if (inline != null && inline.isNotEmpty) return inline;
    final path = widget.attachment.path;
    if (widget.attachment.isLocal && !widget.attachment.hasInlineBytes) {
      return null;
    }
    if (path.startsWith('data:')) {
      return _decodeDataUrl(path);
    }
    final client = widget.filesClient;
    if (client == null) return null;
    try {
      final dataUrl = await client.readMediaDataUrl(path);
      return _decodeDataUrl(dataUrl);
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _decodeDataUrl(String value) {
    final comma = value.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(value.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    if (!attachment.isImage) {
      return _FileChip(attachment: attachment);
    }
    if (attachment.isLocal && !attachment.hasInlineBytes) {
      return _ImageFallback(label: attachment.displayLabel);
    }
    return Semantics(
      label: context.l10n.attachment_image_label,
      child: FutureBuilder<Uint8List?>(
        future: _imageFuture,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                bytes,
                key: const Key('message-attachment-image'),
                width: 160,
                height: 120,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    _ImageFallback(label: attachment.displayLabel),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              width: 160,
              height: 120,
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return _ImageFallback(label: attachment.displayLabel);
        },
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  final String label;

  const _ImageFallback({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('message-attachment-image-failed'),
      width: 160,
      height: 120,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.image_not_supported_outlined, size: 20),
          const SizedBox(height: 4),
          Text(
            context.l10n.attachment_image_load_failed,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  final MessageAttachmentRef attachment;

  const _FileChip({required this.attachment});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.attachment_file_label,
      value: attachment.displayLabel,
      child: Container(
        key: const Key('message-attachment-file'),
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                attachment.displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
