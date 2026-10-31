import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/maps/data/places_repository.dart';
import 'package:edutrack_app/features/schools/presentation/widgets/postal_code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_places_repository.dart';

const _pune = PostalPlace(
  postalCode: '411001',
  city: 'Pune',
  state: 'Maharashtra',
  country: 'India',
  latitude: 18.5236,
  longitude: 73.874,
);

const _mumbai = PostalPlace(
  postalCode: '400001',
  city: 'Mumbai',
  state: 'Maharashtra',
  country: 'India',
  latitude: 18.9388,
  longitude: 72.8354,
);

class _Boxes {
  _Boxes({String postalCode = '', String city = '', String country = ''})
    : postalCode = TextEditingController(text: postalCode),
      city = TextEditingController(text: city),
      country = TextEditingController(text: country);

  final TextEditingController postalCode;
  final TextEditingController city;
  final TextEditingController state = TextEditingController();
  final TextEditingController country;
  final TextEditingController latitude = TextEditingController();
  final TextEditingController longitude = TextEditingController();
}

Widget _wrap(FakePlacesRepository fake, _Boxes boxes) {
  return ProviderScope(
    overrides: [placesRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: PostalCodeField(
          postalCode: boxes.postalCode,
          city: boxes.city,
          state: boxes.state,
          country: boxes.country,
          latitude: boxes.latitude,
          longitude: boxes.longitude,
        ),
      ),
    ),
  );
}

Future<void> _type(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(const Key('school-postal-code')), code);
  // The field waits for a pause in typing before it asks.
  await tester.pump(const Duration(milliseconds: 750));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a postal code fills in the city, state, country and map pin', (tester) async {
    final fake = FakePlacesRepository(postalLookup: const PostalLookup.found(_pune));
    final boxes = _Boxes();
    await tester.pumpWidget(_wrap(fake, boxes));

    await _type(tester, '411001');

    expect(fake.postalLookups.single.code, '411001');
    expect((boxes.city.text, boxes.state.text, boxes.country.text), ('Pune', 'Maharashtra', 'India'));
    expect((boxes.latitude.text, boxes.longitude.text), ('18.5236000', '73.8740000'));
    expect(
      find.text('Pune, Maharashtra, India - filled in the city, state, country and map pin. Check them before saving.'),
      findsOneWidget,
    );
  });

  testWidgets('it waits for a pause rather than asking on every digit', (tester) async {
    final fake = FakePlacesRepository(postalLookup: const PostalLookup.found(_pune));
    await tester.pumpWidget(_wrap(fake, _Boxes()));

    for (final typed in ['41', '411', '4110', '41100', '411001']) {
      await tester.enterText(find.byKey(const Key('school-postal-code')), typed);
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();

    expect(fake.postalLookups.map((asked) => asked.code), ['411001']);
  });

  testWidgets('the country typed tells it which country to look in', (tester) async {
    final fake = FakePlacesRepository(postalLookup: const PostalLookup.found(_pune));
    await tester.pumpWidget(_wrap(fake, _Boxes(country: 'India')));

    await _type(tester, '411001');

    expect(fake.postalLookups.single.country, 'India');
  });

  testWidgets('what somebody typed is kept; what it filled itself it may change', (tester) async {
    final fake = FakePlacesRepository(postalLookup: const PostalLookup.found(_pune));
    final boxes = _Boxes(city: 'Pune Camp');
    await tester.pumpWidget(_wrap(fake, boxes));

    await _type(tester, '411001');

    expect(boxes.city.text, 'Pune Camp');
    expect(boxes.state.text, 'Maharashtra');

    fake.postalLookup = const PostalLookup.found(_mumbai);
    await _type(tester, '400001');

    // Its own state and pin move to the new code; the typed city stays.
    expect((boxes.city.text, boxes.latitude.text), ('Pune Camp', '18.9388000'));
  });

  testWidgets('when everything was typed already, it says so and changes nothing', (tester) async {
    final fake = FakePlacesRepository(postalLookup: const PostalLookup.found(_pune));
    final boxes = _Boxes(city: 'Pune', country: 'India')
      ..state.text = 'MH'
      ..latitude.text = '18.5'
      ..longitude.text = '73.8';
    await tester.pumpWidget(_wrap(fake, boxes));

    await _type(tester, '411001');

    expect(boxes.state.text, 'MH');
    expect(find.text('Pune, Maharashtra, India. What you typed was kept.'), findsOneWidget);
  });

  testWidgets('a code nobody knows says so, and fills nothing', (tester) async {
    final fake = FakePlacesRepository(postalLookup: const PostalLookup.notFound());
    final boxes = _Boxes();
    await tester.pumpWidget(_wrap(fake, boxes));

    await _type(tester, '999999');

    expect(find.text('No place found for this postal code. Check it, or type the address in.'), findsOneWidget);
    expect(boxes.city.text, isEmpty);
  });

  testWidgets('with no lookup available, the boxes are simply left to type', (tester) async {
    final fake = FakePlacesRepository();
    await tester.pumpWidget(_wrap(fake, _Boxes()));

    await _type(tester, '411001');

    expect(find.text("Postal code lookup isn't available right now - type the address in."), findsOneWidget);
  });

  testWidgets('a school being edited is not looked up just by opening it', (tester) async {
    final fake = FakePlacesRepository(postalLookup: const PostalLookup.found(_pune));
    await tester.pumpWidget(_wrap(fake, _Boxes(postalCode: '411001')));
    await tester.pump(const Duration(milliseconds: 750));

    await _type(tester, '411001');

    expect(fake.postalLookups, isEmpty);
  });

  testWidgets('two characters are not worth asking about', (tester) async {
    final fake = FakePlacesRepository(postalLookup: const PostalLookup.found(_pune));
    await tester.pumpWidget(_wrap(fake, _Boxes()));

    await _type(tester, '41');

    expect(fake.postalLookups, isEmpty);
  });
}
