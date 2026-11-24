import 'package:edutrack_app/core/l10n/app_language.dart';
import 'package:edutrack_app/core/l10n/l10n.dart';
import 'package:edutrack_app/core/l10n/language_tile.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';

/// The phone apps' language (docs/mobile-apps-review.md, M11): the phone's
/// own unless the person picks English or Hindi, kept on the phone.
void main() {
  /// A phone app's shell, as main_driver/main_teacher/main_family build it.
  Widget phoneApp(InMemoryKeyValueStore store, {bool picker = true, Locale phone = const Locale('en')}) {
    return ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        languagePickerEnabledProvider.overrideWithValue(picker),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          locale: ref.watch(appLanguageProvider).locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // Stands for the phone's own language: used only when the app
          // forces none, as Flutter does.
          localeResolutionCallback: (forced, supported) {
            final wanted = ref.read(appLanguageProvider).locale ?? phone;
            return supported.firstWhere((l) => l.languageCode == wanted.languageCode, orElse: () => supported.first);
          },
          home: const Scaffold(body: LanguageTile()),
        ),
      ),
    );
  }

  test('a saved code reads back as its language; anything else is the phone', () {
    expect(AppLanguage.fromCode('hi'), AppLanguage.hindi);
    expect(AppLanguage.fromCode('en'), AppLanguage.english);
    expect(AppLanguage.fromCode(null), AppLanguage.phone);
    expect(AppLanguage.fromCode('ta'), AppLanguage.phone);
  });

  testWidgets('picking Hindi switches the app and is kept on the phone', (tester) async {
    final store = InMemoryKeyValueStore();
    await tester.pumpWidget(phoneApp(store));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text("Phone's language"), findsOneWidget);

    await tester.tap(find.byKey(const Key('language-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-hindi')));
    await tester.pumpAndSettle();

    expect(find.text('भाषा'), findsOneWidget, reason: 'the heading is now in Hindi');
    expect(find.text('भाषा बदल दी गई।'), findsOneWidget, reason: 'the confirmation is in the new language');
    expect(store.values[AppLanguageController.key], 'hi');
  });

  testWidgets('the choice survives a restart of the app', (tester) async {
    final store = InMemoryKeyValueStore()..values[AppLanguageController.key] = 'hi';

    await tester.pumpWidget(phoneApp(store));
    await tester.pumpAndSettle();

    expect(find.text('भाषा'), findsOneWidget);
  });

  testWidgets("back to the phone's language forgets the choice", (tester) async {
    final store = InMemoryKeyValueStore()..values[AppLanguageController.key] = 'hi';
    await tester.pumpWidget(phoneApp(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('language-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-phone')));
    await tester.pumpAndSettle();

    expect(store.values.containsKey(AppLanguageController.key), isFalse);
    expect(find.text('Language'), findsOneWidget);
  });

  testWidgets('a phone in Hindi starts in Hindi with nothing chosen', (tester) async {
    await tester.pumpWidget(phoneApp(InMemoryKeyValueStore(), phone: const Locale('hi')));
    await tester.pumpAndSettle();

    expect(find.text('भाषा'), findsOneWidget);
  });

  testWidgets('each option is written in its own language', (tester) async {
    await tester.pumpWidget(phoneApp(InMemoryKeyValueStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-tile')));
    await tester.pumpAndSettle();

    expect(find.text('English'), findsOneWidget);
    expect(find.text('हिन्दी'), findsOneWidget);
  });

  testWidgets('the web office, which stays English, has no picker', (tester) async {
    await tester.pumpWidget(phoneApp(InMemoryKeyValueStore(), picker: false));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('language-tile')), findsNothing);
  });

  testWidgets('a screen with no translations set up above it reads English', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Text(context.l10n.languageTitle))));

    expect(find.text('Language'), findsOneWidget);
  });
}
