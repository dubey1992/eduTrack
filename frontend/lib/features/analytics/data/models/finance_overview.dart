/// Finance analytics, A5 (docs/analytics.md), as `GET /analytics/finance`
/// sends it.
///
/// Every amount is one currency's - exact, as the server sent it - and is
/// never added to another. A month the nightly snapshot had not yet
/// recorded ages for has no overdue-by-age figure, rather than a zero.
library;

/// One currency's numbers in one place: the keys differ by section
/// (`due`, `collected`, `overdue_0_30`, `fees_in`...), so they are kept by
/// name and read by the section that knows them.
class CurrencyAmounts {
  const CurrencyAmounts({required this.currencyCode, required this.values, this.rate});

  factory CurrencyAmounts.fromJson(Map<String, dynamic> json) {
    return CurrencyAmounts(
      currencyCode: json['currency_code'] as String,
      rate: (json['rate'] as num?)?.toDouble(),
      // Every amount, which the server sends as exact text; a row's other
      // text (a class's name, the currency) is not an amount and is left out.
      values: {
        for (final entry in json.entries)
          if (entry.key != 'currency_code' && entry.value is String && double.tryParse(entry.value as String) != null)
            entry.key: double.parse(entry.value as String),
      },
    );
  }

  final String currencyCode;
  final Map<String, double> values;

  /// A percentage where the section has one (collection, by class).
  final double? rate;

  double operator [](String key) => values[key] ?? 0;
}

/// One month of one section: its span and one line per currency, or null
/// where nothing was recorded.
class FinanceMonth {
  const FinanceMonth({required this.from, required this.to, this.amounts, this.asOf});

  factory FinanceMonth.fromJson(Map<String, dynamic> json) {
    final amounts = json['amounts'] as List<dynamic>?;

    return FinanceMonth(
      from: json['from'] as String,
      to: json['to'] as String,
      asOf: json['as_of'] as String?,
      amounts: amounts?.map((row) => CurrencyAmounts.fromJson(row as Map<String, dynamic>)).toList(),
    );
  }

  final String from;
  final String to;

  /// For overdue by age: the night the figures were recorded.
  final String? asOf;
  final List<CurrencyAmounts>? amounts;

  CurrencyAmounts? currency(String code) => amounts?.where((line) => line.currencyCode == code).firstOrNull;
}

class ClassFinance {
  const ClassFinance({required this.classSection, required this.amounts});

  factory ClassFinance.fromJson(Map<String, dynamic> json) {
    return ClassFinance(classSection: json['class_section'] as String, amounts: CurrencyAmounts.fromJson(json));
  }

  final String classSection;
  final CurrencyAmounts amounts;
}

class FinanceOverview {
  const FinanceOverview({
    required this.asOf,
    required this.collection,
    required this.overdueByAge,
    required this.byClass,
    required this.upcoming,
    this.feesVsPayroll,
  });

  factory FinanceOverview.fromJson(Map<String, dynamic> json) {
    List<FinanceMonth> months(Object? raw) =>
        ((raw as List<dynamic>?) ?? const []).map((row) => FinanceMonth.fromJson(row as Map<String, dynamic>)).toList();

    return FinanceOverview(
      asOf: json['as_of'] as String,
      collection: months(json['collection']),
      overdueByAge: months(json['overdue_by_age']),
      byClass: (json['by_class'] as List<dynamic>)
          .map((row) => ClassFinance.fromJson(row as Map<String, dynamic>))
          .toList(),
      upcoming: months(json['upcoming']),
      feesVsPayroll: json.containsKey('fees_vs_payroll') ? months(json['fees_vs_payroll']) : null,
    );
  }

  final String asOf;
  final List<FinanceMonth> collection;
  final List<FinanceMonth> overdueByAge;
  final List<ClassFinance> byClass;
  final List<FinanceMonth> upcoming;

  /// Null for someone who may read fees but not payroll.
  final List<FinanceMonth>? feesVsPayroll;

  /// Every currency anywhere in it, in order - one block of figures each.
  List<String> get currencies {
    final codes = <String>{
      for (final month in [...collection, ...overdueByAge, ...upcoming, ...?feesVsPayroll])
        for (final line in month.amounts ?? const <CurrencyAmounts>[]) line.currencyCode,
      for (final row in byClass) row.amounts.currencyCode,
    };

    return codes.toList()..sort();
  }

  bool get isEmpty => currencies.isEmpty;
}
