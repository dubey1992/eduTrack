import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/platform_messaging/data/models/platform_messaging.dart';
import 'package:edutrack_app/features/platform_messaging/data/platform_messaging_api.dart';
import 'package:edutrack_app/features/platform_messaging/data/platform_messaging_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with one canned response, and remembers what was
/// asked - so the tests see exactly the request the server would.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body);

  final int status;
  final Map<String, dynamic> body;
  RequestOptions? asked;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked = options;

    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

PlatformMessagingRepository _repository(_CannedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))..httpClientAdapter = adapter;

  return PlatformMessagingRepository(PlatformMessagingApi(dio));
}

/// The resource as the backend's platform_messaging_resource writes it.
const _resource = {
  'is_saved': true,
  'provider': 'twilio',
  'available_providers': [
    {'value': 'log', 'label': 'Demo Gateway', 'delivers': false},
    {'value': 'twilio', 'label': 'Twilio', 'delivers': true},
  ],
  'fields': [
    {'key': 'account_sid', 'label': 'Account SID', 'secret': false, 'set': true, 'hint': '…5678'},
    {'key': 'auth_token', 'label': 'Auth token', 'secret': true, 'set': true, 'hint': null},
    {'key': 'sms_from', 'label': 'SMS sender number', 'secret': false, 'set': false, 'hint': null},
    {'key': 'whatsapp_from', 'label': 'WhatsApp sender number', 'secret': false, 'set': false, 'hint': null},
  ],
  'last_tested_at': '2026-10-29T09:35:00Z',
  'last_tested_at_label': '10/29/2026 3:05 PM',
  'last_test_error': 'Authenticate',
  'updated_by_name': 'Platform Owner',
  'whatsapp_templates': [
    {
      'event': 'attendance.absent',
      'event_label': 'Marked absent',
      'tokens': ['student_name', 'date'],
      'template': {
        'template_name': 'HX0001',
        'language': 'en',
        'parameters': ['student_name', 'date'],
        'updated_at': '2026-10-29T09:00:00Z',
      },
    },
    {
      'event': 'fees.reminder',
      'event_label': 'Fee reminder',
      'tokens': ['student_name', 'amount'],
      'template': null,
    },
  ],
};

/// What an account never saved looks like: every optional value null.
const _unsaved = {
  'is_saved': false,
  'provider': 'log',
  'available_providers': [
    {'value': 'log', 'label': 'Demo Gateway', 'delivers': false},
  ],
  'fields': <Object>[],
  'last_tested_at': null,
  'last_tested_at_label': null,
  'last_test_error': null,
  'updated_by_name': null,
  'whatsapp_templates': <Object>[],
};

void main() {
  group('the model', () {
    test('reads every part of the resource', () {
      final settings = PlatformMessaging.fromJson(_resource);

      expect(settings.isSaved, isTrue);
      expect(settings.provider, 'twilio');
      expect(settings.availableProviders.map((p) => p.label), ['Demo Gateway', 'Twilio']);
      expect(settings.availableProviders.map((p) => p.delivers), [false, true]);
      expect(settings.fields.map((f) => f.key), ['account_sid', 'auth_token', 'sms_from', 'whatsapp_from']);
      expect(settings.fields[0].isSet, isTrue);
      expect(settings.fields[0].hint, '…5678');
      expect(settings.fields[1].secret, isTrue);
      expect(settings.fields[1].hint, isNull);
      expect(settings.fields[2].isSet, isFalse);
      expect(settings.lastTestedAtLabel, '10/29/2026 3:05 PM');
      expect(settings.lastTestError, 'Authenticate');
      expect(settings.updatedByName, 'Platform Owner');

      final absent = settings.whatsappTemplates.first;
      expect(absent.eventLabel, 'Marked absent');
      expect(absent.tokens, ['student_name', 'date']);
      expect(absent.template!.templateName, 'HX0001');
      expect(absent.template!.parameters, ['student_name', 'date']);
      expect(settings.whatsappTemplates.last.template, isNull);
    });

    test('reads an account never saved, with its nulls', () {
      final settings = PlatformMessaging.fromJson(_unsaved);

      expect(settings.isSaved, isFalse);
      expect(settings.provider, 'log');
      expect(settings.fields, isEmpty);
      expect(settings.lastTestedAt, isNull);
      expect(settings.lastTestedAtLabel, isNull);
      expect(settings.lastTestError, isNull);
      expect(settings.updatedByName, isNull);
      expect(settings.whatsappTemplates, isEmpty);
    });
  });

  group('the API', () {
    test('reads the account from /platform/messaging', () async {
      final adapter = _CannedAdapter(200, _resource);

      final settings = await _repository(adapter).get();

      expect(adapter.asked!.method, 'GET');
      expect(adapter.asked!.uri.path, '/api/v1/platform/messaging');
      expect(settings.provider, 'twilio');
    });

    test('a save sends the provider and only the credentials it was given', () async {
      final adapter = _CannedAdapter(200, _resource);

      await _repository(adapter).save(provider: 'twilio', credentials: {'sms_from': '+14155550123', 'account_sid': ''});

      expect(adapter.asked!.method, 'PUT');
      expect(adapter.asked!.uri.path, '/api/v1/platform/messaging');
      expect(adapter.asked!.data, {
        'provider': 'twilio',
        'credentials': {'sms_from': '+14155550123', 'account_sid': ''},
      });
    });

    test('a test names the channel and the number, and hands back the message', () async {
      final adapter = _CannedAdapter(200, {'message': 'A test SMS was sent to +91 9876543210.', 'settings': _resource});

      final result = await _repository(adapter).sendTest(channel: MessagingChannel.whatsapp, to: '+91 9876543210');

      expect(adapter.asked!.method, 'POST');
      expect(adapter.asked!.uri.path, '/api/v1/platform/messaging/test');
      expect(adapter.asked!.data, {'channel': 'whatsapp', 'to': '+91 9876543210'});
      expect(result.message, 'A test SMS was sent to +91 9876543210.');
      expect(result.settings.lastTestedAtLabel, '10/29/2026 3:05 PM');
    });

    test('a template is saved and cleared at its event', () async {
      final adapter = _CannedAdapter(200, _resource);
      final repository = _repository(adapter);

      await repository.saveTemplate(
        event: 'attendance.absent',
        templateName: 'HX0002',
        language: 'en_US',
        parameters: ['date', 'student_name'],
      );
      expect(adapter.asked!.method, 'PUT');
      expect(adapter.asked!.uri.path, '/api/v1/platform/whatsapp-templates/attendance.absent');
      expect(adapter.asked!.data, {
        'template_name': 'HX0002',
        'language': 'en_US',
        'parameters': ['date', 'student_name'],
      });

      await repository.clearTemplate('attendance.absent');
      expect(adapter.asked!.method, 'DELETE');
      expect(adapter.asked!.uri.path, '/api/v1/platform/whatsapp-templates/attendance.absent');
    });

    test("a refused test is a Failure in the provider's own words", () async {
      final adapter = _CannedAdapter(422, {
        'code': 'GATEWAY_TEST_FAILED',
        'message': 'The From phone number is not a valid, SMS-capable inbound phone number.',
        'details': <String, dynamic>{},
      });

      await expectLater(
        _repository(adapter).sendTest(channel: MessagingChannel.sms, to: '+91 9876543210'),
        throwsA(
          isA<Failure>()
              .having((f) => f.code, 'code', 'GATEWAY_TEST_FAILED')
              .having(
                (f) => f.message,
                'message',
                'The From phone number is not a valid, SMS-capable inbound phone number.',
              ),
        ),
      );
    });

    test('a refused Super Admin-only read is a Failure, not an exception', () async {
      final adapter = _CannedAdapter(403, {'code': 'FORBIDDEN', 'message': 'This action is unauthorized.'});

      await expectLater(_repository(adapter).get(), throwsA(isA<Failure>().having((f) => f.code, 'code', 'FORBIDDEN')));
    });
  });
}
