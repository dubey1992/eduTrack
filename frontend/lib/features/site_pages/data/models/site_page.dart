/// A website page as a visitor reads it: the published version only
/// (docs/site-pages.md).
class SitePage {
  const SitePage({required this.slug, required this.title, required this.body, this.publishedAt});

  factory SitePage.fromJson(Map<String, dynamic> json) {
    return SitePage(
      slug: json['slug'] as String,
      title: json['title'] as String,
      body: json['body'] as String? ?? '',
      publishedAt: _date(json['published_at']),
    );
  }

  final String slug;
  final String title;

  /// Page text - see [parsePageText] for what it may hold.
  final String body;

  /// Null for a built-in page still showing the words it ships with and no
  /// date of its own, such as About Us.
  final DateTime? publishedAt;
}

/// One line of the Super Admin's list of pages.
class SitePageSummary {
  const SitePageSummary({
    required this.slug,
    required this.title,
    required this.builtIn,
    required this.isLive,
    required this.hasUnpublishedChanges,
    this.publishedAt,
    this.updatedAt,
  });

  factory SitePageSummary.fromJson(Map<String, dynamic> json) {
    return SitePageSummary(
      slug: json['slug'] as String,
      title: json['title'] as String,
      builtIn: json['built_in'] as bool? ?? false,
      isLive: json['is_live'] as bool? ?? false,
      hasUnpublishedChanges: json['has_unpublished_changes'] as bool? ?? false,
      publishedAt: _date(json['published_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  final String slug;

  /// The draft's title, which is what the Super Admin is working on.
  final String title;

  /// About Us, Privacy Policy and Terms of Use: editable, never deleted or
  /// renamed.
  final bool builtIn;

  /// Whether a visitor opening the page's address gets the page.
  final bool isLive;
  final bool hasUnpublishedChanges;
  final DateTime? publishedAt;
  final DateTime? updatedAt;
}

/// A page as the editor opens it: the draft, and what visitors read now.
class SitePageDetail extends SitePageSummary {
  const SitePageDetail({
    required super.slug,
    required super.title,
    required super.builtIn,
    required super.isLive,
    required super.hasUnpublishedChanges,
    required this.body,
    super.publishedAt,
    super.updatedAt,
    this.publishedTitle,
    this.publishedBody,
    this.websiteProblem,
  });

  factory SitePageDetail.fromJson(Map<String, dynamic> json) {
    final summary = SitePageSummary.fromJson(json);

    return SitePageDetail(
      slug: summary.slug,
      title: summary.title,
      builtIn: summary.builtIn,
      isLive: summary.isLive,
      hasUnpublishedChanges: summary.hasUnpublishedChanges,
      publishedAt: summary.publishedAt,
      updatedAt: summary.updatedAt,
      body: json['body'] as String? ?? '',
      publishedTitle: json['published_title'] as String?,
      publishedBody: json['published_body'] as String?,
      websiteProblem: json['website_problem'] as String?,
    );
  }

  /// The draft's text.
  final String body;
  final String? publishedTitle;
  final String? publishedBody;

  /// Set only on a publish whose plain-HTML page could not be written
  /// (docs/seo.md, S2). The publish itself stood.
  final String? websiteProblem;
}

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;
