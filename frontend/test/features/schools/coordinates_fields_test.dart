import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/schools/presentation/widgets/coordinates_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where a school is. Optional, but the pair goes together - half a
/// coordinate points nowhere, and the API refuses it.
void main() {
  late TextEditingController latitude;
  late TextEditingController longitude;
  late GlobalKey<FormState> formKey;

  setUp(() {
    latitude = TextEditingController();
    longitude = TextEditingController();
    formKey = GlobalKey<FormState>();
  });

  Widget wrap() {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Form(
          key: formKey,
          child: CoordinatesFields(latitude: latitude, longitude: longitude),
        ),
      ),
    );
  }

  testWidgets('accepts a school with no coordinate at all', (tester) async {
    await tester.pumpWidget(wrap());

    expect(formKey.currentState!.validate(), isTrue);
  });

  testWidgets('accepts a valid pair', (tester) async {
    await tester.pumpWidget(wrap());

    await tester.enterText(find.widgetWithText(TextFormField, 'Latitude (optional)'), '18.5204');
    await tester.enterText(find.widgetWithText(TextFormField, 'Longitude (optional)'), '73.8567');

    expect(formKey.currentState!.validate(), isTrue);
  });

  testWidgets('refuses half a coordinate', (tester) async {
    await tester.pumpWidget(wrap());

    await tester.enterText(find.widgetWithText(TextFormField, 'Latitude (optional)'), '18.5204');

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Enter a longitude too, or clear the other box.'), findsOneWidget);
  });

  testWidgets('refuses a latitude beyond the poles', (tester) async {
    await tester.pumpWidget(wrap());

    await tester.enterText(find.widgetWithText(TextFormField, 'Latitude (optional)'), '91');
    await tester.enterText(find.widgetWithText(TextFormField, 'Longitude (optional)'), '73.8567');

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.textContaining('between -90.0 and 90.0'), findsOneWidget);
  });

  testWidgets('refuses a longitude beyond the meridian', (tester) async {
    await tester.pumpWidget(wrap());

    await tester.enterText(find.widgetWithText(TextFormField, 'Latitude (optional)'), '18.5204');
    await tester.enterText(find.widgetWithText(TextFormField, 'Longitude (optional)'), '181');

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.textContaining('between -180.0 and 180.0'), findsOneWidget);
  });

  testWidgets('takes a negative coordinate for the other side of the world', (tester) async {
    await tester.pumpWidget(wrap());

    await tester.enterText(find.widgetWithText(TextFormField, 'Latitude (optional)'), '-33.8688');
    await tester.enterText(find.widgetWithText(TextFormField, 'Longitude (optional)'), '-151.2093');

    expect(formKey.currentState!.validate(), isTrue);
  });

  testWidgets('keeps letters out of the box', (tester) async {
    await tester.pumpWidget(wrap());

    await tester.enterText(find.widgetWithText(TextFormField, 'Latitude (optional)'), '18.5N');

    expect(latitude.text, '18.5');
  });
}
