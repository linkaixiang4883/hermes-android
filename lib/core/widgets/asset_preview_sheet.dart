import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

import '../services/media_download_saver.dart';
import '../services/office_text_extractor.dart';
import '../services/remote_files_client.dart';
import '../theme/hermes_theme.dart';
import '../utils/media_tags.dart';

/// Whether [ref] is a video container the shared preview can route to Android's
/// native player. Container recognition does not guarantee codec support.
bool isVideoAsset(MediaTagRef ref) => const {
  'mp4',
  'm4v',
  'mov',
  'webm',
  'mkv',
  'avi',
  '3gp',
}.contains(ref.extension);

/// Whether [ref] is a modern Office container with an offline text preview.
bool isOfficeAsset(MediaTagRef ref) =>
    const {'docx', 'xlsx', 'pptx'}.contains(ref.extension);

/// Opens the shared preview used by chat MEDIA cards, inline file links and
/// (eventually) More → Assets. Bytes are fetched only after this explicit tap.
Future<void> showAssetPreview({
  required BuildContext context,
  required MediaTagRef ref,
  required RemoteFilesDataSource Function() filesClient,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => AssetPreviewSheet(ref: ref, filesClient: filesClient),
  );
}

class AssetPreviewSheet extends StatefulWidget {
  const AssetPreviewSheet({
    super.key,
    required this.ref,
    required this.filesClient,
  });

  final MediaTagRef ref;
  final RemoteFilesDataSource Function() filesClient;

  @override
  State<AssetPreviewSheet> createState() => _AssetPreviewSheetState();
}

class _AssetPreviewSheetState extends State<AssetPreviewSheet> {
  Uint8List? _bytes;
  Object? _error;
  Future<OfficeTextPreview?>? _officeFuture;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final client = widget.filesClient();
    try {
      final download = await client.download(widget.ref.path);
      if (!mounted) return;
      setState(() {
        _bytes = download.bytes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    } finally {
      if (client is RemoteFilesClient) client.close();
    }
  }

  bool get _isVideo => const {
    'mp4',
    'm4v',
    'mov',
    'webm',
    'mkv',
    'avi',
    '3gp',
  }.contains(widget.ref.extension);

  bool get _isOffice => const {'docx', 'xlsx', 'pptx'}.contains(
    widget.ref.extension,
  );

  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null) return;
    try {
      final result = await MediaDownloadSaver.save(
        bytes: bytes,
        filename: widget.ref.filename,
        mimeType: _mime,
      );
      if (!mounted) return;
      if (result == null) {
        await _share();
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.l10n.media_card_saved_to_downloads),
          ),
        );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _share() async {
    final bytes = _bytes;
    if (bytes == null) return;
    try {
      final dir = await getTemporaryDirectory();
      final safe = widget.ref.filename.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final file = File(
        '${dir.path}/hermes-preview-${DateTime.now().microsecondsSinceEpoch}-$safe',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          subject: widget.ref.filename,
          files: <XFile>[XFile(file.path, mimeType: _mime)],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  String? get _mime {
    switch (widget.ref.extension) {
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'avi':
        return 'video/x-msvideo';
      case '3gp':
        return 'video/3gpp';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Dialog.fullscreen(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: Text(
            widget.ref.filename,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: context.l10n.media_card_save_to_downloads,
              onPressed: bytes == null ? null : () => unawaited(_save()),
              icon: const Icon(Icons.download_outlined),
            ),
            IconButton(
              tooltip: context.l10n.media_card_share,
              onPressed: bytes == null ? null : () => unawaited(_share()),
              icon: const Icon(Icons.share_outlined),
            ),
          ],
        ),
        body: _buildBody(context, bytes),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Uint8List? bytes) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || bytes == null) {
      return _PreviewUnavailable(
        message: _error?.toString() ?? context.l10n.preview_unavailable,
        onSave: bytes == null ? null : () => unawaited(_save()),
        onShare: bytes == null ? null : () => unawaited(_share()),
      );
    }
    if (_isVideo) {
      return _VideoPreview(
        bytes: bytes,
        filename: widget.ref.filename,
        onSave: () => unawaited(_save()),
        onShare: () => unawaited(_share()),
      );
    }
    if (_isOffice) {
      final future = _officeFuture ??= extractOfficeText(
        bytes: bytes,
        filename: widget.ref.filename,
      );
      return FutureBuilder<OfficeTextPreview?>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final preview = snapshot.data;
          if (preview == null || preview.text.trim().isEmpty) {
            return _PreviewUnavailable(
              message: context.l10n.preview_unavailable,
              onSave: () => unawaited(_save()),
              onShare: () => unawaited(_share()),
            );
          }
          return _OfficeTextPreviewView(preview: preview);
        },
      );
    }
    return _PreviewUnavailable(
      message: context.l10n.preview_unavailable,
      onSave: () => unawaited(_save()),
      onShare: () => unawaited(_share()),
    );
  }
}

class _OfficeTextPreviewView extends StatelessWidget {
  const _OfficeTextPreviewView({required this.preview});

  final OfficeTextPreview preview;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return ListView(
      padding: const EdgeInsets.all(HermesSpacing.lg),
      children: [
        if (preview.truncated)
          Padding(
            padding: const EdgeInsets.only(bottom: HermesSpacing.md),
            child: Text(
              context.l10n.preview_truncated,
              style: TextStyle(color: tokens.warning),
            ),
          ),
        SelectableText(
          preview.text,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _PreviewUnavailable extends StatelessWidget {
  const _PreviewUnavailable({
    required this.message,
    this.onSave,
    this.onShare,
  });

  final String message;
  final VoidCallback? onSave;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(HermesSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 48),
            const SizedBox(height: HermesSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: HermesSpacing.lg),
            Wrap(
              spacing: HermesSpacing.sm,
              children: [
                if (onSave != null)
                  FilledButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(context.l10n.media_card_save_to_downloads),
                  ),
                if (onShare != null)
                  OutlinedButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share_outlined),
                    label: Text(context.l10n.media_card_share),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({
    required this.bytes,
    required this.filename,
    required this.onSave,
    required this.onShare,
  });

  final Uint8List bytes;
  final String filename;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  File? _file;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final dir = await getTemporaryDirectory();
      final safe = widget.filename.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final file = File(
        '${dir.path}/hermes-video-${DateTime.now().microsecondsSinceEpoch}-$safe',
      );
      await file.writeAsBytes(widget.bytes, flush: true);
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(false);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _file = file;
        _controller = controller;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_controller?.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    final file = _file;
    if (file != null) {
      unawaited(file.delete().catchError((_) => file));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return _PreviewUnavailable(
        message: _error.toString(),
        onSave: widget.onSave,
        onShare: widget.onShare,
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(controller),
                  if (!controller.value.isPlaying)
                    IconButton.filled(
                      onPressed: () => unawaited(controller.play()),
                      icon: const Icon(Icons.play_arrow),
                    ),
                ],
              ),
            ),
          ),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final duration = value.duration;
              final position = value.position;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HermesSpacing.md,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (value.isPlaying) {
                          unawaited(controller.pause());
                        } else {
                          unawaited(controller.play());
                        }
                      },
                      icon: Icon(
                        value.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: duration.inMilliseconds.toDouble().clamp(
                          1,
                          double.infinity,
                        ),
                        value: position.inMilliseconds
                            .clamp(0, duration.inMilliseconds)
                            .toDouble(),
                        onChanged: (milliseconds) => unawaited(
                          controller.seekTo(
                            Duration(milliseconds: milliseconds.round()),
                          ),
                        ),
                      ),
                    ),
                    Text(_clock(position)),
                    IconButton(
                      onPressed: () => unawaited(
                        controller.setVolume(value.volume == 0 ? 1 : 0),
                      ),
                      icon: Icon(
                        value.volume == 0
                            ? Icons.volume_off
                            : Icons.volume_up,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _clock(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
