import 'package:edutrack_app/features/imports/data/models/import_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// What comes back from an upload, read the way the dialog reads it.
void main() {
  group('a file the server accepted', () {
    test('reads the count and the label', () {
      final result = ImportResult.fromJson({'imported': 12, 'label': 'Students', 'details': []});

      expect(result.imported, 12);
      expect(result.label, 'Students');
      expect(result.created, isEmpty);
    });

    test('picks out only the accounts that came with a password', () {
      final result = ImportResult.fromJson({
        'imported': 2,
        'label': 'Teachers and Staff',
        'details': [
          {'id': 1, 'name': 'Priya Nair', 'email': 'priya@example.com', 'temporary_password': 'Abc#12345678'},
          {'id': 2, 'name': 'Bus 12'},
        ],
      });

      expect(result.created, hasLength(2));
      expect(result.withPasswords, hasLength(1));
      expect(result.withPasswords.single.email, 'priya@example.com');
      expect(result.withPasswords.single.temporaryPassword, 'Abc#12345678');
    });

    test('survives a payload with nothing in it', () {
      final result = ImportResult.fromJson(const {});

      expect(result.imported, 0);
      expect(result.label, 'Records');
      expect(result.withPasswords, isEmpty);
    });
  });

  group('a file the server refused', () {
    test('keeps the line number and every message for it', () {
      final error = ImportRowError.fromJson({
        'row': 7,
        'messages': ['The first name field is required.', 'There is no section "Z" in class "Grade 5".'],
      });

      expect(error.row, 7);
      expect(error.messages, hasLength(2));
      expect(error.messages.first, 'The first name field is required.');
    });
  });
}
