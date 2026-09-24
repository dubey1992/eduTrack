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
    # Runs payroll for their own school - salaries, a month's run, payslips.
    # Otherwise an ordinary employee with a staff profile. See docs/payroll.md.
    ACCOUNTANT = "ACCOUNTANT"
    # The person on the bus - attendant or conductor - who runs the trips of
    # the routes they are assigned to, from a phone, signing in with a mobile
    # number and passcode on a registered device. See docs/maps.md.
    BUS_ATTENDANT = "BUS_ATTENDANT"

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


class AssessmentType(models.TextChoices):
    """What kind of test this is. The school's own word for it, from a short
    list rather than free text, so a report can group by it."""

    CLASS_TEST = "class_test"
    UNIT_TEST = "unit_test"
    ASSIGNMENT = "assignment"
    QUIZ = "quiz"
    PRACTICAL = "practical"


class AssessmentStatus(models.TextChoices):
    """A draft is the school's own business; a published result is not.

    Publishing freezes each mark's grade and tells the guardian, so the two
    states are worth keeping apart from the first day (docs/assessments.md).
    """

    DRAFT = "draft"
    PUBLISHED = "published"


class EnrollmentStatus(models.TextChoices):
    """How a student's year ended (docs/promotion.md).

    STUDYING is the only one this slice writes: it is what a year looks like
    while it is being lived. The rest are outcomes a promotion records, and
    they are listed here because the value is contract - the Flutter app
    compares against these strings.
    """

    STUDYING = "studying"
    PROMOTED = "promoted"
    RETAINED = "retained"
    GRADUATED = "graduated"
    LEFT = "left"


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
    WHATSAPP = "whatsapp", "WhatsApp"
    EMAIL = "email", "Email"

    @classmethod
    def external(cls) -> list[str]:
        """The channels that leave the building - everything but the inbox."""
        return [cls.SMS, cls.WHATSAPP, cls.EMAIL]


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
    # Written by hand in the Communication Center rather than by a module:
    # a message to one person or group, an emergency to everyone, a fee
    # reminder to a guardian (docs/communication.md).
    GENERAL = "general"
    EMERGENCY = "emergency"
    FEE = "fee"

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
    GENERAL_MESSAGE = "general.message", "Message"
    EMERGENCY_ALERT = "emergency.alert", "Emergency alert"
    FEE_REMINDER = "fee.reminder", "Fee reminder"

    @classmethod
    def category(cls, event: str) -> str:
        prefix = event.split(".", 1)[0]

        return prefix if prefix in MessageCategory.values else MessageCategory.ANNOUNCEMENT

    @classmethod
    def channels(cls, event: str) -> list[str]:
        """Every channel the event can go out on. Which of them a copy is
        actually recorded on is the school's settings' decision, per channel,
        and the recipient's: a guardian has no login, so no inbox.

        Alerts about a student go to whoever is told about that student and
        never into an inbox; everything else reaches staff, who have one.
        """
        category = cls.category(event)

        if category in (MessageCategory.ATTENDANCE, MessageCategory.TRANSPORT, MessageCategory.FEE):
            return MessageChannel.external()

        return [MessageChannel.IN_APP, *MessageChannel.external()]

    @classmethod
    def is_manual(cls, event: str) -> bool:
        """Written in the Communication Center rather than raised by a module."""
        return cls.category(event) in (MessageCategory.GENERAL, MessageCategory.EMERGENCY, MessageCategory.FEE)

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
    MessageEvent.GENERAL_MESSAGE: "{school_name}: {subject} - {body}",
    MessageEvent.EMERGENCY_ALERT: "EMERGENCY - {school_name}: {body}",
    MessageEvent.FEE_REMINDER: (
        "Dear {guardian_name}, a fee of {amount} for {student_name} is due on {due_date}. "
        "Please pay at the school office. - {school_name}"
    ),
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
    MessageCategory.GENERAL: ["recipient_name", "subject", "body", "school_name"],
    MessageCategory.EMERGENCY: ["subject", "body", "school_name"],
    MessageCategory.FEE: ["student_name", "guardian_name", "amount", "due_date", "school_name"],
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


class PayComponentType(models.TextChoices):
    """A salary component or payslip line: added to pay, or taken from it."""

    EARNING = "earning", "Earning"
    DEDUCTION = "deduction", "Deduction"


class PayslipLineSource(models.TextChoices):
    """Where a payslip line came from. Only an adjustment can be removed."""

    BASIC = "basic", "Basic"
    COMPONENT = "component", "Component"
    ADJUSTMENT = "adjustment", "Adjustment"


class PayrollRunStatus(models.TextChoices):
    DRAFT = "draft", "Draft"
    FINALIZED = "finalized", "Finalized"
    PAID = "paid", "Paid"


class PayslipStatus(models.TextChoices):
    UNPAID = "unpaid", "Unpaid"
    PAID = "paid", "Paid"


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
    """The three choices the prototype offered, kept as they are stored. An
    announcement can now go out on any mix of the four channels, written as a
    comma-separated list ("in_app,sms,whatsapp"); the three names below still
    read as the lists they always meant, so old rows and old clients work."""

    SMS_AND_IN_APP = "sms_in_app", "SMS + In-app"
    SMS_ONLY = "sms", "SMS Only"
    IN_APP_ONLY = "in_app", "In-app Only"

    @classmethod
    def legacy(cls) -> dict[str, list[str]]:
        return {
            cls.SMS_AND_IN_APP: [MessageChannel.IN_APP, MessageChannel.SMS],
            cls.SMS_ONLY: [MessageChannel.SMS],
            cls.IN_APP_ONLY: [MessageChannel.IN_APP],
        }

    @classmethod
    def parse(cls, channels) -> list[str] | None:
        """The channel list a stored or submitted value means, in the order
        MessageChannel declares them, or None when it means nothing."""
        if not isinstance(channels, str):
            return None

        if channels in cls.legacy():
            return list(cls.legacy()[channels])

        wanted = {part.strip() for part in channels.split(",") if part.strip()}

        if not wanted or not wanted <= set(MessageChannel.values):
            return None

        return [channel for channel in MessageChannel.values if channel in wanted]

    @classmethod
    def is_valid(cls, channels) -> bool:
        return cls.parse(channels) is not None

    @classmethod
    def normalise(cls, channels: str) -> str:
        """Stored as the caller wrote it when it is one of the three names, so
        the Laravel contract is unchanged; otherwise as an ordered list."""
        return channels if channels in cls.legacy() else ",".join(cls.parse(channels))

    @classmethod
    def label_for(cls, channels: str) -> str:
        if channels in cls.legacy():
            return cls(channels).label

        return " + ".join(MessageChannel(channel).label for channel in cls.parse(channels) or [])

    @classmethod
    def includes(cls, channels: str, channel: str) -> bool:
        return channel in (cls.parse(channels) or [])

    @classmethod
    def includes_sms(cls, channels: str) -> bool:
        return cls.includes(channels, MessageChannel.SMS)

    @classmethod
    def includes_in_app(cls, channels: str) -> bool:
        return cls.includes(channels, MessageChannel.IN_APP)

    @classmethod
    def message_channels(cls, channels: str) -> list[str]:
        return cls.parse(channels) or []

    @classmethod
    def reaches_guardians(cls, channels: str) -> bool:
        """Guardians have no login, so an announcement reaches them only when
        some external channel is on."""
        return any(cls.includes(channels, channel) for channel in MessageChannel.external())


class TransportStatus(models.TextChoices):
    ACTIVE = "active"
    INACTIVE = "inactive"


class TripDirection(models.TextChoices):
    PICKUP = "pickup"
    DROP = "drop"


class TripStatus(models.TextChoices):
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class TripEventType(models.TextChoices):
    STARTED = "started"
    STOP_REACHED = "stop_reached"
    BOARDED = "boarded"
    DROPPED = "dropped"
    ABSENT = "absent"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    # The attendant pressed Call Parent for a rider. Kept on the timeline:
    # who was called about which child, and when, is part of the trip.
    GUARDIAN_CALLED = "guardian_called"


class TripRiderStatus(models.TextChoices):
    PENDING = "pending"
    BOARDED = "boarded"
    DROPPED = "dropped"
    ABSENT = "absent"

    @classmethod
    def can_become(cls, current: str, following: str) -> bool:
        """Pending boards or is absent; boarded is dropped; dropped and absent
        are final."""
        return following in {
            cls.PENDING: (cls.BOARDED, cls.ABSENT),
            cls.BOARDED: (cls.DROPPED,),
        }.get(current, ())


class EarlyAccessStatus(models.TextChoices):
    NEW = "new", "New"
    CONTACTED = "contacted", "Contacted"
    CONVERTED = "converted", "Converted"
    DECLINED = "declined", "Declined"

    @classmethod
    def settable(cls) -> tuple:
        """Converted is not among them: it means a school exists, and the
        system sets it when one does."""
        return (cls.NEW, cls.CONTACTED, cls.DECLINED)

    @classmethod
    def open(cls) -> tuple:
        return (cls.NEW, cls.CONTACTED)


class NoticeKind(models.TextChoices):
    """What somebody in the Communication Center is writing (docs/communication.md)."""

    MESSAGE = "message", "Message"
    EMERGENCY = "emergency", "Emergency alert"
    FEE_REMINDER = "fee_reminder", "Fee reminder"

    @classmethod
    def event(cls, kind: str) -> str:
        return {
            cls.MESSAGE: MessageEvent.GENERAL_MESSAGE,
            cls.EMERGENCY: MessageEvent.EMERGENCY_ALERT,
            cls.FEE_REMINDER: MessageEvent.FEE_REMINDER,
        }[kind]


class NoticeAudience(models.TextChoices):
    """Who a notice is for. The first two name one person and are sent at
    once; the rest are groups and are fanned out by the queue."""

    STUDENT = "student", "One student"
    STAFF_MEMBER = "staff_member", "One staff member"
    CLASS_SECTION = "class_section", "A class section"
    DEPARTMENT = "department", "A department"
    PARENTS = "parents", "All parents"
    STUDENTS = "students", "All students"
    TEACHERS = "teachers", "All teachers"
    STAFF = "staff", "All staff"
    EVERYONE = "everyone", "Everyone"

    @classmethod
    def needs_target(cls, audience: str) -> bool:
        return audience in (cls.STUDENT, cls.STAFF_MEMBER, cls.CLASS_SECTION, cls.DEPARTMENT)

    @classmethod
    def is_individual(cls, audience: str) -> bool:
        return audience in (cls.STUDENT, cls.STAFF_MEMBER)

    @classmethod
    def reaches_students(cls, audience: str) -> bool:
        """Audiences made of students - reached through their guardians, or
        directly, or both (NoticeRecipients)."""
        return audience in (cls.STUDENT, cls.CLASS_SECTION, cls.PARENTS, cls.STUDENTS, cls.EVERYONE)

    @classmethod
    def reaches_staff(cls, audience: str) -> bool:
        return audience in (cls.STAFF_MEMBER, cls.DEPARTMENT, cls.TEACHERS, cls.STAFF, cls.EVERYONE)


class NoticeRecipients(models.TextChoices):
    """For an audience made of students: who actually receives it."""

    GUARDIANS = "guardians", "Parents / guardians"
    STUDENTS = "students", "Students themselves"
    BOTH = "both", "Both"

    @classmethod
    def for_audience(cls, audience: str, chosen: str | None) -> str:
        """"All parents" and "all students" say it in their name; the other
        student audiences take the form's choice, guardians by default."""
        if audience == NoticeAudience.PARENTS:
            return cls.GUARDIANS

        if audience == NoticeAudience.STUDENTS:
            return cls.STUDENTS

        return chosen or cls.GUARDIANS

    @classmethod
    def includes_guardians(cls, recipients: str) -> bool:
        return recipients in (cls.GUARDIANS, cls.BOTH)

    @classmethod
    def includes_students(cls, recipients: str) -> bool:
        return recipients in (cls.STUDENTS, cls.BOTH)
