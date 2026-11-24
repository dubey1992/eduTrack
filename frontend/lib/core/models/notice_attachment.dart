/// A file a notice carries (docs/mobile-apps-review.md, M9, 8.3): a PDF, a
/// JPEG or a PNG, read through the signed-in API - never a public link.
class NoticeAttachment {
  const NoticeAttachment({
    required this.id,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    required this.url,
  });

  factory NoticeAttachment.fromJson(Map<String, dynamic> json) => NoticeAttachment(
    id: json['id'] as int,
    name: json['name'] as String,
    contentType: json['content_type'] as String,
    sizeBytes: json['size_bytes'] as int,
    url: json['url'] as String,
  );

  /// Every attachment in a JSON list, or none when the key is missing - an
  /// older server, or a message that is not a notice.
  static List<NoticeAttachment> listFrom(Object? json) => [
    for (final item in (json as List<dynamic>?) ?? const []) NoticeAttachment.fromJson(item as Map<String, dynamic>),
  ];

  final int id;
  final String name;
  final String contentType;
  final int sizeBytes;

  /// Relative to the API base.
  final String url;

  bool get isImage => contentType.startsWith('image/');

  /// "240 KB", "1.4 MB".
  String get sizeLabel {
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).ceil()} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
