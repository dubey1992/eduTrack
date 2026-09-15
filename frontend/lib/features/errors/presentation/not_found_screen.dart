import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/status_page.dart';
import '../../auth/application/auth_notifier.dart';

/// A route inside the app that does not exist - a stale bookmark, a link
/// somebody edited by hand, a path from an older version of the app.
///
/// Where it sends them depends on whether they are signed in: back to their
/// dashboard, or to the homepage. Offering "Dashboard" to somebody with no
/// session only produces a second dead end.
class NotFoundScreen extends ConsumerWidget {
  const NotFoundScreen({super.key, required this.location});

  /// The path that did not match, shown so a person can see the typo.
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSignedIn = ref.watch(authNotifierProvider).value != null;

    return StatusPage(
      badge: 'Error 404',
      headline: "We couldn't find that page.",
      body:
          'The link may be out of date, or the address may have a typo in it. '
          'Nothing has gone wrong with your account, and nothing has been lost.',
      actions: [
        FilledButton(
          onPressed: () => context.go(isSignedIn ? '/dashboard' : '/'),
          child: Text(isSignedIn ? 'Back to dashboard' : 'Go to School365ai'),
        ),
        if (!isSignedIn) OutlinedButton(onPressed: () => context.go('/login'), child: const Text('Sign in')),
      ],
      detail: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('You asked for '),
          SelectableText(location, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ],
      ),
    );
  }
}
