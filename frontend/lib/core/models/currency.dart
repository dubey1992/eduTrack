/// A curated list of common currencies for the school-creation dropdown.
/// The backend doesn't restrict to this list (see backend CLAUDE.md rule 5
/// - any 3-letter ISO 4217 code is accepted); this is purely a UX
/// convenience so most admins never need to type a code by hand.
class Currency {
  const Currency(this.code, this.label);

  final String code;
  final String label;

  static const common = [
    Currency('INR', 'Indian Rupee (INR)'),
    Currency('USD', 'US Dollar (USD)'),
    Currency('GBP', 'British Pound (GBP)'),
    Currency('EUR', 'Euro (EUR)'),
    Currency('AED', 'UAE Dirham (AED)'),
    Currency('SAR', 'Saudi Riyal (SAR)'),
    Currency('NGN', 'Nigerian Naira (NGN)'),
    Currency('KES', 'Kenyan Shilling (KES)'),
    Currency('ZAR', 'South African Rand (ZAR)'),
    Currency('PKR', 'Pakistani Rupee (PKR)'),
    Currency('BDT', 'Bangladeshi Taka (BDT)'),
    Currency('PHP', 'Philippine Peso (PHP)'),
    Currency('IDR', 'Indonesian Rupiah (IDR)'),
    Currency('MYR', 'Malaysian Ringgit (MYR)'),
    Currency('SGD', 'Singapore Dollar (SGD)'),
    Currency('AUD', 'Australian Dollar (AUD)'),
    Currency('CAD', 'Canadian Dollar (CAD)'),
  ];
}
