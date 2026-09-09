import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_auth_token_storage.dart';

void main() {
  testWidgets('an unauthenticated visitor sees the marketing homepage', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          authTokenStorageProvider.overrideWithValue(FakeAuthTokenStorage()),
        ],
        child: const EduTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('School365ai'), findsWidgets);
    expect(find.text('Run Your School Smarter, Together.'), findsOneWidget);
  });

  testWidgets('the marketing homepage Login button goes to the login screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          authTokenStorageProvider.overrideWithValue(FakeAuthTokenStorage()),
        ],
        child: const EduTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back 👋'), findsOneWidget);
    expect(find.text('Sign in to continue to School365ai'), findsOneWidget);
  });
}
