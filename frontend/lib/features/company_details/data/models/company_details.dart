/// School365ai as a business: the issuer printed on the receipt a school gets
/// for paying the platform (docs/pdf-design.md, phase 5).
class CompanyDetails {
  const CompanyDetails({
    required this.isSaved,
    this.legalName,
    this.tradingName,
    this.address,
    this.city,
    this.state,
    this.postalCode,
    this.country,
    this.phone,
    this.email,
    this.website,
    this.taxNumber,
    this.registrationNumber,
    this.logoUrl,
    this.updatedByName,
  });

  factory CompanyDetails.fromJson(Map<String, dynamic> json) => CompanyDetails(
    isSaved: json['is_saved'] as bool? ?? false,
    legalName: json['legal_name'] as String?,
    tradingName: json['trading_name'] as String?,
    address: json['address'] as String?,
    city: json['city'] as String?,
    state: json['state'] as String?,
    postalCode: json['postal_code'] as String?,
    country: json['country'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    website: json['website'] as String?,
    taxNumber: json['tax_number'] as String?,
    registrationNumber: json['registration_number'] as String?,
    logoUrl: json['logo_url'] as String?,
    updatedByName: json['updated_by_name'] as String?,
  );

  /// False until the Super Admin saves them for the first time.
  final bool isSaved;
  final String? legalName;
  final String? tradingName;
  final String? address;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;
  final String? phone;
  final String? email;
  final String? website;

  /// GSTIN in India; a VAT or sales-tax number elsewhere.
  final String? taxNumber;

  /// CIN in India; the company registration number elsewhere.
  final String? registrationNumber;
  final String? logoUrl;
  final String? updatedByName;

  /// The fields as the API names them - what the form edits and saves.
  Map<String, String?> toFields() => {
    'legal_name': legalName,
    'trading_name': tradingName,
    'address': address,
    'city': city,
    'state': state,
    'postal_code': postalCode,
    'country': country,
    'phone': phone,
    'email': email,
    'website': website,
    'tax_number': taxNumber,
    'registration_number': registrationNumber,
    'logo_url': logoUrl,
  };
}
