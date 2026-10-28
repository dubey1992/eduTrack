import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/company_details/data/company_details_repository.dart';
import 'package:edutrack_app/features/company_details/data/models/company_details.dart';
import 'package:edutrack_app/features/company_details/presentation/company_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// School365ai's own business details (docs/pdf-design.md, phase 5): the
/// form, what it checks before sending, what it sends, and what it does with
/// a refusal.

class _FakeCompanyRepository implements CompanyDetailsRepository {
  _FakeCompanyRepository({this.details = const CompanyDetails(isSaved: false), this.failLoad, this.failSave});

  CompanyDetails details;
  final Failure? failLoad;
  final Failure? failSave;
  final saves = <Map<String, String>>[];

  @override
  Future<CompanyDetails> get() async {
    if (failLoad != null) throw failLoad!;
    return details;
  }

  @override
  Future<CompanyDetails> save(Map<String, String> fields) async {
    saves.add(fields);
    if (failSave != null) throw failSave!;
    details = CompanyDetails(isSaved: true, legalName: fields['legal_name'], updatedByName: 'Root');
    return details;
  }
}

Widget _wrap(_FakeCompanyRepository fake) => ProviderScope(
  retry: (retryCount, error) => null,
  overrides: [companyDetailsRepositoryProvider.overrideWithValue(fake)],
  child: MaterialApp(
    theme: AppTheme.light(),
    home: const Scaffold(body: CompanyDetailsScreen()),
  ),
);

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void _useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('before the first save it says what receipts carry, and every field is there', (tester) async {
    _useDesktop(tester);
    await tester.pumpWidget(_wrap(_FakeCompanyRepository()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Until these are saved, receipts carry the name "School365ai"'), findsOneWidget);
    for (final label in ['Legal name *', 'Trading name', 'Tax number', 'Street address', 'Billing email', 'Website']) {
      expect(_field(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the legal name is required and bad values are caught before sending', (tester) async {
    _useDesktop(tester);
    final fake = _FakeCompanyRepository();
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    await tester.enterText(_field('Billing email'), 'not-an-email');
    await tester.enterText(_field('Website'), 'not a site');
    await tester.enterText(_field('Logo address'), 'file:///x.png');
    await tester.tap(find.widgetWithText(FilledButton, 'Save details'));
    await tester.pumpAndSettle();

    expect(find.text('Enter the legal name.'), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter a web address, such as school365ai.com.'), findsOneWidget);
    expect(find.text('The logo must be an http(s) address of an image.'), findsOneWidget);
    expect(fake.saves, isEmpty);
  });

  testWidgets('saving sends every field trimmed, and says so', (tester) async {
    _useDesktop(tester);
    final fake = _FakeCompanyRepository();
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    await tester.enterText(_field('Legal name *'), '  School365 AI Private Limited ');
    await tester.enterText(_field('Tax number'), '27ABCDE1234F1Z5');
    await tester.enterText(_field('Billing email'), 'billing@school365ai.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Save details'));
    await tester.pumpAndSettle();

    final sent = fake.saves.single;
    expect(sent['legal_name'], 'School365 AI Private Limited');
    expect(sent['tax_number'], '27ABCDE1234F1Z5');
    expect(sent['phone'], '');
    expect(find.text('Company details saved. New receipts will carry them.'), findsOneWidget);
  });

  testWidgets('a refusal is shown on the form and its field', (tester) async {
    _useDesktop(tester);
    final fake = _FakeCompanyRepository(
      failSave: const Failure(
        code: 'VALIDATION_ERROR',
        message: 'The given data was invalid.',
        details: {
          'errors': {
            'tax_number': ['The tax number field must not be greater than 30 characters.'],
          },
        },
      ),
    );
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    await tester.enterText(_field('Legal name *'), 'School365 AI');
    await tester.tap(find.widgetWithText(FilledButton, 'Save details'));
    await tester.pumpAndSettle();

    expect(find.text('The given data was invalid.'), findsOneWidget);
    expect(find.text('The tax number field must not be greater than 30 characters.'), findsOneWidget);
  });

  testWidgets('saved details fill the form', (tester) async {
    _useDesktop(tester);
    await tester.pumpWidget(
      _wrap(
        _FakeCompanyRepository(
          details: const CompanyDetails(isSaved: true, legalName: 'School365 AI', city: 'Pune', updatedByName: 'Root'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'School365 AI'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Pune'), findsOneWidget);
    expect(find.text('Last saved by Root.'), findsOneWidget);
  });

  testWidgets('details that cannot be read offer a retry, not a blank page', (tester) async {
    _useDesktop(tester);
    await tester.pumpWidget(
      _wrap(
        _FakeCompanyRepository(
          failLoad: const Failure(code: 'SERVER_ERROR', message: 'Something went wrong.'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
  });
}
