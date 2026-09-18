import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every provider that caches data across screens - one that is not
/// autoDispose - must be reset on sign-out, or the next person to sign in on
/// the same browser sees the last person's data until it refetches.
///
/// A sweep of the source rather than a list kept by hand: the list is what
/// went stale before (Phase 21 found seventeen missing).
void main() {
  test('sign-out resets every provider that keeps data between screens', () {
    final reset = File('lib/features/auth/application/auth_notifier.dart').readAsStringSync();
    final declaration = RegExp(r'^final (\w+Provider) =\s*(\w+Provider)(\.\w+)?', multiLine: true);

    // Not data about anybody: the session itself, and the fixed list of zones.
    const exempt = {'authNotifierProvider', 'timezoneListProvider'};

    final missing = <String>[];
    for (final file in Directory('lib/features').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;

      for (final match in declaration.allMatches(file.readAsStringSync())) {
        final name = match.group(1)!;
        final kind = match.group(2)!;
        final modifier = match.group(3);
        final keepsData = (kind.contains('Notifier') || kind == 'FutureProvider') && modifier != '.autoDispose';

        if (keepsData && !exempt.contains(name) && !reset.contains('ref.invalidate($name)')) {
          missing.add(name);
        }
      }
    }

    expect(missing, isEmpty, reason: 'add these to _resetSessionScopedProviders in auth_notifier.dart');
  });
}
