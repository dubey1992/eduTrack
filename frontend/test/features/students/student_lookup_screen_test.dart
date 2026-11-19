import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:edutrack_app/features/students/presentation/student_lookup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_student_repository.dart';

/// Finding a student in the Staff app (docs/mobile-apps-review.md, 7.4).
Student _student(int id, String first, {String? mobile = '+91 98765 43210', StudentStatus? status}) => Student(
  id: id,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  classSectionId: 5,
  classSectionName: 'Grade 8 A',
  admissionNumber: 'ADM-$id',
  firstName: first,
  lastName: 'Rao',
  name: '$first Rao',
  rollNumber: '$id',
  guardianName: 'Meera Rao',
  guardianMobile: mobile,
  address: null,
  status: status ?? StudentStatus.active,
);

void main() {
  late FakeStudentRepository repository;
  late List<Uri> dialled;

  setUp(() {
    repository = FakeStudentRepository(students: [_student(1, 'Aarav'), _student(2, 'Diya', mobile: null)]);
    dialled = [];
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studentRepositoryProvider.overrideWithValue(repository),
          studentDiallerProvider.overrideWithValue((uri) async {
            dialled.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(theme: AppTheme.teacherLight(), home: const StudentLookupScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("opens on the students the server lets this person see, active ones only", (tester) async {
    await pump(tester);

    expect(find.text('Aarav Rao'), findsOneWidget);
    expect(find.text('Grade 8 A · Roll 1 · Adm. ADM-1'), findsOneWidget);
    expect(repository.statusCalls.last, 'active');
  });

  testWidgets('the search is asked of the server once typing pauses', (tester) async {
    await pump(tester);

    await tester.enterText(find.byKey(const Key('student-lookup-search')), 'diya');
    await tester.pump(const Duration(milliseconds: 100));
    expect(repository.searchCalls.last, isNull, reason: 'not on every key');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repository.searchCalls.last, 'diya');
    expect(find.text('Diya Rao'), findsOneWidget);
    expect(find.text('Aarav Rao'), findsNothing);
  });

  testWidgets('nobody matching says so', (tester) async {
    await pump(tester);

    await tester.enterText(find.byKey(const Key('student-lookup-search')), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('No student you can see matches "zzz".'), findsOneWidget);
  });

  testWidgets('the guardian is one tap away, and a child with no number offers no call', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('student-lookup-call-1')));
    await tester.pumpAndSettle();

    expect(dialled.single.toString(), 'tel:+919876543210');
    expect(find.byKey(const Key('student-lookup-call-2')), findsNothing);
  });

  testWidgets('a failure offers a retry', (tester) async {
    repository.failListWith = const Failure(code: 'NETWORK_ERROR', message: 'Could not reach the server.');
    await pump(tester);

    expect(find.text('Could not reach the server.'), findsOneWidget);
  });
}
