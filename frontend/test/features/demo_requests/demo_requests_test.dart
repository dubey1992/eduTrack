import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/core/routing/app_nav.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/brand_loader.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/demo_requests/application/demo_request_notifier.dart';
import 'package:edutrack_app/features/demo_requests/data/demo_request_repository.dart';
import 'package:edutrack_app/features/demo_requests/data/models/demo_request.dart';
import 'package:edutrack_app/features/demo_requests/presentation/demo_request_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/paginated_table.dart';
import '../../support/session_users.dart';

DemoRequest _request({
  int id = 1,
  String schoolName = 'Greenfield High',
  DemoRequestStatus status = DemoRequestStatus.newRequest,
  String? city = 'Pune',
  int? expectedStudents = 850,
  String? preferredTimeLabel = 'Morning',
  String? timezone = 'Asia/Kolkata',
  String? notes,
}) {
  return DemoRequest(
    id: id,
    contactName: 'Priya Nair',
    schoolName: schoolName,
    email: 'priya@greenfield.test',
    phone: '+91 9876543210',
    city: city,
    country: 'India',
    expectedStudents: expectedStudents,
    preferredDate: '2026-11-05',
    preferredTime: preferredTimeLabel?.toLowerCase(),
    preferredTimeLabel: preferredTimeLabel,
    timezone: timezone,
    message: 'We would like to see attendance and fees.',
    status: status,
    notes: notes,
    submittedAt: '10/29/2026 10:30 AM',
  );
}

class _FakeDemoRequestRepository implements DemoRequestRepository {
  _FakeDemoRequestRepository({
    List<DemoRequest>? requests,
    this.failListWith,
    this.failReviewWith,
    this.pending,
    this.lastPage = 1,
  }) : _requests = requests ?? [_request()];

  final List<DemoRequest> _requests;
  final Failure? failListWith;
  final Failure? failReviewWith;

  /// When given, the list waits on it - for looking at the loading state.
  final Completer<void>? pending;

  /// More than one page makes the pagination bar's arrows live.
  final int lastPage;

  final listed = <({String? status, String? query, int page, int perPage})>[];
  int? reviewedId;
  String? reviewedStatus;
  String? reviewedNotes;

  @override
  Future<String> submit(Map<String, dynamic> payload) async => 'Thanks - we will be in touch.';

  @override
  Future<PaginatedResponse<DemoRequest>> list({String? status, String? query, int page = 1, int perPage = 20}) async {
    listed.add((status: status, query: query, page: page, perPage: perPage));
    if (pending != null) await pending!.future;
    if (failListWith != null) throw failListWith!;

    return PaginatedResponse(
      items: _requests,
      currentPage: page,
      lastPage: lastPage,
      total: lastPage == 1 ? _requests.length : lastPage * perPage,
      perPage: perPage,
    );
  }

  @override
  Future<DemoRequest> review(int id, {String? status, String? notes}) async {
    if (failReviewWith != null) throw failReviewWith!;
    reviewedId = id;
    reviewedStatus = status;
    reviewedNotes = notes;

    return _request(id: id, status: DemoRequestStatus.fromApiValue(status ?? 'new'), notes: notes);
  }
}

const _superAdmin = AuthenticatedUser(
  id: 1,
  name: 'Super Admin',
  email: 'admin@example.com',
  role: UserRole.superAdmin,
);

Map<String, dynamic> _json({Map<String, dynamic> overrides = const {}}) {
  return {
    'id': 7,
    'contact_name': 'Priya Nair',
    'school_name': 'Greenfield High',
    'email': 'priya@greenfield.test',
    'phone': '+91 9876543210',
    'city': 'Pune',
    'country': 'India',
    'expected_students': 850,
    'preferred_date': '2026-11-05',
    'preferred_time': 'morning',
    'preferred_time_label': 'Morning',
    'timezone': 'Asia/Kolkata',
    'message': 'Hello',
    'status': 'scheduled',
    'status_label': 'Scheduled',
    'notes': 'Call on Tuesday',
    'reviewed_by_name': 'Super Admin',
    'reviewed_at': '10/29/2026 11:00 AM',
    'submitted_at': '10/29/2026 10:30 AM',
    ...overrides,
  };
}

void main() {
  group('the model', () {
    test('reads every field the API sends', () {
      final request = DemoRequest.fromJson(_json());

      expect(request.id, 7);
      expect(request.schoolName, 'Greenfield High');
      expect(request.expectedStudents, 850);
      expect(request.status, DemoRequestStatus.scheduled);
      expect(request.notes, 'Call on Tuesday');
      expect(request.reviewedByName, 'Super Admin');
      expect(request.location, 'Pune, India');
      // US order, then the part of day and the timezone it was picked in.
      expect(request.preferredSlot, '11/05/2026 · Morning · Asia/Kolkata');
      expect(request.preferredDateLabel, '11/05/2026');
      expect(request.preferredTimeOfDay, 'Morning · Asia/Kolkata');
    });

    test('copes with everything optional left out', () {
      final request = DemoRequest.fromJson(
        _json(
          overrides: {
            'city': null,
            'expected_students': null,
            'preferred_time': null,
            'preferred_time_label': null,
            'timezone': null,
            'message': null,
            'notes': null,
            'reviewed_by_name': null,
            'reviewed_at': null,
          },
        ),
      );

      expect(request.city, isNull);
      expect(request.expectedStudents, isNull);
      expect(request.message, isNull);
      expect(request.reviewedAt, isNull);
      expect(request.location, 'India');
      expect(request.preferredSlot, '11/05/2026');
      expect(request.preferredTimeOfDay, isEmpty);
    });

    test('knows every status, and which are still open', () {
      for (final (value, status) in [
        ('new', DemoRequestStatus.newRequest),
        ('scheduled', DemoRequestStatus.scheduled),
        ('done', DemoRequestStatus.done),
        ('declined', DemoRequestStatus.declined),
      ]) {
        expect(DemoRequestStatus.fromApiValue(value), status);
      }
      expect(DemoRequestStatus.newRequest.isOpen, isTrue);
      expect(DemoRequestStatus.scheduled.isOpen, isTrue);
      expect(DemoRequestStatus.done.isOpen, isFalse);
      expect(DemoRequestStatus.declined.isOpen, isFalse);
    });
  });

  group('the notifier', () {
    late _FakeDemoRequestRepository fake;
    late ProviderContainer container;

    setUp(() {
      fake = _FakeDemoRequestRepository(
        requests: [
          _request(),
          _request(id: 2, schoolName: 'Riverside'),
        ],
      );
      container = ProviderContainer(overrides: [demoRequestRepositoryProvider.overrideWithValue(fake)]);
      addTearDown(container.dispose);
    });

    test('starts on the first page with no filter', () async {
      await container.read(demoRequestNotifierProvider.future);

      expect(fake.listed.single, (status: null, query: '', page: 1, perPage: 20));
    });

    test('a status filter starts again from page one', () async {
      final notifier = container.read(demoRequestNotifierProvider.notifier);
      await container.read(demoRequestNotifierProvider.future);
      await notifier.goToPage(3);

      await notifier.setStatus(DemoRequestStatus.scheduled);

      expect(fake.listed.last, (status: 'scheduled', query: '', page: 1, perPage: 20));
      expect(notifier.status, DemoRequestStatus.scheduled);
    });

    test('a search keeps the filter and starts from page one', () async {
      final notifier = container.read(demoRequestNotifierProvider.notifier);
      await container.read(demoRequestNotifierProvider.future);
      await notifier.setStatus(DemoRequestStatus.newRequest);
      await notifier.goToPage(2);

      await notifier.search('green');

      expect(fake.listed.last, (status: 'new', query: 'green', page: 1, perPage: 20));
    });

    test('pages and page sizes reach the server', () async {
      final notifier = container.read(demoRequestNotifierProvider.notifier);
      await container.read(demoRequestNotifierProvider.future);

      await notifier.goToPage(2);
      expect(fake.listed.last.page, 2);

      await notifier.setPerPage(50);
      expect(fake.listed.last, (status: null, query: '', page: 1, perPage: 50));
    });

    test('a review updates that row in place without re-fetching', () async {
      final notifier = container.read(demoRequestNotifierProvider.notifier);
      final before = await container.read(demoRequestNotifierProvider.future);
      final fetches = fake.listed.length;

      await notifier.review(before.items.first, status: 'done', notes: 'Went well.');

      final after = container.read(demoRequestNotifierProvider).value!;
      expect(fake.listed.length, fetches);
      expect(after.items.first.status, DemoRequestStatus.done);
      expect(after.items.first.notes, 'Went well.');
      // The other row is left alone.
      expect(after.items.last.schoolName, 'Riverside');
    });

    test('a failed review is passed on to the caller, list unchanged', () async {
      final failing = _FakeDemoRequestRepository(
        failReviewWith: const Failure(code: 'VALIDATION_ERROR', message: 'Notes are too long.'),
      );
      final c = ProviderContainer(overrides: [demoRequestRepositoryProvider.overrideWithValue(failing)]);
      addTearDown(c.dispose);
      final before = await c.read(demoRequestNotifierProvider.future);

      await expectLater(
        c.read(demoRequestNotifierProvider.notifier).review(before.items.first, status: 'done'),
        throwsA(isA<Failure>()),
      );
      expect(c.read(demoRequestNotifierProvider).value!.items.first.status, DemoRequestStatus.newRequest);
    });
  });

  group('the Super Admin panel', () {
    Widget wrap(_FakeDemoRequestRepository fake) {
      return ProviderScope(
        overrides: [
          demoRequestRepositoryProvider.overrideWithValue(fake),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _superAdmin)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: DemoRequestScreen()),
        ),
      );
    }

    // Wide enough that the whole table, View included, is on screen; a
    // narrower window scrolls the table sideways rather than squashing it.
    Future<void> pump(
      WidgetTester tester,
      _FakeDemoRequestRepository fake, {
      Size size = const Size(1600, 1000),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
    }

    Future<void> openFirst(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(TextButton, 'View'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a spinner while the list loads', (tester) async {
      final pending = Completer<void>();
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(_FakeDemoRequestRepository(pending: pending)));
      await tester.pump();

      expect(find.byType(BrandLoader), findsOneWidget);

      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Greenfield High\nPune, India'), findsOneWidget);
    });

    testWidgets('leads each row with when they want the demo', (tester) async {
      await pump(tester, _FakeDemoRequestRepository());

      // The date first, the part of day and timezone under it.
      expect(find.text('11/05/2026\nMorning · Asia/Kolkata'), findsOneWidget);
      expect(find.text('Greenfield High\nPune, India'), findsOneWidget);
      expect(find.text('850'), findsOneWidget);
      expect(find.text('New'), findsWidgets);
    });

    testWidgets('the date alone when no part of day or timezone came with it', (tester) async {
      await pump(
        tester,
        _FakeDemoRequestRepository(
          requests: [_request(preferredTimeLabel: null, timezone: null, city: null, expectedStudents: null)],
        ),
      );

      expect(find.text('11/05/2026'), findsOneWidget);
      expect(find.text('Greenfield High\nIndia'), findsOneWidget);
      // Not knowing is different from none.
      expect(find.text('-'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('shows each status with its own badge', (tester) async {
      await pump(
        tester,
        _FakeDemoRequestRepository(
          requests: [for (final (n, status) in DemoRequestStatus.values.indexed) _request(id: n + 1, status: status)],
        ),
      );

      for (final label in ['Scheduled', 'Done', 'Declined']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    testWidgets('lays requests out as cards on a phone', (tester) async {
      await pump(tester, _FakeDemoRequestRepository(), size: const Size(400, 900));

      expect(find.byType(DataTable), findsNothing);
      expect(find.byType(Card), findsOneWidget);
      expect(find.textContaining('11/05/2026 · Morning · Asia/Kolkata'), findsOneWidget);
    });

    testWidgets('says so plainly when nobody has asked yet', (tester) async {
      await pump(tester, _FakeDemoRequestRepository(requests: []));

      expect(find.text('No schools have asked for a demo yet.'), findsOneWidget);
    });

    testWidgets('an error offers a retry that fetches again', (tester) async {
      final fake = _FakeDemoRequestRepository(failListWith: Failure.network());
      await pump(tester, fake);

      expect(find.text(Failure.network().message), findsOneWidget);
      final fetches = fake.listed.length;

      await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(fake.listed.length, fetches + 1);
    });

    testWidgets('the status filter asks the server for just that status', (tester) async {
      final fake = _FakeDemoRequestRepository();
      await pump(tester, fake);

      await tester.tap(find.byType(DropdownButtonFormField<DemoRequestStatus?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scheduled').hitTestable().last);
      await tester.pumpAndSettle();

      expect(fake.listed.last.status, 'scheduled');
      expect(fake.listed.last.page, 1);
    });

    testWidgets('search runs on submit, trimmed', (tester) async {
      final fake = _FakeDemoRequestRepository();
      await pump(tester, fake);

      await tester.enterText(find.widgetWithText(TextField, 'Search school, contact or email'), '  green  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(fake.listed.last.query, 'green');
    });

    testWidgets('the pagination bar moves between pages', (tester) async {
      final fake = _FakeDemoRequestRepository(lastPage: 3);
      await pump(tester, fake);

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();

      expect(fake.listed.last.page, 2);
    });

    testWidgets('opens the whole request', (tester) async {
      await pump(tester, _FakeDemoRequestRepository());
      await openFirst(tester);

      expect(find.text('priya@greenfield.test'), findsOneWidget);
      expect(find.text('+91 9876543210'), findsOneWidget);
      expect(find.text('We would like to see attendance and fees.'), findsOneWidget);
      expect(find.text('11/05/2026 · Morning · Asia/Kolkata'), findsOneWidget);
    });

    testWidgets('offers every status, Done included', (tester) async {
      // Unlike early access, nothing here is set by the system.
      await pump(tester, _FakeDemoRequestRepository());
      await openFirst(tester);

      await tester.tap(find.byType(DropdownButtonFormField<DemoRequestStatus>));
      await tester.pumpAndSettle();

      for (final status in DemoRequestStatus.values) {
        expect(find.text(status.label).hitTestable(), findsWidgets, reason: status.label);
      }
    });

    testWidgets('schedules a request with a note, and says so', (tester) async {
      final fake = _FakeDemoRequestRepository();
      await pump(tester, fake);
      await openFirst(tester);

      await tester.tap(find.byType(DropdownButtonFormField<DemoRequestStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scheduled').hitTestable().last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Notes'), '  Zoom on Thursday 10am.  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(fake.reviewedId, 1);
      expect(fake.reviewedStatus, 'scheduled');
      expect(fake.reviewedNotes, 'Zoom on Thursday 10am.');
      expect(find.text('Request updated.'), findsOneWidget);
      // The dialog has closed and the row shows the new status.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Scheduled'), findsWidgets);
    });

    testWidgets('saves notes alone, keeping the status', (tester) async {
      final fake = _FakeDemoRequestRepository();
      await pump(tester, fake);
      await openFirst(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Notes'), 'Left a voicemail.');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(fake.reviewedStatus, 'new');
      expect(fake.reviewedNotes, 'Left a voicemail.');
    });

    testWidgets('starts from the notes already kept', (tester) async {
      await pump(tester, _FakeDemoRequestRepository(requests: [_request(notes: 'Prefers WhatsApp.')]));
      await openFirst(tester);

      expect(find.widgetWithText(TextField, 'Prefers WhatsApp.'), findsOneWidget);
    });

    testWidgets('shows the server\'s refusal and keeps the dialog open', (tester) async {
      final fake = _FakeDemoRequestRepository(
        failReviewWith: const Failure(
          code: 'VALIDATION_ERROR',
          message: 'Notes may not be longer than 2000 characters.',
        ),
      );
      await pump(tester, fake);
      await openFirst(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Notes'), 'Too long');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Notes may not be longer than 2000 characters.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      // Nothing retyped, and Save is usable again.
      expect(find.text('Too long'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNotNull);
    });

    testWidgets('Close leaves without saving', (tester) async {
      final fake = _FakeDemoRequestRepository();
      await pump(tester, fake);
      await openFirst(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(fake.reviewedId, isNull);
    });

    testWidgets('a full page of requests scrolls above the pagination bar on desktop', (tester) async {
      useShortDesktopWindow(tester);
      final requests = [for (var n = 1; n <= 20; n++) _request(id: n, schoolName: 'School $n')];
      await tester.pumpWidget(wrap(_FakeDemoRequestRepository(requests: requests)));
      await tester.pumpAndSettle();

      await expectLastRowScrollsAbovePagination(tester, find.textContaining('School 20'));
    });
  });

  group('who sees the section', () {
    test('only a Super Admin', () {
      // Demo requests are platform business, same as early access - a school
      // reading them would be reading its competitors' enquiries.
      final item = AppNav.findByPath('/demo-requests')!;

      expect(item.label, 'Demo Requests');
      expect(item.allows(sessionUser(UserRole.superAdmin)), isTrue);
      for (final role in [
        UserRole.groupAdmin,
        UserRole.schoolAdmin,
        UserRole.hod,
        UserRole.teacher,
        UserRole.staff,
        UserRole.transportManager,
        UserRole.accountant,
        UserRole.driver,
        UserRole.busAttendant,
      ]) {
        expect(item.allows(sessionUser(role)), isFalse, reason: '${role.label} must not see demo requests');
      }
    });

    test('sits right after Early Access', () {
      final paths = AppNav.administration.items.map((item) => item.path).toList();

      expect(paths.indexOf('/demo-requests'), paths.indexOf('/early-access') + 1);
    });
  });
}
