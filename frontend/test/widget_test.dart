import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_repository.dart';

void main() {
  testWidgets('an unauthenticated user is routed to the login screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
        child: const EduTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EduTrack School'), findsOneWidget);
    expect(find.text('Sign in to continue'), findsOneWidget);
  });
}
