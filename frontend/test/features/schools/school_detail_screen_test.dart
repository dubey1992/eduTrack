import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/models/working_week.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/schools/presentation/school_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_map.dart';
import '../../support/fake_school_repository.dart';

/// A school on a page of its own.
///
/// **Read-only.** The map here is for looking at where a school is; moving
/// the pin belongs on the edit form, where the change is saved.
School _school({
  String? latitude = '18.5204000',
  String? longitude = '73.8567000',
  String workingDays = '1111100',
  SchoolStatus status = SchoolStatus.active,
}) {
  return School(
    id: 7,
    name: 'Abbey Road School',
    registrationNumber: 'REG-001',
    email: 'head@abbey.invalid',
    phone: '+91 9000000000',
    address: '1 Abbey Road',
    city: 'Pune',
    state: 'MH',
    country: 'India',
    postalCode: '411001',
    latitude: latitude,
    longitude: longitude,
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    workingDays: WorkingWeek.fromApiValue(workingDays),
    logoUrl: null,
    status: status,
  );
}

late FakeMapRenderer renderer;

Widget wrap(FakeSchoolRepository fake, {bool mapWorks = true}) {
  renderer = FakeMapRenderer();

  return ProviderScope(
    overrides: [
      schoolRepositoryProvider.overrideWithValue(fake),
      ...(mapWorks ? [...mapIsAvailable(renderer), ...mapPinsAreReady()] : mapIsUnavailable()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: SchoolDetailScreen(schoolId: 7)),
    ),
  );
}

void main() {
  testWidgets('it asks the server for the school rather than a list it does not have', (tester) async {
    // The page is reachable by its own URL, so a reload has no list in hand
    // to take a row from.
    final fake = FakeSchoolRepository(schools: [_school()]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(fake.finds, 1);
    expect(fake.lastFound, 7);
    expect(find.text('Abbey Road School'), findsOneWidget);
  });

  testWidgets('it shows the facts somebody opened it for', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository(schools: [_school()])));
    await tester.pumpAndSettle();

    expect(find.text('REG-001'), findsOneWidget);
    expect(find.text('head@abbey.invalid'), findsOneWidget);
    expect(find.text('Asia/Kolkata'), findsOneWidget);
    expect(find.text('Monday to Friday'), findsOneWidget);
  });

  testWidgets('a half day is named here too', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository(schools: [_school(workingDays: '1111120')])));
    await tester.pumpAndSettle();

    expect(find.text('Monday to Saturday'), findsOneWidget);
    expect(find.text('Saturday is a half day.'), findsOneWidget);
  });

  testWidgets('a placed school gets one pin, where it is', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository(schools: [_school()])));
    await tester.pumpAndSettle();

    final pin = renderer.markersById['school-7'];

    expect(pin, isNotNull);
    expect(pin!.position.latitude, closeTo(18.5204, 0.00001));
    expect(renderer.markersById, hasLength(1));
  });

  testWidgets('the map is for looking at, not for moving the pin', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository(schools: [_school()])));
    await tester.pumpAndSettle();

    // Moving it belongs on the edit form, where the change is saved.
    expect(renderer.lastView!.onTap, isNull);
  });

  group('a school nobody has placed', () {
    testWidgets('says so, and offers the way to place it', (tester) async {
      await tester.pumpWidget(wrap(FakeSchoolRepository(schools: [_school(latitude: null, longitude: null)])));
      await tester.pumpAndSettle();

      expect(find.text('Nobody has placed this school on the map yet.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Place it'), findsOneWidget);
      // Not an empty frame, and not a pin at (0, 0) off the coast of Africa.
      expect(renderer.markersById, isEmpty);
    });

    testWidgets('half a coordinate is not a place', (tester) async {
      await tester.pumpWidget(wrap(FakeSchoolRepository(schools: [_school(longitude: null)])));
      await tester.pumpAndSettle();

      expect(find.text('Nobody has placed this school on the map yet.'), findsOneWidget);
    });
  });

  testWidgets('with no maps key the page still reads, without the map', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository(schools: [_school()]), mapWorks: false));
    await tester.pumpAndSettle();

    expect(find.text('Abbey Road School'), findsOneWidget);
    expect(find.text('REG-001'), findsOneWidget);
    expect(find.textContaining('Map unavailable'), findsOneWidget);
  });

  testWidgets('a school that will not load says so, with a retry', (tester) async {
    final fake = FakeSchoolRepository()
      ..failFindWith = const Failure(code: 'X', message: 'Could not load that school.');
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Could not load that school.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
  });
}
