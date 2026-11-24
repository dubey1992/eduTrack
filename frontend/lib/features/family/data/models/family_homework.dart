/// Homework for a child's class, as the teachers wrote it in their teaching
/// reports (docs/mobile-apps-review.md, M8, 8.1).
class HomeworkDay {
  const HomeworkDay({required this.date, required this.dateLabel, required this.today, required this.items});

  factory HomeworkDay.fromJson(Map<String, dynamic> json) => HomeworkDay(
    date: json['date'] as String,
    dateLabel: json['date_label'] as String,
    today: json['today'] as bool? ?? false,
    items: [for (final item in json['items'] as List<dynamic>) HomeworkItem.fromJson(item as Map<String, dynamic>)],
  );

  /// `yyyy-MM-dd`.
  final String date;

  /// The school's way of writing it (US order, as everywhere in the app).
  final String dateLabel;
  final bool today;
  final List<HomeworkItem> items;
}

class HomeworkItem {
  const HomeworkItem({required this.id, required this.subject, required this.homework});

  factory HomeworkItem.fromJson(Map<String, dynamic> json) =>
      HomeworkItem(id: json['id'] as int, subject: json['subject'] as String?, homework: json['homework'] as String);

  final int id;
  final String? subject;
  final String homework;
}
