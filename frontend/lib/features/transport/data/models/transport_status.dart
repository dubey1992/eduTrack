enum TransportStatus {
  active('active', 'Active'),
  inactive('inactive', 'Inactive');

  const TransportStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static TransportStatus fromApiValue(String value) => TransportStatus.values.firstWhere((s) => s.apiValue == value);
}
