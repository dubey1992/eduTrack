import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paged_list.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/grade_scales/application/grade_scale_notifier.dart';
import 'package:edutrack_app/features/grade_scales/data/grade_scale_repository.dart';
import 'package:edutrack_app/features/grade_scales/data/models/grade_scale.dart';
import 'package:edutrack_app/features/grade_scales/presentation/grade_scale_dialog.dart';
import 'package:edutrack_app/features/grade_scales/presentation/grade_scale_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_grade_scale_repository.dart';
import '../../support/session_users.dart';

ProviderContainer containerWith(FakeGradeScaleRepository fake) {
  final container = ProviderContainer(
    overrides: [gradeScaleRepositoryProvider.overrideWithValue(fake)],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);

  return container;
}

Future<PagedList<GradeScale>> load(ProviderContainer container) async {
  final sub = container.listen(gradeScaleListNotifierProvider, (_, _) {});
  addTearDown(sub.close);

  return container.read(gradeScaleListNotifierProvider.future);
}

/// The screen and its dialog, with a School Admin signed in unless a test
/// says otherwise.
Widget wrap(FakeGradeScaleRepository fake, {UserRole role = UserRole.schoolAdmin, Widget? child}) {
  return ProviderScope(
    overrides: [
      gradeScaleRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: sessionUser(role))),
    ],
    retry: (retryCount, error) => null,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child ?? const GradeScaleListScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('the band model', () {
    test('reads a range without the noise of trailing zeros', () {
      expect(fakeBand(min: '81.00', max: '90.00').range, '81 - 90');
    });

    test('keeps the decimals that mean something', () {
      expect(fakeBand(min: '32.50', max: '90.00').range, '32.5 - 90');
    });

    test('sends no band id back: the set is replaced whole', () {
      expect(fakeBand().toJson().containsKey('id'), isFalse);
    });

    test('parses a scale and its bands', () {
      final scale = GradeScale.fromJson({
        'id': 4,
        'school_id': 2,
        'school_name': 'Test School',
        'name': 'Primary',
        'is_default': false,
        'bands': [
          {'id': 9, 'label': 'A', 'min_percentage': '61.00', 'max_percentage': '100.00', 'is_failing': false},
        ],
      });

      expect(scale.name, 'Primary');
      expect(scale.isDefault, isFalse);
      expect(scale.bands.single.label, 'A');
    });
  });

  group('the list', () {
    test('loads what the API sends, default first', () async {
      final fake = FakeGradeScaleRepository(
        scales: [
          fakeGradeScale(id: 1, name: 'Zebra', isDefault: false),
          fakeGradeScale(id: 2, name: 'Alpha', isDefault: true),
        ],
      );

      final page = await load(containerWith(fake));

      expect(page.items.map((scale) => scale.name), ['Alpha', 'Zebra']);
    });

    test('creating one refreshes the list', () async {
      final fake = FakeGradeScaleRepository();
      final container = containerWith(fake);
      await load(container);

      await container
          .read(gradeScaleListNotifierProvider.notifier)
          .createScale(name: 'Secondary', isDefault: true, bands: [fakeBand()]);

      expect(container.read(gradeScaleListNotifierProvider).value!.items.length, 1);
      expect(fake.calls, ['listPage', 'create', 'listPage']);
    });

    test('a failed create leaves the list alone and rethrows for the dialog', () async {
      final fake = FakeGradeScaleRepository(
        failWith: {'create': const Failure(code: 'VALIDATION_ERROR', message: 'The name has already been taken.')},
      );
      final container = containerWith(fake);
      await load(container);

      await expectLater(
        container
            .read(gradeScaleListNotifierProvider.notifier)
            .createScale(name: 'Secondary', isDefault: true, bands: [fakeBand()]),
        throwsA(isA<Failure>()),
      );
      expect(container.read(gradeScaleListNotifierProvider).value!.items, isEmpty);
    });

    test('deleting one drops it', () async {
      final fake = FakeGradeScaleRepository(scales: [fakeGradeScale(id: 3)]);
      final container = containerWith(fake);
      final page = await load(container);

      await container.read(gradeScaleListNotifierProvider.notifier).deleteScale(page.items.single);

      expect(container.read(gradeScaleListNotifierProvider).value!.items, isEmpty);
    });
  });

  group('the screen', () {
    testWidgets('shows each scale with its bands', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeGradeScaleRepository(scales: [fakeGradeScale()])));
      await tester.pumpAndSettle();

      expect(find.text('Secondary'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Pass  33 - 100'), findsOneWidget);
      expect(find.text('Fail  0 - 32'), findsOneWidget);
    });

    testWidgets('says what a scale is for when there are none', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeGradeScaleRepository()));
      await tester.pumpAndSettle();

      expect(find.textContaining('No grade scales yet'), findsOneWidget);
    });

    testWidgets('offers a retry when they cannot be loaded', (tester) async {
      useDesktop(tester);
      final fake = FakeGradeScaleRepository(
        failWith: {'listPage': const Failure(code: 'SERVER_ERROR', message: 'Grade scales are unavailable.')},
      );

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.text('Grade scales are unavailable.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a teacher sees the scales and none of the actions', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeGradeScaleRepository(scales: [fakeGradeScale()]), role: UserRole.teacher));
      await tester.pumpAndSettle();

      expect(find.text('Secondary'), findsOneWidget);
      expect(find.text('Add Grade Scale'), findsNothing);
      expect(find.byTooltip('Edit scale'), findsNothing);
      expect(find.byTooltip('Delete scale'), findsNothing);
    });

    testWidgets('deleting asks first and reports a refusal', (tester) async {
      useDesktop(tester);
      final fake = FakeGradeScaleRepository(
        scales: [fakeGradeScale()],
        failWith: {
          'delete': const Failure(
            code: 'HAS_DEPENDENT_RECORDS',
            message: "This is the school's default grade scale. Make another one the default first.",
          ),
        },
      );

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete scale'));
      await tester.pumpAndSettle();
      expect(find.text('Delete grade scale?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(
        find.text("This is the school's default grade scale. Make another one the default first."),
        findsOneWidget,
      );
      expect(find.text('Secondary'), findsOneWidget);
    });
  });

  group('the dialog', () {
    Widget dialogHost(FakeGradeScaleRepository fake, {GradeScale? scale}) {
      return wrap(
        fake,
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => GradeScaleDialog(scale: scale),
            ),
            child: const Text('Open'),
          ),
        ),
      );
    }

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens on one empty band row', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(dialogHost(FakeGradeScaleRepository()));
      await open(tester);

      expect(find.widgetWithText(TextFormField, 'Grade'), findsOneWidget);
      expect(find.text('Add band'), findsOneWidget);
    });

    testWidgets('requires a name and a band', (tester) async {
      useDesktop(tester);
      final fake = FakeGradeScaleRepository();
      await tester.pumpWidget(dialogHost(fake));
      await open(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
      expect(fake.calls, isNot(contains('create')));
    });

    testWidgets('refuses a percentage that is not a number or is out of range', (tester) async {
      useDesktop(tester);
      final fake = FakeGradeScaleRepository();
      await tester.pumpWidget(dialogHost(fake));
      await open(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Secondary)'), 'Secondary');
      await tester.enterText(find.widgetWithText(TextFormField, 'Grade'), 'A');
      await tester.enterText(find.widgetWithText(TextFormField, 'From %'), 'ten');
      await tester.enterText(find.widgetWithText(TextFormField, 'To %'), '120');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Number'), findsOneWidget);
      expect(find.text('0-100'), findsOneWidget);
      expect(fake.calls, isNot(contains('create')));
    });

    testWidgets('a band can be added and removed, and the last one stays', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(dialogHost(FakeGradeScaleRepository()));
      await open(tester);

      // byTooltip finds the Tooltip, not the button it wraps.
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close)).onPressed, isNull);

      await tester.tap(find.text('Add band'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Grade'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Remove band').first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Grade'), findsOneWidget);
    });

    testWidgets('saves the bands it was given and says so', (tester) async {
      useDesktop(tester);
      final fake = FakeGradeScaleRepository();
      await tester.pumpWidget(dialogHost(fake));
      await open(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Secondary)'), 'Secondary');
      await tester.enterText(find.widgetWithText(TextFormField, 'Grade'), 'Recorded');
      await tester.enterText(find.widgetWithText(TextFormField, 'From %'), '0');
      await tester.enterText(find.widgetWithText(TextFormField, 'To %'), '100');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      // One pump to let the snack bar in, before settling dismisses it with
      // the dialog it was posted from.
      await tester.pump();
      await tester.pump();

      expect(fake.calls, contains('create'));
      expect(fake.lastBands.single.label, 'Recorded');
      expect(find.text('Grade scale created.'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets("a band error from the server lands on that band's field", (tester) async {
      useDesktop(tester);
      final fake = FakeGradeScaleRepository(
        failWith: {
          'create': const Failure(
            code: 'VALIDATION_ERROR',
            message: 'The given data was invalid.',
            details: {
              'errors': {
                'bands.0.min_percentage': ['The lowest band must start at 0, so every mark has a grade.'],
              },
            },
          ),
        },
      );
      await tester.pumpWidget(dialogHost(fake));
      await open(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Secondary)'), 'Secondary');
      await tester.enterText(find.widgetWithText(TextFormField, 'Grade'), 'A');
      await tester.enterText(find.widgetWithText(TextFormField, 'From %'), '1');
      await tester.enterText(find.widgetWithText(TextFormField, 'To %'), '100');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('The lowest band must start at 0, so every mark has a grade.'), findsOneWidget);
    });

    testWidgets('a failure with no field named is shown as a banner', (tester) async {
      useDesktop(tester);
      final fake = FakeGradeScaleRepository(
        failWith: {'create': const Failure(code: 'MODULE_DISABLED', message: 'Academics is switched off.')},
      );
      await tester.pumpWidget(dialogHost(fake));
      await open(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Secondary)'), 'Secondary');
      await tester.enterText(find.widgetWithText(TextFormField, 'Grade'), 'A');
      await tester.enterText(find.widgetWithText(TextFormField, 'From %'), '0');
      await tester.enterText(find.widgetWithText(TextFormField, 'To %'), '100');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Academics is switched off.'), findsOneWidget);
    });

    testWidgets('editing opens with the scale already in it', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(dialogHost(FakeGradeScaleRepository(), scale: fakeGradeScale()));
      await open(tester);

      expect(find.text('Edit Grade Scale'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Secondary'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Pass'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Fail'), findsOneWidget);
    });
  });

  group('grading systems', () {
    Widget host(FakeGradeScaleRepository fake, {GradeScale? scale}) => wrap(
      fake,
      child: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => GradeScaleDialog(scale: scale),
          ),
          child: const Text('Open'),
        ),
      ),
    );

    Future<void> open(WidgetTester tester, FakeGradeScaleRepository fake, {GradeScale? scale}) async {
      useDesktop(tester);
      await tester.pumpWidget(host(fake, scale: scale));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    Future<void> pickPreset(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const Key('grade-scale-presets')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a new scale is a percentage scale, with no points column', (tester) async {
      await open(tester, FakeGradeScaleRepository());

      expect(find.byKey(const Key('grade-band-points-0')), findsNothing);
      expect(find.byKey(const Key('grade-scale-multiplier')), findsNothing);
      expect(find.text('Report cards show marks, the percentage and the grade.'), findsOneWidget);
    });

    testWidgets('a preset fills the type, the bands, their points and meanings, and the multiplier', (tester) async {
      final fake = FakeGradeScaleRepository();
      await open(tester, fake);

      await pickPreset(tester, 'Nine-point grades with grade points (CBSE style)');

      expect(find.byKey(const Key('grade-band-points-7')), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Outstanding'), findsOneWidget);

      await save(tester);

      expect(fake.lastKind, GradeScaleKind.gpa);
      expect(fake.lastMultiplier, '9.5');
      expect((fake.lastBands.first.label, fake.lastBands.first.gradePoint), ('A1', '10'));
      expect(fake.lastBands.last.isFailing, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('a preset does not overwrite a name the school already typed', (tester) async {
      await open(tester, FakeGradeScaleRepository());
      await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Secondary)'), 'Senior school');

      await pickPreset(tester, 'Four-point GPA (A to F)');

      expect(find.widgetWithText(TextFormField, 'Senior school'), findsOneWidget);
    });

    testWidgets('a GPA band without points is refused before anything is sent', (tester) async {
      final fake = FakeGradeScaleRepository();
      await open(tester, fake);
      await tester.tap(find.text('Grade points (GPA)'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Secondary)'), 'GPA');
      await tester.enterText(find.widgetWithText(TextFormField, 'Grade'), 'A');
      await tester.enterText(find.widgetWithText(TextFormField, 'From %'), '0');
      await tester.enterText(find.widgetWithText(TextFormField, 'To %'), '100');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Number'), findsOneWidget);
      expect(fake.calls, isNot(contains('create')));
    });

    testWidgets('points are not sent for a scale that is not GPA', (tester) async {
      final fake = FakeGradeScaleRepository();
      await open(tester, fake);
      await pickPreset(tester, 'Four-point GPA (A to F)');

      await tester.tap(find.text('Grades only'));
      await tester.pumpAndSettle();
      await save(tester);

      expect(fake.lastKind, GradeScaleKind.grades);
      expect(fake.lastBands.every((band) => band.gradePoint == null), isTrue);
      expect(fake.lastMultiplier, isNull);
      expect(fake.lastBands.first.description, 'Excellent');
      await tester.pumpAndSettle();
    });

    testWidgets("the server's refusal of a band's points lands on that field", (tester) async {
      final fake = FakeGradeScaleRepository(
        failWith: {
          'create': const Failure(
            code: 'VALIDATION_ERROR',
            message: 'The given data was invalid.',
            details: {
              'errors': {
                'bands.0.grade_point': ['A higher band cannot carry fewer points than "B" (3.00).'],
              },
            },
          ),
        },
      );
      await open(tester, fake);
      await pickPreset(tester, 'Four-point GPA (A to F)');

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('A higher band cannot carry fewer points than "B" (3.00).'), findsOneWidget);
    });

    testWidgets('editing a GPA scale opens on its type, points and multiplier', (tester) async {
      const scale = GradeScale(
        id: 9,
        schoolId: 1,
        schoolName: null,
        name: 'US 4.0',
        isDefault: true,
        kind: GradeScaleKind.gpa,
        gpaMultiplier: '25.00',
        bands: [
          GradeBand(
            id: 1,
            label: 'A',
            minPercentage: '0.00',
            maxPercentage: '100.00',
            isFailing: false,
            gradePoint: '4.00',
          ),
        ],
      );
      await open(tester, FakeGradeScaleRepository(), scale: scale);

      expect(find.widgetWithText(TextFormField, '4.00'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '25.00'), findsOneWidget);
    });

    test('a scale reads its kind, points and meanings, and an old payload is a percentage scale', () {
      final scale = GradeScale.fromJson({
        'id': 1,
        'school_id': 1,
        'name': 'GPA',
        'is_default': true,
        'kind': 'gpa',
        'gpa_multiplier': '9.50',
        'bands': [
          {
            'id': 1,
            'label': 'A1',
            'min_percentage': '91.00',
            'max_percentage': '100.00',
            'is_failing': false,
            'grade_point': '10.00',
            'description': 'Outstanding',
          },
        ],
      });
      final old = GradeScale.fromJson({'id': 2, 'school_id': 1, 'name': 'Old', 'is_default': false, 'bands': []});

      expect((scale.kind, scale.gpaMultiplier, scale.bands.single.points), (GradeScaleKind.gpa, '9.50', '10'));
      expect(scale.bands.single.description, 'Outstanding');
      expect(old.kind, GradeScaleKind.percentage);
    });

    testWidgets('the list says how each scale grades', (tester) async {
      useDesktop(tester);
      final fake = FakeGradeScaleRepository(
        scales: const [
          GradeScale(
            id: 3,
            schoolId: 1,
            schoolName: null,
            name: 'Primary',
            isDefault: true,
            kind: GradeScaleKind.grades,
            bands: [
              GradeBand(
                id: 1,
                label: 'A',
                minPercentage: '0.00',
                maxPercentage: '100.00',
                isFailing: false,
                description: 'Outstanding',
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('grade-scale-kind-3')), findsOneWidget);
      expect(find.text('Grades only'), findsOneWidget);
      expect(find.textContaining('Outstanding'), findsOneWidget);
    });
  });
}
