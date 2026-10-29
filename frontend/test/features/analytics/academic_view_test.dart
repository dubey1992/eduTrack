import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/analytics/data/models/academic_overview.dart';
import 'package:edutrack_app/features/analytics/presentation/analytics_screen.dart';
import 'package:edutrack_app/features/analytics/presentation/widgets/academic_view.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_analytics_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);
const _accountant = AuthenticatedUser(id: 9, name: 'Sam', email: 'sam@example.com', role: UserRole.accountant);

Widget _wrap(FakeAnalyticsRepository fake, Widget child, {AuthenticatedUser actor = _admin}) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      analyticsRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );
}

Widget _view(FakeAnalyticsRepository fake) =>
    _wrap(fake, const SingleChildScrollView(child: AcademicView(schoolId: null)));

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Map<String, dynamic> _withNothing({List<dynamic>? terms}) => {
  ...fakeAcademicJson(terms: terms),
  'subjects': <dynamic>[],
  'classes': <dynamic>[],
  'cells': <dynamic>[],
};

void main() {
  test('a term with no result is null, and the change is between the last two that have one', () {
    final overview = AcademicOverview.fromJson(fakeAcademicJson());

    final maths = overview.subjects.firstWhere((line) => line.label == 'Maths');
    final physics = overview.subjects.firstWhere((line) => line.label == 'Physics');

    expect(maths.terms.last, isNull);
    expect(maths.lastChange, isNull);
    expect(physics.lastChange, (50.0, 75.0));
    expect(physics.detail, 'Science');
    expect(overview.cells.single.detail, 'Physics');
    expect((overview.passMark, overview.weakBelow), (33.0, 40.0));
    expect(overview.terms.last.inProgress, isTrue);
  });

  group('the view', () {
    testWidgets('subjects, classes and each class by subject, term by term', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_view(FakeAnalyticsRepository()));
      await tester.pumpAndSettle();

      expect(find.text('By subject'), findsOneWidget);
      expect(find.text('By class'), findsOneWidget);
      expect(find.text('Each class, by subject'), findsOneWidget);
      // The term still going is marked as such, in each table.
      expect(find.text('Term 2 (so far)'), findsNWidgets(3));
      // Physics fell 25 points, in the subject table and its class's row.
      expect(find.text('25 pts'), findsNWidgets(2));
      expect(find.text('52.5%'), findsOneWidget);
      // Students under the weak line in the latest term.
      expect(find.text('9 of 30'), findsOneWidget);
      // The lines the colours stand for, said.
      expect(find.textContaining('under the 33% pass mark'), findsOneWidget);
    });

    testWidgets('choosing another year asks for it', (tester) async {
      _wide(tester);
      final fake = FakeAnalyticsRepository();
      await tester.pumpWidget(_view(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2026-27 (current)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025-26').last);
      await tester.pumpAndSettle();

      expect(fake.academicAsked.last.academicYearId, 1);
    });

    testWidgets('a year with no terms set up says where to add them', (tester) async {
      _wide(tester);
      await tester.pumpWidget(
        _view(
          FakeAnalyticsRepository(
            academicJson: {
              ..._withNothing(terms: []),
              'terms_set_up': 0,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('This year has no terms yet.'), findsOneWidget);
    });

    testWidgets('a year with no term begun says so', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_view(FakeAnalyticsRepository(academicJson: _withNothing(terms: []))));
      await tester.pumpAndSettle();

      expect(find.text('No term of this year has begun yet.'), findsOneWidget);
    });

    testWidgets('a year with no results yet says so', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_view(FakeAnalyticsRepository(academicJson: _withNothing())));
      await tester.pumpAndSettle();

      expect(find.text('No class test results have been published this year yet.'), findsOneWidget);
    });

    testWidgets("a refusal shows the server's message", (tester) async {
      _wide(tester);
      final fake = FakeAnalyticsRepository(
        failure: const Failure(code: 'MODULE_DISABLED', message: 'Class Tests & Assessments is switched off.'),
      );
      await tester.pumpWidget(_view(fake));
      await tester.pumpAndSettle();

      expect(find.text('Class Tests & Assessments is switched off.'), findsOneWidget);
    });
  });

  group('on the Analytics page', () {
    testWidgets('an admin switches to subjects and classes', (tester) async {
      _wide(tester);
      final fake = FakeAnalyticsRepository();
      await tester.pumpWidget(_wrap(fake, const AnalyticsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Subjects & classes'));
      await tester.pumpAndSettle();

      expect(fake.academicAsked, hasLength(1));
      expect(find.text('By subject'), findsOneWidget);
      // The trend controls belong to the other view.
      expect(find.text('By week'), findsNothing);
    });

    testWidgets('an accountant is not offered it', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_wrap(FakeAnalyticsRepository(), const AnalyticsScreen(), actor: _accountant));
      await tester.pumpAndSettle();

      expect(find.text('Subjects & classes'), findsNothing);
    });
  });
}
