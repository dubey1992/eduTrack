import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/async_value_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(AsyncValue<String> value, {VoidCallback? onRetry}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: AsyncValueView<String>(value: value, onRetry: onRetry, data: (context, data) => Text(data)),
    ),
  );
}

void main() {
  testWidgets('an ordinary failure shows its message and a retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _wrap(
        const AsyncError(Failure(code: 'UNKNOWN_ERROR', message: 'Something went wrong.'), StackTrace.empty),
        onRetry: () => retried = true,
      ),
    );

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('a switched-off module shows the server\'s sentence, quietly, with no retry', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AsyncError(
          Failure(code: Failure.moduleDisabledCode, message: 'Student Attendance is switched off for this school.'),
          StackTrace.empty,
        ),
        onRetry: () {},
      ),
    );

    expect(find.text('Student Attendance is switched off for this school.'), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    // Trying again cannot switch the module back on.
    expect(find.text('Retry'), findsNothing);
  });

  test('Failure knows the code', () {
    expect(const Failure(code: 'MODULE_DISABLED', message: 'x').isModuleDisabled, isTrue);
    expect(const Failure(code: 'FORBIDDEN', message: 'x').isModuleDisabled, isFalse);
  });
}
