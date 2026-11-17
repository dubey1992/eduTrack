import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/photo_picker.dart';
import 'package:edutrack_app/core/utils/picked_file.dart';
import 'package:edutrack_app/core/widgets/app_shell.dart';
import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/features/auth/application/auth_notifier.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/school_logo/application/school_logo_controller.dart';
import 'package:edutrack_app/features/school_logo/data/school_logo_repository.dart';
import 'package:edutrack_app/features/school_logo/presentation/logo_prompt.dart';
import 'package:edutrack_app/features/school_logo/presentation/school_logo_card.dart';
import 'package:edutrack_app/features/school_logo/presentation/school_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_photo_dio.dart';
import '../../support/in_memory_key_value_store.dart';

/// A school's logo (docs/school-logo.md, decided 2026-11-17): uploading it,
/// the reminder a School Admin gets at every sign-in until there is one, and
/// the banner and School Profile screen that go with it.
class FakeSchoolLogoRepository implements SchoolLogoRepository {
  FakeSchoolLogoRepository({this.failWith});

  Failure? failWith;
  final List<(int, String)> uploaded = [];
  final List<int> removed = [];

  @override
  Future<SchoolLogoResult> upload({required int schoolId, required List<int> bytes, required String fileName}) async {
    if (failWith != null) throw failWith!;
    uploaded.add((schoolId, fileName));
    return const SchoolLogoResult(logoUrl: '/schools/7/logo?v=abc', profileComplete: true);
  }

  @override
  Future<SchoolLogoResult> remove(int schoolId) async {
    if (failWith != null) throw failWith!;
    removed.add(schoolId);
    return const SchoolLogoResult(logoUrl: null, profileComplete: false);
  }
}

AuthenticatedUser admin({bool complete = false, UserRole role = UserRole.schoolAdmin}) => AuthenticatedUser(
  id: 3,
  name: 'Ravi Menon',
  email: 'ravi@example.com',
  role: role,
  schoolId: 7,
  schoolName: 'Riverside Public School',
  schoolLogoUrl: complete ? '/schools/7/logo?v=abc' : null,
  schoolProfileComplete: complete,
);

PickedFile png([String name = 'crest.png', int size = 100]) => PickedFile(name: name, bytes: List.filled(size, 1));

List<Override> overrides({
  required FakeSchoolLogoRepository logos,
  required FakeAuthRepository auth,
  PickedFile? picked,
}) => [
  schoolLogoRepositoryProvider.overrideWithValue(logos),
  authRepositoryProvider.overrideWithValue(auth),
  photoPickerProvider.overrideWithValue((_) async => picked),
  dioClientProvider.overrideWithValue(fakePhotoDio()),
  keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
];

void desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> pumpCard(
  WidgetTester tester, {
  required FakeSchoolLogoRepository logos,
  FakeAuthRepository? auth,
  PickedFile? picked,
  String? logoUrl,
}) async {
  desktop(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides(
        logos: logos,
        auth: auth ?? FakeAuthRepository(sessionOnRestore: admin()),
        picked: picked,
      ),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SchoolLogoCard(schoolId: 7, schoolName: 'Riverside Public School', logoUrl: logoUrl),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The signed-in frame on one page, so the reminder can open over it.
Future<ProviderContainer> pumpShell(WidgetTester tester, {required FakeAuthRepository auth}) async {
  desktop(tester);
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      for (final path in ['/dashboard', '/students', '/school-profile'])
        GoRoute(
          path: path,
          builder: (context, state) => AppShell(child: Center(child: Text('Page $path'))),
        ),
    ],
  );
  final container = ProviderContainer(
    overrides: overrides(logos: FakeSchoolLogoRepository(), auth: auth, picked: png()),
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('choosing a file', () {
    test('a PNG or JPEG of 2 MB or less is fine', () {
      expect(logoProblem(fileName: 'Crest.PNG', length: 1000), isNull);
      expect(logoProblem(fileName: 'crest.jpeg', length: maxLogoBytes), isNull);
    });

    test('anything else is refused with the reason', () {
      expect(logoProblem(fileName: 'crest.gif', length: 10), 'The logo must be a JPEG or PNG image.');
      expect(logoProblem(fileName: 'crest.png', length: maxLogoBytes + 1), 'The logo must be 2 MB or smaller.');
    });

    test('only a School Admin whose school has no logo is asked', () {
      expect(needsLogoPrompt(admin()), isTrue);
      expect(needsLogoPrompt(admin(complete: true)), isFalse);
      expect(needsLogoPrompt(admin(role: UserRole.teacher)), isFalse);
      expect(needsLogoPrompt(null), isFalse);
    });
  });

  group('the logo card', () {
    testWidgets('uploads the chosen image, says the profile is complete and refreshes the session', (tester) async {
      final logos = FakeSchoolLogoRepository();
      final auth = FakeAuthRepository(sessionOnRestore: admin());
      await pumpCard(tester, logos: logos, auth: auth, picked: png());
      final before = auth.restoreCalls;

      await tester.tap(find.byKey(const Key('school-logo-upload')));
      await tester.pumpAndSettle();

      expect(logos.uploaded, [(7, 'crest.png')]);
      expect(find.text('Logo saved. Your school profile is complete.'), findsOneWidget);
      expect(auth.restoreCalls, greaterThan(before));
      expect(find.text('Replace logo'), findsOneWidget);
    });

    testWidgets('a file that is not a JPEG or PNG is refused without being sent', (tester) async {
      final logos = FakeSchoolLogoRepository();
      await pumpCard(tester, logos: logos, picked: png('crest.gif'));

      await tester.tap(find.byKey(const Key('school-logo-upload')));
      await tester.pumpAndSettle();

      expect(logos.uploaded, isEmpty);
      expect(find.text('The logo must be a JPEG or PNG image.'), findsOneWidget);
    });

    testWidgets('a file over 2 MB is refused without being sent', (tester) async {
      final logos = FakeSchoolLogoRepository();
      await pumpCard(tester, logos: logos, picked: png('crest.png', maxLogoBytes + 1));

      await tester.tap(find.byKey(const Key('school-logo-upload')));
      await tester.pumpAndSettle();

      expect(logos.uploaded, isEmpty);
      expect(find.text('The logo must be 2 MB or smaller.'), findsOneWidget);
    });

    testWidgets("the server's refusal is shown under the logo", (tester) async {
      final logos = FakeSchoolLogoRepository(
        failWith: const Failure(
          code: 'VALIDATION_ERROR',
          message: 'The given data was invalid.',
          details: {
            'errors': {
              'logo': ['The logo must be a JPEG or PNG image.'],
            },
          },
        ),
      );
      await pumpCard(tester, logos: logos, picked: png());

      await tester.tap(find.byKey(const Key('school-logo-upload')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('school-logo-error')), findsOneWidget);
      expect(find.text('The logo must be a JPEG or PNG image.'), findsOneWidget);
      expect(find.text('Upload logo'), findsOneWidget);
    });

    testWidgets('a network failure says so and the button works again', (tester) async {
      final logos = FakeSchoolLogoRepository(failWith: Failure.network());
      await pumpCard(tester, logos: logos, picked: png());

      await tester.tap(find.byKey(const Key('school-logo-upload')));
      await tester.pumpAndSettle();

      expect(find.text(Failure.network().message), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(find.byKey(const Key('school-logo-upload')));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('cancelling the file chooser changes nothing', (tester) async {
      final logos = FakeSchoolLogoRepository();
      await pumpCard(tester, logos: logos);

      await tester.tap(find.byKey(const Key('school-logo-upload')));
      await tester.pumpAndSettle();

      expect(logos.uploaded, isEmpty);
      expect(find.byKey(const Key('school-logo-error')), findsNothing);
    });

    testWidgets('removing asks first, and keeping it changes nothing', (tester) async {
      final logos = FakeSchoolLogoRepository();
      await pumpCard(tester, logos: logos, logoUrl: '/schools/7/logo?v=abc');

      await tester.tap(find.byKey(const Key('school-logo-remove')));
      await tester.pumpAndSettle();
      expect(find.text('Remove the logo?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(logos.removed, isEmpty);

      await tester.tap(find.byKey(const Key('school-logo-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove logo').last);
      await tester.pumpAndSettle();

      expect(logos.removed, [7]);
      expect(find.text('Logo removed.'), findsOneWidget);
      expect(find.text('Upload logo'), findsOneWidget);
    });
  });

  group('the reminder at sign-in', () {
    testWidgets('a School Admin whose school has no logo is asked as soon as the app opens', (tester) async {
      await pumpShell(tester, auth: FakeAuthRepository(sessionOnRestore: admin()));

      expect(find.byKey(const Key('logo-prompt')), findsOneWidget);
      expect(find.text("Add your school's logo"), findsOneWidget);
      expect(find.byKey(const Key('school-logo-remove')), findsNothing);
    });

    testWidgets('"Remind me later" closes it, and moving around does not bring it back', (tester) async {
      await pumpShell(tester, auth: FakeAuthRepository(sessionOnRestore: admin()));

      await tester.tap(find.byKey(const Key('logo-prompt-later')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('logo-prompt')), findsNothing);

      final context = tester.element(find.text('Page /dashboard'));
      GoRouter.of(context).go('/students');
      await tester.pumpAndSettle();

      expect(find.text('Page /students'), findsOneWidget);
      expect(find.byKey(const Key('logo-prompt')), findsNothing);
    });

    testWidgets('the next sign-in asks again', (tester) async {
      final auth = FakeAuthRepository(sessionOnRestore: admin(), loginAs: admin());
      final container = await pumpShell(tester, auth: auth);
      await tester.tap(find.byKey(const Key('logo-prompt-later')));
      await tester.pumpAndSettle();

      await container.read(authNotifierProvider.notifier).logout();
      await container.read(authNotifierProvider.notifier).login(email: 'ravi@example.com', password: 'secret');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('logo-prompt')), findsOneWidget);
    });

    testWidgets('uploading from it closes it with the good news', (tester) async {
      await pumpShell(tester, auth: FakeAuthRepository(sessionOnRestore: admin()));

      await tester.tap(find.byKey(const Key('school-logo-upload')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('logo-prompt')), findsNothing);
      expect(find.text('Logo saved. Your school profile is complete.'), findsOneWidget);
    });

    testWidgets('a school that has its logo is not asked', (tester) async {
      await pumpShell(tester, auth: FakeAuthRepository(sessionOnRestore: admin(complete: true)));

      expect(find.byKey(const Key('logo-prompt')), findsNothing);
    });

    testWidgets('a teacher is never asked, even when the school has no logo', (tester) async {
      await pumpShell(
        tester,
        auth: FakeAuthRepository(sessionOnRestore: admin(role: UserRole.teacher)),
      );

      expect(find.byKey(const Key('logo-prompt')), findsNothing);
    });
  });

  group('folding the side panel', () {
    Future<void> ctrlB(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl + B folds it and brings it back, wherever the focus is', (tester) async {
      final container = await pumpShell(tester, auth: FakeAuthRepository(sessionOnRestore: admin(complete: true)));
      FocusManager.instance.primaryFocus?.unfocus();

      await ctrlB(tester);
      expect(container.read(navPanelOpenProvider), isFalse);
      expect(find.byKey(const Key('nav-panel')), findsNothing);

      await ctrlB(tester);
      expect(container.read(navPanelOpenProvider), isTrue);
      expect(find.byKey(const Key('nav-panel')), findsOneWidget);
    });

    testWidgets('B alone, or Ctrl + Shift + B, does nothing', (tester) async {
      final container = await pumpShell(tester, auth: FakeAuthRepository(sessionOnRestore: admin(complete: true)));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(container.read(navPanelOpenProvider), isTrue);
    });

    testWidgets('the button in the top bar folds it too', (tester) async {
      final container = await pumpShell(tester, auth: FakeAuthRepository(sessionOnRestore: admin(complete: true)));

      await tester.tap(find.byKey(const Key('nav-panel-toggle')));
      await tester.pumpAndSettle();

      expect(container.read(navPanelOpenProvider), isFalse);
    });
  });

  group('the banner and School Profile', () {
    testWidgets('the banner takes the admin to School Profile', (tester) async {
      desktop(tester);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: ProfileIncompleteBanner()),
          ),
          GoRoute(path: '/school-profile', builder: (context, state) => const Text('School Profile page')),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(theme: AppTheme.light(), routerConfig: router));

      expect(find.text('Your school profile is not complete.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-incomplete-upload')));
      await tester.pumpAndSettle();

      expect(find.text('School Profile page'), findsOneWidget);
    });

    Future<void> pumpProfile(WidgetTester tester, AuthenticatedUser user) async {
      desktop(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(
            logos: FakeSchoolLogoRepository(),
            auth: FakeAuthRepository(sessionOnRestore: user),
          ),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SchoolProfileScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('School Profile says a logo is needed, and offers the upload', (tester) async {
      await pumpProfile(tester, admin());

      expect(find.byKey(const Key('school-profile-incomplete')), findsOneWidget);
      expect(find.text('Upload logo'), findsOneWidget);
      expect(find.text('RP'), findsOneWidget);
    });

    testWidgets('with a logo, School Profile says the profile is complete', (tester) async {
      await pumpProfile(tester, admin(complete: true));

      expect(find.byKey(const Key('school-profile-complete')), findsOneWidget);
      expect(find.text('Replace logo'), findsOneWidget);
      expect(find.byKey(const Key('school-logo-remove')), findsOneWidget);
    });
  });
}
