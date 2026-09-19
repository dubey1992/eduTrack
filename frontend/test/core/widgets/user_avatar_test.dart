import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_photo_dio.dart';

Widget wrap(Widget child, {List<int>? photoBytes}) {
  return ProviderScope(
    overrides: [dioClientProvider.overrideWithValue(fakePhotoDio(bytes: photoBytes))],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// A photo when there is one, the person's initials whenever there is not -
/// including when the photo cannot be fetched.
void main() {
  testWidgets('no photo url shows the initials of the first and last name', (tester) async {
    await tester.pumpWidget(wrap(const UserAvatar(photoUrl: null, name: 'Asha Devi Rao')));
    await tester.pumpAndSettle();

    expect(find.text('AR'), findsOneWidget);
    expect(find.byKey(const Key('user-avatar-photo')), findsNothing);
  });

  testWidgets('a one-word name gives one initial', (tester) async {
    await tester.pumpWidget(wrap(const UserAvatar(photoUrl: null, name: 'admin')));
    await tester.pumpAndSettle();

    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('a photo that cannot be fetched falls back to the initials', (tester) async {
    await tester.pumpWidget(wrap(const UserAvatar(photoUrl: '/users/12/photo?v=1', name: 'Asha Rao')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('AR'), findsOneWidget);
    expect(find.byKey(const Key('user-avatar-photo')), findsNothing);
  });

  testWidgets('a fetched photo is shown in place of the initials', (tester) async {
    await tester.pumpWidget(
      wrap(
        const UserAvatar(photoUrl: '/users/12/photo?v=1', name: 'Asha Rao'),
        photoBytes: const [1, 2, 3],
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('user-avatar-photo')), findsOneWidget);
  });
}
