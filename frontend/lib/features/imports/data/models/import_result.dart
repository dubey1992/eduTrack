/// What a bulk upload produced, one way or the other.
///
/// A file either imports completely or not at all, so these two are never
/// both true: either [rowErrors] is empty and [imported] rows landed, or
/// nothing landed and every row that needs fixing is listed.
class ImportResult {
  const ImportResult({required this.imported, required this.label, this.created = const []});

  factory ImportResult.fromJson(Map<String, dynamic> json) {
    return ImportResult(
      imported: json['imported'] as int? ?? 0,
      label: json['label'] as String? ?? 'Records',
      created: (json['details'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ImportedRecord.fromJson)
          .toList(growable: false),
    );
  }

  final int imported;
  final String label;
  final List<ImportedRecord> created;

  /// The accounts that came back with a generated password - the one moment
  /// anybody sees it.
  List<ImportedRecord> get withPasswords => created.where((record) => record.temporaryPassword != null).toList();
}

class ImportedRecord {
  const ImportedRecord({required this.name, this.email, this.temporaryPassword});

  factory ImportedRecord.fromJson(Map<String, dynamic> json) {
    return ImportedRecord(
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      temporaryPassword: json['temporary_password'] as String?,
    );
  }

  final String name;
  final String? email;
  final String? temporaryPassword;
}

/// One row of the uploaded file, and everything wrong with it.
///
/// [row] is the line number in the spreadsheet, counting the heading row as
/// line 1 - so it points at the row the person can actually go and fix.
class ImportRowError {
  const ImportRowError({required this.row, required this.messages});

  factory ImportRowError.fromJson(Map<String, dynamic> json) {
    return ImportRowError(
      row: json['row'] as int? ?? 0,
      messages: List<String>.from(json['messages'] as List? ?? const []),
    );
  }

  final int row;
  final List<String> messages;
}
