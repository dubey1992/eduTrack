import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/routing/family_router.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/phone_number_field.dart';
import 'package:edutrack_app/features/auth/data/passcode_rules.dart';
import 'package:edutrack_app/features/family/data/family_auth_repository.dart';
import 'package:edutrack_app/features/family/data/family_device_storage.dart';
import 'package:edutrack_app/features/family/data/family_repository.dart';
import 'package:edutrack_app/features/family/data/models/family_day.dart';
import 'package:edutrack_app/features/family/presentation/family_pdf.dart';
import 'package:edutrack_app/features/family/presentation/family_more_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';

/// The whole Family app on a phone-sized screen, on fakes. Starts signed in
/// unless [auth] says otherwise.
Future<(FakeFamilyRepository, FakeFamilyAuthRepository, List<Uri>)> pumpFamilyApp(
  WidgetTester tester, {
  FakeFamilyRepository? data,
  FakeFamilyAuthRepository? auth,
  String? goTo,
  PdfHandOff? onPdf,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repository = data ?? FakeFamilyRepository();
  final session = auth ?? FakeFamilyAuthRepository(account: familyAccount());
  final opened = <Uri>[];

  final container = ProviderContainer(
    overrides: [
      familyRepositoryProvider.overrideWithValue(repository),
      familyAuthRepositoryProvider.overrideWithValue(session),
      if (onPdf != null) pdfHandOffProvider.overrideWithValue(onPdf),
      externalOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return true;
      }),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) =>
            MaterialApp.router(theme: AppTheme.familyLight(), routerConfig: ref.watch(familyRouterProvider)),
      ),
    ),
  );
  await tester.pumpAndSettle();

  if (goTo != null) {
    container.read(familyRouterProvider).go(goTo);
    await tester.pumpAndSettle();
  }

  return (repository, session, opened);
}

void main() {
  group('signing in', () {
    testWidgets('a phone not set up asks for the letter\'s code and checks every field', (tester) async {
      final (_, auth, _) = await pumpFamilyApp(tester, auth: FakeFamilyAuthRepository());

      expect(find.text('Set up the Family app'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('family-setup-code')), '1234');
      await tester.enterText(find.byKey(const Key('family-new-passcode')), '111111');
      await tester.enterText(find.byKey(const Key('family-confirm-passcode')), '222222');
      await tester.tap(find.byKey(const Key('family-sign-in')));
      await tester.pumpAndSettle();

      expect(find.text('Enter the 8-digit setup code from the school\'s letter.'), findsOneWidget);
      expect(find.text('Choose a passcode that is not one digit repeated.'), findsOneWidget);
      expect(find.text('The two passcodes are not the same.'), findsOneWidget);
      expect(auth.setups, isEmpty);
    });

    testWidgets('a good code and passcode sign in and land on Home', (tester) async {
      final (_, auth, _) = await pumpFamilyApp(tester, auth: FakeFamilyAuthRepository());

      await tester.enterText(
        find.descendant(of: find.byType(PhoneNumberField), matching: find.byType(TextField)).last,
        '9876543210',
      );
      await tester.enterText(find.byKey(const Key('family-setup-code')), '48271593');
      await tester.enterText(find.byKey(const Key('family-new-passcode')), '482915');
      await tester.enterText(find.byKey(const Key('family-confirm-passcode')), '482915');
      await tester.tap(find.byKey(const Key('family-sign-in')));
      await tester.pumpAndSettle();

      expect(auth.setups.single['setup_code'], '48271593');
      expect(find.byKey(const Key('family-home')), findsOneWidget);
    });

    testWidgets('a set-up phone asks for the passcode, and says what the school refused', (tester) async {
      final auth = FakeFamilyAuthRepository(
        device: const FamilyDevice(mobile: '+91 9876543210', secret: 'secret'),
        failWith: const Failure(code: 'INVALID_CREDENTIALS', message: 'That mobile number or passcode is wrong.'),
      );
      await pumpFamilyApp(tester, auth: auth);

      expect(find.text('Welcome back'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('family-passcode')), '482915');
      await tester.tap(find.byKey(const Key('family-sign-in')));
      await tester.pumpAndSettle();

      expect(find.text('That mobile number or passcode is wrong.'), findsOneWidget);
      expect(find.byKey(const Key('family-home')), findsNothing);
    });

    testWidgets('a phone the school removed goes back to the setup code', (tester) async {
      final auth = FakeFamilyAuthRepository(
        device: const FamilyDevice(mobile: '+91 9876543210', secret: 'secret'),
        failWith: const Failure(
          code: FamilyAuthRepository.deviceNotRegisteredCode,
          message: 'This phone is not registered any more.',
        ),
      );
      await pumpFamilyApp(tester, auth: auth);

      await tester.enterText(find.byKey(const Key('family-passcode')), '482915');
      await tester.tap(find.byKey(const Key('family-sign-in')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('family-setup-code')), findsOneWidget);
    });

    test('a parent\'s passcode is six digits, not a run', () {
      expect(passcodeProblem('48291', length: 6), 'The passcode must be exactly 6 digits.');
      expect(passcodeProblem('123456', length: 6), contains('straight run'));
      expect(passcodeProblem('482915', length: 6), isNull);
      // The bus crew's four digits are unchanged.
      expect(passcodeProblem('4829'), isNull);
    });
  });

  group('Home', () {
    testWidgets('says the child is in school, with the bus, the fee and the latest notice', (tester) async {
      final data = FakeFamilyRepository(
        today: familyToday(
          bus: const TodayBus(
            route: 'Route 3',
            stop: 'Gate 2',
            pickupTime: '07:30',
            dropTime: '14:10',
            trips: [
              BusTrip(
                direction: 'pickup',
                status: 'completed',
                riderStatus: 'dropped',
                boardedAt: '07:32',
                droppedAt: '07:58',
              ),
            ],
          ),
          fee: NextFee(
            label: 'Term 2',
            dueDate: DateTime(2026, 11, 17),
            amount: 3500,
            currencyCode: 'INR',
            isOverdue: false,
          ),
        ),
      );
      await pumpFamilyApp(tester, data: data);

      expect(find.text('Aarav is in school'), findsOneWidget);
      expect(find.text('Reached school'), findsOneWidget);
      expect(find.textContaining('3,500'), findsOneWidget);
      expect(find.textContaining('due on 11/17/2026'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Sports day'), 200);
      expect(find.text('1 new'), findsOneWidget);
    });

    testWidgets('an absence shows in red words with the teacher\'s note', (tester) async {
      await pumpFamilyApp(
        tester,
        data: FakeFamilyRepository(
          today: familyToday(mark: AttendanceMark.absent, remarks: 'Fever'),
        ),
      );

      expect(find.text('Aarav was marked absent'), findsOneWidget);
      expect(find.text('Note: Fever'), findsOneWidget);
    });

    testWidgets('a holiday says there is no school', (tester) async {
      await pumpFamilyApp(
        tester,
        data: FakeFamilyRepository(today: familyToday(isOpen: false, holiday: 'Diwali')),
      );

      expect(find.text('No school today'), findsOneWidget);
      expect(find.text('Diwali'), findsOneWidget);
    });

    testWidgets('a failure says so and tries again', (tester) async {
      final data = FakeFamilyRepository(failTodayWith: Failure.network());
      await pumpFamilyApp(tester, data: data);

      expect(find.text('No connection'), findsOneWidget);

      data.failTodayWith = null;
      await tester.tap(find.byKey(const Key('family-retry')));
      await tester.pumpAndSettle();

      expect(find.text('Aarav is in school'), findsOneWidget);
    });

    testWidgets('with two children the switcher changes whose day it is', (tester) async {
      final data = FakeFamilyRepository();
      data.todayFor[diya.id] = familyToday(mark: AttendanceMark.leave);
      await pumpFamilyApp(
        tester,
        data: data,
        auth: FakeFamilyAuthRepository(account: familyAccount(children: const [aarav, diya])),
      );

      expect(find.text('Aarav is in school'), findsOneWidget);
      await tester.tap(find.byKey(const Key('family-child-switcher')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('family-child-${diya.id}')));
      await tester.pumpAndSettle();

      expect(find.text('Diya is on leave today'), findsOneWidget);
      expect(data.todayAskedFor, contains(diya.id));
    });
  });

  group('Attendance', () {
    testWidgets('shows the year and the month with their rates, and why a day was missed', (tester) async {
      await pumpFamilyApp(tester, goTo: '/attendance');

      expect(find.text('This school year'), findsOneWidget);
      expect(find.text('90%'), findsOneWidget);
      expect(find.text('Present 108 of 120 days · absent 10 · leave 2'), findsOneWidget);
      expect(find.text('4 school days not marked by the school'), findsOneWidget);
      expect(find.byKey(const Key('family-day-2026-11-04')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('family-missed-days')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Fever'), findsOneWidget);
    });

    testWidgets('steps back a month and cannot go past this one', (tester) async {
      final (data, _, _) = await pumpFamilyApp(tester, goTo: '/attendance');

      final next = tester.widget<IconButton>(find.byKey(const Key('family-month-next')));
      expect(next.onPressed, isNull);

      await tester.tap(find.byKey(const Key('family-month-back')));
      await tester.pumpAndSettle();

      expect(data.monthsAskedFor.length, 2);
      expect(data.monthsAskedFor.toSet().length, 2);
    });
  });

  group('Notices', () {
    testWidgets('opening one reads it, and mark all read clears the rest', (tester) async {
      final data = FakeFamilyRepository(
        notices: [
          familyNotice(),
          familyNotice(id: 2, title: 'Fee reminder'),
        ],
      );
      await pumpFamilyApp(tester, data: data, goTo: '/notices');

      await tester.tap(find.byKey(const Key('family-notice-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('family-notice-open')), findsOneWidget);
      expect(data.markedRead, [1]);

      Navigator.of(tester.element(find.byKey(const Key('family-notice-open')))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('family-read-all')));
      await tester.pumpAndSettle();

      expect(data.markAllReadCalls, 1);
      expect(find.byKey(const Key('family-read-all')), findsNothing);
    });

    testWidgets('no notices says so', (tester) async {
      await pumpFamilyApp(
        tester,
        data: FakeFamilyRepository(notices: []),
        goTo: '/notices',
      );

      expect(find.text('No notices yet'), findsOneWidget);
    });
  });

  group('More', () {
    testWidgets('calls, WhatsApps and emails the school office', (tester) async {
      final (_, _, opened) = await pumpFamilyApp(tester, goTo: '/more');
      await tester.drag(find.byKey(const Key('family-more')), const Offset(0, -400));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('family-call-school')));
      await tester.tap(find.byKey(const Key('family-whatsapp-school')));
      await tester.tap(find.byKey(const Key('family-email-school')));
      await tester.pumpAndSettle();

      expect(opened.map((uri) => uri.toString()), [
        'tel:+91%2080%204000%201234',
        'https://wa.me/918040001234',
        'mailto:office@greenfield.example',
      ]);
    });

    testWidgets('a school with no contact details says so', (tester) async {
      await pumpFamilyApp(
        tester,
        auth: FakeFamilyAuthRepository(account: familyAccount(phone: null)),
        goTo: '/more',
      );

      expect(find.byKey(const Key('family-call-school')), findsNothing);
      expect(find.byKey(const Key('family-email-school')), findsOneWidget);
    });

    testWidgets('signing out asks first, then goes to the sign-in', (tester) async {
      final (_, auth, _) = await pumpFamilyApp(tester, goTo: '/more');

      await tester.scrollUntilVisible(find.byKey(const Key('family-sign-out')), 200);
      await tester.tap(find.byKey(const Key('family-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(auth.logouts, 0);

      await tester.tap(find.byKey(const Key('family-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(auth.logouts, 1);
      expect(find.byKey(const Key('family-sign-in')), findsOneWidget);
    });

    testWidgets('a notification switch saves, and puts itself back when the school refuses', (tester) async {
      final data = FakeFamilyRepository();
      await pumpFamilyApp(tester, data: data, goTo: '/notifications');

      await tester.tap(find.byKey(const Key('family-switch-transport')));
      await tester.pumpAndSettle();
      expect(data.saved, [('transport', false)]);
      expect(find.text('Saved.'), findsOneWidget);

      data.failSaveWith = Failure.network();
      await tester.tap(find.byKey(const Key('family-switch-fee')));
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(find.byKey(const Key('family-switch-fee'))).value, isTrue);
      expect(find.text(Failure.network().message), findsOneWidget);
    });

    testWidgets('the school calendar lists the month\'s holidays and the closed days', (tester) async {
      await pumpFamilyApp(tester, goTo: '/calendar');

      expect(find.text('Guru Nanak Jayanti'), findsNWidgets(2));
      expect(find.text('The school is closed every Saturday and Sunday.'), findsOneWidget);
    });
  });

  group('the router', () {
    testWidgets('signed out, every address goes to the sign-in', (tester) async {
      await pumpFamilyApp(tester, auth: FakeFamilyAuthRepository(), goTo: '/attendance');

      expect(find.byKey(const Key('family-sign-in')), findsOneWidget);
    });

    testWidgets('an unknown address goes Home', (tester) async {
      await pumpFamilyApp(tester, goTo: '/dashboard');

      expect(find.byKey(const Key('family-home')), findsOneWidget);
    });
  });
}
