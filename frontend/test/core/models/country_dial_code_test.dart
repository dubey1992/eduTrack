import 'package:edutrack_app/core/models/country_dial_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CountryDialCode.flag', () {
    test('computes the correct regional-indicator flag emoji from iso2', () {
      const india = CountryDialCode('+91', 'India', 'IN', 10, 10);
      const uk = CountryDialCode('+44', 'United Kingdom', 'GB', 10, 10);

      expect(india.flag, '🇮🇳');
      expect(uk.flag, '🇬🇧');
    });

    test('every curated country has a two-character flag emoji', () {
      for (final country in CountryDialCode.common) {
        // Each regional-indicator symbol is a surrogate pair (2 UTF-16 code
        // units), so a 2-letter ISO code produces a 4-unit string.
        expect(country.flag.length, 4, reason: 'unexpected flag for ${country.iso2}');
      }
    });
  });
}
