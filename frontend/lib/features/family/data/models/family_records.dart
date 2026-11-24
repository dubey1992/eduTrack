/// The attendance calendar, the school calendar, the notices and the
/// notification switches of the Family app (school/family_day.py,
/// school/family_inbox.py).
library;

import '../../../../core/models/notice_attachment.dart';

/// What a day on the attendance calendar was.
enum DayKind {
  present('present'),
  absent('absent'),
  leave('leave'),
  notMarked('not_marked'),
  holiday('holiday'),
  closed('closed'),
  future('future');

  const DayKind(this.apiValue);

  final String apiValue;

  static DayKind fromApiValue(String value) =>
      values.firstWhere((kind) => kind.apiValue == value, orElse: () => notMarked);
}

class AttendanceDay {
  const AttendanceDay({required this.date, required this.kind, required this.holiday, required this.remarks});

  factory AttendanceDay.fromJson(Map<String, dynamic> json) => AttendanceDay(
    date: DateTime.parse(json['date'] as String),
    kind: DayKind.fromApiValue(json['kind'] as String),
    holiday: json['holiday'] as String?,
    remarks: json['remarks'] as String?,
  );

  final DateTime date;
  final DayKind kind;
  final String? holiday;

  /// The teacher's note on an absence or a leave.
  final String? remarks;
}

/// Present, absent and leave over some working days, and the rate.
class AttendanceSummary {
  const AttendanceSummary({
    required this.workingDays,
    this.markedDays,
    this.notMarked = 0,
    required this.present,
    required this.absent,
    required this.leave,
    required this.rate,
    this.label,
  });

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) => AttendanceSummary(
    workingDays: json['working_days'] as int,
    markedDays: json['marked_days'] as int?,
    notMarked: json['not_marked'] as int? ?? 0,
    present: json['present'] as int,
    absent: json['absent'] as int,
    leave: json['leave'] as int,
    rate: (json['rate'] as num?)?.toDouble(),
    label: json['label'] as String?,
  );

  final int workingDays;

  /// The days the register was marked: what the rate is out of. A day the
  /// school never marked does not count against the child.
  final int? markedDays;
  final int notMarked;
  final int present;
  final int absent;
  final int leave;

  /// Null before there is a working day to count.
  final double? rate;

  /// The academic year's name, on the year's summary.
  final String? label;
}

class AttendanceMonth {
  const AttendanceMonth({
    required this.month,
    required this.today,
    required this.days,
    required this.monthSummary,
    required this.yearSummary,
    this.belowLine,
  });

  factory AttendanceMonth.fromJson(Map<String, dynamic> json) {
    final year = json['year_summary'] as Map<String, dynamic>?;
    final below = json['below_line'] as Map<String, dynamic>?;

    return AttendanceMonth(
      month: DateTime.parse('${json['month']}-01'),
      today: DateTime.parse(json['today'] as String),
      days: [for (final d in json['days'] as List<dynamic>) AttendanceDay.fromJson(d as Map<String, dynamic>)],
      monthSummary: AttendanceSummary.fromJson(json['month_summary'] as Map<String, dynamic>),
      yearSummary: year == null ? null : AttendanceSummary.fromJson(year),
      belowLine: below == null
          ? null
          : (rate: double.parse(below['rate'] as String), line: below['line'] as int, days: below['days'] as int),
    );
  }

  /// While attendance stands below the school's early-warning line (M8, 5.4):
  /// the figure over the last [days] school days, and the line.
  final ({double rate, int line, int days})? belowLine;

  /// The 1st of the month shown.
  final DateTime month;
  final DateTime today;
  final List<AttendanceDay> days;
  final AttendanceSummary monthSummary;
  final AttendanceSummary? yearSummary;

  /// The absences and leaves this month, newest first, with their reasons.
  List<AttendanceDay> get missed =>
      days.where((d) => d.kind == DayKind.absent || d.kind == DayKind.leave).toList().reversed.toList();
}

class SchoolHoliday {
  const SchoolHoliday({required this.name, required this.type, required this.start, required this.end});

  factory SchoolHoliday.fromJson(Map<String, dynamic> json) => SchoolHoliday(
    name: json['name'] as String,
    type: json['type'] as String,
    start: DateTime.parse(json['start_date'] as String),
    end: DateTime.parse(json['end_date'] as String),
  );

  final String name;
  final String type;
  final DateTime start;
  final DateTime end;

  bool get isOneDay => start == end;

  bool covers(DateTime day) => !day.isBefore(start) && !day.isAfter(end);
}

class SchoolCalendar {
  const SchoolCalendar({
    required this.month,
    required this.today,
    required this.closedWeekdays,
    required this.holidays,
    required this.upcoming,
  });

  factory SchoolCalendar.fromJson(Map<String, dynamic> json) => SchoolCalendar(
    month: DateTime.parse('${json['month']}-01'),
    today: DateTime.parse(json['today'] as String),
    closedWeekdays: [for (final day in json['closed_weekdays'] as List<dynamic>) day as String],
    holidays: [for (final h in json['holidays'] as List<dynamic>) SchoolHoliday.fromJson(h as Map<String, dynamic>)],
    upcoming: [for (final h in json['upcoming'] as List<dynamic>) SchoolHoliday.fromJson(h as Map<String, dynamic>)],
  );

  final DateTime month;
  final DateTime today;

  /// "saturday", "sunday" - the days of the week the school never opens.
  final List<String> closedWeekdays;
  final List<SchoolHoliday> holidays;
  final List<SchoolHoliday> upcoming;

  static const _weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

  bool isClosedWeekday(DateTime day) => closedWeekdays.contains(_weekdays[day.weekday - 1]);

  SchoolHoliday? holidayOn(DateTime day) => holidays.where((h) => h.covers(day)).firstOrNull;
}

/// One of the school's messages to the parent.
class FamilyNotice {
  const FamilyNotice({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.studentName,
    required this.createdAt,
    required this.read,
    this.reply,
    this.attachments = const [],
  });

  factory FamilyNotice.fromJson(Map<String, dynamic> json) => FamilyNotice(
    id: json['id'] as int,
    category: json['category'] as String,
    title: json['title'] as String?,
    body: json['body'] as String,
    studentName: json['student_name'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    read: json['read'] as bool,
    reply: NoticeReply.fromJson(json['reply'] as Map<String, dynamic>?),
    attachments: NoticeAttachment.listFrom(json['attachments']),
  );

  final int id;
  final String category;
  final String? title;
  final String body;
  final String? studentName;
  final DateTime createdAt;
  final bool read;

  /// A notice that asks the parent a Yes/No question (F5); null otherwise.
  final NoticeReply? reply;

  /// The files the notice carries (M9, 8.3).
  final List<NoticeAttachment> attachments;

  FamilyNotice withReply(NoticeReply value) => FamilyNotice(
    id: id,
    category: category,
    title: title,
    body: body,
    studentName: studentName,
    createdAt: createdAt,
    read: read,
    reply: value,
    attachments: attachments,
  );

  FamilyNotice markedRead() => FamilyNotice(
    id: id,
    category: category,
    title: title,
    body: body,
    studentName: studentName,
    createdAt: createdAt,
    read: true,
    reply: reply,
    attachments: attachments,
  );

  /// The kind of message in plain words, when it has no title of its own.
  String get kindLabel => switch (category) {
    'attendance' => 'Attendance',
    'transport' => 'School bus',
    'fee' => 'Fees',
    'result' => 'Results',
    'emergency' => 'Emergency',
    'announcement' => 'Notice',
    _ => 'Message from school',
  };
}

class NoticesPage {
  const NoticesPage({required this.notices, required this.unreadCount, required this.hasMore});

  final List<FamilyNotice> notices;
  final int unreadCount;
  final bool hasMore;
}

/// Which kinds of message come to the app. An emergency always does.
class FamilyNotificationSettings {
  const FamilyNotificationSettings({
    required this.attendance,
    required this.transport,
    required this.fee,
    required this.result,
    required this.notices,
    this.homework = true,
  });

  factory FamilyNotificationSettings.fromJson(Map<String, dynamic> json) => FamilyNotificationSettings(
    attendance: json['attendance'] as bool,
    transport: json['transport'] as bool,
    fee: json['fee'] as bool,
    result: json['result'] as bool,
    notices: json['notices'] as bool,
    // An older server that does not know the switch sends nothing: on.
    homework: json['homework'] as bool? ?? true,
  );

  final bool attendance;
  final bool transport;
  final bool fee;
  final bool result;
  final bool notices;

  /// The evening "homework for today" message (M8, 8.1).
  final bool homework;

  bool valueOf(String key) => toJson()[key]!;

  FamilyNotificationSettings withValue(String key, bool value) =>
      FamilyNotificationSettings.fromJson({...toJson(), key: value});

  Map<String, bool> toJson() => {
    'attendance': attendance,
    'transport': transport,
    'fee': fee,
    'result': result,
    'notices': notices,
    'homework': homework,
  };
}

/// The question a notice asks, and this parent's answer for each of their
/// children it is about (F5).
class NoticeReply {
  const NoticeReply({required this.question, this.replyBy, required this.open, required this.children});

  static NoticeReply? fromJson(Map<String, dynamic>? json) => json == null
      ? null
      : NoticeReply(
          question: json['question'] as String,
          replyBy: json['reply_by'] == null ? null : DateTime.parse(json['reply_by'] as String),
          open: json['open'] as bool? ?? true,
          children: [
            for (final child in json['children'] as List<dynamic>)
              (
                studentId: (child as Map<String, dynamic>)['student_id'] as int,
                name: child['name'] as String,
                answer: child['answer'] as bool?,
                note: child['note'] as String?,
                answeredAt: child['answered_at'] == null
                    ? null
                    : DateTime.parse(child['answered_at'] as String).toLocal(),
              ),
          ],
        );

  final String question;
  final DateTime? replyBy;

  /// Answers are still taken.
  final bool open;

  /// Each child asked about; [answeredAt] is when the school got the answer.
  final List<({int studentId, String name, bool? answer, String? note, DateTime? answeredAt})> children;

  /// Still open, and a child without an answer.
  bool get awaitsAnswer => open && children.any((child) => child.answer == null);
}
