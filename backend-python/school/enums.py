"""The enums, as the API spells them.

Every one of these is a string the Flutter apps compare against - "SCHOOL_ADMIN",
"active" - so the stored value is contract, not an implementation detail. They
mirror App\Enums one for one; where a PHP enum carries a method, the method
comes with it rather than being re-derived at the call site.

`TextChoices` rather than a bare constant class so a serializer can validate
against `.choices` and get the same answer the database's own check would.
"""

from __future__ import annotations

from django.db import models


class UserRole(models.TextChoices):
    SUPER_ADMIN = "SUPER_ADMIN"
    # Attached to a parent school: reads every branch in its group, and writes
    # into whichever branch it names. Not a platform role - schools and
    # payments stay SUPER_ADMIN. See docs/branches.md.
    GROUP_ADMIN = "GROUP_ADMIN"
    # Attached to any one school. Where that school is part of a group, the
    # same group reach as a Group Admin - the head office looks down at its
    # branches and a branch looks up and across at its sisters. Where it is
    # standalone, which is most schools, exactly one school as always.
    SCHOOL_ADMIN = "SCHOOL_ADMIN"
    HOD = "HOD"
    TEACHER = "TEACHER"
    STAFF = "STAFF"
    TRANSPORT_MANAGER = "TRANSPORT_MANAGER"

    @classmethod
    def administers_school(cls, role: str) -> bool:
        """Administers schools' own affairs - their own school, and every
        branch in its group where there is one.

        Says nothing about *which* schools: that is SchoolScope's question, and
        asking it here instead is how the two would drift apart.

        Deliberately not "is an admin": onboarding a school and recording the
        payments it makes are platform actions and stay SUPER_ADMIN.
        """
        return role in (cls.SCHOOL_ADMIN, cls.GROUP_ADMIN)


class UserStatus(models.TextChoices):
    ACTIVE = "active"
    INACTIVE = "inactive"


class StudentStatus(models.TextChoices):
    ACTIVE = "active"
    INACTIVE = "inactive"


class SchoolStatus(models.TextChoices):
    ACTIVE = "active"
    INACTIVE = "inactive"


class AttendanceStatus(models.TextChoices):
    PRESENT = "present"
    ABSENT = "absent"
    LEAVE = "leave"


class StaffAttendanceStatus(models.TextChoices):
    PRESENT = "present"
    ABSENT = "absent"
    LEAVE = "leave"
    # A staff-only status. Students are present, absent or on leave; a member
    # of staff can also work half a day.
    HALF_DAY = "half_day"


def ucfirst(value: str) -> str:
    """PHP's ucfirst: the first letter up, the rest untouched - not Python's
    capitalize(), which also lowers everything after it."""
    return value[:1].upper() + value[1:]


class MessageChannel(models.TextChoices):
    SMS = "sms", "SMS"
    IN_APP = "in_app", "In-app"


class MessageStatus(models.TextChoices):
    QUEUED = "queued"
    SENT = "sent"
    FAILED = "failed"
    SKIPPED = "skipped"

    @classmethod
    def label_for(cls, status: str) -> str:
        return ucfirst(status)


class MessageCategory(models.TextChoices):
    ATTENDANCE = "attendance"
    TRANSPORT = "transport"
    LEAVE = "leave"
    ANNOUNCEMENT = "announcement"

    @classmethod
    def label_for(cls, category: str) -> str:
        return ucfirst(category)


class AttendanceAlertMode(models.TextChoices):
    OFF = "off", "No attendance alerts"
    ABSENT_ONLY = "absent", "Absent only"
    PRESENT_AND_ABSENT = "both", "Present + Absent"


class MessageEvent(models.TextChoices):
    """Every automatic message the product can send.

    Each event owns its default wording, the tokens that wording may use, the
    log category and the channels it goes out on. A school can override the
    wording but not the token list, so a reworded template can never reference
    data the sender does not have.
    """

    ATTENDANCE_PRESENT = "attendance.present", "Marked present"
    ATTENDANCE_ABSENT = "attendance.absent", "Marked absent"
    TRANSPORT_BOARDED = "transport.boarded", "Boarded the bus"
    TRANSPORT_DROPPED = "transport.dropped", "Dropped off"
    TRANSPORT_ABSENT = "transport.absent", "Did not board"
    LEAVE_APPROVED = "leave.approved", "Leave approved"
    LEAVE_REJECTED = "leave.rejected", "Leave rejected"
    ANNOUNCEMENT_PUBLISHED = "announcement.published", "Announcement"

    @classmethod
    def category(cls, event: str) -> str:
        if event.startswith("attendance."):
            return MessageCategory.ATTENDANCE

        if event.startswith("transport."):
            return MessageCategory.TRANSPORT

        if event.startswith("leave."):
            return MessageCategory.LEAVE

        return MessageCategory.ANNOUNCEMENT

    @classmethod
    def channels(cls, event: str) -> list[str]:
        """Guardians have no login, so student alerts are SMS only. Staff
        alerts also land in the in-app inbox."""
        category = cls.category(event)

        if category in (MessageCategory.LEAVE, MessageCategory.ANNOUNCEMENT):
            return [MessageChannel.IN_APP, MessageChannel.SMS]

        return [MessageChannel.SMS]

    @classmethod
    def default_body(cls, event: str) -> str:
        return DEFAULT_BODIES[event]

    @classmethod
    def tokens(cls, event: str) -> list[str]:
        return TOKENS[cls.category(event)] if event != cls.TRANSPORT_ABSENT else TRANSPORT_ABSENT_TOKENS


DEFAULT_BODIES = {
    MessageEvent.ATTENDANCE_PRESENT: "{student_name} was marked PRESENT on {date}. - {school_name}",
    MessageEvent.ATTENDANCE_ABSENT: (
        "{student_name} was marked ABSENT on {date}. "
        "Please contact the school office if this is unexpected. - {school_name}"
    ),
    MessageEvent.TRANSPORT_BOARDED: (
        "{student_name} boarded {vehicle_name} at {stop_name} at {time}. - {school_name}"
    ),
    MessageEvent.TRANSPORT_DROPPED: (
        "{student_name} was dropped off at {stop_name} at {time}. - {school_name}"
    ),
    MessageEvent.TRANSPORT_ABSENT: (
        "{student_name} did not board {vehicle_name} for the {direction} trip today. - {school_name}"
    ),
    MessageEvent.LEAVE_APPROVED: (
        "Your {leave_type} leave from {start_date} to {end_date} has been approved."
    ),
    MessageEvent.LEAVE_REJECTED: (
        "Your {leave_type} leave from {start_date} to {end_date} was not approved."
    ),
    MessageEvent.ANNOUNCEMENT_PUBLISHED: "{school_name}: {title} - {body}",
}

TOKENS = {
    MessageCategory.ATTENDANCE: [
        "student_name", "class_name", "date", "school_name", "guardian_name",
    ],
    MessageCategory.TRANSPORT: [
        "student_name", "stop_name", "vehicle_name", "route_name", "time", "date",
        "school_name", "guardian_name",
    ],
    MessageCategory.LEAVE: [
        "staff_name", "leave_type", "start_date", "end_date", "days", "remarks", "school_name",
    ],
    MessageCategory.ANNOUNCEMENT: ["title", "body", "school_name", "audience"],
}

# The one event whose tokens differ from its category's: it names a direction
# rather than a time, because nothing was boarded.
TRANSPORT_ABSENT_TOKENS = [
    "student_name", "stop_name", "vehicle_name", "route_name", "direction", "date",
    "school_name", "guardian_name",
]


class PaymentType(models.TextChoices):
    # The labels are what a receipt prints, so they are part of a document a
    # school files rather than a display detail.
    SETUP_FEE = "setup_fee", "Setup Fee"
    ANNUAL_MAINTENANCE = "annual_maintenance", "Annual Maintenance"
    ADDITIONAL_SERVICE = "additional_service", "Additional Service"
    OTHER = "other", "Other"


class PaymentMode(models.TextChoices):
    CASH = "cash", "Cash"
    BANK_TRANSFER = "bank_transfer", "Bank Transfer"
    UPI = "upi", "UPI"
    CHEQUE = "cheque", "Cheque"
    ONLINE = "online", "Online Transfer"


class PaymentStatus(models.TextChoices):
    PENDING = "pending", "Pending"
    PAID = "paid", "Paid"
    PARTIAL = "partial", "Partially Paid"
    CANCELLED = "cancelled", "Cancelled"


class HolidayType(models.TextChoices):
    NATIONAL = "national"
    RELIGIOUS = "religious"
    SCHOOL_EVENT = "school_event"
    VACATION = "vacation"


class LeaveStatus(models.TextChoices):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


class LeaveType(models.TextChoices):
    CASUAL = "casual"
    MEDICAL = "medical"
    EARNED = "earned"
    HALF_DAY = "half_day"

    @classmethod
    def label_for(cls, leave_type: str) -> str:
        """How the type reads inside a message to the applicant.

        Lower case and hyphenated rather than the stored value, because it is
        dropped mid-sentence: "Your half-day leave from ... has been
        approved." Not TextChoices' own `.label`, which title-cases.
        """
        return "half-day" if leave_type == cls.HALF_DAY else leave_type


class DayOfWeek(models.TextChoices):
    """The school week. Five days, because Saturday and Sunday are not
    working days anywhere in the product - the holiday calendar already
    refuses attendance on them, and a grid column nobody can mark is
    furniture."""

    MONDAY = "monday"
    TUESDAY = "tuesday"
    WEDNESDAY = "wednesday"
    THURSDAY = "thursday"
    FRIDAY = "friday"


class AnnouncementAudience(models.TextChoices):
    ALL_SCHOOL = "all_school", "All School"
    TEACHERS = "teachers", "Teachers"
    PARENTS = "parents", "Parents"
    CLASS_SECTION = "class_section", "A class section"
    DEPARTMENT = "department", "A department"

    @classmethod
    def needs_target(cls, audience: str) -> bool:
        return audience in (cls.CLASS_SECTION, cls.DEPARTMENT)

    @classmethod
    def reaches_guardians(cls, audience: str) -> bool:
        return audience in (cls.ALL_SCHOOL, cls.PARENTS, cls.CLASS_SECTION)

    @classmethod
    def reaches_staff(cls, audience: str) -> bool:
        return audience in (cls.ALL_SCHOOL, cls.TEACHERS, cls.DEPARTMENT)


class AnnouncementChannels(models.TextChoices):
    SMS_AND_IN_APP = "sms_in_app", "SMS + In-app"
    SMS_ONLY = "sms", "SMS Only"
    IN_APP_ONLY = "in_app", "In-app Only"

    @classmethod
    def includes_sms(cls, channels: str) -> bool:
        return channels != cls.IN_APP_ONLY

    @classmethod
    def includes_in_app(cls, channels: str) -> bool:
        return channels != cls.SMS_ONLY

    @classmethod
    def message_channels(cls, channels: str) -> list[str]:
        return {
            cls.SMS_AND_IN_APP: [MessageChannel.IN_APP, MessageChannel.SMS],
            cls.SMS_ONLY: [MessageChannel.SMS],
            cls.IN_APP_ONLY: [MessageChannel.IN_APP],
        }[channels]


class TransportStatus(models.TextChoices):
    ACTIVE = "active"
    INACTIVE = "inactive"
