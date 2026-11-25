"""Parent-teacher meetings booked from the Family app
(docs/mobile-apps-review.md, M12, 8.4, decided by the owner 2026-11-25).

- A School Admin creates the meeting day: a title, the date, an optional note
  to parents and the classes taking part.
- Each class teacher, or an admin, opens slots for their class: a time range
  cut into slots of 5 to 60 minutes. The first time a class's slots open, its
  parents get one Family-app message.
- A parent books one slot per child, and may move it to another free slot or
  cancel it until the end of the day before. On the day the list is fixed.
- The teacher sees who booked: the child, the parent and the parent's mobile.
- The day before, booked parents and each teacher with bookings are reminded
  (the Family app and the staff inbox - never an SMS).
- Removing a booked slot, or cancelling the meeting, tells the parents who
  had booked.

Slot times are the school's own wall-clock times on the meeting's date.
"""

from __future__ import annotations

import datetime as dt

from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework import status

from . import audit, dates, modules
from .clock import SchoolClock
from .enums import MessageEvent, SchoolStatus, StudentStatus, UserRole
from .errors import ApiError
from .models import (
    ClassSection,
    Guardian,
    Message,
    PtmBooking,
    PtmMeeting,
    PtmMeetingSection,
    PtmSlot,
    School,
    Student,
    User,
)
from .resources import section_label
from .scope import SchoolScope

SCHEDULED = "scheduled"
CANCELLED = "cancelled"

TITLE_MAX = 120
NOTE_MAX = 300
SLOT_MIN = 5
SLOT_MAX = 60
# One opening never makes more than this many slots: a day of 10-minute
# slots is 48, and a typing slip ("9:00 to 21:00 every 5") should not make 144.
SLOTS_PER_OPENING = 60

# The reminder for tomorrow goes after this, on the school's own clock.
REMIND_AT = dt.time(17, 0)

ADMINS = (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN)


class PtmRefused(ApiError):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    error_code = "PTM_REFUSED"


class SlotTaken(ApiError):
    status_code = status.HTTP_409_CONFLICT
    error_code = "PTM_SLOT_TAKEN"


class BookingClosed(ApiError):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    error_code = "PTM_BOOKING_CLOSED"


def refused(field: str, message: str) -> PtmRefused:
    return PtmRefused(message, {"errors": {field: [message]}})


# -- who may do what -----------------------------------------------------------


def is_admin(actor: User) -> bool:
    return actor.role in ADMINS


def may_manage_meeting(actor: User, meeting: PtmMeeting) -> bool:
    return is_admin(actor) and SchoolScope.for_actor(actor).allows(meeting.school_id)


def may_manage_section(actor: User, meeting: PtmMeeting, section: ClassSection) -> bool:
    """An admin of the school, or the class teacher of that class."""
    if may_manage_meeting(actor, meeting):
        return True

    return section.class_teacher_id is not None and section.class_teacher_id == actor.id


def today_at(school_id: int) -> dt.date:
    return SchoolClock.for_school(school_id).now().date()


def booking_open(meeting: PtmMeeting, today: dt.date | None = None) -> bool:
    """Parents book, move and cancel until the end of the day before."""
    today = today or today_at(meeting.school_id)
    return meeting.status == SCHEDULED and today < meeting.meeting_date


# -- the meeting day -------------------------------------------------------------


def sections_of_school(school_id: int, section_ids) -> list[ClassSection]:
    ids = sorted({int(i) for i in section_ids or []})
    if not ids:
        raise refused("section_ids", "Choose at least one class taking part.")

    found = list(
        ClassSection.objects.select_related("school_class")
        .filter(pk__in=ids, school_class__school_id=school_id)
        .order_by("school_class__level", "school_class__name", "name")
    )
    if len(found) != len(ids):
        raise refused("section_ids", "One of the classes chosen is not at this school.")

    return found


def checked_details(school_id: int, title, meeting_date: dt.date, note) -> tuple[str, str | None]:
    title = (title or "").strip()
    note = (note or "").strip() or None
    if not title or len(title) > TITLE_MAX:
        raise refused("title", f"Give the meeting a name of up to {TITLE_MAX} characters.")
    if note is not None and len(note) > NOTE_MAX:
        raise refused("note", f"Please keep the note to {NOTE_MAX} characters.")
    if meeting_date < today_at(school_id):
        raise refused("meeting_date", "The meeting date cannot be in the past.")

    return title, note


def create_meeting(actor: User, school_id: int, title, meeting_date: dt.date, note, section_ids,
                   request=None) -> PtmMeeting:
    title, note = checked_details(school_id, title, meeting_date, note)
    sections = sections_of_school(school_id, section_ids)

    now = timezone.now()
    with transaction.atomic():
        meeting = PtmMeeting.objects.create(
            school_id=school_id, title=title, meeting_date=meeting_date, note=note, status=SCHEDULED,
            created_by=actor, created_at=now, updated_at=now,
        )
        PtmMeetingSection.objects.bulk_create([
            PtmMeetingSection(ptm_meeting=meeting, class_section=section, created_at=now, updated_at=now)
            for section in sections
        ])
        audit.record(
            action="ptm.created", module="communication", entity_type="ptm_meeting", entity_id=meeting.id,
            school_id=school_id, new={"title": title, "meeting_date": meeting_date.isoformat(),
                                      "section_ids": [s.id for s in sections]},
            request=request,
        )

    return meeting


def update_meeting(meeting: PtmMeeting, title, meeting_date: dt.date, note, section_ids, request=None) -> PtmMeeting:
    """The name, note and classes may change while the meeting is ahead. The
    date may not once a parent has booked - they booked a day, not a time."""
    if meeting.status != SCHEDULED:
        raise refused("status", "This meeting was cancelled, so it cannot be changed.")
    if meeting.meeting_date < today_at(meeting.school_id):
        raise refused("meeting_date", "This meeting is over, so it cannot be changed.")

    title, note = checked_details(meeting.school_id, title, meeting_date, note)
    sections = sections_of_school(meeting.school_id, section_ids)
    has_bookings = PtmBooking.objects.filter(ptm_meeting_id=meeting.id).exists()
    if meeting_date != meeting.meeting_date and has_bookings:
        raise refused(
            "meeting_date",
            "Parents have already booked for this date. Cancel this meeting and create a new one instead.",
        )

    wanted = {s.id for s in sections}
    current = set(PtmMeetingSection.objects.filter(ptm_meeting_id=meeting.id).values_list("class_section_id", flat=True))
    dropped = current - wanted
    if dropped and PtmBooking.objects.filter(ptm_meeting_id=meeting.id, ptm_slot__class_section_id__in=dropped).exists():
        raise refused("section_ids", "A class you removed has bookings. Remove its booked slots first.")

    old = {"title": meeting.title, "meeting_date": meeting.meeting_date.isoformat(), "note": meeting.note,
           "section_ids": sorted(current)}
    now = timezone.now()
    with transaction.atomic():
        meeting.title, meeting.meeting_date, meeting.note, meeting.updated_at = title, meeting_date, note, now
        meeting.save(update_fields=["title", "meeting_date", "note", "updated_at"])
        PtmSlot.objects.filter(ptm_meeting_id=meeting.id, class_section_id__in=dropped).delete()
        PtmMeetingSection.objects.filter(ptm_meeting_id=meeting.id, class_section_id__in=dropped).delete()
        PtmMeetingSection.objects.bulk_create([
            PtmMeetingSection(ptm_meeting=meeting, class_section_id=section_id, created_at=now, updated_at=now)
            for section_id in sorted(wanted - current)
        ])
        audit.record(
            action="ptm.updated", module="communication", entity_type="ptm_meeting", entity_id=meeting.id,
            school_id=meeting.school_id, old=old,
            new={"title": title, "meeting_date": meeting_date.isoformat(), "note": note, "section_ids": sorted(wanted)},
            request=request,
        )

    return meeting


def cancel_meeting(meeting: PtmMeeting, request=None) -> PtmMeeting:
    """Cancelled, not deleted: the parents who booked are told, and the
    bookings stay on record under a cancelled meeting."""
    if meeting.status == CANCELLED:
        return meeting

    now = timezone.now()
    meeting.status = CANCELLED
    meeting.updated_at = now
    meeting.save(update_fields=["status", "updated_at"])
    audit.record(
        action="ptm.cancelled", module="communication", entity_type="ptm_meeting", entity_id=meeting.id,
        school_id=meeting.school_id, request=request,
    )
    if meeting.meeting_date >= today_at(meeting.school_id):
        for booking in bookings_query().filter(ptm_meeting_id=meeting.id):
            tell_cancelled(booking, "The meeting was cancelled.")

    return meeting


# -- slots ---------------------------------------------------------------------------


def parse_time(value, field: str) -> dt.time:
    if isinstance(value, dt.time):
        return value
    try:
        return dt.datetime.strptime(str(value or "").strip()[:5], "%H:%M").time()
    except ValueError:
        raise refused(field, "Give the time as HH:MM, for example 09:30.")


def open_slots(meeting: PtmMeeting, section: ClassSection, actor: User, starts, ends, length, request=None) -> list[PtmSlot]:
    """Cuts [starts, ends) into slots of [length] minutes. A slot that would
    overlap one the class already has is skipped, so opening the same range
    twice adds nothing."""
    if meeting.status != SCHEDULED:
        raise refused("status", "This meeting was cancelled.")
    if meeting.meeting_date < today_at(meeting.school_id):
        raise refused("meeting_date", "This meeting is over.")

    taking_part = PtmMeetingSection.objects.filter(ptm_meeting_id=meeting.id, class_section_id=section.id).first()
    if taking_part is None:
        raise refused("class_section_id", "This class is not taking part in this meeting.")

    start = parse_time(starts, "starts_at")
    end = parse_time(ends, "ends_at")
    try:
        minutes = int(length)
    except (TypeError, ValueError):
        minutes = 0
    if not SLOT_MIN <= minutes <= SLOT_MAX:
        raise refused("slot_minutes", f"Choose a slot length of {SLOT_MIN} to {SLOT_MAX} minutes.")
    if end <= start:
        raise refused("ends_at", "The end time must be after the start time.")

    day = meeting.meeting_date
    cursor = dt.datetime.combine(day, start)
    stop = dt.datetime.combine(day, end)
    step = dt.timedelta(minutes=minutes)
    wanted = []
    while cursor + step <= stop:
        wanted.append((cursor.time(), (cursor + step).time()))
        cursor += step
    if not wanted:
        raise refused("ends_at", f"That range is shorter than one {minutes}-minute slot.")
    if len(wanted) > SLOTS_PER_OPENING:
        raise refused("ends_at", f"That would make {len(wanted)} slots; open at most {SLOTS_PER_OPENING} at a time.")

    existing = list(PtmSlot.objects.filter(ptm_meeting_id=meeting.id, class_section_id=section.id)
                    .values_list("starts_at", "ends_at"))
    fresh = [(s, e) for s, e in wanted if not any(s < e2 and s2 < e for s2, e2 in existing)]

    teacher_id = section.class_teacher_id or (actor.id if not is_admin(actor) else None)
    now = timezone.now()
    with transaction.atomic():
        made = [
            PtmSlot.objects.create(
                school_id=meeting.school_id, ptm_meeting=meeting, class_section=section, teacher_user_id=teacher_id,
                starts_at=s, ends_at=e, created_at=now, updated_at=now,
            )
            for s, e in fresh
        ]
        first_opening = bool(made) and taking_part.slots_opened_at is None
        if first_opening:
            taking_part.slots_opened_at = now
            taking_part.updated_at = now
            taking_part.save(update_fields=["slots_opened_at", "updated_at"])
        if made:
            audit.record(
                action="ptm.slots_opened", module="communication", entity_type="ptm_meeting", entity_id=meeting.id,
                school_id=meeting.school_id,
                new={"class_section_id": section.id, "slots": len(made), "from": start.strftime("%H:%M"),
                     "to": end.strftime("%H:%M"), "minutes": minutes},
                request=request,
            )

    if first_opening and booking_open(meeting):
        tell_slots_open(meeting, section)

    return made


def remove_slot(slot: PtmSlot, request=None) -> None:
    """A free slot goes quietly; a booked one tells the parent who booked it."""
    meeting = slot.ptm_meeting
    if meeting.meeting_date < today_at(meeting.school_id):
        raise refused("meeting_date", "This meeting is over, so its slots stay as they were.")

    booking = bookings_query().filter(ptm_slot_id=slot.id).first()
    old = {"class_section_id": slot.class_section_id, "starts_at": slot.starts_at.strftime("%H:%M"),
           "booked_student_id": booking.student_id if booking else None}
    with transaction.atomic():
        if booking is not None:
            booking.delete()
        slot.delete()
        audit.record(
            action="ptm.slot_removed", module="communication", entity_type="ptm_meeting", entity_id=meeting.id,
            school_id=meeting.school_id, old=old, request=request,
        )
    if booking is not None and meeting.status == SCHEDULED:
        tell_cancelled(booking, "The teacher removed this time. Please book another.", slot=slot)


# -- bookings ---------------------------------------------------------------------


def bookings_query():
    return PtmBooking.objects.select_related(
        "ptm_meeting", "ptm_slot__teacher_user", "ptm_slot__class_section__school_class", "student", "booked_by",
    )


def meetings_for_child(child: Student):
    """The scheduled meetings ahead that the child's class takes part in."""
    if child.class_section_id is None:
        return PtmMeeting.objects.none()

    return (
        PtmMeeting.objects.filter(
            school_id=child.school_id, status=SCHEDULED, meeting_date__gte=today_at(child.school_id),
            sections__class_section_id=child.class_section_id,
        )
        .distinct()
        .order_by("meeting_date", "id")
    )


def book(child: Student, parent: User, meeting: PtmMeeting, slot_id: int, request=None) -> PtmBooking:
    """Books [slot_id] for [child], moving an earlier booking of theirs for
    the same meeting. Two parents after the same slot: the second hears it
    was just taken."""
    if not booking_open(meeting):
        raise BookingClosed("Booking for this meeting has closed. Please contact the school.")

    slot = PtmSlot.objects.filter(pk=slot_id, ptm_meeting_id=meeting.id, class_section_id=child.class_section_id).first()
    if slot is None:
        raise refused("slot_id", "That time is not one of this class's slots.")

    mine = PtmBooking.objects.filter(ptm_meeting_id=meeting.id, student_id=child.id).first()
    if mine is not None and mine.ptm_slot_id == slot.id:
        return mine

    now = timezone.now()
    try:
        with transaction.atomic():
            if mine is not None:
                mine.delete()
            booking = PtmBooking.objects.create(
                school_id=meeting.school_id, ptm_meeting=meeting, ptm_slot=slot, student=child, booked_by=parent,
                created_at=now, updated_at=now,
            )
    except IntegrityError:
        raise SlotTaken("Someone has just booked that time. Please choose another.")

    audit.record(
        action="ptm.booked" if mine is None else "ptm.moved", module="communication", entity_type="ptm_meeting",
        entity_id=meeting.id, school_id=meeting.school_id, actor=parent,
        old={"slot_id": mine.ptm_slot_id} if mine else None,
        new={"student_id": child.id, "slot_id": slot.id, "starts_at": slot.starts_at.strftime("%H:%M")},
        request=request,
    )

    return booking


def cancel_booking(child: Student, parent: User, meeting: PtmMeeting, request=None) -> None:
    if not booking_open(meeting):
        raise BookingClosed("This booking can no longer be changed. Please contact the school.")

    mine = PtmBooking.objects.filter(ptm_meeting_id=meeting.id, student_id=child.id).first()
    if mine is None:
        return

    slot_id = mine.ptm_slot_id
    mine.delete()
    audit.record(
        action="ptm.booking_cancelled", module="communication", entity_type="ptm_meeting", entity_id=meeting.id,
        school_id=meeting.school_id, actor=parent, old={"student_id": child.id, "slot_id": slot_id},
        request=request,
    )


# -- telling people -----------------------------------------------------------------


def time_label(value: dt.time) -> str:
    return dt.datetime.combine(dt.date(2000, 1, 1), value).strftime("%I:%M %p").lstrip("0")


def school_name_of(school_id: int) -> str:
    return School.objects.filter(pk=school_id).values_list("name", flat=True).first() or ""


def family_tokens(meeting: PtmMeeting, student: Student, slot: PtmSlot | None = None, teacher: User | None = None,
                  reason: str = "") -> dict:
    teacher = teacher or (slot.teacher_user if slot is not None else None)
    return {
        "student_name": student.name,
        "title": meeting.title,
        "date": dates.us(meeting.meeting_date),
        "time": time_label(slot.starts_at) if slot is not None else "",
        "teacher_name": teacher.name if teacher is not None else "the class teacher",
        "reason": reason,
        "school_name": school_name_of(meeting.school_id),
    }


def tell_slots_open(meeting: PtmMeeting, section: ClassSection) -> int:
    from .notifications import copy_to_family_app

    teacher = User.objects.filter(pk=section.class_teacher_id).first() if section.class_teacher_id else None
    told = 0
    for student in Student.objects.filter(class_section_id=section.id, status=StudentStatus.ACTIVE):
        told += len(copy_to_family_app(
            MessageEvent.PTM_SLOTS_OPEN, student, family_tokens(meeting, student, teacher=teacher),
            subject=meeting.title,
        ))

    return told


def tell_cancelled(booking: PtmBooking, reason: str, slot: PtmSlot | None = None) -> None:
    from .notifications import copy_to_family_app

    copy_to_family_app(
        MessageEvent.PTM_BOOKING_CANCELLED, booking.student,
        family_tokens(booking.ptm_meeting, booking.student, slot or booking.ptm_slot, reason=reason),
        subject=f"{booking.ptm_meeting.title}: booking cancelled",
    )


def send_reminders(at: dt.datetime | None = None, school_id: int | None = None) -> int:
    """The evening before each meeting: every booked family, and each teacher
    with bookings. Once each - the message written is the proof it went, so
    the cron may run as often as it likes. Returns how many were told."""
    schools = School.objects.filter(status=SchoolStatus.ACTIVE)
    if school_id is not None:
        schools = schools.filter(pk=school_id)

    told = 0
    for school in schools:
        if not modules.is_enabled(school.id, "family_app"):
            continue

        clock = SchoolClock.for_school(school.id)
        now = at.astimezone(clock.now().tzinfo) if at is not None else clock.now()
        if now.time() < REMIND_AT:
            continue

        tomorrow = now.date() + dt.timedelta(days=1)
        for meeting in PtmMeeting.objects.filter(school_id=school.id, status=SCHEDULED, meeting_date=tomorrow):
            told += remind_for(meeting, clock.start_of_day_utc(now.date()))

    return told


def remind_for(meeting: PtmMeeting, since: dt.datetime) -> int:
    from .notifications import copy_to_family_app, notify_staff

    bookings = list(bookings_query().filter(ptm_meeting_id=meeting.id).order_by("ptm_slot__starts_at"))
    if not bookings:
        return 0

    sent_today = Message.objects.filter(school_id=meeting.school_id, created_at__gte=since)
    families_told = set(sent_today.filter(event=MessageEvent.PTM_REMINDER).values_list("student_id", flat=True))
    staff_told = set(sent_today.filter(event=MessageEvent.PTM_TEACHER_REMINDER).values_list("user_id", flat=True))

    told = 0
    by_teacher: dict[int, list[PtmBooking]] = {}
    for booking in bookings:
        if booking.ptm_slot.teacher_user_id:
            by_teacher.setdefault(booking.ptm_slot.teacher_user_id, []).append(booking)
        if booking.student_id in families_told:
            continue
        if copy_to_family_app(
            MessageEvent.PTM_REMINDER, booking.student, family_tokens(meeting, booking.student, booking.ptm_slot),
            subject=f"{meeting.title} tomorrow",
        ):
            told += 1

    for teacher_id, theirs in by_teacher.items():
        if teacher_id in staff_told:
            continue
        teacher = theirs[0].ptm_slot.teacher_user
        notify_staff(
            MessageEvent.PTM_TEACHER_REMINDER, teacher,
            {"title": meeting.title, "date": dates.us(meeting.meeting_date), "count": f"{len(theirs)} parent{'' if len(theirs) == 1 else 's'}",
             "time": time_label(theirs[0].ptm_slot.starts_at)},
            subject=f"{meeting.title} tomorrow",
        )
        told += 1

    return told


# -- what the screens read -----------------------------------------------------------


def parent_mobile(parent: User) -> str | None:
    guardian = Guardian.objects.filter(user_id=parent.id).first()
    return (guardian.login_mobile if guardian else None) or parent.mobile


def meeting_resource(meeting: PtmMeeting, actor: User | None = None) -> dict:
    """A meeting as the office and teachers list it: each class with its
    slot and booking counts. A teacher sees only their own classes in it."""
    rows = list(
        PtmMeetingSection.objects.select_related("class_section__school_class", "class_section__class_teacher")
        .filter(ptm_meeting_id=meeting.id)
        .order_by("class_section__school_class__level", "class_section__school_class__name", "class_section__name")
    )
    if actor is not None and not is_admin(actor):
        rows = [r for r in rows if r.class_section.class_teacher_id == actor.id]

    slots = {}
    for section_id, booked in PtmSlot.objects.filter(ptm_meeting_id=meeting.id).values_list(
        "class_section_id", "booking__id"
    ):
        total, taken = slots.get(section_id, (0, 0))
        slots[section_id] = (total + 1, taken + (1 if booked else 0))

    return {
        "id": meeting.id,
        "school_id": meeting.school_id,
        "title": meeting.title,
        "meeting_date": meeting.meeting_date.isoformat(),
        "note": meeting.note,
        "status": meeting.status,
        "booking_open": booking_open(meeting),
        "sections": [
            {
                "id": r.class_section_id,
                "name": section_label(r.class_section),
                "class_teacher": r.class_section.class_teacher.name if r.class_section.class_teacher_id else None,
                "slots": slots.get(r.class_section_id, (0, 0))[0],
                "booked": slots.get(r.class_section_id, (0, 0))[1],
            }
            for r in rows
        ],
    }


def staff_slot_resource(slot: PtmSlot) -> dict:
    try:
        booking = slot.booking
    except PtmBooking.DoesNotExist:
        booking = None

    return {
        "id": slot.id,
        "starts_at": slot.starts_at.strftime("%H:%M"),
        "ends_at": slot.ends_at.strftime("%H:%M"),
        "teacher_name": slot.teacher_user.name if slot.teacher_user_id else None,
        "booking": None if booking is None else {
            "student": {"id": booking.student_id, "name": booking.student.name},
            "parent": {"name": booking.booked_by.name, "mobile": parent_mobile(booking.booked_by)},
            "booked_at": booking.created_at.isoformat() if booking.created_at else None,
        },
    }


def family_meeting_resource(meeting: PtmMeeting, child: Student) -> dict:
    """A meeting as a parent sees it for one child: the class's slots, taken
    or free (never by whom), and their own booking."""
    slots = list(
        PtmSlot.objects.select_related("teacher_user")
        .filter(ptm_meeting_id=meeting.id, class_section_id=child.class_section_id)
        .order_by("starts_at")
    )
    taken = dict(
        PtmBooking.objects.filter(ptm_meeting_id=meeting.id, ptm_slot__in=slots).values_list("ptm_slot_id", "student_id")
    )
    mine = next((s for s in slots if taken.get(s.id) == child.id), None)
    teacher = next((s.teacher_user for s in slots if s.teacher_user_id), None)
    if teacher is None and child.class_section_id:
        section = ClassSection.objects.select_related("class_teacher").filter(pk=child.class_section_id).first()
        teacher = section.class_teacher if section else None

    return {
        "id": meeting.id,
        "title": meeting.title,
        "meeting_date": meeting.meeting_date.isoformat(),
        "date_label": dates.us(meeting.meeting_date),
        "note": meeting.note,
        "teacher_name": teacher.name if teacher else None,
        "booking_open": booking_open(meeting),
        "my_slot": None if mine is None else {
            "id": mine.id, "starts_at": mine.starts_at.strftime("%H:%M"), "ends_at": mine.ends_at.strftime("%H:%M"),
        },
        "slots": [
            {
                "id": s.id,
                "starts_at": s.starts_at.strftime("%H:%M"),
                "ends_at": s.ends_at.strftime("%H:%M"),
                "free": s.id not in taken,
                "mine": taken.get(s.id) == child.id,
            }
            for s in slots
        ],
    }
