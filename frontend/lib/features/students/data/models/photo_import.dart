/// Student photos in bulk (docs/student-photos.md, P2): what the server says
/// each file would do, and what it did.
library;

/// What will happen to one chosen file.
enum PhotoMatchStatus {
  /// Matches a student who has no photo yet.
  newPhoto('new'),

  /// Matches a student who has one; it will be replaced.
  replace('replace'),

  /// Not a JPEG or PNG by its name.
  notAnImage('not_an_image'),

  /// No student has this admission number.
  unmatched('unmatched'),

  /// Two students' admission numbers differ only by `/`, `-`, `_` or capitals.
  ambiguous('ambiguous'),

  /// Another chosen file is for the same student.
  duplicate('duplicate'),

  /// Over the size the server takes - found on this side, before sending.
  tooLarge('too_large');

  const PhotoMatchStatus(this.apiValue);

  final String apiValue;

  /// Whether the file will be sent.
  bool get uploads => this == newPhoto || this == replace;

  /// Anything this app does not know is held back rather than sent.
  static PhotoMatchStatus fromApiValue(String? value) =>
      values.where((status) => status.apiValue == value).firstOrNull ?? unmatched;
}

/// The student a file matched.
class PhotoMatchStudent {
  const PhotoMatchStudent({
    required this.id,
    required this.name,
    required this.admissionNumber,
    required this.classSectionName,
    required this.hasPhoto,
  });

  factory PhotoMatchStudent.fromJson(Map<String, dynamic> json) => PhotoMatchStudent(
    id: json['id'] as int,
    name: json['name'] as String,
    admissionNumber: json['admission_number'] as String,
    classSectionName: json['class_section_name'] as String?,
    hasPhoto: json['has_photo'] as bool? ?? false,
  );

  final int id;
  final String name;
  final String admissionNumber;
  final String? classSectionName;
  final bool hasPhoto;
}

/// One chosen file, as the preview judged it.
class PhotoPreviewRow {
  const PhotoPreviewRow({required this.fileName, required this.status, this.reason, this.student});

  factory PhotoPreviewRow.fromJson(Map<String, dynamic> json) => PhotoPreviewRow(
    fileName: json['file_name'] as String,
    status: PhotoMatchStatus.fromApiValue(json['status'] as String?),
    reason: json['reason'] as String?,
    student: json['student'] == null ? null : PhotoMatchStudent.fromJson(json['student'] as Map<String, dynamic>),
  );

  final String fileName;
  final PhotoMatchStatus status;

  /// Why it will not be sent, in a sentence. Null when it will.
  final String? reason;
  final PhotoMatchStudent? student;

  PhotoPreviewRow tooLarge(String why) =>
      PhotoPreviewRow(fileName: fileName, status: PhotoMatchStatus.tooLarge, reason: why, student: student);
}

/// What happened to one file that was sent.
enum PhotoUploadStatus {
  added('added'),
  replaced('replaced'),
  skipped('skipped');

  const PhotoUploadStatus(this.apiValue);

  final String apiValue;

  static PhotoUploadStatus fromApiValue(String? value) =>
      values.where((status) => status.apiValue == value).firstOrNull ?? skipped;
}

class PhotoUploadResult {
  const PhotoUploadResult({required this.fileName, required this.status, this.reason, this.studentId});

  factory PhotoUploadResult.fromJson(Map<String, dynamic> json) => PhotoUploadResult(
    fileName: json['file_name'] as String,
    status: PhotoUploadStatus.fromApiValue(json['status'] as String?),
    reason: json['reason'] as String?,
    studentId: json['student_id'] as int?,
  );

  final String fileName;
  final PhotoUploadStatus status;
  final String? reason;
  final int? studentId;
}
