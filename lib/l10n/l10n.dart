import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// Convenience accessor so call sites read `context.l10n.someKey`
/// instead of `AppLocalizations.of(context).someKey`.
extension HermesL10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
