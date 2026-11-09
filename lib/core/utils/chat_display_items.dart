import '../models/gateway_activity.dart';
import '../models/gateway_insight.dart';
import '../models/message_attachment.dart';
import 'message_content.dart';

/// Assistant reasoning rendered as its own collapsible item in the chat list.
class ChatReasoningItem {
  final String text;
  final bool initiallyExpanded;

  /// Stable identity of the reasoning BLOCK (the message it belongs to).
  ///
  /// The reasoning card's expansion belongs to the block, not to its current
  /// text: keying the tile by content rebuilt it on every streamed token and
  /// collapsed it under the finger (the "thinking card cannot be opened"
  /// report).
  final String identity;

  const ChatReasoningItem(
    this.text,
    this.initiallyExpanded, {
    this.identity = '',
  });
}

/// Project a raw Hermes message list into the heterogeneous list the chat
/// screen renders.
///
/// The result mixes four item kinds, in the order the conversation produced
/// them:
///
/// - `Map<String, dynamic>` — a user or assistant bubble, carrying
///   `_display_content` (tool-result blocks stripped) and, for assistant
///   replies, `_retry_prompt` with the user prompt that caused it;
/// - `List<GatewayToolActivity>` — consecutive tool results collapsed into one
///   activity card;
/// - [ChatReasoningItem] — assistant reasoning, emitted before its bubble;
/// - `GatewaySubagentActivity` list and [GatewayNotice] — appended last.
///
/// Tool results are matched positionally against [toolActivities]: stored tool
/// messages consume activities in order, and any activity left over (streamed
/// but not yet persisted by the server) is appended as a trailing card. The
/// caller's [toolActivities] list is never mutated.
List<dynamic> buildChatDisplayItems({
  required List<Map<String, dynamic>> messages,
  List<GatewayToolActivity> toolActivities = const [],
  List<GatewaySubagentActivity> subagentActivities = const [],
  List<GatewayNotice> notices = const [],
  bool verbose = false,
  /// V3-style quiet mode: hide tool/reasoning/subagent/notice cards from the
  /// transcript while keeping human and assistant prose plus MEDIA cards.
  /// Defaults to false so existing pure-model tests keep their explicit
  /// activity fixtures.
  bool quiet = false,
}) {
  final showActivity = verbose || !quiet;
  final toolQueue = List<GatewayToolActivity>.from(toolActivities);
  final displayItems = <dynamic>[];
  final currentGroup = <GatewayToolActivity>[];
  String? lastUserPrompt;

  void flushToolGroup() {
    if (currentGroup.isEmpty) return;
    if (showActivity) displayItems.add(currentGroup.toList());
    currentGroup.clear();
  }

  for (var index = 0; index < messages.length; index++) {
    final msg = messages[index];
    final rawRole = (msg['role'] as String?) ?? 'assistant';
    final role = rawRole == 'agent' ? 'assistant' : rawRole;
    if (isToolResultMessage(msg)) {
      if (toolQueue.isNotEmpty) currentGroup.add(toolQueue.removeAt(0));
      continue;
    }
    if (role != 'user' && role != 'assistant') continue;

    final content = stripToolResultText(messageContentToText(msg['content']));
    final extracted = role == 'user'
        ? extractAttachmentContent(msg['content'])
        : null;
    final displayContent = extracted?.text ?? content;
    final attachments = <MessageAttachmentRef>[
      ..._metadataAttachments(msg),
      ...?extracted?.attachments,
    ];
    final uniqueAttachments = _dedupeAttachments(attachments);
    final reasoning = msg['_gateway_reasoning']?.toString() ?? '';
    final hasReasoning = role == 'assistant' && reasoning.trim().isNotEmpty;
    if (displayContent.isEmpty &&
        uniqueAttachments.isEmpty &&
        !hasReasoning) {
      continue;
    }

    flushToolGroup();

    if (hasReasoning && showActivity) {
      displayItems.add(
        ChatReasoningItem(
          reasoning,
          verbose || msg['_gateway_reasoning_verbose'] == true,
          identity: msg['id']?.toString() ?? 'message-$index',
        ),
      );
    }
    if (displayContent.isNotEmpty || uniqueAttachments.isNotEmpty) {
      if (role == 'user' && displayContent.isNotEmpty) {
        lastUserPrompt = displayContent;
      }
      displayItems.add({
        ...msg,
        'role': role,
        '_display_content': displayContent,
        if (role == 'user' && uniqueAttachments.isNotEmpty)
          '_display_attachments': uniqueAttachments,
        if (role == 'assistant' && lastUserPrompt != null)
          '_retry_prompt': lastUserPrompt,
      });
    }
  }
  flushToolGroup();

  // Tools from gateway events that arrived during streaming but were never
  // matched to a stored message — show them as a trailing card.
  if (showActivity && toolQueue.isNotEmpty) displayItems.add(toolQueue.toList());
  if (showActivity && subagentActivities.isNotEmpty) {
    displayItems.add(List<GatewaySubagentActivity>.from(subagentActivities));
  }
  if (showActivity) displayItems.addAll(notices);

  return displayItems;
}

List<MessageAttachmentRef> _metadataAttachments(Map<String, dynamic> msg) {
  final raw = msg['_display_attachments'];
  if (raw is! List) return const [];
  return raw.whereType<MessageAttachmentRef>().toList(growable: false);
}

List<MessageAttachmentRef> _dedupeAttachments(
  List<MessageAttachmentRef> attachments,
) {
  final seen = <String>{};
  final result = <MessageAttachmentRef>[];
  for (final attachment in attachments) {
    final key = '${attachment.kind.name}\u0000${attachment.path}';
    if (seen.add(key)) result.add(attachment);
  }
  return result;
}
