import 'package:edutrack_app/features/schools/data/models/school_pin.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> row({
  Object? id = 1,
  String name = 'Bright Future',
  Object? latitude = '18.5289123',
  Object? longitude = '73.8744567',
  bool isBranch = false,
  String status = 'active',
  String city = 'Pune',
}) {
  return {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'is_branch': isBranch,
    'status': status,
    'city': city,
  };
}

/// Turning rows into pins (docs/maps.md, M1d).
///
/// The one thing this must never do is put a school somewhere it is not.
/// A careless parse draws a school with no coordinates at (0, 0), off the
/// coast of Africa, where it looks every bit as deliberate as a real one -
/// so anything that is not a point becomes a school nobody has placed yet.
void main() {
  group('a row that is a point', () {
    test('it keeps every decimal place', () {
      // The column is decimal(10,7); the seventh place is about a
      // centimetre, and the whole API agrees on strings to keep it.
      final pin = SchoolPin.fromJson(row())!;

      expect(pin.latitude, closeTo(18.5289123, 0.0000001));
      expect(pin.longitude, closeTo(73.8744567, 0.0000001));
    });

    test('it reads what the map draws it with', () {
      final pin = SchoolPin.fromJson(row(isBranch: true, status: 'inactive'))!;

      expect(pin.isBranch, isTrue);
      expect(pin.isActive, isFalse);
      expect(pin.city, 'Pune');
    });

    test('a number sent as a number is still a point', () {
      // The API sends strings, but a pin that only worked for strings would
      // break silently the day something upstream changes.
      final pin = SchoolPin.fromJson(row(latitude: 18.5289, longitude: 73.8744))!;

      expect(pin.latitude, closeTo(18.5289, 0.0001));
    });

    test('the far corners of the world are points', () {
      expect(SchoolPin.fromJson(row(latitude: '-90', longitude: '-180')), isNotNull);
      expect(SchoolPin.fromJson(row(latitude: '90', longitude: '180')), isNotNull);
    });
  });

  group('a row that is not a point', () {
    test('no coordinates at all', () {
      expect(SchoolPin.fromJson(row(latitude: null, longitude: null)), isNull);
    });

    test('half a coordinate, which points nowhere', () {
      expect(SchoolPin.fromJson(row(longitude: null)), isNull);
      expect(SchoolPin.fromJson(row(latitude: null)), isNull);
    });

    test('something that is not a number', () {
      expect(SchoolPin.fromJson(row(latitude: 'north')), isNull);
      expect(SchoolPin.fromJson(row(latitude: '')), isNull);
    });

    test('a number off the earth', () {
      // The usual cause is a swapped pair: a longitude of 73 in the
      // latitude box is legal, but 180 in it is not.
      expect(SchoolPin.fromJson(row(latitude: '91')), isNull);
      expect(SchoolPin.fromJson(row(longitude: '181')), isNull);
    });

    test('no id to open it by', () {
      expect(SchoolPin.fromJson(row(id: null)), isNull);
      expect(SchoolPin.fromJson(row(id: '7')), isNull);
    });
  });

  group('a status nobody recognises', () {
    test('it is not treated as active', () {
      // A school in a state this build has never heard of should not be
      // drawn as though nothing were the matter with it.
      for (final status in ['', 'suspended', 'ACTIVE', 'archived']) {
        expect(SchoolPin.fromJson(row(status: status))!.isActive, isFalse, reason: status);
      }
    });
  });

  group('reading a whole answer', () {
    test('placed and unplaced come back separately', () {
      final locations = SchoolLocations.fromJson({
        'placed': [row(id: 1)],
        'unplaced': [
          {'id': 2, 'name': 'Nowhere Yet'},
        ],
        'more_than_shown': false,
      });

      expect(locations.placed.single.id, 1);
      expect(locations.unplaced.single.name, 'Nowhere Yet');
    });

    test('a placed row that is not a point moves across rather than vanishing', () {
      // It is still a school somebody has to deal with. Dropping it would
      // hide a school that exists from the only screen that lists the ones
      // needing attention.
      final locations = SchoolLocations.fromJson({
        'placed': [row(id: 1, name: 'Broken Row', latitude: 'north')],
        'unplaced': const [],
        'more_than_shown': false,
      });

      expect(locations.placed, isEmpty);
      expect(locations.unplaced.single.name, 'Broken Row');
    });

    test('rows that are not objects are skipped, not crashed on', () {
      final locations = SchoolLocations.fromJson({
        'placed': ['nonsense', 42, row(id: 1)],
        'unplaced': ['nonsense'],
        'more_than_shown': false,
      });

      expect(locations.placed.single.id, 1);
      expect(locations.unplaced, isEmpty);
    });

    test('a shape nobody expected is empty rather than a crash', () {
      for (final body in <Map<String, dynamic>>[
        {},
        {'placed': null, 'unplaced': null},
        {'placed': 'nonsense', 'unplaced': 42},
      ]) {
        final locations = SchoolLocations.fromJson(body);

        expect(locations.isEmpty, isTrue, reason: '$body');
        expect(locations.moreThanShown, isFalse, reason: '$body');
      }
    });

    test('"there are more" is only true when the server said so', () {
      expect(SchoolLocations.fromJson({'more_than_shown': true}).moreThanShown, isTrue);
      expect(SchoolLocations.fromJson({'more_than_shown': 'yes'}).moreThanShown, isFalse);
      expect(SchoolLocations.fromJson({}).moreThanShown, isFalse);
    });

    test('a page with pins on it is not empty', () {
      final locations = SchoolLocations.fromJson({
        'placed': [row()],
        'unplaced': const [],
      });

      expect(locations.isEmpty, isFalse);
    });
  });
}
