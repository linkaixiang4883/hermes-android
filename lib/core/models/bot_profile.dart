/// One Hermes profile as the Bots roster shows it.
///
/// A bot IS a profile: its identity, SOUL, model and memory live there, and
/// its one permanent conversation is a hidden session titled exactly
/// `Bot Chat` (the gateway resolves it in `canonical_session`). Nothing here
/// stores a session id — the title is the identity.
class BotProfile {
  final String name;
  final String displayName;
  final String model;
  final String description;
  final int skillCount;
  final bool isDefault;

  /// The registry row the gateway resolved for this bot's canonical chat
  /// (`profiles.list.canonical_session`); null when the bot has never talked.
  final Map<String, dynamic>? canonicalSession;

  const BotProfile({
    required this.name,
    required this.displayName,
    required this.model,
    required this.description,
    this.skillCount = 0,
    this.isDefault = false,
    this.canonicalSession,
  });

  /// What the roster row shows big: the profile's display name, else its name.
  String get title => displayName.trim().isEmpty ? name : displayName.trim();

  /// First character for the avatar placeholder (works for CJK too).
  String get initial {
    final source = title;
    return source.isEmpty ? '?' : source.substring(0, 1).toUpperCase();
  }

  static BotProfile fromJson(Map<String, dynamic> json) {
    final rawCanonical = json['canonical_session'];
    return BotProfile(
      name: (json['name'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      skillCount: (json['skill_count'] as num?)?.toInt() ?? 0,
      isDefault: json['is_default'] == true,
      canonicalSession: rawCanonical is Map
          ? Map<String, dynamic>.from(rawCanonical)
          : null,
    );
  }

  /// Last-message preview the gateway attached to the canonical chat, if any.
  String get preview {
    final row = canonicalSession;
    if (row == null) return '';
    return (row['preview'] ?? '').toString().trim();
  }
}
