import 'package:dio/dio.dart';
import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/currency_formatter.dart';
import 'package:edutrack_app/features/analytics/data/analytics_api.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/analytics/data/models/analytics_series.dart';
import 'package:edutrack_app/features/analytics/presentation/analytics_screen.dart';
import 'package:edutrack_app/features/analytics/presentation/series_line.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);
const _groupAdmin = AuthenticatedUser(
  id: 3,
  name: 'Group',
  email: 'group@example.com',
  role: UserRole.groupAdmin,
  managesBranches: true,
);
const _root = AuthenticatedUser(id: 1, name: 'Root', email: 'root@example.com', role: UserRole.superAdmin);

const _measures = [
  AnalyticsMeasure(
    key: 'student_attendance_rate',
    label: 'Student attendance',
    unit: AnalyticsUnit.percent,
    snapshot: false,
  ),
  AnalyticsMeasure(key: 'fees_collected', label: 'Fees collected', unit: AnalyticsUnit.money, snapshot: false),
  AnalyticsMeasure(key: 'active_students', label: 'Students on roll', unit: AnalyticsUnit.count, snapshot: true),
];

AnalyticsSeries _attendance() => AnalyticsSeries.fromJson({
  'measure': 'student_attendance_rate',
  'label': 'Student attendance',
  'unit': 'percent',
  'interval': 'month',
  'from': '2026-07-01',
  'to': '2026-09-14',
  'points': [
    {'from': '2026-07-01', 'to': '2026-07-31', 'working_days': 23, 'value': 91.5},
    {'from': '2026-08-01', 'to': '2026-08-31', 'working_days': 0, 'value': null},
    {'from': '2026-09-01', 'to': '2026-09-14', 'working_days': 10, 'value': 88},
  ],
});

AnalyticsSeries _collected() => AnalyticsSeries.fromJson({
  'measure': 'fees_collected',
  'label': 'Fees collected',
  'unit': 'money',
  'interval': 'month',
  'from': '2026-06-01',
  'to': '2026-07-15',
  'points': [
    {
      'from': '2026-06-01',
      'to': '2026-06-30',
      'working_days': 22,
      'amounts': [
        {'currency_code': 'INR', 'amount': '1000.00'},
      ],
    },
    {
      'from': '2026-07-01',
      'to': '2026-07-15',
      'working_days': 11,
      'amounts': [
        {'currency_code': 'INR', 'amount': '400.00'},
        {'currency_code': 'USD', 'amount': '10.00'},
      ],
    },
  ],
});

AnalyticsSeries _noRecordingsYet() => AnalyticsSeries.fromJson({
  'measure': 'active_students',
  'label': 'Students on roll',
  'unit': 'count',
  'interval': 'month',
  'from': '2026-09-01',
  'to': '2026-09-14',
  'points': [
    {'from': '2026-09-01', 'to': '2026-09-14', 'working_days': 10, 'value': null},
  ],
});

AnalyticsSeries _neverTaken() => AnalyticsSeries.fromJson({
  'measure': 'staff_attendance_rate',
  'label': 'Staff attendance',
  'unit': 'percent',
  'interval': 'month',
  'from': '2026-09-01',
  'to': '2026-09-14',
  'points': [
    {'from': '2026-09-01', 'to': '2026-09-14', 'working_days': 10, 'value': null},
  ],
});

class _FakeAnalyticsRepository extends AnalyticsRepository {
  _FakeAnalyticsRepository({this.measureList = _measures, this.failure}) : super(AnalyticsApi(Dio()));

  final List<AnalyticsMeasure> measureList;
  final Failure? failure;
  final asked = <({String measure, AnalyticsInterval interval, int? schoolId})>[];

  @override
  Future<List<AnalyticsMeasure>> measures() async => measureList;

  @override
  Future<AnalyticsSeries> series(
    String measure, {
    AnalyticsInterval interval = AnalyticsInterval.month,
    int? schoolId,
    String? from,
    String? to,
    int? classSectionId,
    int? departmentId,
  }) async {
    asked.add((measure: measure, interval: interval, schoolId: schoolId));
    if (failure != null) throw failure!;

    return switch (measure) {
      'fees_collected' => _collected(),
      'active_students' => _noRecordingsYet(),
      'staff_attendance_rate' => _neverTaken(),
      _ => _attendance(),
    };
  }
}

Widget _wrap(_FakeAnalyticsRepository fake, {AuthenticatedUser actor = _admin}) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      analyticsRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AnalyticsScreen()),
    ),
  );
}

void _useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('charts the first measure, with a gap drawn as a dash and never as 0%', (tester) async {
    _useDesktop(tester);
    final fake = _FakeAnalyticsRepository();
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    expect(fake.asked.single, (measure: 'student_attendance_rate', interval: AnalyticsInterval.month, schoolId: null));
    expect(find.text('Jul 2026'), findsWidgets);
    expect(find.text('91.5%'), findsWidgets);
    expect(find.text('88%'), findsWidgets);
    // August had no working day: a dash, explained, and certainly not 0%.
    expect(find.text('0%'), findsNothing);
    expect(find.textContaining('A dash is a period with no figure'), findsOneWidget);
    // Latest against the last period that had a figure, in points.
    expect(find.text('-3.5 pts'), findsOneWidget);
    // A rate is not added up into a total.
    expect(find.text('Total in range'), findsNothing);
  });

  testWidgets('money is one chart per currency, never added together', (tester) async {
    _useDesktop(tester);
    await tester.pumpWidget(_wrap(_FakeAnalyticsRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Fees collected'));
    await tester.pumpAndSettle();

    expect(find.text('Fees collected (INR)'), findsOneWidget);
    expect(find.text('Fees collected (USD)'), findsOneWidget);
    // A flow adds up over the range - within its own currency.
    expect(find.text('Total in range'), findsNWidgets(2));
    expect(find.text(formatCurrency(1400, 'INR')), findsOneWidget);
    // June had no dollars: nought, since it was recorded.
    expect(find.text(formatCurrency(0, 'USD')), findsWidgets);
  });

  testWidgets('a figure not recorded yet says when it starts rather than drawing nothing', (tester) async {
    _useDesktop(tester);
    await tester.pumpWidget(_wrap(_FakeAnalyticsRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Students on roll'));
    await tester.pumpAndSettle();

    expect(find.textContaining('recorded once a day'), findsOneWidget);
  });

  testWidgets('a school that ran but took no attendance is told so, not shown 0%', (tester) async {
    _useDesktop(tester);
    await tester.pumpWidget(
      _wrap(
        _FakeAnalyticsRepository(
          measureList: const [
            AnalyticsMeasure(
              key: 'staff_attendance_rate',
              label: 'Staff attendance',
              unit: AnalyticsUnit.percent,
              snapshot: false,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('The school ran, but no staff attendance was recorded.'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('opens on the measure a dashboard card asked for', (tester) async {
    _useDesktop(tester);
    final fake = _FakeAnalyticsRepository();
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [
          analyticsRepositoryProvider.overrideWithValue(fake),
          schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AnalyticsScreen(initialMeasure: 'fees_collected')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fake.asked.single.measure, 'fees_collected');
    expect(find.text('Fees collected (INR)'), findsOneWidget);
  });

  testWidgets('by week asks the server for weeks', (tester) async {
    _useDesktop(tester);
    final fake = _FakeAnalyticsRepository();
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Last 12 months'), findsOneWidget);
    await tester.tap(find.text('By week'));
    await tester.pumpAndSettle();

    expect(fake.asked.last.interval, AnalyticsInterval.week);
    expect(find.text('Last 12 weeks'), findsOneWidget);
  });

  testWidgets('a role with nothing to chart is told so', (tester) async {
    _useDesktop(tester);
    await tester.pumpWidget(_wrap(_FakeAnalyticsRepository(measureList: const [])));
    await tester.pumpAndSettle();

    expect(find.text('There are no charts for your role yet.'), findsOneWidget);
  });

  testWidgets("a refusal shows the server's message with a retry", (tester) async {
    _useDesktop(tester);
    final fake = _FakeAnalyticsRepository(
      failure: const Failure(code: 'VALIDATION_ERROR', message: 'A chart by month covers at most 24 months.'),
    );
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('A chart by month covers at most 24 months.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(fake.asked, hasLength(2));
  });

  testWidgets('a Super Admin picks a school before anything is asked', (tester) async {
    _useDesktop(tester);
    final fake = _FakeAnalyticsRepository();
    await tester.pumpWidget(_wrap(fake, actor: _root));
    await tester.pumpAndSettle();

    expect(find.text('Pick a school to see its charts.'), findsOneWidget);
    expect(fake.asked, isEmpty);
  });

  testWidgets('a group admin picks a branch, since the whole group is not charted yet', (tester) async {
    _useDesktop(tester);
    final fake = _FakeAnalyticsRepository();
    await tester.pumpWidget(_wrap(fake, actor: _groupAdmin));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pick a branch to see its charts.'), findsOneWidget);
    expect(fake.asked, isEmpty);
  });

  test('a period reads as its month, or as the Monday of its week', () {
    const cut = AnalyticsPoint(from: '2026-09-02', to: '2026-09-06', workingDays: 3, value: 50);

    expect(periodLabel(cut, AnalyticsInterval.month), 'Sep 2026');
    // A first week cut short at Wednesday the 2nd is still the week of the 31st.
    expect(periodLabel(cut, AnalyticsInterval.week), '08/31');
  });
}
