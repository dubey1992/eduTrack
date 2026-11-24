import 'package:flutter/widgets.dart';

import '../errors/failure.dart';
import 'l10n.dart';

/// A failure in the person's language (docs/mobile-apps-review.md, M11).
///
/// The app's own failures - no connection, a slow server, the unexpected -
/// are translated. A message the server wrote is shown as the server wrote
/// it: the server speaks English in this phase (decided 2026-11-24, app
/// screens only).
extension FailureText on Failure {
  String localizedMessage(BuildContext context) {
    final l10n = context.l10n;
    if (message == Failure.network().message) return l10n.errorNoConnection;
    if (message == Failure.timeout().message) return l10n.errorTimeout;
    if (message == Failure.unknown().message) return l10n.errorUnknown;

    return message;
  }
}
