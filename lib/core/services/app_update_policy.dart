/// Centralised switch for the fork's optional in-app update installer.
///
/// The download/verification/install code ships so a future release can be
/// enabled quickly, but production keeps this false: startup and taps only
/// open the release page. Tests inject an enabled installer explicitly.
abstract final class AppUpdatePolicy {
  static const bool inAppInstallerEnabled = false;
}
