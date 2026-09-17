"""What a record looks like on the wire.

The Python half of App/Http/Resources. Every key here is read by name in the
Flutter apps, so this file is the contract in the most literal sense: renaming
`first_name`, or sending an id as a string, breaks a client that rule 1 of the
migration says must not be touched.

Plain functions returning dicts, not DRF serializers. Two reasons. Laravel's
resources are exactly this - a method returning an array - so a reviewer can
put the two side by side and see that they agree. And `whenLoaded` has no DRF
equivalent: it omits a key rather than sending null, and reproducing "the key
is absent" through a serializer field would take more machinery than the thing
it is reproducing.
"""

from __future__ import annotations

from . import money, sms, working_hours
from .clock import DATE, DATE_TIME, TIME, SchoolClock
from .enums import AnnouncementChannels, AttendanceAlertMode, MessageCategory, MessageChannel, MessageEvent, MessageStatus
from .fields import as_utc
from .models import School, Student, StudentTransportAssignment, User
from .scope import SchoolScope


def timestamp(value) -> str | None:
    """An instant in the form Eloquent's JSON serialization produces -
    `2026-09-16T10:23:45.000000Z`.

    Six digits of fractional seconds and a literal Z, always, because that is
    what the client has been parsing since the first release.

    Through `as_utc` rather than a bare `.astimezone()`: a naive datetime out
    of a `timestamp without time zone` column means UTC here, and Python's
    default reading of a naive value is the machine's local zone. See
    school/fields.py - this is the second line of defence, the field being the
    first.
    """
    if value is None:
        return None

    return as_utc(value).strftime("%Y-%m-%dT%H:%M:%S.%f") + "Z"


def attendance_resource(mark) -> dict:
    section = mark.class_section

    body = {
        "id": mark.id,
        "school_id": mark.school_id,
        "academic_year_id": mark.academic_year_id,
        "class_section_id": mark.class_section_id,
        "class_section_name": (
            f"{section.school_class.name} {section.name}".strip()
            if section is not None and loaded(section, "school_class")
            else None
        ),
        "student_id": mark.student_id,
        "attendance_date": mark.attendance_date.isoformat(),
        "status": mark.status,
        "remarks": mark.remarks,
        "marked_by": mark.marked_by_id,
        "created_at": timestamp(mark.created_at),
    }

    if loaded(mark, "student"):
        body["student_name"] = mark.student.name if mark.student else None

    if loaded(mark, "marked_by"):
        body["marked_by_name"] = mark.marked_by.name if mark.marked_by else None

    return body


def staff_attendance_resource(mark) -> dict:
    profile = mark.staff_profile

    body = {
        "id": mark.id,
        "school_id": mark.school_id,
        "staff_profile_id": mark.staff_profile_id,
        "employee_id": profile.employee_id if profile else None,
        "attendance_date": mark.attendance_date.isoformat(),
        "status": mark.status,
        "check_in": working_hours.clock(mark.check_in),
        "check_out": working_hours.clock(mark.check_out),
        "working_hours": working_hours.format_span(mark.check_in, mark.check_out),
        "remarks": mark.remarks,
        "marked_by": mark.marked_by_id,
        "created_at": timestamp(mark.created_at),
    }

    if loaded(mark, "staff_profile"):
        body["staff_name"] = profile.user.name if profile else None
        body["department_name"] = (
            profile.department.name if profile and profile.department_id else None
        )

    if loaded(mark, "marked_by"):
        body["marked_by_name"] = mark.marked_by.name if mark.marked_by else None

    return body


def staff_leave_resource(leave) -> dict:
    """One leave request, as the Staff Leave Management screen reads it.

    Every relation this touches is eager-loaded by the service before a
    resource is ever built, so the names are always here rather than
    sometimes - Laravel's `whenLoaded` on the same fields is belt and braces
    against a caller that forgot, not a shape that varies in practice.
    """
    profile = leave.staff_profile

    return {
        "id": leave.id,
        "school_id": leave.school_id,
        "staff_profile_id": leave.staff_profile_id,
        "employee_id": profile.employee_id if profile else None,
        "staff_name": profile.user.name if profile else None,
        "department_name": (
            profile.department.name if profile and profile.department_id else None
        ),
        "leave_type": leave.leave_type,
        "start_date": leave.start_date.isoformat(),
        "end_date": leave.end_date.isoformat(),
        "reason": leave.reason,
        "status": leave.status,
        "applied_by_name": leave.applied_by.name if leave.applied_by_id else None,
        "reviewed_by_name": leave.reviewed_by.name if leave.reviewed_by_id else None,
        "review_remarks": leave.review_remarks,
        "created_at": timestamp(leave.created_at),
    }


def timetable_entry_resource(entry) -> dict:
    """One cell of the week's grid.

    The names travel with the ids because the grid is drawn from this alone -
    a client that had to look up each subject and teacher would fire a request
    per cell.
    """
    section = entry.class_section

    return {
        "id": entry.id,
        "school_id": entry.school_id,
        "class_section_id": entry.class_section_id,
        "class_section_name": (
            f"{section.school_class.name} {section.name}" if section else None
        ),
        "period_id": entry.period_id,
        "period_number": entry.period.period_number if entry.period_id else None,
        "day_of_week": entry.day_of_week,
        "subject_id": entry.subject_id,
        "subject_name": entry.subject.name if entry.subject_id else None,
        "teacher_id": entry.teacher_id,
        "teacher_name": entry.teacher.name if entry.teacher_id else None,
    }


def daily_teaching_report_resource(report) -> dict:
    """One period's report, with enough of the period to recognise it by."""
    entry = report.timetable_entry
    section = entry.class_section if entry else None

    return {
        "id": report.id,
        "school_id": report.school_id,
        "timetable_entry_id": report.timetable_entry_id,
        "class_section_name": (
            f"{section.school_class.name} {section.name}" if section else None
        ),
        "period_number": entry.period.period_number if entry else None,
        "subject_name": entry.subject.name if entry else None,
        "teacher_id": report.teacher_id,
        "teacher_name": report.teacher.name if report.teacher_id else None,
        "report_date": report.report_date.isoformat(),
        "topic_taught": report.topic_taught,
        "homework": report.homework,
        "remarks": report.remarks,
        "reviewed_by": report.reviewed_by_id,
        "reviewed_by_name": report.reviewed_by.name if report.reviewed_by_id else None,
        "reviewed_at": timestamp(report.reviewed_at),
    }


def syllabus_topic_resource(topic) -> dict:
    return {
        "id": topic.id,
        "school_id": topic.school_id,
        "subject_id": topic.subject_id,
        "subject_name": topic.subject.name,
        "title": topic.title,
        "sequence_number": topic.sequence_number,
    }


def message_resource(message) -> dict:
    """One row of the message log, or one message in an inbox.

    The times are rendered server-side on the school's clock, so the log
    agrees with the time written inside the message itself.
    """
    clock = SchoolClock.for_school(message.school if loaded(message, "school") else message.school_id)

    return {
        "id": message.id,
        "school_id": message.school_id,
        "event": message.event,
        "event_label": MessageEvent(message.event).label,
        "category": message.category,
        "category_label": MessageCategory.label_for(message.category),
        "channel": message.channel,
        "channel_label": MessageChannel(message.channel).label,
        "recipient_name": message.recipient_name,
        "recipient_mobile": message.recipient_mobile,
        "student_id": message.student_id,
        "student_name": message.student_name,
        "announcement_id": message.announcement_id,
        "subject": message.subject,
        "body": message.body,
        "status": message.status,
        "status_label": MessageStatus.label_for(message.status),
        "provider": message.provider,
        "provider_label": None if message.provider is None else sms.label(message.provider),
        "failure_reason": message.failure_reason,
        "sent_at": timestamp(message.sent_at),
        "read_at": timestamp(message.read_at),
        "created_at": timestamp(message.created_at),
        "created_at_label": clock.format(message.created_at, TIME),
        "created_on_label": clock.format(message.created_at, DATE),
        "sent_at_label": clock.format(message.sent_at, TIME),
        "timezone": clock.timezone(),
    }


def message_template_resource(row: dict) -> dict:
    event = row["event"]

    return {
        "event": event,
        "event_label": MessageEvent(event).label,
        "category": MessageEvent.category(event),
        "channels": list(MessageEvent.channels(event)),
        "body": row["body"],
        "default_body": row["default_body"],
        "is_custom": row["is_custom"],
        "tokens": MessageEvent.tokens(event),
        "updated_at": timestamp(row["updated_at"]),
        "updated_by_name": row["updated_by_name"],
    }


def communication_setting_resource(setting) -> dict:
    return {
        "school_id": setting.school_id,
        "sms_enabled": setting.sms_enabled,
        "attendance_alerts": setting.attendance_alerts,
        "attendance_alerts_label": AttendanceAlertMode(setting.attendance_alerts).label,
        "transport_alerts_enabled": setting.transport_alerts_enabled,
        "leave_alerts_enabled": setting.leave_alerts_enabled,
        "provider": setting.provider,
        "provider_label": sms.label(setting.provider),
        "sender_id": setting.sender_id,
        "available_providers": sms.available(),
        # Whether the school has ever saved these, or is looking at defaults.
        "is_saved": setting.pk is not None,
    }


def announcement_resource(announcement) -> dict:
    clock = SchoolClock.for_school(
        announcement.school if loaded(announcement, "school") else announcement.school_id
    )

    return {
        "id": announcement.id,
        "school_id": announcement.school_id,
        "school_name": announcement.school.name,
        "title": announcement.title,
        "body": announcement.body,
        "audience_type": announcement.audience_type,
        "audience_id": announcement.audience_id,
        "audience_label": announcement.audience_label,
        "channels": announcement.channels,
        "channels_label": AnnouncementChannels(announcement.channels).label,
        "expires_at": announcement.expires_at.isoformat() if announcement.expires_at else None,
        # Expired means before today *at the school*.
        "has_expired": announcement.expires_at is not None and announcement.expires_at.isoformat() < clock.date(),
        "published_by_name": announcement.published_by.name if announcement.published_by_id else None,
        "published_at": timestamp(announcement.published_at),
        "published_at_label": clock.format(announcement.published_at, DATE_TIME),
        "recipients_count": announcement.recipients_count,
        "sms_count": announcement.sms_count,
        "in_app_count": announcement.in_app_count,
    }


def staff_profile_resource(profile, class_teacher_of=None) -> dict:
    """An employee: their employment record and the login behind it.

    One resource for two rows, because the Add Employee screen is one form.
    `class_teacher_of` is passed in for the same reason `sections` is on a
    class - it is a prefetch, and a resource that walked the relation would
    fire a query per employee in a list.
    """
    user = profile.user

    return {
        "id": profile.id,
        "user_id": profile.user_id,
        "employee_id": profile.employee_id,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "name": user.name,
        "email": user.email,
        "mobile": user.mobile,
        "role": user.role,
        "status": user.status,
        "school_id": profile.school_id,
        "school_name": profile.school.name if profile.school_id else None,
        "department_id": profile.department_id,
        "department_name": profile.department.name if profile.department_id else None,
        "designation": profile.designation,
        "joining_date": profile.joining_date.isoformat(),
        "address": profile.address,
        # "Assigned classes" - derived from the class teacher a section names,
        # not a table of its own.
        "class_teacher_of": class_teacher_of or [],
    }


def payment_resource(payment) -> dict:
    body = {
        "id": payment.id,
        "school_id": payment.school_id,
        "payment_type": payment.payment_type,
        # Strings, always. Money through a JSON number is money through a
        # float, and the client formats it rather than doing arithmetic on it.
        "amount": str(payment.amount),
        "paid_amount": str(payment.paid_amount),
        "remaining_amount": str(
            money.remaining(
                money.amount(payment.amount), money.amount(payment.paid_amount), payment.status
            )
        ),
        # Never absent, and never a converted total. Each payment carries the
        # currency its school used at the time (CLAUDE.md rule 5).
        "currency_code": payment.currency_code,
        "payment_date": payment.payment_date.isoformat(),
        "payment_mode": payment.payment_mode,
        "reference_number": payment.reference_number,
        "notes": payment.notes,
        "status": payment.status,
        "created_by": payment.created_by_id,
        "receipt_sent_at": timestamp(payment.receipt_sent_at),
        "created_at": timestamp(payment.created_at),
    }

    if loaded(payment, "school"):
        body["school_name"] = payment.school.name

    if loaded(payment, "created_by"):
        body["created_by_name"] = payment.created_by.name

    return body


def period_resource(period) -> dict:
    return {
        "id": period.id,
        "school_id": period.school_id,
        "period_number": period.period_number,
        # "09:00", not "09:00:00" - a clock time in the school's own day,
        # rendered the way the timetable shows it.
        "start_time": period.start_time.strftime("%H:%M"),
        "end_time": period.end_time.strftime("%H:%M"),
    }


def holiday_resource(holiday, affected_records=None) -> dict:
    body = {
        "id": holiday.id,
        "school_id": holiday.school_id,
        "name": holiday.name,
        "type": holiday.type,
        "start_date": holiday.start_date.isoformat(),
        "end_date": holiday.end_date.isoformat(),
        # Inclusive of both ends: a holiday that starts and finishes on the
        # same date is one day, not none.
        "days": (holiday.end_date - holiday.start_date).days + 1,
        "created_at": timestamp(holiday.created_at),
    }

    if loaded(holiday, "school"):
        body["school_name"] = holiday.school.name

    # Only on a write. Reading the calendar should not count attendance rows
    # for every holiday on the page.
    if affected_records is not None:
        body["affected_records"] = affected_records

    return body


def class_section_resource(section) -> dict:
    body = {
        "id": section.id,
        "school_class_id": section.school_class_id,
        "name": section.name,
        "room_number": section.room_number,
        "class_teacher_id": section.class_teacher_id,
    }

    if loaded(section, "class_teacher"):
        body["class_teacher_name"] = (
            section.class_teacher.name if section.class_teacher else None
        )

    return body


def school_class_resource(school_class, sections=None) -> dict:
    """A class, with its sections where they have been fetched.

    `sections` is passed in rather than read off the instance: it is a
    prefetch, and a resource that walked the relation itself would fire a
    query per class in a list.
    """
    body = {
        "id": school_class.id,
        "school_id": school_class.school_id,
        "academic_year_id": school_class.academic_year_id,
        "name": school_class.name,
        "level": school_class.level,
        "created_at": timestamp(school_class.created_at),
    }

    if loaded(school_class, "school"):
        body["school_name"] = school_class.school.name

    if loaded(school_class, "academic_year"):
        body["academic_year_name"] = school_class.academic_year.name

    if sections is not None:
        body["sections"] = [class_section_resource(section) for section in sections]

    return body


def department_resource(department) -> dict:
    body = {
        "id": department.id,
        "school_id": department.school_id,
        "name": department.name,
        "hod_user_id": department.hod_user_id,
        "created_at": timestamp(department.created_at),
    }

    if loaded(department, "school"):
        body["school_name"] = department.school.name

    if loaded(department, "hod_user"):
        body["hod_name"] = department.hod_user.name if department.hod_user else None

    return body


def subject_resource(subject) -> dict:
    body = {
        "id": subject.id,
        "school_id": subject.school_id,
        "department_id": subject.department_id,
        "code": subject.code,
        "name": subject.name,
        "min_class_level": subject.min_class_level,
        "max_class_level": subject.max_class_level,
        "lead_teacher_id": subject.lead_teacher_id,
        "created_at": timestamp(subject.created_at),
    }

    if loaded(subject, "school"):
        body["school_name"] = subject.school.name

    if loaded(subject, "department"):
        body["department_name"] = subject.department.name

    if loaded(subject, "lead_teacher"):
        body["lead_teacher_name"] = subject.lead_teacher.name if subject.lead_teacher else None

    return body


def academic_year_resource(year) -> dict:
    body = {
        "id": year.id,
        "school_id": year.school_id,
        "name": year.name,
        # Dates, not instants: `2026-04-01` is the same day everywhere, and
        # rendering it through a timezone would move it.
        "start_date": year.start_date.isoformat(),
        "end_date": year.end_date.isoformat(),
        "is_current": year.is_current,
        "created_at": timestamp(year.created_at),
    }

    if loaded(year, "school"):
        body["school_name"] = year.school.name

    return body


def school_resource(school: School, branch_count: int | None = None) -> dict:
    """A school, or a branch of one.

    `branch_count` is passed in rather than read off the instance: it comes
    from an annotation on the list query, and a resource that fetched it
    itself would fire a query per row.
    """
    body = {
        "id": school.id,
        "name": school.name,
        # Where this school sits in its group. Null for a standalone school,
        # which is what most are. See docs/branches.md.
        "parent_school_id": school.parent_school_id,
        "registration_number": school.registration_number,
        "email": school.email,
        "phone": school.phone,
        "address": school.address,
        "city": school.city,
        "state": school.state,
        "country": school.country,
        "postal_code": school.postal_code,
        # Strings, not floats. `decimal(10,7)` through a float loses the
        # seventh place, and Laravel's `decimal:7` cast sends a string too.
        "latitude": None if school.latitude is None else str(school.latitude),
        "longitude": None if school.longitude is None else str(school.longitude),
        "currency_code": school.currency_code,
        "timezone": school.timezone,
        "logo_url": school.logo_url,
        "status": school.status,
        "created_at": timestamp(school.created_at),
    }

    if loaded(school, "parent_school"):
        body["parent_school_name"] = school.parent_school.name if school.parent_school else None

    if branch_count is not None:
        body["branch_count"] = branch_count

    return body


def user_resource(user: User, viewer: User | None = None) -> dict:
    """The session user - what login returns and what /me answers.

    `viewer` is whoever is reading. It decides one field (see
    `manages_branches` below) and is passed explicitly rather than pulled off
    a request, because at login there is no authenticated request yet: the
    token was issued a line earlier.
    """
    # Reads the already-loaded school where there is one, so a paginated user
    # list does not fire a query per row.
    clock = SchoolClock.for_user(user)

    body = {
        "id": user.id,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "name": user.name,
        "email": user.email,
        "mobile": user.mobile,
        "role": user.role,
        "is_sub_admin": user.is_sub_admin,
        "status": user.status,
        "school_id": user.school_id,
        # True for an account created by a bulk import, which was given a
        # generated password: the client keeps it on the change-password
        # screen until it chooses one of its own.
        "must_change_password": user.must_change_password,
        "timezone": clock.timezone(),
        # The session's clock. The client measures every date it shows or
        # defaults to against these two, never against the browser's own
        # timezone. A Super Admin belongs to no school and gets the platform's
        # zone.
        "current_time": clock.now_iso8601(),
    }

    if "school" in user._state.fields_cache:
        body["school_name"] = user.school.name if user.school else None

    # Whether "my school" is ambiguous for this account, so the client knows
    # to ask which branch a record belongs to. True for an admin of a school
    # in a group, false for a standalone one - which is why the client cannot
    # work it out from the role alone.
    #
    # Only ever computed for the signed-in user reading their own session: it
    # costs a query, and a paginated user list would pay it per row for
    # something no row needs.
    if viewer is not None and viewer.id == user.id:
        body["manages_branches"] = SchoolScope.for_actor(user).covers_a_group()

    return body


def loaded(instance, name: str) -> bool:
    """Has this relation already been fetched?

    The Python answer to Eloquent's `relationLoaded()`, and it decides whether
    a key appears at all - `whenLoaded` omits a field rather than sending null,
    so getting this wrong changes the shape rather than the value. Asked
    through the field's own `is_cached` rather than by poking at the instance,
    because that is the supported way and touching the attribute would silently
    fire the query this is trying to avoid.
    """
    return instance._meta.get_field(name).is_cached(instance)


def student_resource(student: Student) -> dict:
    section = student.class_section

    body = {
        "id": student.id,
        "school_id": student.school_id,
        "class_section_id": student.class_section_id,
        "class_section_name": (
            f"{section.school_class.name} {section.name}".strip()
            if section is not None and loaded(section, "school_class")
            else None
        ),
        "admission_number": student.admission_number,
        "first_name": student.first_name,
        "last_name": student.last_name,
        "name": student.name,
        "roll_number": student.roll_number,
        "guardian_name": student.guardian_name,
        "guardian_mobile": student.guardian_mobile,
        "address": student.address,
        "status": student.status,
        "created_at": timestamp(student.created_at),
    }

    if loaded(student, "school"):
        body["school_name"] = student.school.name if student.school else None

    if loaded(student, "studenttransportassignment"):
        body["transport"] = transport_resource(assignment_of(student))

    return body


def assignment_of(student: Student):
    """The student's transport assignment, or None.

    A reverse one-to-one raises rather than returning None when there is no
    matching row, even after select_related has established that there isn't
    one. Django models a missing one-to-one as an error; Laravel models it as
    null, and null is what the client is promised.
    """
    try:
        return student.studenttransportassignment
    except StudentTransportAssignment.DoesNotExist:
        return None


def transport_resource(assignment) -> dict | None:
    """The student's current bus route and stop, or null when they do not use
    school transport.

    Transport is M11's work, but this key is part of the student's shape and
    Laravel's StudentController eager-loads the relation - so Laravel always
    sends `transport`, as null for most students. Omitting the key here would
    have been a difference the Flutter client happens to survive, since it
    reads a missing key and an explicit null the same way. Surviving a
    difference is not the same as not having one.
    """
    if assignment is None:
        return None

    route = assignment.route

    return {
        "route_id": assignment.route_id,
        "route_name": route.name,
        "route_label": route_label(route),
        "vehicle_name": route.vehicle.name if route.vehicle_id else None,
        "stop_id": assignment.transport_stop_id,
        "stop_name": assignment.transport_stop.name,
    }


def route_label(route) -> str:
    """"Bus 04 - Green Park" - the vehicle and the route, as a driver would
    say it. Ported from TransportRoute::label()."""
    vehicle = route.vehicle.name if route.vehicle_id else None

    return f"{vehicle} - {route.name}" if vehicle else route.name
