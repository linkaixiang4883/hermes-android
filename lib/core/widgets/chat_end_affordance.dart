import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Accessible floating action that returns a chat to its current end.
class ChatEndAffordance extends StatelessWidget {
  static const buttonKey = Key('chat-go-to-end');
  static const countKey = Key('chat-new-message-count');

  final int newMessageCount;
  final VoidCallback onPressed;

  const ChatEndAffordance({
    required this.newMessageCount,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final hasNewMessages = newMessageCount > 0;
    final indicatorText = hasNewMessages ? context.l10n.newCount(newMessageCount) : context.l10n.latest;
    final semanticsValue = switch (newMessageCount) {
      0 => context.l10n.noNewMessages,
      1 => context.l10n.oneNewMessage,
      _ => context.l10n.newMessages(newMessageCount),
    };

    return Semantics(
      label: context.l10n.goToEnd,
      value: semanticsValue,
      button: true,
      excludeSemantics: true,
      child: FloatingActionButton.extended(
        key: buttonKey,
        heroTag: null,
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_downward_rounded),
        label: Text(indicatorText, key: countKey),
      ),
    );
  }
}
