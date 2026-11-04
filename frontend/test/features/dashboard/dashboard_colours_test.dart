import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_colors.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/theme/chart_palette.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/analytics/presentation/widgets/trend_bar_chart.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/dashboard/data/dashboard_repository.dart';
import 'package:edutrack_app/features/dashboard/data/models/dashboard.dart';
import 'package:edutrack_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_analytics_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_dashboard_repository.dart';
import '../../support/fake_school_repository.dart';

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);

/// A school's dashboard with every tone and all three rings.
const _colourful = Dashboard(
  role: 'SCHOOL_ADMIN',
  asOf: '2026-11-04',
  isWorkingDay: true,
  holiday: null,
  schoolId: 1,
  cards: [
    DashboardCard(key: 'students', label: 'Students', value: '842', hint: 'on the roll', tone: 'neutral'),
    DashboardCard(key: 'staff', label: 'Teachers & staff', value: '68', hint: 'on the payroll', tone: 'neutral'),
    DashboardCard(key: 'attendance', label: 'Attendance today', value: '82%', hint: 'present', tone: 'caution'),
    DashboardCard(key: 'fees_overdue', label: 'Students overdue', value: '4', hint: 'past due', tone: 'warning'),
    DashboardCard(key: 'performance', label: 'Results', value: '71%', hint: '30 students', tone: 'ok'),
  ],
  attendanceTrend: [
    TrendPoint(date: '2026-11-02', label: 'Nov 02', attendanceRate: 95),
    TrendPoint(date: '2026-11-03', label: 'Nov 03', attendanceRate: 82),
    TrendPoint(date: '2026-11-04', label: 'Nov 04', attendanceRate: 60),
  ],
  attention: [],
  breakdowns: [
    DashboardBreakdown(
      key: 'student_attendance_today',
      title: 'Students today',
      headline: '82%',
      caption: 'present of 100 marked',
      segments: [
        BreakdownSegment(key: 'present', label: 'Present', value: 82, display: '82'),
        BreakdownSegment(key: 'absent', label: 'Absent', value: 12, display: '12'),
        BreakdownSegment(key: 'leave', label: 'On leave', value: 6, display: '6'),
        BreakdownSegment(key: 'not_marked', label: 'Not marked yet', value: 0, display: '0'),
      ],
    ),
    DashboardBreakdown(
      key: 'fee_collection',
      title: 'Fees collected',
      headline: '75%',
      caption: 'of INR 4,000.00 fallen due',
      segments: [
        BreakdownSegment(key: 'collected', label: 'Collected', value: 3000, display: 'INR 3,000.00'),
        BreakdownSegment(key: 'outstanding', label: 'Still owed', value: 1000, display: 'INR 1,000.00'),
      ],
    ),
  ],
);

Widget wrap(Dashboard dashboard, {ThemeData? theme}) {
  return ProviderScope(
    overrides: [
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository(dashboard: dashboard)),
      analyticsRepositoryProvider.overrideWithValue(FakeAnalyticsRepository()),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: const Scaffold(body: DashboardScreen()),
    ),
  );
}

Future<void> pump(WidgetTester tester, Dashboard dashboard, {ThemeData? theme}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(wrap(dashboard, theme: theme));
  await tester.pumpAndSettle();
}

/// The colour a card's value is drawn in.
Color _valueColour(WidgetTester tester, String key, String value) => tester
    .widget<Text>(find.descendant(of: find.byKey(Key('stat-card-$key')), matching: find.text(value)))
    .style!
    .color!;

/// The colourful dashboard (decided 2026-11-04): a colour per figure, colour
/// by meaning for anything that is good or bad, and rings for today's split.
void main() {
  group('the number cards', () {
    testWidgets('each figure has its own colour', (tester) async {
      await pump(tester, _colourful);

      final students = tester.widget<Card>(find.byKey(const Key('stat-card-students')));
      final staff = tester.widget<Card>(find.byKey(const Key('stat-card-staff')));

      expect(students.color, ChartPalette.blue.lightSoft);
      expect(staff.color, ChartPalette.violet.lightSoft);
      expect(students.color, isNot(staff.color));
    });

    testWidgets('a value is green, amber or red by what it means, and a plain count stays plain', (tester) async {
      await pump(tester, _colourful);

      expect(_valueColour(tester, 'attendance', '82%'), AppColors.light.warning);
      expect(_valueColour(tester, 'fees_overdue', '4'), AppColors.light.danger);
      expect(_valueColour(tester, 'performance', '71%'), AppColors.light.success);
      expect(
        _valueColour(tester, 'students', '842'),
        isNot(anyOf(AppColors.light.success, AppColors.light.warning, AppColors.light.danger)),
      );
    });

    testWidgets('a card the palette does not know is still coloured', (tester) async {
      expect(ChartPalette.hueFor('something_new'), isA<ChartHue>());
      expect(ChartPalette.iconFor('something_new'), Icons.insights_outlined);
    });

    testWidgets('they take the dark shades in the dark theme', (tester) async {
      await pump(tester, _colourful, theme: AppTheme.dark());

      expect(tester.widget<Card>(find.byKey(const Key('stat-card-students'))).color, ChartPalette.blue.darkSoft);
      expect(tester.takeException(), isNull);
    });
  });

  group('the rings', () {
    testWidgets('show the headline, and each part with its share', (tester) async {
      await pump(tester, _colourful);

      expect(find.text('Students today'), findsOneWidget);
      expect(find.byKey(const Key('ring-headline-student_attendance_today')), findsOneWidget);
      expect(find.text('present of 100 marked'), findsOneWidget);
      expect(find.text('Not marked yet'), findsOneWidget);
      expect(find.text('12%'), findsOneWidget, reason: 'Absent, 12 of 100');
    });

    testWidgets('fees are shown in the school currency', (tester) async {
      await pump(tester, _colourful);

      expect(find.byKey(const Key('ring-headline-fee_collection')), findsOneWidget);
      expect(find.text('INR 3,000.00'), findsOneWidget);
      expect(find.text('INR 1,000.00'), findsOneWidget);
      expect(find.text('of INR 4,000.00 fallen due'), findsOneWidget);
    });

    testWidgets('a day with nothing counted draws an empty ring, not a crash', (tester) async {
      await pump(
        tester,
        const Dashboard(
          role: 'SCHOOL_ADMIN',
          asOf: '2026-11-04',
          isWorkingDay: true,
          holiday: null,
          schoolId: 1,
          cards: [],
          attendanceTrend: [],
          attention: [],
          breakdowns: [
            DashboardBreakdown(
              key: 'staff_attendance_today',
              title: 'Staff today',
              headline: '-',
              caption: 'no one marked yet',
              segments: [BreakdownSegment(key: 'not_marked', label: 'Not marked yet', value: 0, display: '0')],
            ),
          ],
        ),
      );

      expect(find.text('Staff today'), findsOneWidget);
      expect(find.text('no one marked yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a dashboard without them shows none', (tester) async {
      await pump(tester, defaultDashboard);

      expect(find.text('Students today'), findsNothing);
      expect(find.byKey(const Key('ring-headline-fee_collection')), findsNothing);
    });

    test('they are read from the server', () {
      final dashboard = Dashboard.fromJson({
        'role': 'SCHOOL_ADMIN',
        'as_of': '2026-11-04',
        'cards': [],
        'breakdowns': [
          {
            'key': 'fee_collection',
            'title': 'Fees collected',
            'headline': '75%',
            'caption': 'of INR 4,000.00 fallen due',
            'segments': [
              {'key': 'collected', 'label': 'Collected', 'value': 3000.0, 'display': 'INR 3,000.00'},
              {'key': 'outstanding', 'label': 'Still owed', 'value': 1000, 'display': 'INR 1,000.00'},
            ],
          },
        ],
      });

      expect(dashboard.breakdowns.single.total, 4000);
      expect(Dashboard.fromJson({'role': 'TEACHER', 'as_of': '2026-11-04'}).breakdowns, isEmpty);
    });
  });

  group('attendance bars', () {
    test('fall into bands at 90 and 75', () {
      expect(
        [
          for (final rate in [100.0, 90, 89.9, 75, 74.9]) AttendanceBands.of(rate.toDouble()),
        ],
        [AttendanceBand.good, AttendanceBand.good, AttendanceBand.fair, AttendanceBand.fair, AttendanceBand.poor],
      );
    });

    testWidgets('are green, amber and red, with a key saying which is which', (tester) async {
      await pump(tester, _colourful);

      final colours = tester
          .widgetList<Container>(find.byType(Container))
          .map((box) => (box.decoration as BoxDecoration?)?.color)
          .toSet();

      expect(colours, containsAll([AppColors.light.success, AppColors.light.warning, AppColors.light.danger]));
      expect(find.text('90% and above'), findsOneWidget);
      expect(find.text('75-89%'), findsOneWidget);
      expect(find.text('Below 75%'), findsOneWidget);
    });

    testWidgets('a trend chart takes a colour per bar, and leaves gaps grey', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: TrendBarChart(
                maxValue: 100,
                colour: Colors.purple,
                colourOf: (value) => value > 50 ? Colors.green : Colors.red,
                bars: const [
                  TrendBar(label: 'Sep', value: 80, valueLabel: '80%'),
                  TrendBar(label: 'Oct', value: 20, valueLabel: '20%'),
                  TrendBar(label: 'Nov', value: null, valueLabel: '-'),
                ],
              ),
            ),
          ),
        ),
      );

      final colours = tester
          .widgetList<Container>(find.byType(Container))
          .map((box) => (box.decoration as BoxDecoration?)?.color)
          .whereType<Color>()
          .toList();

      expect(colours, containsAll([Colors.green, Colors.red]));
      expect(colours, isNot(contains(Colors.purple)), reason: 'the per-bar colour wins');
    });
  });
}
