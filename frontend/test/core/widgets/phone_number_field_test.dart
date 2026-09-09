import 'package:edutrack_app/core/widgets/phone_number_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Form(child: child)),
  );
}

void main() {
  testWidgets('composes the dial code and number into the controller', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(wrap(PhoneNumberField(controller: controller, label: 'Mobile')));

    await tester.enterText(find.byType(TextFormField), '9876543210');
    await tester.pump();

    expect(controller.text, '+91 9876543210');
  });

  testWidgets('an existing "+code number" value pre-fills the matching dial code and number', (tester) async {
    final controller = TextEditingController(text: '+44 7911123456');
    await tester.pumpWidget(wrap(PhoneNumberField(controller: controller, label: 'Mobile')));

    expect(find.text('🇬🇧 +44 GB'), findsOneWidget);
    expect(find.text('7911123456'), findsOneWidget);
  });

  testWidgets('a required empty field fails validation', (tester) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: PhoneNumberField(controller: controller, label: 'Phone', required: true),
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Phone is required'), findsOneWidget);
  });

  testWidgets('non-digit characters are rejected as the number is typed', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(wrap(PhoneNumberField(controller: controller, label: 'Mobile')));

    await tester.enterText(find.byType(TextFormField), '98a76-5 43210');
    await tester.pump();

    expect(controller.text, '+91 9876543210');
  });

  testWidgets('typing more digits than the selected country allows is capped', (tester) async {
    final controller = TextEditingController();
    // Default country is India - a fixed 10 digits.
    await tester.pumpWidget(wrap(PhoneNumberField(controller: controller, label: 'Mobile')));

    await tester.enterText(find.byType(TextFormField), '987654321098765');
    await tester.pump();

    expect(controller.text, '+91 9876543210');
  });

  testWidgets('a number shorter than the selected country expects fails validation', (tester) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            // India expects exactly 10 digits - 5 is too short.
            child: PhoneNumberField(controller: controller..text = '+91 98765', label: 'Mobile'),
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('India numbers are 10 digits'), findsOneWidget);
  });

  testWidgets('an optional empty field passes validation', (tester) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: PhoneNumberField(controller: controller, label: 'Mobile'),
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isTrue);
  });
}
