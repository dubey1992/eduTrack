import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/core/routing/app_router.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/auth/application/auth_notifier.dart';
import 'package:edutrack_app/features/auth/data/attendant_auth_api.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/presentation/attendant_login_screen.dart';
import 'package:edutrack_app/features/auth/presentation/login_screen.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/my_trip/data/my_trip_api.dart';
import 'package:edutrack_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_attendant_auth_api.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_auth_token_storage.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/my_trip_fixtures.dart';

void main() {
  late FakeAttendantAuthApi api;
  late InMemoryKeyValueStore store;
  late FakeAuthTokenStorage tokens;

  setUp(() {
    api = FakeAttendantAuthApi();
    store = InMemoryKeyValueStore();
    tokens = FakeAuthTokenStorage();
  });

  /// A phone this attendant registered earlier.
  void registerPhone() {
    store.values['attendant_mobile'] = '+91 9876543210';
    store.values['attendant_device_secret'] = 'stored-secret';
  }

  List<Override> overrides() => [
    authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
    attendantAuthApiProvider.overrideWithValue(api),
    authTokenStorageProvider.overrideWithValue(tokens),
    keyValueStoreProvider.overrideWithValue(store),
  ];

  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: AttendantLoginScreen()),
      ),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(AttendantLoginScreen)));
    // In the app the router has read the session long before anybody signs
    // in; here it is read now, so its start-up check is over first.
    container.read(authNotifierProvider);
    await tester.pumpAndSettle();
    return container;
  }

  Finder field(String key) => find.byKey(Key(key));

  Future<void> submit(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ElevatedButton, label));
    await tester.pumpAndSettle();
  }

  Future<void> fillRegisterForm(
    WidgetTester tester, {
    String mobile = '9876543210',
    String setupCode = '12345678',
    String passcode = '4827',
    String? confirm,
  }) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Mobile'), mobile);
    await tester.enterText(field('attendant-setup-code'), setupCode);
    await tester.enterText(field('attendant-new-passcode'), passcode);
    await tester.enterText(field('attendant-confirm-passcode'), confirm ?? passcode);
  }

  group('a phone that is not registered', () {
    testWidgets('asks to register it with a setup code', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Register this phone'), findsOneWidget);
      expect(field('attendant-setup-code'), findsOneWidget);
      expect(field('attendant-new-passcode'), findsOneWidget);
      expect(field('attendant-confirm-passcode'), findsOneWidget);
      expect(field('attendant-passcode'), findsNothing);
    });

    testWidgets('checks the passcode rules before asking the server', (tester) async {
      await pumpScreen(tester);

      Future<void> tryPasscode(String passcode, String message, {String? confirm}) async {
        await fillRegisterForm(tester, passcode: passcode, confirm: confirm);
        await submit(tester, 'Register and sign in');
        expect(find.text(message), findsOneWidget, reason: passcode);
      }

      await tryPasscode('482', 'The passcode must be exactly 4 digits.');
      await tryPasscode('7777', 'Choose a passcode that is not one digit repeated.');
      await tryPasscode('1234', 'Choose a passcode that is not a straight run like 1234.');
      await tryPasscode('4827', 'The passcodes do not match', confirm: '4872');

      expect(api.setupCalls, isEmpty);
    });

    testWidgets('needs the whole 8-digit setup code and a mobile number', (tester) async {
      await pumpScreen(tester);

      await fillRegisterForm(tester, mobile: '', setupCode: '1234');
      await submit(tester, 'Register and sign in');

      expect(find.text('Enter the 8-digit setup code from your office'), findsOneWidget);
      expect(find.text('Mobile is required'), findsOneWidget);
      expect(api.setupCalls, isEmpty);
    });

    testWidgets('registering keeps the device secret and the session token, and signs in', (tester) async {
      final container = await pumpScreen(tester);

      await fillRegisterForm(tester);
      await submit(tester, 'Register and sign in');

      expect(api.setupCalls.single, {'mobile': '+91 9876543210', 'setup_code': '12345678', 'passcode': '4827'});
      expect(store.values['attendant_device_secret'], 'secret-from-the-server');
      expect(store.values['attendant_mobile'], '+91 9876543210');
      expect(await tokens.readToken(), 'attendant-token');
      expect(container.read(authNotifierProvider).value?.role, UserRole.busAttendant);
    });

    testWidgets('an expired setup code is explained', (tester) async {
      const message = 'That setup code is wrong or has expired. Ask your school office for a new one.';
      api.error = apiError('/auth/attendant/setup', 401, 'WRONG_PASSCODE', message);
      await pumpScreen(tester);

      await fillRegisterForm(tester);
      await submit(tester, 'Register and sign in');

      expect(find.text(message), findsOneWidget);
      expect(store.values['attendant_device_secret'], isNull);
      expect(await tokens.readToken(), isNull);
    });
  });

  group('a registered phone', () {
    testWidgets('asks only for the passcode, with the number filled in', (tester) async {
      registerPhone();
      await pumpScreen(tester);

      expect(find.text('Bus attendant sign in'), findsOneWidget);
      expect(field('attendant-passcode'), findsOneWidget);
      expect(field('attendant-setup-code'), findsNothing);
      expect(find.widgetWithText(TextFormField, '9876543210'), findsOneWidget);
    });

    testWidgets('the passcode is hidden, and typed on a number pad', (tester) async {
      registerPhone();
      await pumpScreen(tester);

      final editable = tester.widget<EditableText>(
        find.descendant(of: field('attendant-passcode'), matching: find.byType(EditableText)),
      );
      expect(editable.obscureText, isTrue);
      expect(editable.keyboardType, TextInputType.number);
    });

    testWidgets('signs in with the stored secret', (tester) async {
      registerPhone();
      final container = await pumpScreen(tester);

      await tester.enterText(field('attendant-passcode'), '4827');
      await submit(tester, 'Sign In');

      expect(api.loginCalls.single, {'mobile': '+91 9876543210', 'passcode': '4827', 'device_secret': 'stored-secret'});
      expect(await tokens.readToken(), 'attendant-token');
      expect(container.read(authNotifierProvider).value?.name, 'Asha Attendant');
    });

    testWidgets('a wrong passcode says how many tries are left, and clears the field', (tester) async {
      registerPhone();
      api.error = apiError('/auth/attendant/login', 401, 'WRONG_PASSCODE', 'Wrong passcode. 3 tries left.');
      await pumpScreen(tester);

      await tester.enterText(field('attendant-passcode'), '4828');
      await submit(tester, 'Sign In');

      expect(find.text('Wrong passcode. 3 tries left.'), findsOneWidget);
      expect(find.text('4828'), findsNothing);
      expect(field('attendant-passcode'), findsOneWidget);
      expect(store.values['attendant_device_secret'], 'stored-secret');
    });

    testWidgets('a locked account says who can unlock it', (tester) async {
      registerPhone();
      const message = 'Too many wrong tries. Ask your school office to unlock your account.';
      api.error = apiError('/auth/attendant/login', 423, 'ACCOUNT_LOCKED', message);
      await pumpScreen(tester);

      await tester.enterText(field('attendant-passcode'), '4827');
      await submit(tester, 'Sign In');

      expect(find.text(message), findsOneWidget);
    });

    testWidgets('a phone the school no longer knows forgets its secret and asks to register again', (tester) async {
      registerPhone();
      const message = 'This phone is not registered for that mobile number. Ask your school office for a setup code.';
      api.error = apiError('/auth/attendant/login', 401, 'DEVICE_NOT_REGISTERED', message);
      await pumpScreen(tester);

      await tester.enterText(field('attendant-passcode'), '4827');
      await submit(tester, 'Sign In');

      expect(find.text(message), findsOneWidget);
      expect(find.text('Register this phone'), findsOneWidget);
      expect(field('attendant-setup-code'), findsOneWidget);
      expect(store.values['attendant_device_secret'], isNull);
      // The number stays, so it need not be typed again.
      expect(find.widgetWithText(TextFormField, '9876543210'), findsOneWidget);
    });

    testWidgets('a passcode is required before asking the server', (tester) async {
      registerPhone();
      await pumpScreen(tester);

      await submit(tester, 'Sign In');

      expect(find.text('Enter your 4-digit passcode'), findsOneWidget);
      expect(api.loginCalls, isEmpty);
    });
  });

  group('in the app', () {
    Future<GoRouterForTest> pumpApp(WidgetTester tester) async {
      // Wide: the app opens on the marketing page, laid out for a desktop.
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides(),
            myTripApiProvider.overrideWithValue(FakeMyTripApi()),
            locationSourceProvider.overrideWithValue(FakeLocationSource(access: LocationAccess.denied)),
          ],
          child: const EduTrackApp(),
        ),
      );
      await tester.pumpAndSettle();
      return GoRouterForTest(tester);
    }

    testWidgets('the email sign-in page offers the attendant sign-in', (tester) async {
      final router = await pumpApp(tester);
      router.go('/login');
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.tap(find.text('Bus attendant? Sign in with your mobile number'));
      await tester.pumpAndSettle();

      expect(find.byType(AttendantLoginScreen), findsOneWidget);
      expect(router.path, '/attendant-login');
    });

    testWidgets('signing in lands on My Trip', (tester) async {
      registerPhone();
      final router = await pumpApp(tester);
      router.go('/attendant-login');
      await tester.pumpAndSettle();

      await tester.enterText(field('attendant-passcode'), '4827');
      await submit(tester, 'Sign In');

      expect(router.path, '/my-trip');
      expect(find.text('North Loop'), findsOneWidget);
    });
  });
}

/// The app's router, read off the running app.
class GoRouterForTest {
  GoRouterForTest(this._tester);

  final WidgetTester _tester;

  ProviderContainer get _container => ProviderScope.containerOf(_tester.element(find.byType(MaterialApp)));

  void go(String location) => _container.read(routerProvider).go(location);

  String get path => _container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;
}
