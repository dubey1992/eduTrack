/// Parent-teacher meetings as the school runs them (docs/mobile-apps-review.md,
/// M12, 8.4). The parent's side is in features/family.
class PtmMeeting {
  const PtmMeeting({
    required this.id,
    required this.schoolId,
    required this.title,
    required this.date,
    required this.cancelled,
    required this.bookingOpen,
    required this.classes,
    this.note,
  });

  factory PtmMeeting.fromJson(Map<String, dynamic> json) => PtmMeeting(
    id: json['id'] as int,
    schoolId: json['school_id'] as int,
    title: json['title'] as String,
    date: DateTime.parse(json['meeting_date'] as String),
    note: json['note'] as String?,
    cancelled: json['status'] == 'cancelled',
    bookingOpen: json['booking_open'] as bool,
    classes: [
      for (final row in json['sections'] as List<dynamic>) PtmMeetingClass.fromJson(row as Map<String, dynamic>),
    ],
  );

  final int id;
  final int schoolId;
  final String title;
  final DateTime date;
  final String? note;
  final bool cancelled;

  /// Parents may still book, move and cancel: until the end of the day before.
  final bool bookingOpen;

  /// The classes taking part - for a teacher, only their own.
  final List<PtmMeetingClass> classes;
}

class PtmMeetingClass {
  const PtmMeetingClass({
    required this.id,
    required this.name,
    required this.slots,
    required this.booked,
    this.classTeacher,
  });

  factory PtmMeetingClass.fromJson(Map<String, dynamic> json) => PtmMeetingClass(
    id: json['id'] as int,
    name: json['name'] as String,
    classTeacher: json['class_teacher'] as String?,
    slots: json['slots'] as int,
    booked: json['booked'] as int,
  );

  /// The class section's id.
  final int id;
  final String name;
  final String? classTeacher;
  final int slots;
  final int booked;
}

/// What the office fills in to create or change a meeting.
class PtmMeetingDraft {
  const PtmMeetingDraft({required this.title, required this.date, required this.sectionIds, this.note, this.schoolId});

  final String title;
  final DateTime date;
  final String? note;
  final List<int> sectionIds;

  /// Only for someone who answers for several schools; the server decides otherwise.
  final int? schoolId;
}

class PtmSlot {
  const PtmSlot({required this.id, required this.startsAt, required this.endsAt, this.teacherName, this.booking});

  factory PtmSlot.fromJson(Map<String, dynamic> json) {
    final booking = json['booking'] as Map<String, dynamic>?;
    return PtmSlot(
      id: json['id'] as int,
      startsAt: json['starts_at'] as String,
      endsAt: json['ends_at'] as String,
      teacherName: json['teacher_name'] as String?,
      booking: booking == null ? null : PtmBooking.fromJson(booking),
    );
  }

  final int id;

  /// "09:30", the school's own time on the meeting's date.
  final String startsAt;
  final String endsAt;
  final String? teacherName;
  final PtmBooking? booking;
}

class PtmBooking {
  const PtmBooking({required this.studentName, required this.parentName, this.parentMobile});

  factory PtmBooking.fromJson(Map<String, dynamic> json) {
    final parent = json['parent'] as Map<String, dynamic>;
    return PtmBooking(
      studentName: (json['student'] as Map<String, dynamic>)['name'] as String,
      parentName: parent['name'] as String,
      parentMobile: parent['mobile'] as String?,
    );
  }

  final String studentName;
  final String parentName;
  final String? parentMobile;
}
