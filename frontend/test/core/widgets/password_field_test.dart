import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/password_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The password field every form in the app uses.
void main() {
  Widget wrap(TextEditingController controller, {String? Function(String?)? validator}) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Form(
          child: PasswordField(controller: controller, validator: validator),
        ),
      ),
    );
  }

  EditableText editable(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText));

  testWidgets('hides what is typed until asked otherwise', (tester) async {
    await tester.pumpWidget(wrap(TextEditingController()));

    expect(editable(tester).obscureText, isTrue);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('reveals the password on tap and hides it again', (tester) async {
    await tester.pumpWidget(wrap(TextEditingController()));

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(editable(tester).obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();

    expect(editable(tester).obscureText, isTrue);
  });

  testWidgets('revealing does not disturb what has been typed', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(wrap(controller));

    await tester.enterText(find.byType(TextFormField), 'Correct#Horse9');
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(controller.text, 'Correct#Horse9');
    expect(find.text('Correct#Horse9'), findsOneWidget);
  });

  testWidgets('rejects a password shorter than eight characters by default', (tester) async {
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Form(
            key: key,
            child: PasswordField(controller: TextEditingController(text: 'short')),
          ),
        ),
      ),
    );

    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('At least 8 characters'), findsOneWidget);
  });

  testWidgets('a caller can supply its own rule', (tester) async {
    // The edit-user form allows a blank value, meaning "keep the current one".
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Form(
            key: key,
            child: PasswordField(
              controller: TextEditingController(),
              validator: (value) => (value != null && value.isNotEmpty && value.length < 8) ? 'Too short' : null,
            ),
          ),
        ),
      ),
    );

    expect(key.currentState!.validate(), isTrue);
  });

  testWidgets('says what the toggle will do', (tester) async {
    await tester.pumpWidget(wrap(TextEditingController()));

    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(find.byTooltip('Hide password'), findsOneWidget);
  });
}
