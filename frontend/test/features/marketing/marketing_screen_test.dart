import 'package:edutrack_app/features/marketing/presentation/marketing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget wrap() {
  return MaterialApp.router(
    routerConfig: GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const MarketingScreen()),
        GoRoute(
          path: '/login',
          builder: (context, state) => const Scaffold(body: Text('Login Screen')),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('shows the hero headline, feature grid and footer', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Run Your School Smarter, Together.'), findsOneWidget);
    expect(find.text('Powerful Features for Modern Schools'), findsOneWidget);
    expect(find.text('Student Management'), findsOneWidget);
    expect(find.text('Be Part of the Future of Education'), findsOneWidget);
    expect(find.text('© 2026 School365ai. All rights reserved.'), findsOneWidget);
  });

  testWidgets('tapping Login navigates to the login route', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('Login Screen'), findsOneWidget);
  });

  testWidgets('tapping Join Early Access shows a custom dialog, not a JS alert', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Join Early Access').first);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Thanks for your interest!'), findsOneWidget);
  });
}
