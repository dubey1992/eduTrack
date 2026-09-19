import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/school_clock.dart';
import 'package:edutrack_app/core/widgets/status_badge.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/staff/data/attendant_access_repository.dart';
import 'package:edutrack_app/features/staff/data/models/attendant_access.dart';
import 'package:edutrack_app/features/staff/presentation/attendant_sign_in_dialog.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/attendant_fixtures.dart';
import '../../support/fake_attendant_access_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_user_repository.dart';

/// India, +5:30 - so a UTC instant from the API must come out five and a
/// half hours later on screen, whatever zone the test machine is in.
final _kolkataClock = SchoolClock(
  timezone: 'Asia/Kolkata',
  schoolTimeAtAnchor: DateTime(2026, 9, 10, 13, 30),
  anchorUtc: DateTime.utc(2026, 9, 10, 8, 0),
);

final _schoolAdmin = AuthenticatedUser(
  id: 5,
  name: 'Admin',
  email: 'admin@example.com',
  role: UserRole.schoolAdmin,
  clock: _kolkataClock,
);

const _attendantUser = AppUser(
  id: 131,
  firstName: 'Meera',
  lastName: 'Sharma',
  name: 'Meera Sharma',
  email: 'attendant-1a2b3c4d5e6f7a8b@no-email.invalid',
  mobile: '+91 9876543210',
  role: UserRole.busAttendant,
  status: UserStatus.active,
);

/// The ordinary user unlock, which on the server also clears the passcode
/// lock - so the panel's refetch sees the account unlocked.
class _UnlockingUserRepository extends FakeUserRepository {
  _UnlockingUserRepository(this.access) : super(users: [_attendantUser]);

  final FakeAttendantAccessRepository access;

  @override
  Future<AppUser> unlock(int userId) async {
    access.unlockOnServer();
    return super.unlock(userId);
  }
}

Widget wrap(FakeAttendantAccessRepository access, {FakeUserRepository? users}) {
  return ProviderScope(
    overrides: [
      attendantAccessRepositoryProvider.overrideWithValue(access),
      userRepositoryProvider.overrideWithValue(users ?? _UnlockingUserRepository(access)),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _schoolAdmin)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AttendantSignInDialog(profile: meeraAttendant),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Records what reaches the clipboard - the test binding has no real one.
List<String> _captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

void main() {
  testWidgets('a new attendant: the mobile, no passcode yet, no phone', (tester) async {
    await tester.pumpWidget(wrap(FakeAttendantAccessRepository(access: freshAccess)));
    await _open(tester);

    expect(find.text('Sign-in · Meera Sharma'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('Not set up yet - issue a setup code'), findsOneWidget);
    expect(find.text('None waiting'), findsOneWidget);
    expect(find.text('No phone registered yet.'), findsOneWidget);
    expect(find.text('Locked after 5 wrong tries'), findsNothing);
    expect(find.text('Issue setup code'), findsOneWidget);
  });

  testWidgets('a load failure shows the message and Retry loads it', (tester) async {
    final access = FakeAttendantAccessRepository(
      access: freshAccess,
      failGetWith: const Failure(code: 'FORBIDDEN', message: 'You cannot manage this employee.'),
    );
    await tester.pumpWidget(wrap(access));
    await _open(tester);

    expect(find.text('You cannot manage this employee.'), findsOneWidget);
    // No actions on something that never loaded.
    expect(find.text('Issue setup code'), findsNothing);

    access.failGetWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('Issue setup code'), findsOneWidget);
  });

  testWidgets('issuing a code shows it once, spaced, with its expiry, number and a Copy button', (tester) async {
    final copied = _captureClipboard(tester);
    final access = FakeAttendantAccessRepository(access: freshAccess)
      ..nextExpiresAt = DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String();
    await tester.pumpWidget(wrap(access));
    await _open(tester);

    await tester.tap(find.text('Issue setup code'));
    await tester.pumpAndSettle();

    expect(access.issueCalls, 1);
    expect(find.text('Setup code for Meera Sharma'), findsOneWidget);
    expect(find.text('1234 5678'), findsOneWidget);
    expect(find.textContaining('Valid for 24 hours, until '), findsOneWidget);
    expect(find.text('For mobile number +919876543210'), findsOneWidget);
    expect(find.textContaining("tap 'Bus attendant? Sign in with your mobile number'"), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, ['12345678']);
    expect(find.text('Setup code copied.'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // The code is gone for good; the panel now says one is waiting.
    expect(find.text('1234 5678'), findsNothing);
    expect(find.textContaining('Waiting to be used - valid until '), findsOneWidget);
  });

  testWidgets('a pending code shows its expiry on the school clock', (tester) async {
    const pending = AttendantAccess(
      loginMobile: '+919876543210',
      hasPasscode: false,
      isLocked: false,
      setupCodePending: true,
      setupCodeExpiresAt: '2026-09-11T02:00:00.000000Z',
      devices: [],
    );
    await tester.pumpWidget(wrap(FakeAttendantAccessRepository(access: pending)));
    await _open(tester);

    // 02:00 UTC is 7:30 AM in Kolkata.
    expect(find.text('Waiting to be used - valid until 09/11/2026 7:30 AM'), findsOneWidget);
  });

  testWidgets('replacing a waiting code asks first; Cancel issues nothing', (tester) async {
    const pending = AttendantAccess(
      loginMobile: '+919876543210',
      hasPasscode: false,
      isLocked: false,
      setupCodePending: true,
      setupCodeExpiresAt: '2026-09-11T02:00:00.000000Z',
      devices: [],
    );
    final access = FakeAttendantAccessRepository(access: pending);
    await tester.pumpWidget(wrap(access));
    await _open(tester);

    await tester.tap(find.text('Issue setup code'));
    await tester.pumpAndSettle();
    expect(find.text('Replace the waiting setup code?'), findsOneWidget);
    expect(find.textContaining('Issuing a new code replaces it'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(access.issueCalls, 0);

    await tester.tap(find.text('Issue setup code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Issue new code'));
    await tester.pumpAndSettle();
    expect(access.issueCalls, 1);
    expect(find.text('1234 5678'), findsOneWidget);
  });

  testWidgets('a refused code (account switched off) is shown in the panel', (tester) async {
    final access = FakeAttendantAccessRepository(
      access: freshAccess,
      failIssueWith: const Failure(
        code: 'ACCOUNT_INACTIVE',
        message: 'This account is switched off. Switch it on before issuing a setup code.',
      ),
    );
    await tester.pumpWidget(wrap(access));
    await _open(tester);

    await tester.tap(find.text('Issue setup code'));
    await tester.pumpAndSettle();

    expect(find.text('This account is switched off. Switch it on before issuing a setup code.'), findsOneWidget);
    expect(find.textContaining('Setup code for'), findsNothing);
  });

  testWidgets('registered phones: active and removed, and removing one asks first', (tester) async {
    final access = FakeAttendantAccessRepository(access: setUpAccess);
    await tester.pumpWidget(wrap(access));
    await _open(tester);

    expect(find.text('Set'), findsOneWidget);
    expect(find.text('Redmi Note 12'), findsOneWidget);
    expect(find.text('Old Samsung'), findsOneWidget);
    // Registered 02:00 UTC on 09/09 -> 7:30 AM in Kolkata.
    expect(find.text('Registered 09/09/2026 7:30 AM · Last used 09/10/2026 7:15 AM'), findsOneWidget);
    expect(find.text('Registered 09/01/2026 7:30 AM · Last used -'), findsOneWidget);
    expect(find.widgetWithText(StatusBadge, 'Active'), findsOneWidget);
    expect(find.widgetWithText(StatusBadge, 'Removed'), findsOneWidget);
    // Only the active phone can be removed.
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sign out and remove Redmi Note 12? The attendant will need a new setup code to use that phone again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(access.lastRemovedDeviceId, isNull);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(access.lastRemovedDeviceId, 7);
    expect(find.text('Redmi Note 12 was removed.'), findsOneWidget);
    expect(find.widgetWithText(StatusBadge, 'Removed'), findsNWidgets(2));
    expect(find.widgetWithText(TextButton, 'Remove'), findsNothing);
  });

  testWidgets('a locked account shows the red badge, and Unlock clears it', (tester) async {
    final access = FakeAttendantAccessRepository(access: setUpAccess.copyWith(isLocked: true));
    final users = _UnlockingUserRepository(access);
    await tester.pumpWidget(wrap(access, users: users));
    await _open(tester);

    expect(find.text('Locked after 5 wrong tries'), findsOneWidget);

    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(users.unlockCalls, 1);
    expect(find.text('Locked after 5 wrong tries'), findsNothing);
    expect(find.text('Meera Sharma can sign in again.'), findsOneWidget);
  });

  test('SetupCodeDialog.spaced groups the digits in fours', () {
    expect(SetupCodeDialog.spaced('12345678'), '1234 5678');
    expect(SetupCodeDialog.spaced('1234'), '1234');
    expect(SetupCodeDialog.spaced(''), '');
  });
}
