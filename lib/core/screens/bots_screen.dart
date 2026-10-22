// Bot Mode's roster, natively.
//
// A bot is a Hermes profile. Its one permanent conversation is a hidden
// session titled exactly `Bot Chat`, resolved by title on every open — the
// client never stores a session id, so the relationship cannot dangle.
//
// Nothing here writes transcripts: the ChatScreen the roster opens does the
// real work, with `Session.profile` carrying the bot's scope.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

import '../models/bot_profile.dart';
import '../services/connection_manager.dart';
import '../services/desktop_gateway_client.dart';
import '../theme/hermes_theme.dart';

/// Reads the roster. Injectable so the pane is testable without a gateway.
typedef BotsRosterLoader = Future<List<BotProfile>> Function();

/// Resolves (and, first time, creates) one bot's canonical chat.
typedef BotChatOpener = Future<Session> Function(BotProfile bot);

class BotsScreen extends StatefulWidget {
  final SavedConnection connection;

  /// The shared gateway client. Null only in tests, which inject [testLoader]
  /// and [testOpener] instead.
  final DesktopGatewayClient? client;

  /// True when this screen built the client itself and must close it.
  final bool ownsClient;

  /// Navigation stays with the host: it knows how to push a ChatScreen.
  final ValueChanged<Session>? onOpenSession;

  @visibleForTesting
  final BotsRosterLoader? testLoader;

  @visibleForTesting
  final BotChatOpener? testOpener;

  /// Poll cadence while visible — the desktop roster uses the same window.
  final Duration refreshInterval;

  const BotsScreen({
    super.key,
    required this.connection,
    this.client,
    this.ownsClient = false,
    this.onOpenSession,
    this.testLoader,
    this.testOpener,
    this.refreshInterval = const Duration(seconds: 5),
  });

  @override
  State<BotsScreen> createState() => _BotsScreenState();
}

class _BotsScreenState extends State<BotsScreen> {
  List<BotProfile> _bots = const [];
  bool _loading = true;
  String? _error;
  String? _opening;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(widget.refreshInterval, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (widget.ownsClient) widget.client?.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final loader =
          widget.testLoader ??
          () => widget.client!.listProfiles();
      final bots = await loader();
      if (!mounted) return;
      setState(() {
        _bots = bots;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        // A later failure keeps the last roster behind the notice; only a
        // first read with nothing to show becomes an error state.
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _open(BotProfile bot) async {
    if (_opening != null) return;
    setState(() => _opening = bot.name);
    try {
      final opener =
          widget.testOpener ??
          (bot) => widget.client!.resolveBotChat(bot.name);
      final session = await opener(bot);
      if (!mounted) return;
      widget.onOpenSession?.call(session);
      if (mounted) Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.l10n.bot_chat_open_failed(error.toString())),
          ),
        );
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.bots)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _bots.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_bots.isEmpty && _error != null) {
      return ListView(
        padding: const EdgeInsets.all(HermesSpacing.lg),
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: HermesSpacing.md),
          Text(
            context.l10n.bots_load_failed,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: HermesSpacing.sm),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: HermesSpacing.lg),
          Center(
            child: FilledButton(
              onPressed: _load,
              child: Text(context.l10n.retry),
            ),
          ),
        ],
      );
    }
    if (_bots.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(HermesSpacing.lg),
        children: [
          Icon(
            Icons.smart_toy_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: HermesSpacing.md),
          Text(
            context.l10n.bots_empty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: HermesSpacing.sm),
          Text(
            context.l10n.bots_subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }
    return ListView.separated(
      itemCount: _bots.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final bot = _bots[index];
        final opening = _opening == bot.name;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            child: Text(bot.initial),
          ),
          title: Text(bot.title),
          subtitle: Text(
            [
              if (bot.model.trim().isNotEmpty) bot.model.trim(),
              if (bot.preview.isNotEmpty) bot.preview,
              if (bot.preview.isEmpty && bot.description.isNotEmpty)
                bot.description,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: opening
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: opening ? null : () => unawaited(_open(bot)),
        );
      },
    );
  }
}
