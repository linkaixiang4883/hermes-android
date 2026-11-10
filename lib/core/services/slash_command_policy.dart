/// Commands that are advertised by the gateway but are not useful on a phone.
///
/// Keep names lower-case and without the leading slash. This is intentionally
/// the only list the catalogue and the send gate consult; add entries here as
/// real desktop catalogues expose commands that do not make sense on mobile.
const Set<String> mobileBlockedSlashCommands = <String>{};

bool isMobileSlashCommandBlocked(String name) =>
    mobileBlockedSlashCommands.contains(
      name.trim().replaceFirst(RegExp(r'^/+'), '').toLowerCase(),
    );
