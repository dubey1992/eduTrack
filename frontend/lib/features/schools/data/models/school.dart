enum SchoolStatus {
  active('active'),
  inactive('inactive');

  const SchoolStatus(this.apiValue);

  final String apiValue;

  static SchoolStatus fromApiValue(String value) => SchoolStatus.values.firstWhere((s) => s.apiValue == value);
}

class School {
  const School({
    required this.id,
    required this.name,
    required this.registrationNumber,
    required this.email,
    required this.phone,
    required this.address,
    required this.city,
    required this.state,
    required this.country,
    required this.postalCode,
    required this.currencyCode,
    required this.timezone,
    required this.logoUrl,
    required this.status,
  });

  factory School.fromJson(Map<String, dynamic> json) {
    return School(
      id: json['id'] as int,
      name: json['name'] as String,
      registrationNumber: json['registration_number'] as String?,
      email: json['email'] as String,
      phone: json['phone'] as String,
      address: json['address'] as String,
      city: json['city'] as String,
      state: json['state'] as String,
      country: json['country'] as String,
      postalCode: json['postal_code'] as String,
      currencyCode: json['currency_code'] as String,
      timezone: json['timezone'] as String? ?? 'UTC',
      logoUrl: json['logo_url'] as String?,
      status: SchoolStatus.fromApiValue(json['status'] as String),
    );
  }

  final int id;
  final String name;
  final String? registrationNumber;
  final String email;
  final String phone;
  final String address;
  final String city;
  final String state;
  final String country;
  final String postalCode;
  final String currencyCode;

  /// The IANA zone this school's dates and times are read in, e.g.
  /// `Asia/Kolkata`. Decides what "today" means for everything it records.
  final String timezone;
  final String? logoUrl;
  final SchoolStatus status;

  School copyWith({SchoolStatus? status}) {
    return School(
      id: id,
      name: name,
      registrationNumber: registrationNumber,
      email: email,
      phone: phone,
      address: address,
      city: city,
      state: state,
      country: country,
      postalCode: postalCode,
      currencyCode: currencyCode,
      timezone: timezone,
      logoUrl: logoUrl,
      status: status ?? this.status,
    );
  }
}
