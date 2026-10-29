import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/platform_messaging/application/platform_messaging_notifier.dart';
import 'package:edutrack_app/features/platform_messaging/data/models/platform_messaging.dart';
import 'package:edutrack_app/features/platform_messaging/data/platform_messaging_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_platform_messaging_repository.dart';

ProviderContainer makeContainer(FakePlatformMessagingRepository fake) {
  final container = ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [platformMessagingRepositoryProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  return container;
}

/// School365ai's messaging account: loaded once, replaced by whatever a
/// save, test or template change hands back, and left alone when one fails.
void main() {
  test('loads the account from the API', () async {
    final container = makeContainer(FakePlatformMessagingRepository());

    final settings = await container.read(platformMessagingNotifierProvider.future);

    expect(settings.provider, 'twilio');
    expect(settings.fields, hasLength(4));
    expect(settings.whatsappTemplates.map((t) => t.event), ['attendance.absent', 'fees.reminder']);
  });

  test('a failed load is the error state', () async {
    final fake = FakePlatformMessagingRepository(
      failGetWith: const Failure(code: 'FORBIDDEN', message: 'This action is unauthorized.'),
    );
    final container = makeContainer(fake);

    await expectLater(container.read(platformMessagingNotifierProvider.future), throwsA(isA<Failure>()));
    expect(container.read(platformMessagingNotifierProvider).hasError, isTrue);
  });

  test('load() asks the API again', () async {
    final fake = FakePlatformMessagingRepository();
    final container = makeContainer(fake);
    await container.read(platformMessagingNotifierProvider.future);

    fake.settings = unsavedPlatformMessaging();
    await container.read(platformMessagingNotifierProvider.notifier).load();

    expect(fake.getCalls, 2);
    expect(container.read(platformMessagingNotifierProvider).value!.provider, 'log');
  });

  test('save sends what it was given and replaces the state with what came back', () async {
    final fake = FakePlatformMessagingRepository(settings: unsavedPlatformMessaging());
    final container = makeContainer(fake);
    await container.read(platformMessagingNotifierProvider.future);

    await container
        .read(platformMessagingNotifierProvider.notifier)
        .save(provider: 'twilio', credentials: {'account_sid': 'AC1234', 'auth_token': 'secret'});

    expect(fake.lastProvider, 'twilio');
    expect(fake.lastCredentials, {'account_sid': 'AC1234', 'auth_token': 'secret'});
    final state = container.read(platformMessagingNotifierProvider).value!;
    expect(state.isSaved, isTrue);
    expect(state.provider, 'twilio');
    expect(state.fields.firstWhere((f) => f.key == 'auth_token').isSet, isTrue);
    expect(state.fields.firstWhere((f) => f.key == 'sms_from').isSet, isFalse);
    expect(state.updatedByName, 'Platform Owner');
  });

  test('a refused save throws and leaves the loaded account in place', () async {
    final fake = FakePlatformMessagingRepository(
      failSaveWith: const Failure(
        code: 'VALIDATION_ERROR',
        message: 'Choose Twilio, or the Demo Gateway that sends nothing.',
        details: {
          'errors': {
            'provider': ['Choose Twilio, or the Demo Gateway that sends nothing.'],
          },
        },
      ),
    );
    final container = makeContainer(fake);
    await container.read(platformMessagingNotifierProvider.future);

    await expectLater(
      container.read(platformMessagingNotifierProvider.notifier).save(provider: 'nope', credentials: const {}),
      throwsA(isA<Failure>().having((f) => f.validationErrors['provider'], 'provider error', isNotEmpty)),
    );

    final state = container.read(platformMessagingNotifierProvider);
    expect(state.hasError, isFalse);
    expect(state.value!.provider, 'twilio');
  });

  test('a test returns the message and records the test on the account', () async {
    final fake = FakePlatformMessagingRepository(settings: platformMessaging(lastTestError: 'Authenticate'));
    final container = makeContainer(fake);
    await container.read(platformMessagingNotifierProvider.future);

    final message = await container
        .read(platformMessagingNotifierProvider.notifier)
        .sendTest(MessagingChannel.sms, '+91 9876543210');

    expect(fake.lastTestChannel, MessagingChannel.sms);
    expect(fake.lastTestTo, '+91 9876543210');
    expect(message, 'A test SMS was sent to +91 9876543210.');
    final state = container.read(platformMessagingNotifierProvider).value!;
    expect(state.lastTestedAtLabel, '10/29/2026 3:05 PM');
    expect(state.lastTestError, isNull);
  });

  test("a refused test throws in the provider's words and keeps the account", () async {
    final fake = FakePlatformMessagingRepository(
      failTestWith: const Failure(code: 'GATEWAY_TEST_FAILED', message: 'Authenticate'),
    );
    final container = makeContainer(fake);
    await container.read(platformMessagingNotifierProvider.future);

    await expectLater(
      container.read(platformMessagingNotifierProvider.notifier).sendTest(MessagingChannel.whatsapp, '+91 9876543210'),
      throwsA(isA<Failure>().having((f) => f.message, 'message', 'Authenticate')),
    );
    expect(container.read(platformMessagingNotifierProvider).hasValue, isTrue);
  });

  test('a template saved and cleared replaces the account each time', () async {
    final fake = FakePlatformMessagingRepository();
    final container = makeContainer(fake);
    await container.read(platformMessagingNotifierProvider.future);
    final notifier = container.read(platformMessagingNotifierProvider.notifier);

    await notifier.saveTemplate(
      event: 'fees.reminder',
      templateName: 'HX0009',
      language: 'en',
      parameters: ['amount', 'student_name'],
    );
    var reminder = container.read(platformMessagingNotifierProvider).value!.whatsappTemplates.last;
    expect(reminder.template!.templateName, 'HX0009');
    expect(reminder.template!.parameters, ['amount', 'student_name']);

    await notifier.clearTemplate('fees.reminder');
    reminder = container.read(platformMessagingNotifierProvider).value!.whatsappTemplates.last;
    expect(fake.lastTemplateCleared, 'fees.reminder');
    expect(reminder.template, isNull);
  });

  test('a refused template change throws and keeps the account', () async {
    final fake = FakePlatformMessagingRepository(
      failTemplateWith: const Failure(code: 'VALIDATION_ERROR', message: 'Remove {grade}.'),
    );
    final container = makeContainer(fake);
    await container.read(platformMessagingNotifierProvider.future);

    await expectLater(
      container
          .read(platformMessagingNotifierProvider.notifier)
          .saveTemplate(event: 'attendance.absent', templateName: 'HX1', language: 'en', parameters: ['grade']),
      throwsA(isA<Failure>()),
    );
    expect(
      container.read(platformMessagingNotifierProvider).value!.whatsappTemplates.first.template!.templateName,
      'HX0001',
    );
  });
}
