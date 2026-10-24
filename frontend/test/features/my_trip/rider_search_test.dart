import 'package:edutrack_app/features/my_trip/data/rider_search.dart';
import 'package:edutrack_app/features/transport/data/models/transport_trip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/my_trip_fixtures.dart';

/// Finding a child by what the crew knows - typed or heard
/// (docs/driver-app.md, D8).
void main() {
  TripRider rider(String name, {int id = 1, String? className = 'Grade 2 A'}) {
    final json = riderJson(id, name, stopId: 101)..['class_section_name'] = className;
    return TripRider.fromJson(json);
  }

  final sai = rider('Sai Iyer', id: 5);
  final saanvi = rider('Saanvi Verma', id: 6, className: 'Grade 3 A');

  test('an empty search keeps everybody', () {
    expect(riderMatches(sai, ''), isTrue);
    expect(riderMatches(sai, '   '), isTrue);
  });

  test('the start of a first or last name is enough', () {
    expect(riderMatches(sai, 'sa'), isTrue);
    expect(riderMatches(sai, 'Iy'), isTrue);
    expect(riderMatches(sai, 'Sai Iy'), isTrue);
  });

  test('every word asked for has to land somewhere', () {
    expect(riderMatches(sai, 'Sai Verma'), isFalse);
    expect(riderMatches(saanvi, 'Saanvi Verma'), isTrue);
  });

  test('the admission number and the class find a child too', () {
    expect(riderMatches(sai, 'ADM-5'), isTrue);
    expect(riderMatches(sai, 'adm 5'), isTrue);
    expect(riderMatches(saanvi, 'grade 3'), isTrue);
    expect(riderMatches(sai, 'grade 3'), isFalse);
  });

  test('a letter or two wrong, as a recogniser hears it, still finds the child', () {
    expect(riderMatches(sai, 'Sai Ayer'), isTrue);
    expect(riderMatches(saanvi, 'Sanvi'), isTrue);
    expect(riderMatches(saanvi, 'Saanvi Varma'), isTrue);
    expect(riderMatches(rider('Kabir Rao', id: 3), 'Kabeer'), isTrue, reason: 'two edits on a six-letter word');
  });

  test('but the slack is small, and short words have to be exact', () {
    expect(riderMatches(sai, 'Soi'), isFalse);
    expect(riderMatches(saanvi, 'Sai'), isFalse);
    expect(riderMatches(saanvi, 'Sunita'), isFalse, reason: 'three edits is a different name');
    expect(riderMatches(rider('Kabir Rao', id: 3), 'Kabeer Roy'), isFalse, reason: 'Roy is three letters, exact only');
  });

  test('findRiders keeps the order it was given', () {
    final found = findRiders([saanvi, sai], 'sa');
    expect(found.map((r) => r.name), ['Saanvi Verma', 'Sai Iyer']);
    expect(findRiders([saanvi, sai], 'nobody'), isEmpty);
  });
}
