import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/mail_settings/application/mail_settings_notifier.dart';
import 'package:edutrack_app/features/mail_settings/data/mail_settings_repository.dart';
import 'package:edutrack_app/features/mail_settings/data/models/mail_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_mail_settings_repository.dart';

ProviderContainer makeContainer(FakeMailSettingsRepository fake) {
  final container = ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [mailSettingsRepositoryProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  return container;
}

/// The platform's SMTP settings: loaded once, replaced by whatever a save or
/// a test hands back, and left alone when either of those fails.
void main() {
  test('loads the settings from the API', () async {
    final container = makeContainer(FakeMailSettingsRepository());

    final settings = await container.read(mailSettingsNotifierProvider.future);

    expect(settings.host, 'smtp.example.com');
    expect(settings.port, 587);
    expect(settings.encryption, MailEncryption.tls);
    expect(settings.fromDatabase, isTrue);
  });

  test('a failed load is the error state', () async {
    final fake = FakeMailSettingsRepository(
      failGetWith: const Failure(code: 'FORBIDDEN', message: 'Only a Super Admin can do this.'),
    );
    final container = makeContainer(fake);

    await expectLater(container.read(mailSettingsNotifierProvider.future), throwsA(isA<Failure>()));
    expect(container.read(mailSettingsNotifierProvider).hasError, isTrue);
  });

  test('load() asks the API again', () async {
    final fake = FakeMailSettingsRepository();
    final container = makeContainer(fake);
    await container.read(mailSettingsNotifierProvider.future);
    expect(fake.getCalls, 1);

    fake.settings = mailSettings(host: 'smtp.changed.example.com');
    await container.read(mailSettingsNotifierProvider.notifier).load();

    expect(fake.getCalls, 2);
    expect(container.read(mailSettingsNotifierProvider).value?.host, 'smtp.changed.example.com');
  });

  test('save sends every field and replaces the state with what came back', () async {
    final fake = FakeMailSettingsRepository();
    final container = makeContainer(fake);
    await container.read(mailSettingsNotifierProvider.future);

    await container
        .read(mailSettingsNotifierProvider.notifier)
        .save(
          isActive: false,
          host: 'smtp.new.example.com',
          port: 465,
          encryption: MailEncryption.ssl,
          username: null,
          password: 'new-secret',
          fromAddress: 'alerts@example.com',
          fromName: 'Alerts',
        );

    expect(fake.lastSave, {
      'is_active': false,
      'host': 'smtp.new.example.com',
      'port': 465,
      'encryption': 'ssl',
      'username': null,
      'password': 'new-secret',
      'from_address': 'alerts@example.com',
      'from_name': 'Alerts',
    });
    final state = container.read(mailSettingsNotifierProvider).value!;
    expect(state.host, 'smtp.new.example.com');
    expect(state.isActive, isFalse);
    expect(state.passwordSet, isTrue);
    expect(state.updatedByName, 'Platform Owner');
  });

  test('a password of null keeps the stored one; an empty one clears it', () async {
    final fake = FakeMailSettingsRepository();
    final container = makeContainer(fake);
    await container.read(mailSettingsNotifierProvider.future);
    final notifier = container.read(mailSettingsNotifierProvider.notifier);

    await notifier.save(
      isActive: true,
      host: 'smtp.example.com',
      port: 587,
      encryption: MailEncryption.tls,
      username: 'mailer',
      fromAddress: 'no-reply@example.com',
      fromName: 'School365ai',
    );
    expect(fake.lastSave!['password'], isNull);
    expect(container.read(mailSettingsNotifierProvider).value!.passwordSet, isTrue);

    await notifier.save(
      isActive: true,
      host: 'smtp.example.com',
      port: 587,
      encryption: MailEncryption.tls,
      username: 'mailer',
      password: '',
      fromAddress: 'no-reply@example.com',
      fromName: 'School365ai',
    );
    expect(fake.lastSave!['password'], '');
    expect(container.read(mailSettingsNotifierProvider).value!.passwordSet, isFalse);
  });

  test('a refused save throws and leaves the loaded settings in place', () async {
    final fake = FakeMailSettingsRepository(
      failSaveWith: const Failure(
        code: 'VALIDATION_ERROR',
        message: 'The host field is required.',
        details: {
          'errors': {
            'host': ['The host field is required.'],
          },
        },
      ),
    );
    final container = makeContainer(fake);
    await container.read(mailSettingsNotifierProvider.future);

    await expectLater(
      container
          .read(mailSettingsNotifierProvider.notifier)
          .save(
            isActive: true,
            host: '',
            port: 587,
            encryption: MailEncryption.tls,
            fromAddress: 'no-reply@example.com',
            fromName: 'School365ai',
          ),
      throwsA(isA<Failure>().having((f) => f.validationErrors['host'], 'host error', ['The host field is required.'])),
    );

    final state = container.read(mailSettingsNotifierProvider);
    expect(state.hasValue, isTrue);
    expect(state.hasError, isFalse);
    expect(state.value!.host, 'smtp.example.com');
  });

  test('a test email returns the message and records the test on the settings', () async {
    final fake = FakeMailSettingsRepository();
    final container = makeContainer(fake);
    await container.read(mailSettingsNotifierProvider.future);

    final message = await container.read(mailSettingsNotifierProvider.notifier).sendTest('ops@example.com');

    expect(fake.lastTestTo, 'ops@example.com');
    expect(message, 'A test email was sent to ops@example.com.');
    expect(container.read(mailSettingsNotifierProvider).value!.lastTestedAtLabel, '09/19/2026 11:00 AM');
  });

  test('a test the server could not send throws with its reason and keeps the settings', () async {
    final fake = FakeMailSettingsRepository(
      failTestWith: const Failure(code: 'MAIL_TEST_FAILED', message: 'Connection refused by smtp.example.com:587'),
    );
    final container = makeContainer(fake);
    await container.read(mailSettingsNotifierProvider.future);

    await expectLater(
      container.read(mailSettingsNotifierProvider.notifier).sendTest('ops@example.com'),
      throwsA(isA<Failure>().having((f) => f.message, 'message', 'Connection refused by smtp.example.com:587')),
    );

    expect(container.read(mailSettingsNotifierProvider).hasValue, isTrue);
  });
}
