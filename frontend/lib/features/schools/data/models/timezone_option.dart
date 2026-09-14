/// One entry in the timezone picker on the school form.
///
/// The list is served by the API rather than hardcoded here, so it can never
/// offer a zone the backend would reject, and so it stays correct as the
/// IANA database changes.
class TimezoneOption {
  const TimezoneOption({required this.name, required this.region, required this.label, required this.offsetMinutes});

  factory TimezoneOption.fromJson(Map<String, dynamic> json) {
    return TimezoneOption(
      name: json['name'] as String,
      region: json['region'] as String,
      label: json['label'] as String,
      offsetMinutes: json['offset_minutes'] as int,
    );
  }

  /// The IANA identifier, e.g. `Asia/Kolkata` - the value the API stores.
  final String name;

  /// The continent it sorts under, e.g. `Asia`.
  final String region;

  /// What the picker shows, e.g. `Asia/Kolkata (GMT+05:30)`.
  final String label;

  /// Its current offset from UTC, used to order the list the way a person
  /// expects to read it.
  final int offsetMinutes;
}
