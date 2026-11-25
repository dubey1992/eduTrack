/// A parent-teacher meeting for one child's class (docs/mobile-apps-review.md,
/// M12, 8.4): the class's slots, free or taken (never by whom), and the
/// parent's own booking.
class FamilyMeeting {
  const FamilyMeeting({
    required this.id,
    required this.title,
    required this.date,
    required this.dateLabel,
    required this.bookingOpen,
    required this.slots,
    this.note,
    this.teacherName,
    this.mySlot,
  });

  factory FamilyMeeting.fromJson(Map<String, dynamic> json) {
    final mine = json['my_slot'] as Map<String, dynamic>?;
    return FamilyMeeting(
      id: json['id'] as int,
      title: json['title'] as String,
      date: DateTime.parse(json['meeting_date'] as String),
      dateLabel: json['date_label'] as String,
      note: json['note'] as String?,
      teacherName: json['teacher_name'] as String?,
      bookingOpen: json['booking_open'] as bool,
      mySlot: mine == null ? null : FamilyMeetingSlot.fromJson({...mine, 'free': false, 'mine': true}),
      slots: [
        for (final slot in json['slots'] as List<dynamic>) FamilyMeetingSlot.fromJson(slot as Map<String, dynamic>),
      ],
    );
  }

  final int id;
  final String title;
  final DateTime date;

  /// The date as the server writes it (US order).
  final String dateLabel;
  final String? note;
  final String? teacherName;

  /// Booking, moving and cancelling close at the end of the day before.
  final bool bookingOpen;
  final FamilyMeetingSlot? mySlot;
  final List<FamilyMeetingSlot> slots;

  bool get hasFreeSlot => slots.any((slot) => slot.free);
}

class FamilyMeetingSlot {
  const FamilyMeetingSlot({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.free,
    required this.mine,
  });

  factory FamilyMeetingSlot.fromJson(Map<String, dynamic> json) => FamilyMeetingSlot(
    id: json['id'] as int,
    startsAt: json['starts_at'] as String,
    endsAt: json['ends_at'] as String,
    free: json['free'] as bool,
    mine: json['mine'] as bool,
  );

  final int id;

  /// "09:30", the school's own time on the meeting's date.
  final String startsAt;
  final String endsAt;
  final bool free;
  final bool mine;
}
