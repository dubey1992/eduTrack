enum DayOfWeek {
  monday('monday', 'Monday'),
  tuesday('tuesday', 'Tuesday'),
  wednesday('wednesday', 'Wednesday'),
  thursday('thursday', 'Thursday'),
  friday('friday', 'Friday');

  const DayOfWeek(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static DayOfWeek fromApiValue(String value) => DayOfWeek.values.firstWhere((d) => d.apiValue == value);
}
