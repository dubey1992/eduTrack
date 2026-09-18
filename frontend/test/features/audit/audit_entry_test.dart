import 'package:edutrack_app/features/audit/data/models/audit_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuditEntry.fromJson', () {
    test('reads every field the API sends', () {
      final entry = AuditEntry.fromJson({
        'id': 12,
        'created_at': '2026-09-16T10:23:45.000000Z',
        'created_at_label': '09/16/2026 3:53 PM',
        'school_id': 3,
        'school_name': 'Green Valley School',
        'user_id': 7,
        'user_name': 'Anita Sharma',
        'user_role': 'SCHOOL_ADMIN',
        'module': 'staff_attendance',
        'action': 'staff_attendance.updated',
        'entity_type': 'staff_attendance',
        'entity_id': 99,
        'old_values': {'status': 'absent'},
        'new_values': {'status': 'present'},
        'ip': '10.0.0.5',
      });

      expect(entry.id, 12);
      expect(entry.createdAt, DateTime.utc(2026, 9, 16, 10, 23, 45));
      expect(entry.whenLabel, '09/16/2026 3:53 PM');
      expect(entry.schoolLabel, 'Green Valley School');
      expect(entry.actorLabel, 'Anita Sharma');
      expect(entry.roleLabel, 'School Admin');
      expect(entry.moduleLabel, 'Staff attendance');
      expect(entry.actionLabel, 'Staff attendance updated');
      expect(entry.recordLabel, 'Staff attendance #99');
      expect(entry.ip, '10.0.0.5');
      expect(entry.changeShape, AuditChangeShape.beforeAndAfter);
      expect(entry.changes.single.fieldLabel, 'Status');
      expect((entry.changes.single.before, entry.changes.single.after), ('absent', 'present'));
    });

    test('tolerates a platform entry with no school, user, record or values', () {
      final entry = AuditEntry.fromJson({
        'id': 1,
        'created_at': '2026-09-16T10:23:45.000000Z',
        'school_id': null,
        'school_name': null,
        'user_id': null,
        'user_name': null,
        'user_role': null,
        'module': 'schools',
        'action': 'school.suspended',
        'entity_type': 'school',
        'entity_id': null,
        'old_values': null,
        'new_values': null,
        'ip': null,
      });

      expect(entry.schoolLabel, 'Platform');
      expect(entry.actorLabel, 'System');
      expect(entry.roleLabel, isNull);
      expect(entry.recordLabel, 'School');
      expect(entry.changeShape, AuditChangeShape.none);
      expect(entry.changes, isEmpty);
      // No server label: the raw instant, plainly marked as UTC.
      expect(entry.whenLabel, '09/16/2026 10:23 AM UTC');
    });
  });

  test('a failed sign-in is attributed to the address that was tried', () {
    final entry = AuditEntry.fromJson({
      'id': 5,
      'created_at': '2026-09-16T10:23:45.000000Z',
      'module': 'auth',
      'action': 'user.sign_in_failed',
      'entity_type': 'user',
      'new_values': {'email': 'ghost@example.com'},
    });

    expect(entry.actorLabel, 'ghost@example.com');
    expect(entry.moduleLabel, 'Sign-in & security');
    expect(entry.changeShape, AuditChangeShape.afterOnly);
  });

  test('a deleted account still reads as an account, not the system', () {
    final entry = AuditEntry.fromJson({
      'id': 6,
      'created_at': '2026-09-16T10:23:45.000000Z',
      'user_id': 44,
      'module': 'students',
      'action': 'student.deleted',
      'entity_type': 'student',
      'entity_id': 3,
      'old_values': {'first_name': 'Arjun'},
    });

    expect(entry.actorLabel, 'Unknown account');
    expect(entry.changeShape, AuditChangeShape.beforeOnly);
  });

  test('unknown modules and roles are humanised rather than rejected', () {
    expect(AuditModule.labelFor('library_books'), 'Library books');
    expect(AuditModule.labelFor('teaching'), 'Teaching reports');
    expect(AuditModule.labelFor('academic'), 'Academic setup');
  });

  test('values are shown as text a person can read', () {
    expect(formatAuditValue(null), '-');
    expect(formatAuditValue(''), '-');
    expect(formatAuditValue(false), 'No');
    expect(formatAuditValue(12.5), '12.5');
    expect(formatAuditValue({'a': 1}), '{"a":1}');
    expect(formatAuditValue([1, 2]), '[1,2]');
  });
}
