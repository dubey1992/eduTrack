/// A curated list of common country calling codes for phone-number fields.
/// Mirrors [Currency]'s "curated common list" pattern - the backend doesn't
/// restrict to this list, it's purely a UX convenience so most admins never
/// need to type a dial code by hand.
class CountryDialCode {
  const CountryDialCode(this.dialCode, this.countryName, this.iso2, this.minLength, this.maxLength);

  final String dialCode;
  final String countryName;
  final String iso2;

  /// The national number's expected digit-count range (excluding the dial
  /// code) - e.g. India's mobile numbers are a fixed 10 digits, so
  /// `minLength == maxLength == 10`; countries with genuinely variable
  /// lengths (Indonesia, Germany) get a real range instead of a guess.
  final int minLength;
  final int maxLength;

  String get label => '$dialCode $countryName';

  /// The flag emoji for [iso2], computed rather than hardcoded per entry -
  /// each Unicode "regional indicator symbol" letter sits at a fixed offset
  /// from the Latin letter it represents, so e.g. "IN" becomes 🇮🇳.
  String get flag {
    final codeUnits = iso2.toUpperCase().codeUnits.map((c) => 0x1F1E6 + (c - 0x41));
    return String.fromCharCodes(codeUnits);
  }

  static const common = [
    CountryDialCode('+91', 'India', 'IN', 10, 10),
    CountryDialCode('+1', 'United States', 'US', 10, 10),
    CountryDialCode('+1', 'Canada', 'CA', 10, 10),
    CountryDialCode('+44', 'United Kingdom', 'GB', 10, 10),
    CountryDialCode('+49', 'Germany', 'DE', 10, 11),
    CountryDialCode('+33', 'France', 'FR', 9, 9),
    CountryDialCode('+971', 'UAE', 'AE', 9, 9),
    CountryDialCode('+966', 'Saudi Arabia', 'SA', 9, 9),
    CountryDialCode('+234', 'Nigeria', 'NG', 10, 10),
    CountryDialCode('+254', 'Kenya', 'KE', 9, 9),
    CountryDialCode('+27', 'South Africa', 'ZA', 9, 9),
    CountryDialCode('+92', 'Pakistan', 'PK', 10, 10),
    CountryDialCode('+880', 'Bangladesh', 'BD', 10, 10),
    CountryDialCode('+63', 'Philippines', 'PH', 10, 10),
    CountryDialCode('+62', 'Indonesia', 'ID', 9, 12),
    CountryDialCode('+60', 'Malaysia', 'MY', 9, 10),
    CountryDialCode('+65', 'Singapore', 'SG', 8, 8),
    CountryDialCode('+61', 'Australia', 'AU', 9, 9),
  ];

  /// Finds the entry whose [dialCode] prefixes [value] (longest match wins,
  /// so e.g. "+91..." doesn't get misread against a shorter unrelated
  /// prefix). Falls back to the first entry when nothing matches.
  static CountryDialCode? matchPrefix(String value) {
    CountryDialCode? best;
    for (final country in common) {
      if (value.startsWith('${country.dialCode} ') &&
          (best == null || country.dialCode.length > best.dialCode.length)) {
        best = country;
      }
    }
    return best;
  }
}
