import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/my_trip/presentation/widgets/bulk_mark_sheet.dart';
import 'package:edutrack_app/features/my_trip/presentation/widgets/rider_tile.dart';
import 'package:edutrack_app/features/transport/data/models/transport_trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_photo_dio.dart';
import '../../support/transport_fixtures.dart';

/// Children's photos for the bus crew (docs/mobile-apps-review.md, M9, 3.3):
/// a face beside each name on the trip and in "Board all", initials where
/// the school has no photo.
void main() {
  TripRider withPhoto(TripRider rider) => TripRider.fromJson({
    'student_id': rider.studentId,
    'admission_number': rider.admissionNumber,
    'name': rider.name,
    'class_section_name': rider.classSectionName,
    'guardian_name': rider.guardianName,
    'guardian_mobile': rider.guardianMobile,
    'stop_id': rider.stopId,
    'stop_name': rider.stopName,
    'stop_sequence_number': rider.stopSequenceNumber,
    'status': rider.status.apiValue,
    'photo_url': '/students/${rider.studentId}/photo?v=abc',
  });

  Widget wrap(Widget child) => ProviderScope(
    overrides: [
      dioClientProvider.overrideWithValue(fakePhotoDio(bytes: const [1, 2, 3])),
    ],
    child: MaterialApp(
      theme: AppTheme.crewLight(),
      home: Scaffold(body: child),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  test('the photo is read from the trip, and kept through a mark', () {
    final rider = withPhoto(arjunTripRider);

    expect(rider.photoUrl, '/students/7/photo?v=abc');
    expect(rider.copyWith(status: TripRiderStatus.boarded).photoUrl, '/students/7/photo?v=abc');
  });

  testWidgets("a child's photo sits beside their name on the trip", (tester) async {
    await tester.pumpWidget(
      wrap(RiderTile(rider: withPhoto(arjunTripRider), running: true, onMark: (_) {}, onCallParent: () {})),
    );
    await settle(tester);

    expect(
      find.descendant(of: find.byKey(const Key('rider-photo-7')), matching: find.byKey(const Key('user-avatar-photo'))),
      findsOneWidget,
    );
  });

  testWidgets('no photo shows the initials', (tester) async {
    await tester.pumpWidget(wrap(RiderTile(rider: arjunTripRider, running: true, onMark: (_) {}, onCallParent: () {})));
    await settle(tester);

    expect(find.text('AK'), findsOneWidget);
    expect(find.byKey(const Key('user-avatar-photo')), findsNothing);
  });

  testWidgets('"Board all" shows each face to untick the one who is not there', (tester) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showBulkMarkSheet(
              context,
              riders: [withPhoto(arjunTripRider), meeraTripRider],
              to: TripRiderStatus.boarded,
              where: 'Lake View',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byKey(const Key('bulk-mark-7')), matching: find.byKey(const Key('user-avatar-photo'))),
      findsOneWidget,
    );
    expect(find.descendant(of: find.byKey(const Key('bulk-mark-8')), matching: find.text('MS')), findsOneWidget);
  });
}
