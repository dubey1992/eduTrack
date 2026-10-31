import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/setup_guide/data/setup_guide_repository.dart';
import 'package:edutrack_app/features/setup_guide/presentation/setup_guide_card.dart';
import 'package:edutrack_app/features/setup_guide/presentation/setup_guide_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_department_repository.dart';
import '../../support/fake_setup_guide_repository.dart';

/// A new school's setup guide (docs/onboarding.md, slice O4).

Widget wrap(FakeSetupGuideRepository fake, {String start = '/setup-guide'}) {
  final router = GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (context, state) =>
            const Scaffold(body: Column(children: [SetupGuideCard(), Text('Dashboard figures')])),
      ),
      GoRoute(
        path: '/setup-guide',
        builder: (context, state) => const Scaffold(body: SetupGuideScreen()),
      ),
      for (final path in [
        '/academic-years',
        '/departments',
        '/classes',
        '/subjects',
        '/staff',
        '/students',
        '/holidays',
      ])
        GoRoute(
          path: path,
          builder: (context, state) => Scaffold(body: Text('Screen $path')),
        ),
    ],
  );

  return ProviderScope(
    overrides: [
      setupGuideRepositoryProvider.overrideWithValue(fake),
      departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository()),
    ],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  );
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('the guide', () {
    testWidgets('lists the six steps in order with what is done and what comes first', (tester) async {
      _tall(tester);
      await tester.pumpWidget(wrap(FakeSetupGuideRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Set up Sunrise Public School'), findsOneWidget);
      final titles = ['Academic year', 'Departments', 'Classes & sections', 'Subjects', 'Teachers & staff', 'Students'];
      final tops = [for (final title in titles) tester.getTopLeft(find.text(title)).dy];
      expect(tops, [...tops]..sort());
      expect(find.text('Add the academic year first.'), findsOneWidget);
      // Quick setup waits until there is a year to put classes in.
      expect(find.text('Quick setup'), findsNothing);
    });

    testWidgets('a done step shows what the school has', (tester) async {
      _tall(tester);
      await tester.pumpWidget(wrap(FakeSetupGuideRepository(doneSteps: 2)));
      await tester.pumpAndSettle();

      expect(find.text('Academic year summary'), findsOneWidget);
      expect(find.textContaining('2 of 6 done'), findsOneWidget);
      expect(find.text('Quick setup'), findsOneWidget);
    });

    testWidgets('a step opens the screen where it is done', (tester) async {
      _tall(tester);
      await tester.pumpWidget(wrap(FakeSetupGuideRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Academic year'));
      await tester.pumpAndSettle();

      expect(find.text('Screen /academic-years'), findsOneWidget);
    });

    testWidgets('common departments are added in one step and the guide moves on', (tester) async {
      _tall(tester);
      final fake = FakeSetupGuideRepository(doneSteps: 1);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add common departments'));
      await tester.pumpAndSettle();
      expect(find.text('Add 2 departments'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'Arts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 3 departments'));
      await tester.pumpAndSettle();

      expect(fake.addedDepartments, ['Primary', 'Science', 'Arts']);
      expect(find.text('Added 3 departments.'), findsOneWidget);
      expect(find.textContaining('2 of 6 done'), findsOneWidget);
    });

    testWidgets('nothing ticked is refused before anything is sent', (tester) async {
      _tall(tester);
      final fake = FakeSetupGuideRepository(doneSteps: 1);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add common departments'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Primary'));
      await tester.tap(find.widgetWithText(FilterChip, 'Science'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add departments'));
      await tester.pumpAndSettle();

      expect(find.text('Tick at least one department.'), findsOneWidget);
      expect(fake.addedDepartments, isNull);
    });

    testWidgets('hiding asks first; confirmed, it is hidden for the school', (tester) async {
      _tall(tester);
      final fake = FakeSetupGuideRepository(doneSteps: 3);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('setup-guide-hide')));
      await tester.pumpAndSettle();
      expect(find.text('Hide the setup guide?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fake.calls, isNot(contains('close')));

      await tester.tap(find.byKey(const Key('setup-guide-hide')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Hide'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('close'));
      expect(find.byKey(const Key('setup-guide-reopen')), findsOneWidget);
    });

    testWidgets('a finished guide closes without asking', (tester) async {
      _tall(tester);
      final fake = FakeSetupGuideRepository(doneSteps: 6);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.text('Sunrise Public School is set up'), findsOneWidget);
      await tester.tap(find.text('Close the guide'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('close'));
    });

    testWidgets('a hidden guide can be put back on the dashboard', (tester) async {
      _tall(tester);
      final fake = FakeSetupGuideRepository(doneSteps: 2, closed: true);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('setup-guide-reopen')));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('reopen'));
      expect(find.byKey(const Key('setup-guide-hide')), findsOneWidget);
    });

    testWidgets('a failure to load offers a retry', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        wrap(
          FakeSetupGuideRepository(
            failWith: {'show': const Failure(code: 'SERVER_ERROR', message: 'Something went wrong.')},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('the dashboard card', () {
    testWidgets('shows progress and the next step', (tester) async {
      await tester.pumpWidget(wrap(FakeSetupGuideRepository(doneSteps: 2), start: '/dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('Set up your school'), findsOneWidget);
      expect(find.text('2 of 6 steps done. Next: Classes & sections.'), findsOneWidget);

      await tester.tap(find.text('Continue setup'));
      await tester.pumpAndSettle();
      expect(find.text('Set up Sunrise Public School'), findsOneWidget);
    });

    testWidgets('a brand-new school is taken to the guide, once', (tester) async {
      _tall(tester);
      await tester.pumpWidget(wrap(FakeSetupGuideRepository(), start: '/dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('Set up Sunrise Public School'), findsOneWidget);

      // Back to the dashboard: it stays there this time.
      final context = tester.element(find.byType(SetupGuideScreen));
      GoRouter.of(context).go('/dashboard');
      await tester.pumpAndSettle();
      expect(find.text('Dashboard figures'), findsOneWidget);
    });

    testWidgets('a hidden guide is not on the dashboard and does not open itself', (tester) async {
      await tester.pumpWidget(wrap(FakeSetupGuideRepository(closed: true), start: '/dashboard'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('setup-guide-card')), findsNothing);
      expect(find.text('Dashboard figures'), findsOneWidget);
    });

    testWidgets('a guide that cannot load leaves the dashboard as it is', (tester) async {
      await tester.pumpWidget(
        wrap(
          FakeSetupGuideRepository(
            failWith: {'show': const Failure(code: 'SERVER_ERROR', message: 'Down.')},
          ),
          start: '/dashboard',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('setup-guide-card')), findsNothing);
      expect(find.text('Dashboard figures'), findsOneWidget);
    });
  });
}
