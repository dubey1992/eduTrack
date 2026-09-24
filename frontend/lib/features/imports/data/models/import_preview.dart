/// What a file would import, without importing it (docs/imports.md).
///
/// The same reading and the same checks as a real upload, so a file that
/// would be refused is refused here too. What comes back is the parsed rows,
/// which is what somebody needs to answer "is this the right spreadsheet".
class ImportPreview {
  const ImportPreview({
    required this.label,
    required this.headings,
    required this.rowCount,
    required this.rows,
    required this.truncated,
  });

  factory ImportPreview.fromJson(Map<String, dynamic> json) {
    return ImportPreview(
      label: json['label'] as String? ?? 'Records',
      headings: List<String>.from(json['headings'] as List? ?? const []),
      rowCount: json['row_count'] as int? ?? 0,
      rows: [
        for (final row in json['rows'] as List? ?? const []) PreviewRow.fromJson((row as Map).cast<String, dynamic>()),
      ],
      truncated: json['truncated'] as bool? ?? false,
    );
  }

  final String label;
  final List<String> headings;

  /// Every row in the file, not just the ones shown.
  final int rowCount;
  final List<PreviewRow> rows;

  /// True when the file holds more rows than were sent back.
  final bool truncated;
}

class PreviewRow {
  const PreviewRow({required this.row, required this.values});

  factory PreviewRow.fromJson(Map<String, dynamic> json) {
    return PreviewRow(
      row: json['row'] as int? ?? 0,
      values: [for (final value in json['values'] as List? ?? const []) value as String?],
    );
  }

  /// The line in the spreadsheet, counting the headings as line 1.
  final int row;
  final List<String?> values;
}
