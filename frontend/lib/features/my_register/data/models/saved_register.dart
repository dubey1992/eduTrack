import '../../../attendance/data/models/attendance_status.dart';

/// A class register taken on the phone and not yet accepted by the server
/// (docs/teacher-app.md, T2). Kept on the phone until it lands, so a
/// register taken in a corridor with no signal is never lost.
class SavedRegister {
  const SavedRegister({
    required this.clientId,
    required this.userId,
    required this.classSectionId,
    required this.classSection,
    required this.date,
    required this.marks,
    required this.savedAt,
  });

  factory SavedRegister.fromJson(Map<String, dynamic> json) => SavedRegister(
    clientId: json['client_id'] as String,
    userId: json['user_id'] as int,
    classSectionId: json['class_section_id'] as int,
    classSection: json['class_section'] as String,
    date: json['date'] as String,
    marks: {
      for (final entry in (json['marks'] as Map<String, dynamic>).entries)
        int.parse(entry.key): AttendanceStatus.fromApiValue(entry.value as String),
    },
    savedAt: DateTime.parse(json['saved_at'] as String),
  );

  /// The phone's own name for this submission.
  final String clientId;

  /// Who took it. Only they send it: a phone two teachers share never sends
  /// one teacher's register under the other's sign-in.
  final int userId;
  final int classSectionId;

  /// "Grade 3 A", for saying which register.
  final String classSection;

  /// `yyyy-MM-dd`, the school's date the register is for.
  final String date;

  /// Student id to their mark.
  final Map<int, AttendanceStatus> marks;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'user_id': userId,
    'class_section_id': classSectionId,
    'class_section': classSection,
    'date': date,
    'marks': {for (final entry in marks.entries) '${entry.key}': entry.value.apiValue},
    'saved_at': savedAt.toIso8601String(),
  };

  /// What `POST attendance` takes.
  List<Map<String, dynamic>> get records => [
    for (final entry in marks.entries) {'student_id': entry.key, 'status': entry.value.apiValue},
  ];

  bool isFor(int sectionId, String day) => classSectionId == sectionId && date == day;
}

/// A register the server turned down, kept to be read: there is nothing the
/// phone can do about it by trying again.
class UnsentRegister {
  const UnsentRegister({
    required this.clientId,
    required this.userId,
    required this.classSectionId,
    required this.classSection,
    required this.date,
    required this.reason,
  });

  factory UnsentRegister.fromJson(Map<String, dynamic> json) => UnsentRegister(
    clientId: json['client_id'] as String,
    userId: json['user_id'] as int,
    classSectionId: json['class_section_id'] as int,
    classSection: json['class_section'] as String,
    date: json['date'] as String,
    reason: json['reason'] as String,
  );

  factory UnsentRegister.of(SavedRegister register, String reason) => UnsentRegister(
    clientId: register.clientId,
    userId: register.userId,
    classSectionId: register.classSectionId,
    classSection: register.classSection,
    date: register.date,
    reason: reason,
  );

  final String clientId;
  final int userId;
  final int classSectionId;
  final String classSection;
  final String date;
  final String reason;

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'user_id': userId,
    'class_section_id': classSectionId,
    'class_section': classSection,
    'date': date,
    'reason': reason,
  };

  bool isFor(int sectionId, String day) => classSectionId == sectionId && date == day;
}

/// The class list as the phone last saw it, so the register opens without
/// signal. Names and roll numbers only - never anybody's marks.
class CachedStudent {
  const CachedStudent({required this.studentId, required this.name, required this.rollNumber});

  factory CachedStudent.fromJson(Map<String, dynamic> json) => CachedStudent(
    studentId: json['student_id'] as int,
    name: json['name'] as String,
    rollNumber: json['roll_number'] as String?,
  );

  final int studentId;
  final String name;
  final String? rollNumber;

  Map<String, dynamic> toJson() => {'student_id': studentId, 'name': name, 'roll_number': rollNumber};
}
