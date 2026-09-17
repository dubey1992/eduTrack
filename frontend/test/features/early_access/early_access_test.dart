import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/core/routing/app_nav.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/early_access/data/early_access_repository.dart';
import 'package:edutrack_app/features/early_access/data/models/early_access_request.dart';
import 'package:edutrack_app/features/early_access/presentation/early_access_screen.dart';
import 'package:edutrack_app/features/marketing/presentation/widgets/early_access_form.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/schools/presentation/add_school_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/paginated_table.dart';

EarlyAccessRequest _request({
  int id = 1,
  String schoolName = 'Greenfield High',
  EarlyAccessStatus status = EarlyAccessStatus.newRequest,
  int? expectedStudents = 850,
  String? convertedSchoolName,
}) {
  return EarlyAccessRequest(
    id: id,
    schoolName: schoolName,
    contactName: 'Priya Nair',
    contactRole: 'Principal',
    email: 'priya@greenfield.test',
    phone: '+91 9876543210',
    city: 'Pune',
    country: 'India',
    expectedStudents: expectedStudents,
    currentSoftware: 'Spreadsheets',
    message: 'We open a second campus in June.',
    status: status,
    convertedSchoolName: convertedSchoolName,
    submittedAt: '09/15/2026 10:30 AM',
  );
}

class _FakeEarlyAccessRepository implements EarlyAccessRepository {
  _FakeEarlyAccessRepository({List<EarlyAccessRequest>? requests, this.failSubmitWith})
    : _requests = requests ?? [_request()];

  final List<EarlyAccessRequest> _requests;
  final Failure? failSubmitWith;

  Map<String, dynamic>? submitted;
  int? reviewedId;
  String? reviewedStatus;
  String? reviewedNotes;

  @override
  Future<String> submit(Map<String, dynamic> payload) async {
    if (failSubmitWith != null) throw failSubmitWith!;
    submitted = payload;

    return 'Thanks - we have your details and will be in touch soon.';
  }

  @override
  Future<PaginatedResponse<EarlyAccessRequest>> list({
    String? status,
    String? query,
    int page = 1,
    int perPage = 20,
  }) async {
    return PaginatedResponse(items: _requests, currentPage: 1, lastPage: 1, total: _requests.length, perPage: perPage);
  }

  @override
  Future<EarlyAccessRequest> review(int id, {String? status, String? notes}) async {
    reviewedId = id;
    reviewedStatus = status;
    reviewedNotes = notes;

    return _request(id: id, status: EarlyAccessStatus.fromApiValue(status ?? 'new'));
  }
}

const _superAdmin = AuthenticatedUser(
  id: 1,
  name: 'Super Admin',
  email: 'admin@example.com',
  role: UserRole.superAdmin,
);

void main() {
  group('the public form', () {
    Widget wrap(_FakeEarlyAccessRepository fake) {
      return ProviderScope(
        overrides: [earlyAccessRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  TextButton(onPressed: () => showEarlyAccessDialog(context), child: const Text('Join Early Access')),
            ),
          ),
        ),
      );
    }

    Future<void> open(WidgetTester tester, _FakeEarlyAccessRepository fake) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(wrap(fake));
      await tester.tap(find.text('Join Early Access'));
      await tester.pumpAndSettle();
    }

    Future<void> fillRequired(WidgetTester tester) async {
      await tester.enterText(find.widgetWithText(TextFormField, 'School name'), 'Greenfield High');
      await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Priya Nair');
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'priya@greenfield.test');
      await tester.enterText(find.widgetWithText(TextFormField, 'City'), 'Pune');
      await tester.enterText(find.widgetWithText(TextFormField, 'Country'), 'India');
      await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '9876543210');
    }

    testWidgets('asks for what a callback actually needs', (tester) async {
      await open(tester, _FakeEarlyAccessRepository());

      expect(find.text('Join Early Access'), findsWidgets);
      for (final label in ['School name', 'Your name', 'Email', 'City', 'Country']) {
        expect(find.widgetWithText(TextFormField, label), findsOneWidget, reason: '$label is missing');
      }
    });

    testWidgets('treats the student count as a bonus, not a requirement', (tester) async {
      // A school that does not know its number should still be able to get in
      // touch.
      final fake = _FakeEarlyAccessRepository();
      await open(tester, fake);
      await fillRequired(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Request access'));
      await tester.pumpAndSettle();

      expect(fake.submitted, isNotNull);
      expect(fake.submitted!['expected_students'], isNull);
    });

    testWidgets('will not submit without the essentials', (tester) async {
      final fake = _FakeEarlyAccessRepository();
      await open(tester, fake);

      await tester.tap(find.widgetWithText(FilledButton, 'Request access'));
      await tester.pumpAndSettle();

      expect(find.text('School name is required'), findsOneWidget);
      expect(find.text('Email is required'), findsOneWidget);
      expect(fake.submitted, isNull);
    });

    testWidgets('checks an email looks like one', (tester) async {
      final fake = _FakeEarlyAccessRepository();
      await open(tester, fake);
      await fillRequired(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'not-an-email');

      await tester.tap(find.widgetWithText(FilledButton, 'Request access'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(fake.submitted, isNull);
    });

    testWidgets('sends everything the school filled in', (tester) async {
      final fake = _FakeEarlyAccessRepository();
      await open(tester, fake);
      await fillRequired(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Your role (optional)'), 'Principal');
      await tester.enterText(find.widgetWithText(TextFormField, 'Roughly how many students? (optional)'), '850');

      await tester.tap(find.widgetWithText(FilledButton, 'Request access'));
      await tester.pumpAndSettle();

      expect(fake.submitted!['school_name'], 'Greenfield High');
      expect(fake.submitted!['contact_role'], 'Principal');
      expect(fake.submitted!['expected_students'], 850);
      // Composed with the dial code, ready to ring.
      expect(fake.submitted!['phone'], contains('9876543210'));
      expect(fake.submitted!['phone'], startsWith('+'));
    });

    testWidgets('thanks them afterwards rather than leaving a filled form', (tester) async {
      await open(tester, _FakeEarlyAccessRepository());
      await fillRequired(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Request access'));
      await tester.pumpAndSettle();

      expect(find.text('Thanks for your interest!'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'School name'), findsNothing);
    });

    testWidgets('keeps what was typed when the server says no', (tester) async {
      final fake = _FakeEarlyAccessRepository(
        failSubmitWith: const Failure(code: 'TOO_MANY_REQUESTS', message: 'Too many requests. Try again later.'),
      );
      await open(tester, fake);
      await fillRequired(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Request access'));
      await tester.pumpAndSettle();

      expect(find.text('Too many requests. Try again later.'), findsOneWidget);
      // Nothing retyped.
      expect(find.text('Greenfield High'), findsOneWidget);
    });
  });

  group('the Super Admin panel', () {
    Widget wrap(_FakeEarlyAccessRepository fake) {
      return ProviderScope(
        overrides: [
          earlyAccessRepositoryProvider.overrideWithValue(fake),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _superAdmin)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: EarlyAccessScreen()),
        ),
      );
    }

    Future<void> pump(WidgetTester tester, _FakeEarlyAccessRepository fake) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
    }

    testWidgets('lists what each school told us', (tester) async {
      await pump(tester, _FakeEarlyAccessRepository());

      expect(find.text('Greenfield High'), findsOneWidget);
      expect(find.text('Pune, India'), findsOneWidget);
      expect(find.text('850'), findsOneWidget);
      expect(find.text('New'), findsWidgets);
    });

    testWidgets('says nothing rather than zero when a size was not given', (tester) async {
      await pump(tester, _FakeEarlyAccessRepository(requests: [_request(expectedStudents: null)]));

      // Not knowing is different from none.
      expect(find.text('-'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('says so plainly when nobody has asked yet', (tester) async {
      await pump(tester, _FakeEarlyAccessRepository(requests: []));

      expect(find.text('No schools have asked for access yet.'), findsOneWidget);
    });

    testWidgets('opens the whole request', (tester) async {
      await pump(tester, _FakeEarlyAccessRepository());

      await tester.tap(find.widgetWithText(TextButton, 'View'));
      await tester.pumpAndSettle();

      expect(find.text('priya@greenfield.test'), findsOneWidget);
      expect(find.text('Spreadsheets'), findsOneWidget);
      expect(find.text('We open a second campus in June.'), findsOneWidget);
    });

    testWidgets('moves a request along with a note', (tester) async {
      final fake = _FakeEarlyAccessRepository();
      await pump(tester, fake);

      await tester.tap(find.widgetWithText(TextButton, 'View'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<EarlyAccessStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contacted').hitTestable());
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Notes'), 'Demo on Friday.');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(fake.reviewedId, 1);
      expect(fake.reviewedStatus, 'contacted');
      expect(fake.reviewedNotes, 'Demo on Friday.');
    });

    testWidgets('never offers Converted as something to choose', (tester) async {
      // It means a school exists, and onboarding one is what sets it.
      await pump(tester, _FakeEarlyAccessRepository());

      await tester.tap(find.widgetWithText(TextButton, 'View'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<EarlyAccessStatus>));
      await tester.pumpAndSettle();

      expect(find.text('Converted').hitTestable(), findsNothing);
      expect(find.text('Declined').hitTestable(), findsOneWidget);
    });

    testWidgets('a converted request has nothing left to decide', (tester) async {
      await pump(
        tester,
        _FakeEarlyAccessRepository(
          requests: [_request(status: EarlyAccessStatus.converted, convertedSchoolName: 'Greenfield High')],
        ),
      );

      await tester.tap(find.widgetWithText(TextButton, 'View'));
      await tester.pumpAndSettle();

      expect(find.textContaining('has been onboarded'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Onboard this school'), findsNothing);
    });

    testWidgets('a full page of requests scrolls above the pagination bar on desktop', (tester) async {
      useShortDesktopWindow(tester);
      final requests = [for (var n = 1; n <= 20; n++) _request(id: n, schoolName: 'School $n')];
      await tester.pumpWidget(wrap(_FakeEarlyAccessRepository(requests: requests)));
      await tester.pumpAndSettle();

      await expectLastRowScrollsAbovePagination(tester, find.text('School 20'));
    });
  });

  group('onboarding from a request', () {
    testWidgets('starts from what the school already told us', (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _superAdmin)),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: AddSchoolDialog(fromEarlyAccess: _request())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nobody should have to retype what the form already captured.
      expect(find.text('Greenfield High'), findsOneWidget);
      expect(find.text('priya@greenfield.test'), findsOneWidget);
      expect(find.text('Pune'), findsOneWidget);
      expect(find.text('India'), findsOneWidget);
      // The dial code is split back out of the stored number.
      expect(find.text('9876543210'), findsOneWidget);
    });

    testWidgets('a plain Add School starts empty', (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _superAdmin)),
          ],
          child: const MaterialApp(home: Scaffold(body: AddSchoolDialog())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Greenfield High'), findsNothing);
    });
  });

  group('who sees the section', () {
    test('only a Super Admin', () {
      // Signups are platform business, same as onboarding and payments - a
      // school reading them would be reading its competitors' enquiries.
      final item = AppNav.findByPath('/early-access')!;

      expect(item.allows(UserRole.superAdmin), isTrue);
      for (final role in [
        UserRole.groupAdmin,
        UserRole.schoolAdmin,
        UserRole.hod,
        UserRole.teacher,
        UserRole.staff,
        UserRole.transportManager,
        UserRole.accountant,
      ]) {
        expect(item.allows(role), isFalse, reason: '${role.label} must not see early access requests');
      }
    });
  });
}
