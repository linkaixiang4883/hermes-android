// Read-only view of a Desktop-local ("legacy") group chat.
//
// Desktop mirrors these rooms into the default profile's metadata so a phone
// can read them; there is no hosted room behind the mirror, so this screen has
// no composer and no polling — just the bounded history and the promotion hint.

import 'package:flutter/material.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

import '../models/legacy_group_chat.dart';
import '../theme/hermes_theme.dart';

class LegacyGroupRoomScreen extends StatelessWidget {
  final LegacyGroupChat room;

  const LegacyGroupRoomScreen({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(room.title, overflow: TextOverflow.ellipsis),
            Text(
              context.l10n.group_legacy_section,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Material(
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HermesSpacing.md,
                vertical: HermesSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: HermesSpacing.sm),
                  Expanded(
                    child: Text(
                      context.l10n.group_legacy_banner,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: HermesSpacing.md,
                vertical: HermesSpacing.md,
              ),
              itemCount: room.messages.length,
              itemBuilder: (context, index) {
                final message = room.messages[index];
                return _LegacyPost(
                  key: ValueKey('legacy-post-${message.id}-$index'),
                  message: message,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Forum-style post: author header, time, then the body — the same shape the
/// hosted-room timeline uses, so both kinds of group read alike.
class _LegacyPost extends StatelessWidget {
  final LegacyGroupMessage message;

  const _LegacyPost({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = message.author.isEmpty
        ? (message.fromMember ? 'Bot' : context.l10n.group_you)
        : message.author;
    final initial = author.isEmpty ? '?' : author.substring(0, 1).toUpperCase();
    final at = message.sentAt?.toLocal();
    final stamp = at == null
        ? ''
        : '${at.month}/${at.day} '
              '${at.hour.toString().padLeft(2, '0')}:'
              '${at.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: HermesSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: message.fromMember
                ? theme.colorScheme.tertiaryContainer
                : theme.colorScheme.primary,
            child: Text(
              initial,
              style: theme.textTheme.labelMedium?.copyWith(
                color: message.fromMember
                    ? theme.colorScheme.onTertiaryContainer
                    : theme.colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: HermesSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (message.source.isNotEmpty) ...[
                      const SizedBox(width: HermesSpacing.xs),
                      Text(
                        message.source,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (stamp.isNotEmpty)
                      Text(
                        stamp,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: HermesSpacing.md,
                    vertical: HermesSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: message.fromMember
                        ? theme.colorScheme.surfaceContainerLow
                        : theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.45,
                          ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: message.fromMember
                          ? theme.colorScheme.outlineVariant
                          : theme.colorScheme.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: SelectableText(
                    message.text,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
