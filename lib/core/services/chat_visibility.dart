import 'package:flutter/foundation.dart';

/// Which chats are on screen right now (mobile session ids).
///
/// Notification policy reads this: a turn that settles in front of the user is
/// not news, and a prompt that is already on screen must not also buzz. The
/// set is process-global because notifications are app-wide.
class ChatVisibility {
  static final ValueNotifier<Set<String>> visible =
      ValueNotifier<Set<String>>(const {});
}

extension ChatVisibilityOps on ValueNotifier<Set<String>> {
  void enter(String sessionId) {
    if (sessionId.isEmpty) return;
    if (value.contains(sessionId)) return;
    value = {...value, sessionId};
  }

  void leave(String sessionId) {
    if (!value.contains(sessionId)) return;
    value = value.where((id) => id != sessionId).toSet();
  }

  bool shows(String sessionId) => value.contains(sessionId);
}
