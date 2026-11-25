/// An event with photos (docs/mobile-apps-review.md, M12, 8.6) - the same
/// shape for the school's screens and the Family app; the school's carries
/// who posted it and whether this person may change it.
class GalleryEvent {
  const GalleryEvent({
    required this.id,
    required this.schoolId,
    required this.title,
    required this.date,
    required this.dateLabel,
    required this.photos,
    this.description,
    this.classSectionId,
    this.className,
    this.postedBy,
    this.canChange = false,
  });

  factory GalleryEvent.fromJson(Map<String, dynamic> json) {
    final section = json['class_section'] as Map<String, dynamic>?;
    return GalleryEvent(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      title: json['title'] as String,
      date: DateTime.parse(json['event_date'] as String),
      dateLabel: json['date_label'] as String,
      description: json['description'] as String?,
      classSectionId: section?['id'] as int?,
      className: section?['name'] as String?,
      postedBy: json['posted_by'] as String?,
      canChange: json['can_change'] as bool? ?? false,
      photos: [for (final p in json['photos'] as List<dynamic>) GalleryPhoto.fromJson(p as Map<String, dynamic>)],
    );
  }

  final int id;
  final int schoolId;
  final String title;
  final DateTime date;
  final String dateLabel;
  final String? description;

  /// Null for the whole school.
  final int? classSectionId;
  final String? className;
  final String? postedBy;
  final bool canChange;
  final List<GalleryPhoto> photos;
}

class GalleryPhoto {
  const GalleryPhoto({required this.id, required this.url, required this.thumbUrl});

  factory GalleryPhoto.fromJson(Map<String, dynamic> json) =>
      GalleryPhoto(id: json['id'] as int, url: json['url'] as String, thumbUrl: json['thumb_url'] as String);

  final int id;

  /// API paths, read with the session (core/widgets/signed_in_image.dart).
  final String url;
  final String thumbUrl;
}

/// What a poster fills in for a new or changed event.
class GalleryEventDraft {
  const GalleryEventDraft({
    required this.title,
    required this.date,
    this.description,
    this.classSectionId,
    this.schoolId,
  });

  final String title;
  final DateTime date;
  final String? description;

  /// Null for the whole school (admins only).
  final int? classSectionId;
  final int? schoolId;
}

/// Most photos an event may carry (server rule).
const galleryMaxPhotos = 20;
