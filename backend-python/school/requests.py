"""What a request is allowed to contain.

The Python half of app/Http/Requests. Frontend validation is UX; this is the
validation that counts (CLAUDE.md rule 12), and it has to refuse exactly what
Laravel refuses - the same fields, the same 422, the same sentence.

The rule that shapes most of this file: **the client's school_id is never
trusted** (CLAUDE.md rule 10). An actor pinned to one school writes into that
school whatever the request says. Anybody who could mean more than one has to
name it, and naming one outside their reach fails validation rather than being
quietly ignored - otherwise a write would land somewhere they cannot see.
"""

from __future__ import annotations

from django.db.models import Q
from rest_framework import serializers

import datetime as dt
import decimal
import re

from . import attendants, audit, hashing, mailer, notices, notifications, permissions, sms, whatsapp
from .enums import (
    UserStatus,
    MessageChannel,
    NoticeAudience,
    NoticeKind,
    NoticeRecipients,
    EarlyAccessStatus,
    TripDirection,
    TripRiderStatus,
    TransportStatus,
    AnnouncementAudience,
    AnnouncementChannels,
    AttendanceAlertMode,
    AssessmentType,
    AttendanceStatus,
    MessageCategory,
    MessageChannel,
    MessageEvent,
    MessageStatus,
    DayOfWeek,
    HolidayType,
    LeaveType,
    PaymentMode,
    PaymentStatus,
    PaymentType,
    StaffAttendanceStatus,
    StudentStatus,
    UserRole,
)
from .models import (
    AttendantCredential,
    AcademicTerm,
    AcademicYear,
    Assessment,
    GradeScale,
    SyllabusTopic,
    ClassSection,
    Department,
    Holiday,
    Period,
    EarlyAccessRequest,
    School,
    SchoolClass,
    StaffProfile,
    Student,
    Subject,
    SyllabusTopic,
    TimetableEntry,
    Driver,
    TransportRoute,
    TransportStop,
    Vehicle,
    User,
)
from .clock import SchoolClock
from .scope import SchoolScope
from .validation import (
    PHP_INTEGER,
    CoordinateField,
    attribute,
    LaravelBooleanField,
    LaravelCharField,
    LaravelDateField,
    LaravelIntegerField,
    MobileField,
    PasswordField,
    TimezoneField,
    UrlField,
    already_taken,
    at_least,
    at_most,
    password_rules,
    bad_format,
    confirmation_does_not_match,
    does_not_exist,
    must_be_a_number,
    must_be_after,
    must_be_an_integer,
    must_be_between,
    normalise,
    not_a_date,
    not_an_email,
    optional_text,
    prohibits,
    too_long,
    required,
    required_without,
    selected_is_invalid,
)

# ISO 4217: three upper-case letters and nothing else.
CURRENCY_PATTERN = re.compile(r"^[A-Z]{3}$")

# Deliberately permissive, matching Laravel's `email` rule rather than trying
# to be cleverer than it: something, an @, something with a dot in it. A
# stricter pattern here would refuse addresses the PHP backend accepts, which
# is a contract difference dressed up as a fix.
EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class EmailField(LaravelCharField):
    """Laravel's `email` rule, as permissive as it is - see EMAIL_PATTERN.

    `lowercase` is Laravel's LowercasesEmail: the forms that look an account up
    by address ask in the form the address is stored in.
    """

    def __init__(self, field_name: str, lowercase: bool = False, **kwargs) -> None:
        super().__init__(field_name, **kwargs)
        self._lowercase = lowercase

    def to_internal_value(self, data):
        value = super().to_internal_value(data)

        if self._lowercase:
            value = value.strip().lower()

        if not EMAIL_PATTERN.match(value):
            raise serializers.ValidationError(not_an_email(self._field_name))

        return value


class OptionalEmailField(LaravelCharField):
    """A `nullable|email|max:255` field: blank and null both mean "none on
    record", anything else has to look like an address."""

    def __init__(self, field_name: str, **kwargs) -> None:
        kwargs.setdefault("required", False)
        kwargs.setdefault("allow_null", True)
        kwargs.setdefault("allow_blank", True)
        super().__init__(field_name, max_length=255, **kwargs)

    def to_internal_value(self, data):
        if data is None or data == "":
            return None

        value = super().to_internal_value(data)

        if not EMAIL_PATTERN.match(value):
            raise serializers.ValidationError(not_an_email(self._field_name))

        return value.strip().lower()


class ScopedSerializer(serializers.Serializer):
    """A form that knows who is filling it in.

    The scope decides what `school_id` may say, so it has to be available
    while the fields are being checked rather than afterwards.
    """

    def __init__(self, *args, actor=None, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        self.actor = actor

    @property
    def scope(self) -> SchoolScope:
        return SchoolScope.for_actor(self.actor)

    def requested_school_id(self):
        """What the request asked for, if anything."""
        value = self.initial_data.get("school_id")

        return None if value is None or value == "" else value

    def resolved_school_id(self):
        """The school this write lands in. Never simply what the client sent."""
        requested = self.requested_school_id()

        try:
            requested = None if requested is None else int(requested)
        except (TypeError, ValueError):
            requested = None

        return self.scope.writable_school_id(requested)

    def validate_school_id_field(self) -> None:
        """Laravel's schoolIdRules(), which cannot be expressed as a field
        declaration because what it demands depends on the actor.

        An actor with exactly one school writes into it regardless, so the
        field is ignored rather than checked. Anybody who could mean more than
        one - a Super Admin, who belongs to none, or an admin of a school in a
        group - has to name it, and it has to be one they can reach.
        """
        if self.scope.default_school_id() is not None:
            return

        requested = self.requested_school_id()

        if requested is None:
            raise serializers.ValidationError({"school_id": [required("school_id")]})

        try:
            school_id = int(requested)
        except (TypeError, ValueError):
            raise serializers.ValidationError({"school_id": [does_not_exist("school_id")]})

        reachable = School.objects.filter(pk=school_id)

        if not self.scope.is_unrestricted():
            reachable = reachable.filter(pk__in=self.scope.ids() or [])

        if not reachable.exists():
            raise serializers.ValidationError({"school_id": [does_not_exist("school_id")]})


class StoreStudentRequest(ScopedSerializer):
    class_section_id = LaravelIntegerField("class_section_id")
    admission_number = LaravelCharField("admission_number", max_length=30)
    first_name = LaravelCharField("first_name", max_length=100)
    last_name = LaravelCharField("last_name", max_length=100)
    roll_number = optional_text("roll_number", 20)
    guardian_name = LaravelCharField("guardian_name", max_length=150)
    guardian_mobile = MobileField("guardian_mobile")
    guardian_email = OptionalEmailField("guardian_email")
    student_mobile = MobileField("student_mobile")
    student_email = OptionalEmailField("student_email")
    address = optional_text("address", 500)

    def validate(self, attrs):
        self.validate_school_id_field()

        school_id = self.resolved_school_id()
        errors = {}

        if not section_belongs_to(attrs["class_section_id"], school_id):
            errors["class_section_id"] = [does_not_exist("class_section_id")]

        if admission_number_taken(attrs["admission_number"], school_id):
            errors["admission_number"] = [already_taken("admission_number")]

        if errors:
            raise serializers.ValidationError(errors)

        attrs["school_id"] = school_id

        return attrs


class UpdateStudentRequest(ScopedSerializer):
    """A PATCH: every field optional, but a field that is sent must be good.

    `school_id` is fixed at creation and is not on this form at all, same as
    every other feature - a student does not move between schools by being
    edited.
    """

    class_section_id = LaravelIntegerField("class_section_id", required=False)
    admission_number = LaravelCharField("admission_number", max_length=30, required=False)
    first_name = LaravelCharField("first_name", max_length=100, required=False)
    last_name = LaravelCharField("last_name", max_length=100, required=False)
    roll_number = optional_text("roll_number", 20)
    guardian_name = LaravelCharField("guardian_name", max_length=150, required=False)
    guardian_mobile = MobileField("guardian_mobile")
    guardian_email = OptionalEmailField("guardian_email")
    student_mobile = MobileField("student_mobile")
    student_email = OptionalEmailField("student_email")
    address = optional_text("address", 500)

    def __init__(self, *args, student: Student = None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.student = student

    def validate(self, attrs):
        school_id = self.student.school_id
        errors = {}

        if "class_section_id" in attrs and not section_belongs_to(attrs["class_section_id"], school_id):
            errors["class_section_id"] = [does_not_exist("class_section_id")]

        if "admission_number" in attrs and admission_number_taken(
            attrs["admission_number"], school_id, ignoring=self.student.id
        ):
            errors["admission_number"] = [already_taken("admission_number")]

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


def section_belongs_to(class_section_id, school_id) -> bool:
    """Is this section one of the school's?

    `class_sections` has no school_id column of its own, so the question has
    to be asked through `school_classes`. A section from another school is an
    invalid selection, not a forbidden one: the client never had a legitimate
    way to name it, so a 422 on the field is the honest answer.
    """
    if school_id is None:
        return False

    return ClassSection.objects.filter(
        pk=class_section_id,
        school_class__in=SchoolClass.objects.filter(school_id=school_id).values("id"),
    ).exists()


def admission_number_taken(admission_number, school_id, ignoring: int | None = None) -> bool:
    """Unique per school, not globally - two schools may each have an ADM-001."""
    taken = Student.objects.filter(school_id=school_id, admission_number=admission_number)

    if ignoring is not None:
        taken = taken.exclude(pk=ignoring)

    return taken.exists()


# -- schools ----------------------------------------------------------------


class SchoolForm(serializers.Serializer):
    """The fields a school is described by, shared by create and edit.

    Only a Super Admin reaches either, so there is no scope to apply: a school
    is a platform record, not a tenant one.
    """

    name = LaravelCharField("name", max_length=255)
    registration_number = optional_text("registration_number", 100)
    email = LaravelCharField("email", max_length=255)
    phone = MobileField("phone", required=True, allow_null=False)
    address = LaravelCharField("address", max_length=255)
    city = LaravelCharField("city", max_length=100)
    state = LaravelCharField("state", max_length=100)
    country = LaravelCharField("country", max_length=100)
    postal_code = LaravelCharField("postal_code", max_length=20)
    latitude = CoordinateField("latitude", -90, 90)
    longitude = CoordinateField("longitude", -180, 180)
    currency_code = LaravelCharField("currency_code", max_length=3)
    timezone = TimezoneField("timezone", max_length=64)
    logo_url = UrlField("logo_url", max_length=2048, required=False, allow_null=True)
    parent_school_id = LaravelIntegerField(
        "parent_school_id", required=False, allow_null=True
    )

    def __init__(self, *args, school: School = None, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        # The school being edited, if this is an edit. It decides what the
        # uniqueness and parent checks are allowed to ignore.
        self.school = school

    def validate_email(self, value: str) -> str:
        if not EMAIL_PATTERN.match(value):
            raise serializers.ValidationError(not_an_email("email"))

        return value

    def validate_currency_code(self, value: str) -> str:
        # ISO 4217, upper case. Lower case is refused rather than corrected -
        # the currency is fixed at creation and copied onto every payment, so
        # guessing here would put a guess in a ledger (CLAUDE.md rule 5).
        if not CURRENCY_PATTERN.match(value):
            raise serializers.ValidationError(bad_format("currency_code"))

        return value

    def validate(self, attrs):
        errors = {}

        taken = School.objects.filter(email=attrs["email"]) if "email" in attrs else School.objects.none()

        if self.school is not None:
            taken = taken.exclude(pk=self.school.pk)

        if taken.exists():
            errors["email"] = [already_taken("email")]

        # Half a coordinate points nowhere.
        latitude = attrs.get("latitude")
        longitude = attrs.get("longitude")

        if latitude is None and longitude is not None:
            errors["latitude"] = ["Enter a latitude as well, or clear the longitude."]

        if longitude is None and latitude is not None:
            errors["longitude"] = ["Enter a longitude as well, or clear the latitude."]

        parent_error = self.check_parent(attrs.get("parent_school_id"))

        if parent_error:
            errors["parent_school_id"] = [parent_error]

        if errors:
            raise serializers.ValidationError(errors)

        return attrs

    def check_parent(self, parent_id) -> str | None:
        """Keeps a school group exactly one level deep.

        A parent with branches, and nothing below that. Groups of groups would
        mean a recursive query everywhere a group is resolved - and everywhere
        that forgot would silently miss half the group, which is the worst
        kind of isolation bug because it looks like missing data rather than a
        leak.

        Ported from App\\Rules\\ValidParentSchool, message for message.
        """
        if parent_id is None:
            return None

        parent = School.objects.filter(pk=parent_id).first()

        if parent is None:
            return does_not_exist("parent_school_id")

        if self.school is not None and parent.id == self.school.id:
            return "A school cannot be a branch of itself."

        if parent.parent_school_id is not None:
            return (
                f'"{parent.name}" is itself a branch. '
                "A group is one level deep: pick its parent instead."
            )

        if self.school is not None and School.objects.filter(parent_school_id=self.school.id).exists():
            return (
                f'"{self.school.name}" has branches of its own, '
                "so it cannot become a branch of another school."
            )

        return None


class StoreSchoolRequest(SchoolForm):
    # Set when a school is onboarded from a signup request, so the request can
    # record what it became. The early-access module itself is M11; this field
    # is here because it is part of the schools contract today.
    early_access_request_id = LaravelIntegerField(
        "early_access_request_id", required=False, allow_null=True
    )

    def validate(self, attrs):
        attrs = super().validate(attrs)

        request_id = attrs.get("early_access_request_id")

        if request_id is not None and not EarlyAccessRequest.objects.filter(pk=request_id).exists():
            raise serializers.ValidationError(
                {"early_access_request_id": [does_not_exist("early_access_request_id")]}
            )

        return attrs


class UpdateSchoolRequest(SchoolForm):
    """A PATCH: every field optional, but a field that is sent must be good."""

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)

        # `sometimes` in Laravel's words: a field absent from the body is not
        # checked and not written. Applied here rather than by declaring two
        # near-identical field lists, which is how the two forms drift apart.
        for name, field in self.fields.items():
            field.required = False


# -- student attendance -----------------------------------------------------


class SchoolDateField(LaravelDateField):
    """A date that cannot be in the future - measured at the *school*.

    Laravel's `before_or_equal:today` resolves "today" from the server, which
    runs in UTC. A teacher in Asia/Kolkata marking the register at 7am is five
    and a half hours ahead of that, so before 05:30 UTC the server would
    reject a perfectly ordinary morning as being in the future.
    """

    def __init__(self, field_name: str, **kwargs) -> None:
        super().__init__(field_name, **kwargs)
        self._field_name = field_name

    def to_internal_value(self, data):
        value = super().to_internal_value(data)
        today = self.context.get("school_today")

        if today is not None and value > today:
            raise serializers.ValidationError(
                f"The {attribute(self._field_name)} field must be a date "
                f"before or equal to {today.isoformat()}."
            )

        return value


class AttendanceRecordSerializer(serializers.Serializer):
    student_id = LaravelIntegerField("student_id")
    status = LaravelCharField("status", max_length=20)
    remarks = optional_text("remarks", 255)


class AttendanceRegisterRequest(serializers.Serializer):
    """`class_section_id` is body data, not a route-bound model.

    So a bad id fails validation with a 422, and ownership is checked in the
    view once the section is known to be real - a 403 about a section that
    does not exist would tell a caller it does.
    """

    class_section_id = LaravelIntegerField("class_section_id")
    date = SchoolDateField("date")

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def validate_class_section_id(self, value):
        if not ClassSection.objects.filter(pk=value).exists():
            raise serializers.ValidationError(does_not_exist("class_section_id"))

        return value


class MarkAttendanceRequest(serializers.Serializer):
    class_section_id = LaravelIntegerField("class_section_id")
    attendance_date = SchoolDateField("attendance_date")
    records = AttendanceRecordSerializer(many=True)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def validate_class_section_id(self, value):
        if not ClassSection.objects.filter(pk=value).exists():
            raise serializers.ValidationError(does_not_exist("class_section_id"))

        return value

    def validate_records(self, value):
        if not value:
            raise serializers.ValidationError(required("records"))

        student_ids = [record["student_id"] for record in value]

        if len(student_ids) != len(set(student_ids)):
            raise serializers.ValidationError(
                "Each student can only appear once in the attendance records."
            )

        return value

    def validate(self, attrs):
        errors = {}

        for record in attrs["records"]:
            if record["status"] not in AttendanceStatus.values:
                errors["records"] = [selected_is_invalid("status")]
                break

        # Every student named has to be an active student of *this* section.
        # A mark against somebody else's student would be a row nobody's
        # register shows and every percentage counts.
        named = {record["student_id"] for record in attrs["records"]}
        belong = set(
            Student.objects.filter(
                id__in=named,
                class_section_id=attrs["class_section_id"],
                status=StudentStatus.ACTIVE,
            ).values_list("id", flat=True)
        )

        if named - belong:
            errors.setdefault("records", []).append(selected_is_invalid("student_id"))

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


# -- staff attendance -------------------------------------------------------


class ClockTimeField(serializers.TimeField):
    """"08:05" and nothing else - a clock time in the school's own day."""

    def __init__(self, field_name: str, **kwargs) -> None:
        kwargs.setdefault("required", False)
        kwargs.setdefault("allow_null", True)
        super().__init__(
            format="%H:%M",
            input_formats=["%H:%M"],
            error_messages={
                "invalid": f"The {attribute(field_name)} field must match the format H:i."
            },
            **kwargs,
        )


class StaffAttendanceRecordSerializer(serializers.Serializer):
    staff_profile_id = LaravelIntegerField("staff_profile_id")
    status = LaravelCharField("status", max_length=20)
    check_in = ClockTimeField("check_in")
    check_out = ClockTimeField("check_out")
    remarks = optional_text("remarks", 255)


class StaffAttendanceScopedRequest(ScopedSerializer):
    """The half these three forms share: whose school, and which department.

    A Super Admin names the school; everybody else is scoped to their own
    whatever they send.
    """

    department_id = LaravelIntegerField("department_id", required=False, allow_null=True)

    def check_department(self, attrs, errors) -> None:
        department_id = attrs.get("department_id")

        if department_id is not None and not Department.objects.filter(
            pk=department_id
        ).exists():
            errors["department_id"] = [does_not_exist("department_id")]


class StaffAttendanceRegisterRequest(StaffAttendanceScopedRequest):
    date = SchoolDateField("date")

    def validate(self, attrs):
        errors = {}
        self.check_department(attrs, errors)

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


class MarkStaffAttendanceRequest(StaffAttendanceScopedRequest):
    attendance_date = SchoolDateField("attendance_date")
    records = StaffAttendanceRecordSerializer(many=True)

    def validate_records(self, value):
        if not value:
            raise serializers.ValidationError(required("records"))

        ids = [record["staff_profile_id"] for record in value]

        if len(ids) != len(set(ids)):
            raise serializers.ValidationError(
                "Each staff member can only appear once in the attendance records."
            )

        return value

    def validate(self, attrs):
        errors = {}
        self.check_department(attrs, errors)

        school_id = self.resolved_school_id()

        for record in attrs["records"]:
            if record["status"] not in StaffAttendanceStatus.values:
                errors["records"] = [selected_is_invalid("status")]
                break

        # Whose register this actor may mark. An HOD is narrowed to the
        # departments they head - never another department in the same school
        # - which is the same rule the roster applies, enforced here so a
        # hand-made request cannot get round it.
        markable = StaffProfile.objects.filter(school_id=school_id)

        if self.actor.role == UserRole.HOD:
            markable = markable.filter(department__hod_user_id=self.actor.id)

        named = {record["staff_profile_id"] for record in attrs["records"]}
        allowed = set(markable.filter(id__in=named).values_list("id", flat=True))

        if named - allowed:
            errors.setdefault("records", []).append(selected_is_invalid("staff_profile_id"))

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


# -- timetable --------------------------------------------------------------


class TimetableGridRequest(ScopedSerializer):
    """Which way to slice the week.

    By class section (one class's whole week, the Timetable screen) or by
    teacher ("my timetable", the same grid sliced the other way). Exactly one
    of the two: both together would be two different questions in one request,
    and neither leaves nothing to draw.

    Whether the actor may *see* that class or that teacher is not asked here.
    A bad id is a 422; somebody else's id is a 404, decided once the target is
    loaded - see views/timetable.py.
    """

    class_section_id = LaravelIntegerField(
        "class_section_id", required=False, allow_null=True
    )
    teacher_id = LaravelIntegerField("teacher_id", required=False, allow_null=True)

    def validate(self, attrs):
        section = attrs.get("class_section_id")
        teacher = attrs.get("teacher_id")
        errors = {}

        if section is None and teacher is None:
            errors["class_section_id"] = [
                required_without("class_section_id", "teacher_id")
            ]
            errors["teacher_id"] = [required_without("teacher_id", "class_section_id")]
        elif section is not None and teacher is not None:
            errors["class_section_id"] = [prohibits("class_section_id", "teacher_id")]

        if section is not None and not ClassSection.objects.filter(pk=section).exists():
            errors.setdefault("class_section_id", []).append(
                selected_is_invalid("class_section_id")
            )

        if teacher is not None and not User.objects.filter(pk=teacher).exists():
            errors.setdefault("teacher_id", []).append(selected_is_invalid("teacher_id"))

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


class UpsertTimetableEntryRequest(ScopedSerializer):
    """One cell of the grid.

    Every id is checked against the school this write lands in, not merely
    against its own table: a period, a subject or a teacher from another
    school is as wrong as one that does not exist, and "the selected period is
    invalid" is the honest answer to both.

    A class section has no school of its own - it belongs to a class, which
    belongs to a school - so that one is checked through its class.
    """

    class_section_id = LaravelIntegerField("class_section_id")
    period_id = LaravelIntegerField("period_id")
    day_of_week = LaravelCharField("day_of_week", max_length=255)
    subject_id = LaravelIntegerField("subject_id")
    teacher_id = LaravelIntegerField("teacher_id")

    def validate(self, attrs):
        self.validate_school_id_field()

        school_id = self.resolved_school_id()
        errors = {}

        in_this_school = SchoolClass.objects.filter(school_id=school_id).values("id")

        if not ClassSection.objects.filter(
            pk=attrs["class_section_id"], school_class_id__in=in_this_school
        ).exists():
            errors["class_section_id"] = [selected_is_invalid("class_section_id")]

        if not Period.objects.filter(pk=attrs["period_id"], school_id=school_id).exists():
            errors["period_id"] = [selected_is_invalid("period_id")]

        if attrs["day_of_week"] not in DayOfWeek.values:
            errors["day_of_week"] = [selected_is_invalid("day_of_week")]

        if not Subject.objects.filter(
            pk=attrs["subject_id"], school_id=school_id
        ).exists():
            errors["subject_id"] = [selected_is_invalid("subject_id")]

        # Only somebody who teaches. An admin account is not a name that
        # belongs in a timetable cell, whatever else it may do in the school.
        if not User.objects.filter(
            pk=attrs["teacher_id"],
            school_id=school_id,
            role__in=(UserRole.TEACHER, UserRole.HOD),
        ).exists():
            errors["teacher_id"] = [selected_is_invalid("teacher_id")]

        if errors:
            raise serializers.ValidationError(errors)

        attrs["school_id"] = school_id

        return attrs


# -- daily teaching reports -------------------------------------------------


class StoreDailyTeachingReportRequest(ScopedSerializer):
    """What was taught in one period.

    Structural checks only: does the period exist, is the date one it was
    scheduled on. Whether it is *this* teacher's period is ownership, which
    the policy answers with a 403 rather than a 422 here.
    """

    timetable_entry_id = LaravelIntegerField("timetable_entry_id")
    report_date = LaravelDateField("report_date")
    topic_taught = LaravelCharField("topic_taught", max_length=255)
    homework = optional_text("homework", 500)
    remarks = optional_text("remarks", 500)

    def validate_timetable_entry_id(self, value):
        if not TimetableEntry.objects.filter(pk=value).exists():
            raise serializers.ValidationError(selected_is_invalid("timetable_entry_id"))

        return value

    def validate_report_date(self, value):
        """Both date rules, reported together the way Laravel reports them.

        A field-level check rather than `validate()`, because DRF skips
        `validate()` as soon as any field fails - a missing topic would then
        hide a future date, where Laravel lists both.
        """
        problems = []
        today = self.context.get("school_today")

        if today is not None and value > today:
            problems.append(
                f"The {attribute('report_date')} field must be a date "
                f"before or equal to {today.isoformat()}."
            )

        try:
            entry_id = int(str(self.initial_data.get("timetable_entry_id")))
        except ValueError:
            entry_id = None

        entry = (
            None if entry_id is None else TimetableEntry.objects.filter(pk=entry_id).first()
        )

        if entry is not None:
            weekday = value.strftime("%A").lower()

            if weekday != entry.day_of_week:
                problems.append(
                    "The report date must fall on the day this period is scheduled "
                    f"({entry.day_of_week.capitalize()})."
                )

        if problems:
            raise serializers.ValidationError(problems)

        return value


class TeachingReportSummaryRequest(serializers.Serializer):
    """The day the KPI row is about."""

    date = LaravelDateField("date")

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)


# -- syllabus ---------------------------------------------------------------
#
# Most checks below are field-level validators rather than one `validate()`.
# Laravel reports every failing field at once, and DRF skips `validate()` the
# moment any single field fails - so a title that is too long would otherwise
# hide a sequence number that is already taken.


def as_id(value):
    """An id off raw input, or None - the way `Model::find()` treats junk."""
    try:
        return int(str(value))
    except ValueError:
        return None


class SyllabusTopicListRequest(serializers.Serializer):
    subject_id = LaravelIntegerField("subject_id")

    def validate_subject_id(self, value):
        if not Subject.objects.filter(pk=value).exists():
            raise serializers.ValidationError(selected_is_invalid("subject_id"))

        return value


class StoreSyllabusTopicRequest(ScopedSerializer):
    subject_id = LaravelIntegerField("subject_id")
    title = LaravelCharField("title", max_length=255)
    sequence_number = LaravelIntegerField("sequence_number", min_value=1)

    def validate_subject_id(self, value):
        # A subject of the school this topic is filed under - another
        # school's is as invalid as one that does not exist.
        if not Subject.objects.filter(pk=value, school_id=self.resolved_school_id()).exists():
            raise serializers.ValidationError(selected_is_invalid("subject_id"))

        return value

    def validate_sequence_number(self, value):
        # Against the subject as sent, as Laravel's rule reads it: unique
        # within a subject, so every subject can start at 1.
        taken = SyllabusTopic.objects.filter(
            subject_id=as_id(self.initial_data.get("subject_id")), sequence_number=value
        ).exists()

        if taken:
            raise serializers.ValidationError(already_taken("sequence_number"))

        return value

    def validate(self, attrs):
        self.validate_school_id_field()

        return attrs


class UpdateSyllabusTopicRequest(serializers.Serializer):
    """The subject is fixed at creation: moving a topic to another subject
    is a new topic, not an edit."""

    title = LaravelCharField("title", max_length=255, required=False)
    sequence_number = LaravelIntegerField("sequence_number", min_value=1, required=False)

    def __init__(self, *args, topic=None, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        self.topic = topic

    def validate_sequence_number(self, value):
        taken = (
            SyllabusTopic.objects.filter(subject_id=self.topic.subject_id, sequence_number=value)
            .exclude(pk=self.topic.pk)
            .exists()
        )

        if taken:
            raise serializers.ValidationError(already_taken("sequence_number"))

        return value


class SyllabusChecklistRequest(serializers.Serializer):
    class_section_id = LaravelIntegerField("class_section_id")
    subject_id = LaravelIntegerField("subject_id")

    def validate_class_section_id(self, value):
        if not ClassSection.objects.filter(pk=value).exists():
            raise serializers.ValidationError(selected_is_invalid("class_section_id"))

        return value

    def validate_subject_id(self, value):
        if not Subject.objects.filter(pk=value).exists():
            raise serializers.ValidationError(selected_is_invalid("subject_id"))

        return value


class ToggleSyllabusProgressRequest(serializers.Serializer):
    syllabus_topic_id = LaravelIntegerField("syllabus_topic_id")
    class_section_id = LaravelIntegerField("class_section_id")
    completed = LaravelBooleanField("completed")

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def validate_syllabus_topic_id(self, value):
        if not SyllabusTopic.objects.filter(pk=value).exists():
            raise serializers.ValidationError(selected_is_invalid("syllabus_topic_id"))

        return value

    def validate_class_section_id(self, value):
        # A section of the topic's own school. With no such topic there is no
        # school, and so no section can match - the same answer Laravel gives.
        topic = SyllabusTopic.objects.filter(
            pk=as_id(self.initial_data.get("syllabus_topic_id"))
        ).first()

        in_that_school = topic is not None and ClassSection.objects.filter(
            pk=value, school_class__school_id=topic.school_id
        ).exists()

        if not in_that_school:
            raise serializers.ValidationError(selected_is_invalid("class_section_id"))

        return value


# -- HOD department report --------------------------------------------------

# Laravel's date_format:Y-m, which also re-formats what it parsed and compares:
# "2026-9" parses but formats as "2026-09", so it fails, and "2026-13" rolls
# over into the next year and fails the same way.
YEAR_MONTH = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")


class HodDepartmentReportRequest(ScopedSerializer):
    department_id = LaravelIntegerField("department_id", required=False, allow_null=True)
    month = LaravelCharField("month", max_length=255, required=False, allow_null=True)

    def validate_department_id(self, value):
        # A department of the school being reported on. A real one from
        # another school is a 422 here, not a 403 later.
        if value is not None and not Department.objects.filter(
            pk=value, school_id=self.resolved_school_id()
        ).exists():
            raise serializers.ValidationError(selected_is_invalid("department_id"))

        return value

    def validate_month(self, value):
        if value is not None and not YEAR_MONTH.match(value):
            raise serializers.ValidationError(
                f"The {attribute('month')} field must match the format Y-m."
            )

        return value

    def validate(self, attrs):
        self.validate_school_id_field()

        return attrs


# -- communication ----------------------------------------------------------

# Three SMS segments. Templates are refused past it before they are saved.
MAX_BODY_LENGTH = 480

SENDER_ID = re.compile(r"^[A-Za-z0-9-]+$")


def php_int(value) -> int:
    """PHP's (int) cast of a query-string value: the leading run of digits,
    with an optional sign, and 0 when there is none - "12abc" is 12, "abc" is
    0. The controllers that read `school_id` raw rely on exactly this."""
    match = re.match(r"^\s*([+-]?\d+)", str(value))

    return int(match.group(1)) if match else 0


def requested_school(actor, value):
    """Which school a communication screen is about.

    Absent means the actor's own school; anything sent is cast the way PHP
    casts it. The policy then decides whether that school is theirs - there is
    no scoping here, on purpose, because Laravel has none at this step either.
    """
    return actor.school_id if value is None else php_int(value)


def enum_choice(field_name: str, choices):
    """A nullable enum filter, refused with Laravel's sentence."""

    def check(value):
        if value is not None and value not in choices:
            raise serializers.ValidationError(selected_is_invalid(field_name))

        return value

    return check


class MessageIndexRequest(serializers.Serializer):
    """The message log's filters. Unlike the other lists, a bad `per_page` is
    a 422 here rather than a silent default - the form request says so."""

    school_id = LaravelIntegerField("school_id", required=False, allow_null=True)
    category = LaravelCharField("category", max_length=255, required=False, allow_null=True)
    channel = LaravelCharField("channel", max_length=255, required=False, allow_null=True)
    status = LaravelCharField("status", max_length=255, required=False, allow_null=True)
    date_from = LaravelDateField("date_from", required=False, allow_null=True)
    date_to = LaravelDateField("date_to", required=False, allow_null=True)
    q = LaravelCharField("q", max_length=100, required=False, allow_null=True)
    per_page = LaravelIntegerField("per_page", required=False, allow_null=True, min_value=1, max_value=100)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def validate_school_id(self, value):
        if value is not None and not School.objects.filter(pk=value).exists():
            raise serializers.ValidationError(selected_is_invalid("school_id"))

        return value

    validate_category = staticmethod(enum_choice("category", MessageCategory.values))
    validate_channel = staticmethod(enum_choice("channel", MessageChannel.values))
    validate_status = staticmethod(enum_choice("status", MessageStatus.values))

    def validate_date_to(self, value):
        # Only when date_from is itself a date - Laravel says nothing about
        # the order of two dates when one of them is not a date at all.
        try:
            start = self.fields["date_from"].to_internal_value(self.initial_data.get("date_from"))
        except serializers.ValidationError:
            start = None

        if value is not None and start is not None and value < start:
            raise serializers.ValidationError(
                "The date to field must be a date after or equal to date from."
            )

        return value


class UpdateMessageTemplateRequest(serializers.Serializer):
    body = LaravelCharField("body", max_length=MAX_BODY_LENGTH, allow_blank=False)

    def __init__(self, *args, event=None, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        self.event = event

    def validate_body(self, value):
        """Every failing rule, as Laravel lists them: too short, then any
        placeholder this event does not provide."""
        problems = []

        if len(value) < 10:
            problems.append("The body field must be at least 10 characters.")

        allowed = MessageEvent.tokens(self.event)
        unknown = notifications.unknown_tokens(value, allowed)

        if unknown:
            problems.append(
                "This message can only use these placeholders: {"
                + "}, {".join(allowed)
                + "}. Remove {"
                + "}, {".join(unknown)
                + "}."
            )

        if problems:
            raise serializers.ValidationError(problems)

        return value


class UpdateCommunicationSettingRequest(serializers.Serializer):
    school_id = LaravelIntegerField("school_id", required=False, allow_null=True)
    sms_enabled = LaravelBooleanField("sms_enabled")
    attendance_alerts = LaravelCharField("attendance_alerts", max_length=255)
    transport_alerts_enabled = LaravelBooleanField("transport_alerts_enabled")
    leave_alerts_enabled = LaravelBooleanField("leave_alerts_enabled")
    provider = LaravelCharField("provider", max_length=255)
    sender_id = LaravelCharField("sender_id", max_length=20, required=False, allow_null=True)
    # The channels added after Phase 16 are optional on the form, so a client
    # that only knows the SMS switches keeps working.
    whatsapp_enabled = LaravelBooleanField("whatsapp_enabled", required=False)
    whatsapp_provider = LaravelCharField("whatsapp_provider", max_length=255, required=False)
    email_enabled = LaravelBooleanField("email_enabled", required=False)
    credentials = serializers.JSONField(required=False, allow_null=True)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def validate_school_id(self, value):
        if value is not None and not School.objects.filter(pk=value).exists():
            raise serializers.ValidationError(selected_is_invalid("school_id"))

        return value

    validate_attendance_alerts = staticmethod(enum_choice("attendance_alerts", AttendanceAlertMode.values))

    def validate_provider(self, value):
        if value not in sms.GATEWAYS:
            raise serializers.ValidationError("That SMS gateway is not available.")

        return value

    def validate_whatsapp_provider(self, value):
        if value not in whatsapp.GATEWAYS:
            raise serializers.ValidationError("That WhatsApp gateway is not available.")

        return value

    def validate_credentials(self, value):
        """{provider: {field: value}} for providers and fields that exist. A
        value is text or null; nothing longer than a column holds."""
        if value is None:
            return None

        if not isinstance(value, dict):
            raise serializers.ValidationError("The credentials field must be an object keyed by provider.")

        problems = []

        for provider, fields in value.items():
            allowed = credential_keys(provider)

            if allowed is None:
                problems.append(f'Unknown provider "{provider}".')
                continue

            if not isinstance(fields, dict):
                problems.append(f'The credentials for "{provider}" must be an object.')
                continue

            for key, text in fields.items():
                if key not in allowed:
                    problems.append(f'"{key}" is not a setting of the {provider} provider.')
                elif text is not None and not isinstance(text, str):
                    problems.append(f'The {provider} {key} must be text.')
                elif text is not None and len(text) > 255:
                    problems.append(f'The {provider} {key} may not be greater than 255 characters.')

        if problems:
            raise serializers.ValidationError(problems)

        return value

    def validate_sender_id(self, value):
        if value is not None and not SENDER_ID.match(value):
            raise serializers.ValidationError(
                "A sender ID can only contain letters, numbers and hyphens."
            )

        return value


def credential_keys(provider: str) -> set[str] | None:
    """Every field the SMS or WhatsApp adapter of this name asks for, or None
    for a name no adapter has."""
    gateways = [g for registry in (sms.GATEWAYS, whatsapp.GATEWAYS) for name, g in registry.items() if name == provider]

    if not gateways:
        return None

    return {key for gateway in gateways for key, _label, _secret in gateway.CREDENTIALS}


class SendTestMessageRequest(serializers.Serializer):
    """A test through the school's own provider: which channel, to which number."""

    school_id = LaravelIntegerField("school_id", required=False, allow_null=True)
    channel = LaravelCharField("channel", max_length=20)
    to = MobileField("to", required=True, allow_null=False, allow_blank=False)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def validate_channel(self, value):
        if value not in (MessageChannel.SMS, MessageChannel.WHATSAPP):
            raise serializers.ValidationError("A test message goes by SMS or WhatsApp.")

        return value


LANGUAGE_CODE = re.compile(r"^[a-z]{2,3}(_[A-Za-z]{2,4})?$")


class UpdateWhatsappTemplateRequest(serializers.Serializer):
    """Which of the school's registered WhatsApp templates carries an event,
    and which of the event's tokens fill its numbered parameters, in order."""

    school_id = LaravelIntegerField("school_id", required=False, allow_null=True)
    template_name = LaravelCharField("template_name", max_length=120)
    language = LaravelCharField("language", max_length=10, required=False, allow_null=True, allow_blank=True)
    parameters = serializers.ListField(child=serializers.CharField(), required=False, allow_empty=True, max_length=10)

    def __init__(self, *args, event: str, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        self.event = event

    def validate_language(self, value):
        if value in (None, ""):
            return "en"

        if not LANGUAGE_CODE.match(value):
            raise serializers.ValidationError('A language is a code such as "en" or "en_US".')

        return value

    def validate_parameters(self, value):
        allowed = MessageEvent.tokens(self.event)
        unknown = [name for name in value if name not in allowed]

        if unknown:
            raise serializers.ValidationError(
                "This message can only fill parameters from these placeholders: {"
                + "}, {".join(allowed)
                + "}. Remove {"
                + "}, {".join(dict.fromkeys(unknown))
                + "}."
            )

        return value


class ChannelListField(serializers.Field):
    """A list of channels, or the same as a comma-separated string off a
    query string. Unknown names are refused by name; duplicates collapse."""

    default_error_messages = {"required": "Pick at least one channel."}

    def to_internal_value(self, data):
        """Only the shape here; the names are checked in the form's validate(),
        so a bad channel is reported alongside every other bad field."""
        if isinstance(data, str):
            data = [part.strip() for part in data.split(",")]

        if not isinstance(data, list):
            return []

        return [str(channel) for channel in dict.fromkeys(data) if channel]

    @staticmethod
    def problems(chosen: list[str]) -> list[str]:
        unknown = [channel for channel in chosen if channel not in MessageChannel.values]

        if unknown:
            return ['"' + '", "'.join(unknown) + '" is not a channel.']

        if not chosen:
            return ["Pick at least one channel."]

        return []

    @staticmethod
    def ordered(chosen: list[str]) -> list[str]:
        return [channel for channel in MessageChannel.values if channel in chosen]

    def to_representation(self, value):
        return value


class SendNoticeRequest(ScopedSerializer):
    """A message written by hand: what kind, who for, on which channels.

    `preview` is the same form with the text left out - the count the compose
    dialog shows before anything is written.
    """

    kind = LaravelCharField("kind", max_length=30)
    audience_type = LaravelCharField("audience_type", max_length=30)
    audience_id = serializers.JSONField(required=False, allow_null=True, default=None)
    recipients = LaravelCharField("recipients", max_length=20, required=False, allow_null=True, allow_blank=True)
    channels = ChannelListField()
    subject = LaravelCharField("subject", max_length=150, required=False, allow_null=True, allow_blank=True)
    body = LaravelCharField("body", max_length=1000, required=False, allow_null=True, allow_blank=True)
    amount = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, allow_null=True,
        error_messages={"invalid": "The amount field must be a number.", "max_digits": "The amount is too large."},
    )
    due_date = LaravelDateField("due_date", required=False, allow_null=True)

    def __init__(self, *args, preview: bool = False, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.preview = preview

    validate_kind = staticmethod(enum_choice("kind", NoticeKind.values))
    validate_audience_type = staticmethod(enum_choice("audience_type", NoticeAudience.values))

    def validate_recipients(self, value):
        if value in (None, ""):
            return None

        if value not in NoticeRecipients.values:
            raise serializers.ValidationError(selected_is_invalid("recipients"))

        return value

    def validate_audience_id(self, value):
        if value is None:
            return None

        if isinstance(value, bool) or not (
            isinstance(value, int) or (isinstance(value, str) and re.fullmatch(r"[+-]?\d+", value.strip()))
        ):
            raise serializers.ValidationError("The audience id field must be an integer.")

        return int(value)

    def validate(self, attrs):
        self.validate_school_id_field()
        school_id = self.resolved_school_id()
        errors = {}

        audience = attrs.get("audience_type")
        target = attrs.get("audience_id")

        if audience is not None:
            if NoticeAudience.needs_target(audience) and target is None:
                errors["audience_id"] = ["Pick who this message is for."]
            elif NoticeAudience.needs_target(audience) and not notices.target_exists(school_id, audience, target):
                errors["audience_id"] = ["That person, class or department does not belong to this school."]

        if "channels" in attrs:
            problems = ChannelListField.problems(attrs["channels"])
            attrs["channels"] = ChannelListField.ordered(attrs["channels"])

            # A channel the school has not switched on carries nothing, so
            # asking for it is a mistake worth naming rather than a silent zero.
            if not problems and school_id is not None:
                setting = notifications.settings_for(school_id)
                off = [
                    MessageChannel(channel).label
                    for channel in attrs["channels"]
                    if not notifications.channel_enabled(channel, setting)
                ]

                if off:
                    problems = [f"{' and '.join(off)} is switched off for this school."]

            if problems:
                errors["channels"] = problems

        kind = attrs.get("kind")

        if kind is not None and not self.preview:
            errors.update(self.text_problems(kind, attrs))

        if errors:
            raise serializers.ValidationError(errors)

        attrs["school_id"] = school_id

        return attrs

    @staticmethod
    def text_problems(kind: str, attrs: dict) -> dict:
        problems = {}
        body = (attrs.get("body") or "").strip()
        subject = (attrs.get("subject") or "").strip()

        if kind == NoticeKind.FEE_REMINDER:
            if attrs.get("amount") is None:
                problems["amount"] = [required("amount")]
            elif attrs["amount"] <= 0:
                problems["amount"] = ["The amount must be greater than zero."]

            if attrs.get("due_date") is None:
                problems["due_date"] = [required("due_date")]

            return problems

        if len(body) < 10:
            problems["body"] = ["The body field must be at least 10 characters."]

        if kind == NoticeKind.MESSAGE and not subject:
            problems["subject"] = [required("subject")]

        return problems


class UpdateProfileRequest(serializers.Serializer):
    """What a person may change about themselves (docs/profile.md): their
    name, mobile and home address. Every field is optional - a PATCH - but a
    field that is sent must be good. Anything else in the body (role, email,
    school_id, employee_id...) is not a field here and is ignored, so there
    is no way to smuggle an admin-only change through this form."""

    first_name = LaravelCharField("first_name", max_length=100, required=False)
    last_name = LaravelCharField("last_name", max_length=100, required=False)
    mobile = MobileField("mobile")
    address = optional_text("address", 500)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def validate(self, attrs):
        # Whitespace-only names never get here: normalise() trims them to
        # nothing, and the field's own required rule refuses nothing.
        if not attrs:
            raise serializers.ValidationError({"first_name": ["Send at least one detail to change."]})

        return attrs


class ChangeEmailRequest(serializers.Serializer):
    """A new sign-in address, confirmed with the current password.

    The password is asked because the address is where a reset link goes:
    whoever can change it can take the account, so a session left open on a
    shared computer must not be enough.
    """

    email = EmailField("email", lowercase=True, max_length=255)
    current_password = LaravelCharField("current_password")

    def __init__(self, *args, actor=None, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        self.actor = actor

    def validate(self, attrs):
        errors = {}

        if not hashing.check(attrs["current_password"], self.actor.password):
            errors["current_password"] = ["That is not your current password."]

        if attrs["email"] == (self.actor.email or "").lower():
            errors["email"] = ["That is already your email address."]
        elif User.objects.filter(email__iexact=attrs["email"]).exclude(pk=self.actor.pk).exists():
            errors["email"] = [already_taken("email")]

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


class UpdateModuleSettingRequest(serializers.Serializer):
    """A module's switches and settings for one school. Every field is
    optional so a screen can move one switch without resending the rest;
    the platform switch is the Super Admin's alone, and the settings are
    checked one by one against what the module declares."""

    school_id = LaravelIntegerField("school_id", required=False, allow_null=True)
    platform_enabled = LaravelBooleanField("platform_enabled", required=False)
    school_enabled = LaravelBooleanField("school_enabled", required=False)
    settings = serializers.JSONField(required=False, allow_null=True)

    def __init__(self, *args, module, actor=None, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        self.module = module
        self.actor = actor

    def validate_platform_enabled(self, value):
        if self.actor is not None and self.actor.role != UserRole.SUPER_ADMIN:
            raise serializers.ValidationError("Only the Super Admin can grant or withdraw a module.")

        return value

    def validate_settings(self, value):
        if value is None:
            return None

        if not isinstance(value, dict):
            raise serializers.ValidationError("The settings field must be an object.")

        declared = {setting.key: setting for setting in self.module.settings}
        problems = []
        clean = {}

        for key, raw in value.items():
            setting = declared.get(key)

            if setting is None:
                problems.append(f'"{key}" is not a setting of {self.module.label}.')
                continue

            if setting.type == "bool":
                if not isinstance(raw, bool):
                    problems.append(f"{setting.label} must be true or false.")
                    continue
            elif setting.type == "int":
                if isinstance(raw, bool) or not isinstance(raw, int):
                    problems.append(f"{setting.label} must be a whole number.")
                    continue

                if setting.min is not None and raw < setting.min or setting.max is not None and raw > setting.max:
                    problems.append(f"{setting.label} must be between {setting.min} and {setting.max}.")
                    continue

            clean[key] = raw

        if problems:
            raise serializers.ValidationError(problems)

        return clean

    def validate(self, attrs):
        if not self.module.switchable:
            for switch in ("platform_enabled", "school_enabled"):
                if switch in attrs and attrs[switch] is False:
                    raise serializers.ValidationError({switch: [f"{self.module.label} cannot be switched off."]})

        if not attrs:
            raise serializers.ValidationError({"settings": ["Send a switch or a setting to change."]})

        return attrs


class UpdatePermissionsRequest(serializers.Serializer):
    """The whole matrix, or the part of it being changed: {role: {module:
    level}}. Unknown roles, modules or levels are refused by name, and the
    Super Admin's own row cannot be sent at all."""

    matrix = serializers.JSONField()

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def validate_matrix(self, value):
        if not isinstance(value, dict) or not value:
            raise serializers.ValidationError("The matrix must map roles to their modules and levels.")

        problems = []

        for role, cells in value.items():
            if role not in permissions.EDITABLE_ROLES:
                problems.append(f'"{role}" is not a role whose permissions can be edited.')
                continue

            if not isinstance(cells, dict):
                problems.append(f"The {role} row must map modules to levels.")
                continue

            for module, level in cells.items():
                if module not in permissions.MODULES:
                    problems.append(f'"{module}" is not a module in the matrix.')
                elif level not in permissions.LEVELS:
                    problems.append(f'"{level}" is not a level; use none, view or manage.')

        if problems:
            raise serializers.ValidationError(problems)

        return value


class UpdateMailSettingRequest(serializers.Serializer):
    """The platform's SMTP server. The password is optional on every save:
    left out keeps the stored one, blank clears it."""

    is_active = LaravelBooleanField("is_active", required=False)
    host = LaravelCharField("host", max_length=255)
    port = LaravelIntegerField("port")
    encryption = LaravelCharField("encryption", max_length=10)
    username = optional_text("username", 255)
    password = serializers.CharField(required=False, allow_null=True, allow_blank=True, max_length=255, trim_whitespace=False)
    from_address = EmailField("from_address", max_length=255)
    from_name = LaravelCharField("from_name", max_length=120)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def validate_port(self, value):
        if not 1 <= value <= 65535:
            raise serializers.ValidationError("The port must be between 1 and 65535.")

        return value

    def validate_encryption(self, value):
        if value not in mailer.ENCRYPTIONS:
            raise serializers.ValidationError("Encryption is none, tls or ssl.")

        return value


class SendTestEmailRequest(serializers.Serializer):
    to = EmailField("to", max_length=255)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)


# -- announcements ----------------------------------------------------------


class PublishAnnouncementRequest(ScopedSerializer):
    """A notice and who it is for.

    Mostly field-level checks, so every failing field is reported together
    the way Laravel reports them. The target has to belong to the school
    being announced to - an id from another school is refused with the same
    sentence as one that does not exist.
    """

    title = LaravelCharField("title", max_length=150)
    body = LaravelCharField("body", max_length=2000)
    audience_type = LaravelCharField("audience_type", max_length=255)
    # A None default so the field's own check still runs when it is left out:
    # DRF skips validate_<field> for an absent field with no default, and the
    # "pick a target" rule is exactly about the field being absent.
    audience_id = serializers.JSONField(required=False, allow_null=True, default=None)
    channels = LaravelCharField("channels", max_length=255)
    expires_at = serializers.JSONField(required=False, allow_null=True, default=None)

    def __init__(self, *args, school_today=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.school_today = school_today

    def audience(self):
        value = self.initial_data.get("audience_type")

        return value if value in AnnouncementAudience.values else None

    def validate_title(self, value):
        if len(value) < 3:
            raise serializers.ValidationError("The title field must be at least 3 characters.")

        return value

    def validate_body(self, value):
        if len(value) < 10:
            raise serializers.ValidationError("The body field must be at least 10 characters.")

        return value

    validate_audience_type = staticmethod(enum_choice("audience_type", AnnouncementAudience.values))

    def validate_channels(self, value):
        """One of the three names, or a comma-separated mix of channels."""
        if not AnnouncementChannels.is_valid(value):
            raise serializers.ValidationError(selected_is_invalid("channels"))

        return AnnouncementChannels.normalise(value)

    def validate_audience_id(self, value):
        audience = self.audience()

        if value is None:
            if audience is not None and AnnouncementAudience.needs_target(audience):
                raise serializers.ValidationError("Pick the class or department this announcement is for.")

            return None

        # An integer, as Laravel's rule reads one: a JSON number with no
        # fraction, or a string of digits.
        if isinstance(value, bool) or not (
            (isinstance(value, int)) or (isinstance(value, str) and re.fullmatch(r"[+-]?\d+", value.strip()))
        ):
            raise serializers.ValidationError("The audience id field must be an integer.")

        target = int(value)
        school_id = self.resolved_school_id()

        if audience == AnnouncementAudience.CLASS_SECTION:
            found = ClassSection.objects.filter(pk=target, school_class__academic_year__school_id=school_id).exists()
        elif audience == AnnouncementAudience.DEPARTMENT:
            found = Department.objects.filter(pk=target, school_id=school_id).exists()
        else:
            found = True

        if not found:
            raise serializers.ValidationError("That class or department does not belong to this school.")

        return target

    def validate_expires_at(self, value):
        if value is None:
            return None

        problems = []

        try:
            day = LaravelDateField("expires_at").to_internal_value(value)
        except serializers.ValidationError:
            day = None
            problems.append("The expires at field must be a valid date.")

        # An unreadable date fails the "not in the past" rule as well, and
        # Laravel says both.
        if day is None or (self.school_today is not None and day < self.school_today):
            problems.append("An expiry date cannot be in the past.")

        if problems:
            raise serializers.ValidationError(problems)

        return day

    def validate(self, attrs):
        self.validate_school_id_field()

        attrs["school_id"] = self.resolved_school_id()

        return attrs


# -- transport master data --------------------------------------------------
#
# Uniqueness and "belongs to this school" run in field-level validators, so
# every failing field is reported at once as Laravel reports them. A field
# that is not even an integer stops at that, as it does in Laravel.

DRIVER_MOBILE = re.compile(r"^\+[1-9][0-9 ]{6,17}$")

# PHP's date_format:H:i, which re-formats what it parsed and compares: "7:05"
# formats back as "07:05" and fails, and "24:00" rolls over and fails too.
CLOCK_TIME = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


class PartialForm(serializers.Serializer):
    """A PATCH form: Laravel's `sometimes|required` - absent is fine, present
    and empty is "required"."""

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

        for field in self.fields.values():
            field.required = False


def taken(queryset, field_name: str):
    if queryset.exists():
        raise serializers.ValidationError(already_taken(field_name))


def clock_time(field_name: str):
    def check(value):
        if value is not None and not CLOCK_TIME.match(value):
            raise serializers.ValidationError(f"The {attribute(field_name)} field must match the format H:i.")

        return value

    return check


class StoreVehicleRequest(ScopedSerializer):
    name = LaravelCharField("name", max_length=50)
    registration_number = LaravelCharField("registration_number", max_length=30)
    capacity = LaravelIntegerField("capacity", min_value=1, max_value=200)

    def validate_registration_number(self, value):
        taken(Vehicle.objects.filter(school_id=self.resolved_school_id(), registration_number=value), "registration_number")

        return value

    def validate(self, attrs):
        self.validate_school_id_field()
        attrs["school_id"] = self.resolved_school_id()

        return attrs


class UpdateVehicleRequest(PartialForm):
    name = LaravelCharField("name", max_length=50)
    registration_number = LaravelCharField("registration_number", max_length=30)
    capacity = LaravelIntegerField("capacity", min_value=1, max_value=200)
    status = LaravelCharField("status", max_length=255)

    def __init__(self, *args, vehicle=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.vehicle = vehicle

    def validate_registration_number(self, value):
        taken(
            Vehicle.objects.filter(school_id=self.vehicle.school_id, registration_number=value).exclude(pk=self.vehicle.pk),
            "registration_number",
        )

        return value

    validate_status = staticmethod(enum_choice("status", TransportStatus.values))


class DriverFields(serializers.Serializer):
    name = LaravelCharField("name", max_length=150)
    mobile = LaravelCharField("mobile", max_length=20, required=False, allow_null=True)
    licence_number = LaravelCharField("licence_number", max_length=50)
    licence_expiry = LaravelDateField("licence_expiry", required=False, allow_null=True)

    def validate_mobile(self, value):
        if value is not None and not DRIVER_MOBILE.match(value):
            raise serializers.ValidationError(bad_format("mobile"))

        return value


class StoreDriverRequest(DriverFields, ScopedSerializer):
    def validate_licence_number(self, value):
        taken(Driver.objects.filter(school_id=self.resolved_school_id(), licence_number=value), "licence_number")

        return value

    def validate(self, attrs):
        self.validate_school_id_field()
        attrs["school_id"] = self.resolved_school_id()

        return attrs


class UpdateDriverRequest(DriverFields, PartialForm):
    status = LaravelCharField("status", max_length=255)

    def __init__(self, *args, driver=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.driver = driver

    def validate_licence_number(self, value):
        taken(
            Driver.objects.filter(school_id=self.driver.school_id, licence_number=value).exclude(pk=self.driver.pk),
            "licence_number",
        )

        return value

    validate_status = staticmethod(enum_choice("status", TransportStatus.values))


class RouteFields(serializers.Serializer):
    """A route's vehicle and driver: an active one of this school, not already
    on another route. Both failures are reported when both are true."""

    name = LaravelCharField("name", max_length=100)
    vehicle_id = LaravelIntegerField("vehicle_id", required=False, allow_null=True)
    driver_id = LaravelIntegerField("driver_id", required=False, allow_null=True)
    # The Bus Attendant who runs the route's trips. One may cover several
    # routes, so unlike a vehicle or driver it is not exclusive.
    attendant_user_id = LaravelIntegerField("attendant_user_id", required=False, allow_null=True)

    def route_school(self):
        raise NotImplementedError

    def validate_attendant_user_id(self, value):
        if value is None:
            return None

        usable = User.objects.filter(
            pk=value, school_id=self.route_school(), role=UserRole.BUS_ATTENDANT, status=UserStatus.ACTIVE
        )

        if not usable.exists():
            raise serializers.ValidationError("The selected attendant is not an active Bus Attendant of this school.")

        return value

    def current(self, field: str):
        return None

    def ignoring(self):
        return None

    def assignable(self, model, value, field, noun, verb):
        problems = []
        usable = model.objects.filter(pk=value, school_id=self.route_school())
        keep = self.current(field)
        usable = usable.filter(Q(status=TransportStatus.ACTIVE) | Q(pk=keep)) if keep else usable.filter(status=TransportStatus.ACTIVE)

        if not usable.exists():
            problems.append(f"The selected {noun} is not an active {noun} of this school.")

        others = TransportRoute.objects.filter(**{field: value})
        if self.ignoring() is not None:
            others = others.exclude(pk=self.ignoring())

        if others.exists():
            problems.append(f"That {noun} is already {verb} another route.")

        if problems:
            raise serializers.ValidationError(problems)

        return value

    def validate_vehicle_id(self, value):
        return None if value is None else self.assignable(Vehicle, value, "vehicle_id", "vehicle", "serving")

    def validate_driver_id(self, value):
        return None if value is None else self.assignable(Driver, value, "driver_id", "driver", "assigned to")


class StoreTransportRouteRequest(RouteFields, ScopedSerializer):
    def route_school(self):
        return self.resolved_school_id()

    def validate_name(self, value):
        taken(TransportRoute.objects.filter(school_id=self.resolved_school_id(), name=value), "name")

        return value

    def validate(self, attrs):
        self.validate_school_id_field()
        attrs["school_id"] = self.resolved_school_id()

        return attrs


class UpdateTransportRouteRequest(RouteFields, PartialForm):
    status = LaravelCharField("status", max_length=255)

    def __init__(self, *args, route=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.route = route

    def route_school(self):
        return self.route.school_id

    def current(self, field: str):
        # Keeping what the route already has stays valid even if it has since
        # been deactivated; "active" only applies to a new choice.
        return getattr(self.route, field)

    def ignoring(self):
        return self.route.pk

    def validate_name(self, value):
        taken(TransportRoute.objects.filter(school_id=self.route.school_id, name=value).exclude(pk=self.route.pk), "name")

        return value

    validate_status = staticmethod(enum_choice("status", TransportStatus.values))


# A stop further than this from its school is almost always a latitude and
# longitude typed the wrong way round.
MAX_STOP_DISTANCE_KM = 100


class StopFields(serializers.Serializer):
    name = LaravelCharField("name", max_length=100)
    sequence_number = LaravelIntegerField("sequence_number", min_value=1, max_value=200)
    pickup_time = LaravelCharField("pickup_time", max_length=255, required=False, allow_null=True)
    drop_time = LaravelCharField("drop_time", max_length=255, required=False, allow_null=True)
    latitude = CoordinateField("latitude", -90, 90)
    longitude = CoordinateField("longitude", -180, 180)

    validate_pickup_time = staticmethod(clock_time("pickup_time"))
    validate_drop_time = staticmethod(clock_time("drop_time"))

    def siblings(self):
        raise NotImplementedError

    def stop_school(self):
        raise NotImplementedError

    def validate(self, attrs):
        """A position is a pair, and near its school."""
        errors = {}
        sent = [field for field in ("latitude", "longitude") if field in attrs]

        if len(sent) == 1:
            other = "longitude" if sent[0] == "latitude" else "latitude"
            errors[other] = [f"Enter a {other} as well, or clear the {sent[0]}."]
        elif len(sent) == 2 and (attrs["latitude"] is None) != (attrs["longitude"] is None):
            missing = "latitude" if attrs["latitude"] is None else "longitude"
            present = "longitude" if missing == "latitude" else "latitude"
            errors[missing] = [f"Enter a {missing} as well, or clear the {present}."]
        elif len(sent) == 2 and attrs["latitude"] is not None:
            school = School.objects.filter(pk=self.stop_school()).values("latitude", "longitude").first()

            if school and school["latitude"] is not None and school["longitude"] is not None:
                from .geo import distance_m

                away = distance_m(attrs["latitude"], attrs["longitude"], school["latitude"], school["longitude"]) / 1000

                if away > MAX_STOP_DISTANCE_KM:
                    errors["latitude"] = [
                        f"This stop is {away:,.0f} km from the school. Check the latitude and longitude "
                        "are not the wrong way round."
                    ]

        if errors:
            raise serializers.ValidationError(errors)

        return attrs

    def validate_name(self, value):
        taken(self.siblings().filter(name=value), "name")

        return value

    def validate_sequence_number(self, value):
        taken(self.siblings().filter(sequence_number=value), "sequence_number")

        return value


class StoreTransportStopRequest(StopFields):
    def __init__(self, *args, route=None, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        self.route = route

    def siblings(self):
        return TransportStop.objects.filter(route_id=self.route.pk)

    def stop_school(self):
        return self.route.school_id


class UpdateTransportStopRequest(StopFields, PartialForm):
    def __init__(self, *args, stop=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.stop = stop

    def siblings(self):
        return TransportStop.objects.filter(route_id=self.stop.route_id).exclude(pk=self.stop.pk)

    def stop_school(self):
        return self.stop.school_id


class AssignStudentTransportRequest(serializers.Serializer):
    route_id = LaravelIntegerField("route_id")
    transport_stop_id = LaravelIntegerField("transport_stop_id")

    def __init__(self, *args, student=None, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        self.student = student

    def validate_route_id(self, value):
        if not TransportRoute.objects.filter(pk=value, school_id=self.student.school_id).exists():
            raise serializers.ValidationError("The selected route does not belong to this school.")

        return value

    def validate_transport_stop_id(self, value):
        # Against the route as sent, whatever became of it - as Laravel reads it.
        if not TransportStop.objects.filter(pk=value, route_id=as_id(self.initial_data.get("route_id"))).exists():
            raise serializers.ValidationError("The selected stop is not on the selected route.")

        return value


# -- transport trips --------------------------------------------------------


class StartTripRequest(ScopedSerializer):
    route_id = LaravelIntegerField("route_id")
    direction = LaravelCharField("direction", max_length=255)

    def validate_route_id(self, value):
        if not self.scope.apply_to(TransportRoute.objects.filter(pk=value)).exists():
            raise serializers.ValidationError("The selected route does not belong to this school.")

        return value

    validate_direction = staticmethod(enum_choice("direction", TripDirection.values))


class UpdateTripRiderRequest(serializers.Serializer):
    # "pending" is the starting state, never something a person sets.
    status = LaravelCharField("status", max_length=255)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    validate_status = staticmethod(enum_choice(
        "status", (TripRiderStatus.BOARDED, TripRiderStatus.DROPPED, TripRiderStatus.ABSENT)
    ))


# -- early access and password resets --------------------------------------

INTERNATIONAL_PHONE = re.compile(r"^\+[1-9][0-9 ]{6,17}$")


class StoreEarlyAccessRequest(serializers.Serializer):
    school_name = LaravelCharField("school_name", max_length=150)
    contact_name = LaravelCharField("contact_name", max_length=150)
    contact_role = optional_text("contact_role", 100)
    email = EmailField("email", max_length=255)
    phone = LaravelCharField("phone", max_length=20)
    city = LaravelCharField("city", max_length=100)
    country = LaravelCharField("country", max_length=100)
    # Roughly how big they are - the most useful thing for deciding who to
    # call first. Optional: plenty of people do not know.
    expected_students = LaravelIntegerField("expected_students", required=False, allow_null=True, min_value=1)
    current_software = optional_text("current_software", 150)
    message = optional_text("message", 2000)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def validate_phone(self, value):
        if not INTERNATIONAL_PHONE.match(value):
            raise serializers.ValidationError("Include the country code, like +91 9876543210.")

        return value

    def validate_expected_students(self, value):
        if value is not None and value > 200000:
            raise serializers.ValidationError(
                "That is more students than any school we know of - please get in touch directly."
            )

        return value


class ReviewEarlyAccessRequest(PartialForm):
    status = LaravelCharField("status", max_length=255)
    notes = LaravelCharField("notes", max_length=2000, allow_null=True)

    def validate_status(self, value):
        if value not in EarlyAccessStatus.settable():
            raise serializers.ValidationError(
                "A request becomes Converted by onboarding the school, not by saying so."
            )

        return value


class ForgotPasswordRequest(serializers.Serializer):
    email = EmailField("email", lowercase=True, max_length=255)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)


class ResetPasswordRequest(serializers.Serializer):
    token = LaravelCharField("token", max_length=None)
    email = EmailField("email", lowercase=True, max_length=None)
    password = LaravelCharField("password", max_length=None, trim_whitespace=False)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def validate_password(self, value):
        if len(value) < 8:
            raise serializers.ValidationError("The password field must be at least 8 characters.")

        password_rules(value)

        return value


# -- leave ------------------------------------------------------------------


class ApplyStaffLeaveRequest(ScopedSerializer):
    """A staff member's own leave request.

    No `school_id` and no `staff_profile_id`: both are read off the actor's
    employment record by the view. The same rule as school context - who this
    leave belongs to is derived from who is asking, never sent.
    """

    leave_type = LaravelCharField("leave_type", max_length=255)
    start_date = LaravelDateField("start_date")
    end_date = LaravelDateField("end_date")
    reason = LaravelCharField("reason", max_length=500)

    def validate(self, attrs):
        errors = {}

        if attrs["leave_type"] not in LeaveType.values:
            errors["leave_type"] = [selected_is_invalid("leave_type")]

        # after_or_equal, not after: a one-day leave starts and ends on the
        # same date.
        if attrs["end_date"] < attrs["start_date"]:
            errors["end_date"] = [
                "The end date field must be a date after or equal to start date."
            ]

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


class ReviewStaffLeaveRequest(ScopedSerializer):
    """Approving or rejecting. The decision itself is the route, so the only
    thing the body carries is why."""

    remarks = optional_text("remarks", 500)


# -- teachers and staff -----------------------------------------------------

# What "add an employee" may create. Never an admin account, whoever is doing
# the adding - that is the Users screen's job, and it derives the admin tier
# from the actor rather than from a field.
STAFF_ROLES = (
    UserRole.HOD, UserRole.TEACHER, UserRole.STAFF, UserRole.TRANSPORT_MANAGER, UserRole.ACCOUNTANT,
    UserRole.BUS_ATTENDANT,
)


class StoreStaffRequest(ScopedSerializer):
    """One form, two records: the login and the employment profile.

    The prototype's Add Employee screen is a single form, and the two are
    created in one transaction - a login with no employment record is
    invisible to Attendance and Leave, and a profile with no login is somebody
    on a roster who cannot sign in.
    """

    first_name = LaravelCharField("first_name", max_length=100)
    last_name = LaravelCharField("last_name", max_length=100)
    # Optional for a Bus Attendant only (see validate()); required otherwise.
    email = LaravelCharField("email", max_length=255, required=False, allow_null=True, allow_blank=True)
    mobile = MobileField("mobile")
    # A Bus Attendant has no password: they sign in with a passcode on a
    # registered phone. Required for everybody else.
    password = PasswordField("password", required=False, allow_null=True)
    role = LaravelCharField("role")
    employee_id = LaravelCharField("employee_id", max_length=30)
    department_id = LaravelIntegerField("department_id", required=False, allow_null=True)
    designation = optional_text("designation", 100)
    joining_date = LaravelDateField("joining_date")
    address = optional_text("address", 500)

    def validate_email(self, value):
        if value in (None, ""):
            return None

        value = value.strip().lower()

        if not EMAIL_PATTERN.match(value):
            raise serializers.ValidationError(not_an_email("email"))

        return value

    def validate(self, attrs):
        errors = {}

        try:
            self.validate_school_id_field()
        except serializers.ValidationError as invalid:
            errors.update(invalid.detail)

        school_id = self.resolved_school_id()
        is_attendant = attrs.get("role") == UserRole.BUS_ATTENDANT

        if attrs.get("role") not in STAFF_ROLES:
            errors["role"] = [selected_is_invalid("role")]

        if is_attendant:
            # The mobile number is how they sign in, so it is required and
            # must not already sign somebody else in.
            if not attrs.get("mobile"):
                errors["mobile"] = ["A Bus Attendant signs in with their mobile number, so it is required."]
            elif AttendantCredential.objects.filter(login_mobile=attendants.login_mobile(attrs["mobile"])).exists():
                errors["mobile"] = ["Another Bus Attendant already signs in with this mobile number."]

            attrs.pop("password", None)

            if not attrs.get("email"):
                attrs["email"] = attendants.placeholder_email()
        else:
            if not attrs.get("email"):
                errors["email"] = [required("email")]

            if not attrs.get("password"):
                errors["password"] = [required("password")]

        if attrs.get("email") and User.objects.filter(email=attrs["email"]).exists():
            errors["email"] = [already_taken("email")]

        if StaffProfile.objects.filter(
            school_id=school_id, employee_id=attrs["employee_id"]
        ).exists():
            errors["employee_id"] = [already_taken("employee_id")]

        department_id = attrs.get("department_id")

        if department_id is not None and not Department.objects.filter(
            pk=department_id, school_id=school_id
        ).exists():
            errors["department_id"] = [does_not_exist("department_id")]

        if errors:
            raise serializers.ValidationError(errors)

        attrs["school_id"] = school_id

        return attrs

    def user_data(self) -> dict:
        """The half that becomes the login.

        `school_id` is included and is the *resolved* one, not whatever the
        request sent. Without it a Super Admin - who belongs to no school, so
        has nothing to fall back on - would create an employee attached to no
        school at all.
        """
        return {
            field: self.validated_data[field]
            for field in (
                "first_name",
                "last_name",
                "email",
                "mobile",
                "password",
                "role",
                "school_id",
            )
            if field in self.validated_data
        }

    def profile_data(self) -> dict:
        """The half that becomes the employment record."""
        return {
            field: self.validated_data.get(field)
            for field in ("employee_id", "department_id", "designation", "joining_date", "address")
        }


class UpdateStaffProfileRequest(ScopedSerializer):
    """The employment record only.

    The login behind it - name, email, role - is edited through the Users
    endpoints, so that the admin hierarchy is enforced in one place rather
    than two.
    """

    employee_id = LaravelCharField("employee_id", max_length=30, required=False)
    department_id = LaravelIntegerField("department_id", required=False, allow_null=True)
    designation = optional_text("designation", 100)
    joining_date = LaravelDateField("joining_date", required=False)
    address = optional_text("address", 500)

    def __init__(self, *args, profile=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.profile = profile

    def validate(self, attrs):
        school_id = self.profile.school_id
        errors = {}

        if "employee_id" in attrs and StaffProfile.objects.filter(
            school_id=school_id, employee_id=attrs["employee_id"]
        ).exclude(pk=self.profile.pk).exists():
            errors["employee_id"] = [already_taken("employee_id")]

        department_id = attrs.get("department_id")

        if department_id is not None and not Department.objects.filter(
            pk=department_id, school_id=school_id
        ).exists():
            errors["department_id"] = [does_not_exist("department_id")]

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


# -- payments ---------------------------------------------------------------


class MoneyField(serializers.Field):
    """A `decimal(12,2)` figure, kept as a Decimal all the way to the column.

    Two places a float would be wrong in this product are money and
    coordinates, and this is the one somebody eventually reconciles by hand.
    """

    def __init__(self, field_name: str, minimum="0", **kwargs) -> None:
        super().__init__(**kwargs)
        self._field_name = field_name
        self._minimum = decimal.Decimal(minimum)

    def to_internal_value(self, data):
        if data is None or data == "":
            return None

        try:
            value = decimal.Decimal(str(data))
        except (decimal.InvalidOperation, TypeError, ValueError):
            raise serializers.ValidationError(must_be_a_number(self._field_name))

        if not value.is_finite():
            raise serializers.ValidationError(must_be_a_number(self._field_name))

        # Two decimal places, no more. A third would be silently rounded by
        # the column, which is how a ledger stops adding up.
        if value.as_tuple().exponent < -2:
            raise serializers.ValidationError(bad_format(self._field_name))

        if value < self._minimum:
            raise serializers.ValidationError(at_least(self._field_name, self._minimum))

        return value.quantize(decimal.Decimal("0.01"))

    def to_representation(self, value):
        return None if value is None else str(value)


class PaymentForm(serializers.Serializer):
    payment_type = LaravelCharField("payment_type", max_length=50)
    amount = MoneyField("amount", minimum="0.01")
    payment_date = LaravelDateField("payment_date")
    payment_mode = LaravelCharField("payment_mode", max_length=50)
    reference_number = optional_text("reference_number", 100)
    notes = optional_text("notes", 1000)
    # How much has actually arrived. The status is derived from it, so the two
    # can never contradict each other; `status` is still accepted because
    # Cancelled is a decision rather than a consequence of the figures.
    paid_amount = MoneyField("paid_amount", required=False, allow_null=True)
    status = LaravelCharField("status", max_length=20)

    def __init__(self, *args, payment=None, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        self.payment = payment

    def check(self, attrs) -> dict:
        errors = {}

        for field, choices in (
            ("payment_type", PaymentType),
            ("payment_mode", PaymentMode),
            ("status", PaymentStatus),
        ):
            if field in attrs and attrs[field] not in choices.values:
                errors[field] = [selected_is_invalid(field)]

        total = attrs.get("amount")

        if total is None and self.payment is not None:
            total = self.payment.amount

        paid = attrs.get("paid_amount")

        if paid is not None and total is not None and paid > total:
            errors["paid_amount"] = [
                "The amount received cannot be more than the payment amount."
            ]

        return errors


class StorePaymentRequest(PaymentForm):
    school_id = LaravelIntegerField("school_id")

    def validate(self, attrs):
        errors = self.check(attrs)

        # A Super Admin belongs to no school, so there is no scope to fall
        # back on: the payment has to name the school it is against, and it
        # has to be a real one.
        if not School.objects.filter(pk=attrs["school_id"]).exists():
            errors["school_id"] = [does_not_exist("school_id")]

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


class UpdatePaymentRequest(PaymentForm):
    """`school_id` and `currency_code` are fixed at creation.

    The currency especially: it is copied from the school at the moment of
    payment and stays with the record, so a historical payment stays correct
    even if the school's currency is later changed (CLAUDE.md rule 5).
    """

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)

        for field in self.fields.values():
            field.required = False

    def validate(self, attrs):
        errors = self.check(attrs)

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


# -- periods and holidays ---------------------------------------------------


class PeriodForm(ScopedSerializer):
    period_number = LaravelIntegerField("period_number", min_value=1, max_value=20)
    # "H:i" and nothing else. A period is a clock time in the school's own day,
    # not an instant, so it carries no date and no zone.
    start_time = serializers.TimeField(
        format="%H:%M",
        input_formats=["%H:%M"],
        error_messages={"invalid": "The start time field must match the format H:i."},
    )
    end_time = serializers.TimeField(
        format="%H:%M",
        input_formats=["%H:%M"],
        error_messages={"invalid": "The end time field must match the format H:i."},
    )

    def check(self, attrs, school_id, ignoring=None) -> dict:
        errors = {}

        if "period_number" in attrs:
            taken = Period.objects.filter(
                school_id=school_id, period_number=attrs["period_number"]
            )

            if ignoring is not None:
                taken = taken.exclude(pk=ignoring)

            if taken.exists():
                errors["period_number"] = [already_taken("period_number")]

        start = attrs.get("start_time")
        end = attrs.get("end_time")

        if start is not None and end is not None and end <= start:
            errors["end_time"] = [must_be_after("end_time", "start_time")]

        return errors


class StorePeriodRequest(PeriodForm):
    def validate(self, attrs):
        self.validate_school_id_field()

        school_id = self.resolved_school_id()
        errors = self.check(attrs, school_id)

        if errors:
            raise serializers.ValidationError(errors)

        attrs["school_id"] = school_id

        return attrs


class UpdatePeriodRequest(PeriodForm):
    def __init__(self, *args, period=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.period = period

        for field in self.fields.values():
            field.required = False

    def validate(self, attrs):
        # Whichever end was not sent comes from the stored row, so moving one
        # of them cannot invert the period.
        attrs.setdefault("start_time", self.period.start_time)
        attrs.setdefault("end_time", self.period.end_time)

        errors = self.check(attrs, self.period.school_id, ignoring=self.period.pk)

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


class HolidayForm(ScopedSerializer):
    name = LaravelCharField("name", max_length=100)
    type = LaravelCharField("type", max_length=20)
    start_date = LaravelDateField("start_date")
    end_date = LaravelDateField("end_date")

    def check(self, attrs) -> dict:
        errors = {}

        if "type" in attrs and attrs["type"] not in HolidayType.values:
            errors["type"] = [selected_is_invalid("type")]

        start = attrs.get("start_date")
        end = attrs.get("end_date")

        # after_or_equal, not after: a one-day holiday starts and ends on the
        # same date.
        if start is not None and end is not None and end < start:
            errors["end_date"] = [
                "The end date field must be a date after or equal to start date."
            ]

        return errors


class StoreHolidayRequest(HolidayForm):
    def validate(self, attrs):
        self.validate_school_id_field()

        errors = self.check(attrs)

        if errors:
            raise serializers.ValidationError(errors)

        attrs["school_id"] = self.resolved_school_id()

        return attrs


class UpdateHolidayRequest(HolidayForm):
    def __init__(self, *args, holiday=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.holiday = holiday

        for field in self.fields.values():
            field.required = False

    def validate(self, attrs):
        attrs.setdefault("start_date", self.holiday.start_date)
        attrs.setdefault("end_date", self.holiday.end_date)

        errors = self.check(attrs)

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


# -- classes and sections ---------------------------------------------------


class StoreSchoolClassRequest(ScopedSerializer):
    academic_year_id = LaravelIntegerField("academic_year_id")
    name = LaravelCharField("name", max_length=50)
    level = LaravelIntegerField("level", min_value=0, max_value=12)

    def validate(self, attrs):
        self.validate_school_id_field()

        school_id = self.resolved_school_id()
        errors = {}

        if not AcademicYear.objects.filter(
            pk=attrs["academic_year_id"], school_id=school_id
        ).exists():
            errors["academic_year_id"] = [does_not_exist("academic_year_id")]

        # Unique within the year, not the school: "Grade 8" exists again next
        # year and is a different class.
        if SchoolClass.objects.filter(
            academic_year_id=attrs["academic_year_id"], name=attrs["name"]
        ).exists():
            errors["name"] = [already_taken("name")]

        if errors:
            raise serializers.ValidationError(errors)

        attrs["school_id"] = school_id

        return attrs


class UpdateSchoolClassRequest(ScopedSerializer):
    """The year a class belongs to is fixed at creation - moving a class
    between years would take its sections and students with it."""

    name = LaravelCharField("name", max_length=50, required=False)
    level = LaravelIntegerField("level", min_value=0, max_value=12, required=False)

    def __init__(self, *args, school_class=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.school_class = school_class

    def validate(self, attrs):
        if "name" in attrs and SchoolClass.objects.filter(
            academic_year_id=self.school_class.academic_year_id, name=attrs["name"]
        ).exclude(pk=self.school_class.pk).exists():
            raise serializers.ValidationError({"name": [already_taken("name")]})

        return attrs


class ClassSectionForm(serializers.Serializer):
    name = LaravelCharField("name", max_length=10)
    room_number = optional_text("room_number", 20)
    class_teacher_id = LaravelIntegerField("class_teacher_id", required=False, allow_null=True)

    def __init__(self, *args, school_class=None, section=None, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        self.school_class = school_class
        self.section = section

    def validate(self, attrs):
        school_class = self.school_class or self.section.school_class
        errors = {}

        if "name" in attrs:
            taken = ClassSection.objects.filter(school_class_id=school_class.id, name=attrs["name"])

            if self.section is not None:
                taken = taken.exclude(pk=self.section.pk)

            if taken.exists():
                errors["name"] = [already_taken("name")]

        class_teacher_id = attrs.get("class_teacher_id")

        if class_teacher_id is not None and not teaches_at(class_teacher_id, school_class.school_id):
            errors["class_teacher_id"] = [does_not_exist("class_teacher_id")]

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


class StoreClassSectionRequest(ClassSectionForm):
    pass


class UpdateClassSectionRequest(ClassSectionForm):
    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)

        for field in self.fields.values():
            field.required = False


# -- departments and subjects -----------------------------------------------

# Who may head a department or lead a subject. Not an admin: leading a subject
# is a teaching role, and an admin who also teaches has a TEACHER or HOD
# account for that.
TEACHING_ROLES = (UserRole.HOD, UserRole.TEACHER)


def teaches_at(user_id, school_id) -> bool:
    return User.objects.filter(
        pk=user_id, school_id=school_id, role__in=TEACHING_ROLES
    ).exists()


class StoreDepartmentRequest(ScopedSerializer):
    name = LaravelCharField("name", max_length=100)
    hod_user_id = LaravelIntegerField("hod_user_id", required=False, allow_null=True)

    def validate(self, attrs):
        self.validate_school_id_field()

        school_id = self.resolved_school_id()
        errors = {}

        # Unique per school, not globally: two schools may each have a
        # Science department and neither is wrong.
        if Department.objects.filter(school_id=school_id, name=attrs["name"]).exists():
            errors["name"] = [already_taken("name")]

        hod_user_id = attrs.get("hod_user_id")

        if hod_user_id is not None and not teaches_at(hod_user_id, school_id):
            errors["hod_user_id"] = [does_not_exist("hod_user_id")]

        if errors:
            raise serializers.ValidationError(errors)

        attrs["school_id"] = school_id

        return attrs


class UpdateDepartmentRequest(ScopedSerializer):
    name = LaravelCharField("name", max_length=100, required=False)
    hod_user_id = LaravelIntegerField("hod_user_id", required=False, allow_null=True)

    def __init__(self, *args, department=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.department = department

    def validate(self, attrs):
        school_id = self.department.school_id
        errors = {}

        if "name" in attrs and Department.objects.filter(
            school_id=school_id, name=attrs["name"]
        ).exclude(pk=self.department.pk).exists():
            errors["name"] = [already_taken("name")]

        hod_user_id = attrs.get("hod_user_id")

        if hod_user_id is not None and not teaches_at(hod_user_id, school_id):
            errors["hod_user_id"] = [does_not_exist("hod_user_id")]

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


class SubjectForm(ScopedSerializer):
    """The fields a subject is described by, shared by create and edit."""

    department_id = LaravelIntegerField("department_id")
    code = LaravelCharField("code", max_length=20)
    name = LaravelCharField("name", max_length=100)
    # A class level, 0 to 12 - 0 being a nursery or reception year. The pair
    # says which classes may be taught this subject at all.
    min_class_level = LaravelIntegerField("min_class_level", min_value=0, max_value=12)
    max_class_level = LaravelIntegerField("max_class_level", min_value=0, max_value=12)
    lead_teacher_id = LaravelIntegerField("lead_teacher_id", required=False, allow_null=True)

    def check(self, attrs, school_id, ignoring=None) -> dict:
        errors = {}

        if "department_id" in attrs and not Department.objects.filter(
            pk=attrs["department_id"], school_id=school_id
        ).exists():
            errors["department_id"] = [does_not_exist("department_id")]

        if "code" in attrs:
            taken = Subject.objects.filter(school_id=school_id, code=attrs["code"])

            if ignoring is not None:
                taken = taken.exclude(pk=ignoring)

            if taken.exists():
                errors["code"] = [already_taken("code")]

        lead_teacher_id = attrs.get("lead_teacher_id")

        if lead_teacher_id is not None and not teaches_at(lead_teacher_id, school_id):
            errors["lead_teacher_id"] = [does_not_exist("lead_teacher_id")]

        # Only when both are present and both are good - a range check on a
        # missing bound would be a second error about the same mistake.
        low = attrs.get("min_class_level")
        high = attrs.get("max_class_level")

        if low is not None and high is not None and high < low:
            errors["max_class_level"] = [
                "The max class level must be at or above the min class level."
            ]

        return errors


class StoreSubjectRequest(SubjectForm):
    def validate(self, attrs):
        self.validate_school_id_field()

        school_id = self.resolved_school_id()
        errors = self.check(attrs, school_id)

        if errors:
            raise serializers.ValidationError(errors)

        attrs["school_id"] = school_id

        return attrs


class UpdateSubjectRequest(SubjectForm):
    def __init__(self, *args, subject=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.subject = subject

        for field in self.fields.values():
            field.required = False

    def validate(self, attrs):
        school_id = self.subject.school_id

        # Whichever bound was not sent is taken from the stored row, so
        # raising just the minimum above the stored maximum is still caught.
        attrs.setdefault("min_class_level", self.subject.min_class_level)
        attrs.setdefault("max_class_level", self.subject.max_class_level)

        errors = self.check(attrs, school_id, ignoring=self.subject.pk)

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


# -- academic years ---------------------------------------------------------


class StoreAcademicYearRequest(ScopedSerializer):
    name = LaravelCharField("name", max_length=50)
    start_date = LaravelDateField("start_date")
    end_date = LaravelDateField("end_date")
    is_current = LaravelBooleanField("is_current", required=False, default=False)

    def validate(self, attrs):
        self.validate_school_id_field()

        if attrs["end_date"] <= attrs["start_date"]:
            raise serializers.ValidationError(
                {"end_date": [must_be_after("end_date", "start_date")]}
            )

        attrs["school_id"] = self.resolved_school_id()

        return attrs


class UpdateAcademicYearRequest(ScopedSerializer):
    """`school_id` is fixed at creation, and `is_current` is only ever changed
    through the dedicated set-current action - a year becoming current makes
    another one stop being current, which is not something a field edit should
    do quietly."""

    name = LaravelCharField("name", max_length=50, required=False)
    start_date = LaravelDateField("start_date", required=False)
    end_date = LaravelDateField("end_date", required=False)

    def __init__(self, *args, year=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.year = year

    def validate(self, attrs):
        # Compared against what is stored for whichever end was not sent, so
        # moving one date cannot silently invert the year.
        start = attrs.get("start_date", self.year.start_date)
        end = attrs.get("end_date", self.year.end_date)

        if end <= start:
            raise serializers.ValidationError(
                {"end_date": ["The end date must be after the start date."]}
            )

        return attrs


# -- academic terms ---------------------------------------------------------


class TermFields(ScopedSerializer):
    """What both term forms check, which is almost everything.

    A term is only meaningful against its year and its siblings: it has to sit
    inside the year, and it must not overlap another term of the same year. So
    the checks need the year loaded and the siblings read, and both forms want
    exactly the same ones.
    """

    name = LaravelCharField("name", max_length=50)
    sequence_number = LaravelIntegerField("sequence_number", min_value=1, max_value=20)
    start_date = LaravelDateField("start_date")
    end_date = LaravelDateField("end_date")

    def __init__(self, *args, term=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.term = term

    def check_dates(self, year, start, end, errors: dict) -> None:
        if end <= start:
            errors["end_date"] = [must_be_after("end_date", "start_date")]

        # Checked even when the two dates are already the wrong way round: a
        # form tells somebody everything that is wrong with it at once.
        span = f"{year.name}, which runs from {year.start_date} to {year.end_date}"

        if start < year.start_date or start > year.end_date:
            errors["start_date"] = [f"The term must start inside {span}."]

        if end < year.start_date or end > year.end_date:
            errors["end_date"] = [f"The term must end inside {span}."]

    def check_siblings(self, year, start, end, name, sequence, errors: dict) -> None:
        siblings = AcademicTerm.objects.filter(academic_year_id=year.id)

        if self.term is not None:
            siblings = siblings.exclude(pk=self.term.id)

        # Checked here rather than left to the unique index, so the answer is
        # a 422 naming the field instead of a 500 out of the database.
        if siblings.filter(name=name).exists():
            errors["name"] = [already_taken("name")]

        if siblings.filter(sequence_number=sequence).exists():
            errors["sequence_number"] = [already_taken("sequence_number")]

        if "start_date" in errors or "end_date" in errors:
            return

        # Two terms may touch - one ending on the 31st and the next starting
        # on the 1st - but they may not cover the same day, or a mark on that
        # day would belong to both.
        clash = siblings.filter(start_date__lte=end, end_date__gte=start).first()

        if clash is not None:
            errors["start_date"] = [
                f"These dates overlap {clash.name} ({clash.start_date} to {clash.end_date})."
            ]


class StoreAcademicTermRequest(TermFields):
    academic_year_id = LaravelIntegerField("academic_year_id")

    def validate_academic_year_id(self, value: int) -> int:
        # The year decides the school, so a year outside the actor's scope is
        # simply not a year they can name (CLAUDE.md rule 10).
        if not self.scope.apply_to(AcademicYear.objects.filter(pk=value)).exists():
            raise serializers.ValidationError(does_not_exist("academic_year_id"))

        return value

    def validate(self, attrs):
        year = AcademicYear.objects.get(pk=attrs["academic_year_id"])
        errors: dict[str, list[str]] = {}

        self.check_dates(year, attrs["start_date"], attrs["end_date"], errors)
        self.check_siblings(
            year, attrs["start_date"], attrs["end_date"], attrs["name"], attrs["sequence_number"], errors
        )

        if errors:
            raise serializers.ValidationError(errors)

        # Never from the request: the year the term hangs off says which
        # school it belongs to.
        attrs["school_id"] = year.school_id

        return attrs


class UpdateAcademicTermRequest(TermFields):
    """The year is fixed at creation. Moving a term to another year would move
    every result filed under it, which is not an edit of a name and a date."""

    name = LaravelCharField("name", max_length=50, required=False)
    sequence_number = LaravelIntegerField("sequence_number", min_value=1, max_value=20, required=False)
    start_date = LaravelDateField("start_date", required=False)
    end_date = LaravelDateField("end_date", required=False)

    def validate(self, attrs):
        term = self.term
        year = term.academic_year
        errors: dict[str, list[str]] = {}

        # Whatever was not sent keeps what is stored, so moving one end cannot
        # silently invert the term or walk it out of its year.
        start = attrs.get("start_date", term.start_date)
        end = attrs.get("end_date", term.end_date)
        name = attrs.get("name", term.name)
        sequence = attrs.get("sequence_number", term.sequence_number)

        self.check_dates(year, start, end, errors)
        self.check_siblings(year, start, end, name, sequence, errors)

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


# -- grade scales -----------------------------------------------------------

MAX_BANDS = 20


class GradeScaleRequest(ScopedSerializer):
    """A scale and its bands, sent and replaced as one set.

    The bands only make sense together - "is there a gap" is a question about
    the whole set - so they arrive inline and are checked here rather than
    one PATCH at a time. Errors are keyed the way the screen needs them:
    `bands.2.min_percentage`.

    The rules:

    - the lowest band starts at 0 and the highest ends at 100, so every
      percentage a mark can produce has a grade;
    - bands may not overlap, because a percentage with two grades is not a
      grade;
    - a percentage falls in **the highest band whose minimum it reaches**.
      That is what lets a school write its bands the way it says them out
      loud - 91 to 100, 81 to 90 - without 90.5 falling down a crack.
    """

    name = LaravelCharField("name", max_length=50)
    is_default = LaravelBooleanField("is_default", required=False, default=False)

    def __init__(self, *args, scale=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.scale = scale

    def to_internal_value(self, data):
        errors: dict[str, list[str]] = {}

        try:
            attrs = super().to_internal_value(data)
        except serializers.ValidationError as failure:
            errors.update({key: list(value) for key, value in failure.detail.items()})
            attrs = {}

        attrs["bands"] = self.read_bands(errors)

        if errors:
            raise serializers.ValidationError(errors)

        return attrs

    def read_bands(self, errors: dict) -> list[dict]:
        raw = self.initial_data.get("bands")

        if raw is None:
            raw = []

        if not isinstance(raw, list):
            raise serializers.ValidationError({"bands": ["The bands must be a list."]})

        if not raw:
            errors["bands"] = ["A scale needs at least one band."]
            return []

        if len(raw) > MAX_BANDS:
            errors["bands"] = [f"A scale can have at most {MAX_BANDS} bands."]
            return []

        bands, labels = [], set()

        for index, item in enumerate(raw):
            prefix = f"bands.{index}"
            item = item if isinstance(item, dict) else {}
            label = (item.get("label") or "").strip() if isinstance(item.get("label"), str) else ""

            if not label:
                errors[f"{prefix}.label"] = [required("label")]
            elif len(label) > 10:
                errors[f"{prefix}.label"] = [too_long("label", 10)]
            elif label.lower() in labels:
                errors[f"{prefix}.label"] = [f'"{label}" appears twice.']

            labels.add(label.lower())

            low = self.percentage(item.get("min_percentage"), f"{prefix}.min_percentage", errors)
            high = self.percentage(item.get("max_percentage"), f"{prefix}.max_percentage", errors)

            if low is not None and high is not None and high < low:
                errors[f"{prefix}.max_percentage"] = [
                    "The max percentage field must be greater than or equal to min percentage."
                ]

            bands.append({
                "label": label,
                "min_percentage": low,
                "max_percentage": high,
                "is_failing": bool(item.get("is_failing")),
            })

        if not errors:
            self.check_the_set(bands, errors)

        return bands

    @staticmethod
    def percentage(value, field: str, errors: dict):
        """0 to 100, to two decimals, as the column stores it."""
        if value is None or value == "":
            errors[field] = [required(field.rsplit(".", 1)[-1])]
            return None

        try:
            parsed = decimal.Decimal(str(value)).quantize(decimal.Decimal("0.01"))
        except (decimal.InvalidOperation, TypeError, ValueError):
            errors[field] = [must_be_a_number(field.rsplit(".", 1)[-1])]
            return None

        if parsed < 0 or parsed > 100:
            errors[field] = [must_be_between(field.rsplit(".", 1)[-1], 0, 100)]
            return None

        return parsed

    @staticmethod
    def check_the_set(bands: list[dict], errors: dict) -> None:
        """What one band cannot know: where it sits among the others."""
        order = sorted(range(len(bands)), key=lambda i: bands[i]["min_percentage"])

        lowest = bands[order[0]]
        if lowest["min_percentage"] != 0:
            errors[f"bands.{order[0]}.min_percentage"] = [
                "The lowest band must start at 0, so every mark has a grade."
            ]

        highest = bands[order[-1]]
        if highest["max_percentage"] != 100:
            errors[f"bands.{order[-1]}.max_percentage"] = [
                "The highest band must end at 100, so full marks have a grade."
            ]

        for position, index in enumerate(order[1:], start=1):
            below = bands[order[position - 1]]
            band = bands[index]

            if band["min_percentage"] <= below["max_percentage"]:
                errors[f"bands.{index}.min_percentage"] = [
                    f'This band overlaps "{below["label"]}", which runs to {below["max_percentage"]}.'
                ]


    def check_the_name(self, school_id, name: str, excluding: int | None = None) -> None:
        """Checked here rather than left to the unique index, so a school that
        names two scales alike is told which field is wrong instead of being
        handed a 500."""
        taken = GradeScale.objects.filter(school_id=school_id, name=name)

        if excluding is not None:
            taken = taken.exclude(pk=excluding)

        if taken.exists():
            raise serializers.ValidationError({"name": [already_taken("name")]})


class StoreGradeScaleRequest(GradeScaleRequest):
    def validate(self, attrs):
        self.validate_school_id_field()
        attrs["school_id"] = self.resolved_school_id()
        self.check_the_name(attrs["school_id"], attrs["name"])

        return attrs


class UpdateGradeScaleRequest(GradeScaleRequest):
    """The school is fixed at creation, like every other school-owned record."""

    def validate(self, attrs):
        self.check_the_name(self.scale.school_id, attrs["name"], excluding=self.scale.id)

        return attrs


# -- assessments ------------------------------------------------------------

# A test out of more than this is somebody's typo, not a school's marking
# scheme. Guarded because max_marks is the denominator of every percentage.
MAX_TOTAL_MARKS = decimal.Decimal("1000")


class AssessmentFields(ScopedSerializer):
    """What both assessment forms check (docs/assessments.md).

    Every id in this form is checked twice: that the actor may reach it at
    all, and that it belongs with the others. A subject from the right school
    taught at a different class level, a term from another year, a topic from
    a different subject - each is a request that looks fine field by field
    and means nothing as a whole.
    """

    type = LaravelCharField("type", max_length=20)
    title = LaravelCharField("title", max_length=150)
    max_marks = serializers.CharField(required=False, allow_null=True)
    pass_marks = serializers.CharField(required=False, allow_null=True)
    weightage = serializers.CharField(required=False, allow_null=True)
    assessment_date = LaravelDateField("assessment_date")

    def __init__(self, *args, assessment=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.assessment = assessment

    validate_type = staticmethod(enum_choice("type", AssessmentType.values))

    def reachable(self, model, field: str, value, errors: dict, column: str = "school_id"):
        """A record of this id that the actor may reach, or None with the
        error already recorded. The id alone is never enough."""
        if value is None:
            return None

        found = self.scope.apply_to(model.objects.filter(pk=value), column=column).first()

        if found is None:
            errors[field] = [does_not_exist(field)]

        return found

    def marks(self, field: str, value, errors: dict, *, is_required: bool):
        # Not `required`: that is the name of the message helper, and a
        # keyword argument of the same name shadowed it into a bool.
        if value is None or value == "":
            if is_required:
                errors[field] = [required(field)]
            return None

        try:
            parsed = decimal.Decimal(str(value)).quantize(decimal.Decimal("0.01"))
        except (decimal.InvalidOperation, TypeError, ValueError):
            errors[field] = [must_be_a_number(field)]
            return None

        if field == "max_marks" and parsed <= 0:
            errors[field] = ["The max marks field must be greater than 0."]
            return None

        if parsed < 0:
            errors[field] = [at_least(field, 0)]
            return None

        if parsed > MAX_TOTAL_MARKS:
            errors[field] = [at_most(field, int(MAX_TOTAL_MARKS))]
            return None

        return parsed

    def check_the_pieces_belong_together(self, values: dict, section, subject, term, errors: dict) -> None:
        """The rules that take more than one record to answer."""
        if section is None or subject is None or term is None:
            return

        school_class = section.school_class

        # The term and the section have to be talking about the same year, or
        # a result would be filed under a term the class never sat in.
        if term.academic_year_id != school_class.academic_year_id:
            errors["academic_term_id"] = [
                f"{term.name} belongs to a different academic year than {school_class.name}."
            ]

        # A subject is taught to a range of class levels. Outside it, the
        # subject is simply not this class's subject.
        if not (subject.min_class_level <= school_class.level <= subject.max_class_level):
            errors["subject_id"] = [f"{subject.name} is not taught at {school_class.name}."]

        date = values.get("assessment_date")

        if date is not None and not (term.start_date <= date <= term.end_date):
            errors["assessment_date"] = [
                f"The date must fall inside {term.name} ({term.start_date} to {term.end_date})."
            ]

    def check_topic(self, topic, subject, errors: dict) -> None:
        if topic is not None and subject is not None and topic.subject_id != subject.id:
            errors["syllabus_topic_id"] = [f'"{topic.title}" is not a topic of {subject.name}.']

    def to_internal_value(self, data):
        """Field checks and cross-record checks together.

        DRF alone stops at the first field that fails, so a type nobody
        recognises would hide a test out of zero marks, and the teacher would
        fix one thing at a time. Everything this form knows is reported at
        once (CLAUDE.md rule 12).
        """
        errors: dict[str, list[str]] = {}

        try:
            attrs = super().to_internal_value(data)
        except serializers.ValidationError as failure:
            errors.update({key: list(value) for key, value in failure.detail.items()})
            attrs = {}

        self.collect(attrs, errors)

        if errors:
            raise serializers.ValidationError(errors)

        return attrs

    def given_id(self, attrs: dict, field: str):
        """An id the form was sent, even when another field failed.

        Same reason as given_date: DRF returns nothing once anything is
        invalid, and the cross-record rules are the ones worth reporting
        together.
        """
        if attrs.get(field) is not None:
            return attrs[field]

        raw = self.initial_data.get(field)

        try:
            return int(raw)
        except (TypeError, ValueError):
            return None

    def given_date(self, attrs: dict, fallback=None):
        """The date the form was sent, even when another field failed.

        DRF hands back nothing at all once any field is invalid, so a bad
        title would otherwise hide a date outside the term - and the teacher
        would be told about them one at a time.
        """
        if attrs.get("assessment_date") is not None:
            return attrs["assessment_date"]

        raw = self.initial_data.get("assessment_date")

        try:
            return dt.date.fromisoformat(str(raw)[:10])
        except (TypeError, ValueError):
            return fallback

    def check_weightage(self, values: dict, section, subject, term, errors: dict) -> None:
        """One subject's tests in one term share 100 percent between them.

        Over-allocating is refused rather than quietly rounded, because the
        sum is what a term average will be computed from.
        """
        weightage = values.get("weightage")

        if weightage is None or section is None or subject is None or term is None:
            return

        siblings = Assessment.objects.filter(
            academic_term_id=term.id, class_section_id=section.id, subject_id=subject.id
        ).exclude(weightage=None)

        if self.assessment is not None:
            siblings = siblings.exclude(pk=self.assessment.id)

        already = sum((row.weightage for row in siblings), decimal.Decimal("0"))

        if already + weightage > 100:
            errors["weightage"] = [
                f"{subject.name} already has {already:.2f}% of {term.name} allocated. "
                "This would take it past 100%."
            ]


class StoreAssessmentRequest(AssessmentFields):
    class_section_id = LaravelIntegerField("class_section_id")
    subject_id = LaravelIntegerField("subject_id")
    academic_term_id = LaravelIntegerField("academic_term_id")
    syllabus_topic_id = LaravelIntegerField("syllabus_topic_id", required=False, allow_null=True)
    grade_scale_id = LaravelIntegerField("grade_scale_id", required=False, allow_null=True)

    def collect(self, attrs: dict, errors: dict) -> None:
        # A section carries no school_id of its own; it is reached through its
        # class, which is why the scope is applied down that path.
        section = self.reachable(
            ClassSection, "class_section_id", self.given_id(attrs, "class_section_id"), errors,
            column="school_class__school_id",
        )
        subject = self.reachable(Subject, "subject_id", self.given_id(attrs, "subject_id"), errors)
        term = self.reachable(AcademicTerm, "academic_term_id", self.given_id(attrs, "academic_term_id"), errors)
        topic = self.reachable(SyllabusTopic, "syllabus_topic_id", self.given_id(attrs, "syllabus_topic_id"), errors)
        scale = self.reachable(GradeScale, "grade_scale_id", self.given_id(attrs, "grade_scale_id"), errors)

        attrs["max_marks"] = self.marks("max_marks", self.initial_data.get("max_marks"), errors, is_required=True)
        attrs["pass_marks"] = self.marks("pass_marks", self.initial_data.get("pass_marks"), errors, is_required=False)
        attrs["weightage"] = self.marks("weightage", self.initial_data.get("weightage"), errors, is_required=False)

        check_pass_marks(attrs, errors)
        check_weightage_range(attrs, errors)
        self.check_the_pieces_belong_together(
            {**attrs, "assessment_date": self.given_date(attrs)}, section, subject, term, errors
        )
        self.check_topic(topic, subject, errors)
        self.check_weightage(attrs, section, subject, term, errors)

        if section is not None:
            # Never from the request: the section says which school and which
            # year this test belongs to (CLAUDE.md rule 10).
            attrs["school_id"] = section.school_class.school_id
            attrs["academic_year_id"] = section.school_class.academic_year_id


class UpdateAssessmentRequest(AssessmentFields):
    """The section and the subject are fixed at creation.

    Moving a test to another class would carry its marks with it, which is
    not an edit of a title and a date.
    """

    type = LaravelCharField("type", max_length=20, required=False)
    title = LaravelCharField("title", max_length=150, required=False)
    assessment_date = LaravelDateField("assessment_date", required=False)
    academic_term_id = LaravelIntegerField("academic_term_id", required=False)
    syllabus_topic_id = LaravelIntegerField("syllabus_topic_id", required=False, allow_null=True)
    grade_scale_id = LaravelIntegerField("grade_scale_id", required=False, allow_null=True)

    def collect(self, attrs: dict, errors: dict) -> None:
        assessment = self.assessment

        section = assessment.class_section
        subject = assessment.subject
        term = assessment.academic_term

        if "academic_term_id" in attrs:
            term = self.reachable(AcademicTerm, "academic_term_id", attrs["academic_term_id"], errors) or term

        topic = assessment.syllabus_topic
        if "syllabus_topic_id" in attrs:
            topic = self.reachable(SyllabusTopic, "syllabus_topic_id", attrs["syllabus_topic_id"], errors)

        if "grade_scale_id" in attrs:
            scale = self.reachable(GradeScale, "grade_scale_id", attrs["grade_scale_id"], errors)
            attrs["grade_scale_id"] = scale.id if scale is not None else None

        for field in ("max_marks", "pass_marks", "weightage"):
            if field in attrs:
                attrs[field] = self.marks(field, attrs[field], errors, is_required=(field == "max_marks"))

        # Whatever was not sent keeps what is stored, so moving one field
        # cannot leave the record contradicting itself.
        merged = {
            "assessment_date": self.given_date(attrs, assessment.assessment_date),
            "max_marks": attrs.get("max_marks", assessment.max_marks),
            "pass_marks": attrs.get("pass_marks", assessment.pass_marks),
            "weightage": attrs.get("weightage", assessment.weightage),
        }

        check_pass_marks(merged, errors)
        check_weightage_range(merged, errors)
        self.check_the_pieces_belong_together(merged, section, subject, term, errors)
        self.check_topic(topic, subject, errors)
        self.check_weightage(merged, section, subject, term, errors)


def check_pass_marks(values: dict, errors: dict) -> None:
    """A pass mark nobody could reach is a test everybody fails."""
    maximum = values.get("max_marks")
    passing = values.get("pass_marks")

    if maximum is not None and passing is not None and passing > maximum and "pass_marks" not in errors:
        errors["pass_marks"] = ["The pass marks field must not be greater than max marks."]


def check_weightage_range(values: dict, errors: dict) -> None:
    weightage = values.get("weightage")

    if weightage is not None and weightage > 100 and "weightage" not in errors:
        errors["weightage"] = [must_be_between("weightage", 0, 100)]


# -- users ------------------------------------------------------------------

# What a School or Group Admin may assign when editing somebody. Not the admin
# roles: promoting a colleague to admin is the create path's business, and it
# derives the tier from who is doing the creating.
SCHOOL_ADMIN_ASSIGNABLE_ROLES = (
    UserRole.HOD,
    UserRole.TEACHER,
    UserRole.STAFF,
    UserRole.TRANSPORT_MANAGER,
    UserRole.ACCOUNTANT,
)


class StoreUserRequest(ScopedSerializer):
    """Onboards an admin-tier account.

    The only roles this endpoint creates are SCHOOL_ADMIN and - for a Super
    Admin - GROUP_ADMIN. Whether the result is a "School Admin" or a "Sub
    Admin" depends on who is creating it, not on anything in this request.
    """

    first_name = LaravelCharField("first_name", max_length=100)
    last_name = LaravelCharField("last_name", max_length=100)
    email = LaravelCharField("email", max_length=255)
    mobile = MobileField("mobile")
    password = PasswordField("password")
    role = LaravelCharField("role")

    def validate_email(self, value: str) -> str:
        # Stored lowercase, so validation has to ask in the same form or the
        # unique rule looks for something the index will refuse later - a 500
        # where a field-level 422 belongs.
        value = value.strip().lower()

        if not EMAIL_PATTERN.match(value):
            raise serializers.ValidationError(not_an_email("email"))

        return value

    def validate(self, attrs):
        errors = {}

        role = attrs.get("role")
        allowed = (
            [UserRole.SCHOOL_ADMIN, UserRole.GROUP_ADMIN]
            if self.actor.role == UserRole.SUPER_ADMIN
            else [UserRole.SCHOOL_ADMIN]
        )

        if role not in allowed:
            errors["role"] = [selected_is_invalid("role")]

        if User.objects.filter(email=attrs["email"]).exists():
            errors["email"] = [already_taken("email")]

        try:
            self.validate_school_id_field()
        except serializers.ValidationError as invalid:
            errors.update(invalid.detail)

        # A Group Admin sits at the parent and answers for the branches
        # beneath it. Attaching one to a branch would be claiming the branch
        # is the group.
        if role == UserRole.GROUP_ADMIN and "school_id" not in errors:
            school = School.objects.filter(pk=self.resolved_school_id()).first()

            if school is not None and school.parent_school_id is not None:
                errors["school_id"] = [
                    f'"{school.name}" is a branch. '
                    "A Group Admin belongs to the school the branches sit under."
                ]

        if errors:
            raise serializers.ValidationError(errors)

        attrs["school_id"] = self.resolved_school_id()

        return attrs


class UpdateUserRequest(ScopedSerializer):
    first_name = LaravelCharField("first_name", max_length=100, required=False)
    last_name = LaravelCharField("last_name", max_length=100, required=False)
    email = LaravelCharField("email", max_length=255, required=False)
    mobile = MobileField("mobile")
    password = PasswordField("password", required=False)
    role = LaravelCharField("role", required=False)

    def __init__(self, *args, user: User = None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        # Moving a user between schools is not a feature, so school_id is
        # deliberately not on this form at all.
        self.user = user

    def validate_email(self, value: str) -> str:
        value = value.strip().lower()

        if not EMAIL_PATTERN.match(value):
            raise serializers.ValidationError(not_an_email("email"))

        return value

    def validate(self, attrs):
        errors = {}

        if "email" in attrs and User.objects.filter(email=attrs["email"]).exclude(
            pk=self.user.pk
        ).exists():
            errors["email"] = [already_taken("email")]

        if self.user.role == UserRole.BUS_ATTENDANT and "mobile" in attrs:
            login = attendants.login_mobile(attrs["mobile"])

            if login is None:
                errors["mobile"] = ["A Bus Attendant signs in with their mobile number, so it cannot be removed."]
            elif AttendantCredential.objects.filter(login_mobile=login).exclude(user_id=self.user.pk).exists():
                errors["mobile"] = ["Another Bus Attendant already signs in with this mobile number."]

        if "role" in attrs and attrs["role"] != self.user.role and UserRole.BUS_ATTENDANT in (attrs["role"], self.user.role):
            errors["role"] = [
                "A Bus Attendant signs in differently from everybody else, so the role cannot be changed to "
                "or from it. Add the person again with the role they need."
            ]
        elif "role" in attrs:
            if attrs["role"] not in UserRole.values:
                errors["role"] = [selected_is_invalid("role")]
            elif (
                self.actor.role == UserRole.SCHOOL_ADMIN
                and attrs["role"] not in SCHOOL_ADMIN_ASSIGNABLE_ROLES
            ):
                errors["role"] = [
                    "A school admin can only assign the HOD, Teacher, Staff, "
                    "Transport Manager or Accountant role."
                ]

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


# -- auth -------------------------------------------------------------------


class LoginRequest(serializers.Serializer):
    email = serializers.EmailField(
        error_messages={
            "required": required("email"),
            "null": required("email"),
            "blank": required("email"),
            "invalid": "The email field must be a valid email address.",
        }
    )
    password = LaravelCharField("password")

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def validate_email(self, value: str) -> str:
        # The User model stores addresses lowercase, so the lookup has to ask
        # in the same form or a perfectly good password is reported as wrong.
        # Laravel does this in prepareForValidation for the same reason.
        return value.strip().lower()


class ChangePasswordRequest(serializers.Serializer):
    """`current_password` + `password` `confirmed` + `different`.

    The two messages Laravel overrides are overridden here too. They are what
    a person reads when they mistype, and "That is not your current password."
    is a better sentence than the default - which is why somebody wrote it.
    """

    current_password = LaravelCharField("current_password")
    password = PasswordField("password")
    password_confirmation = LaravelCharField("password_confirmation", required=False, allow_null=True)

    def __init__(self, *args, actor=None, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        self.actor = actor

    def validate(self, attrs):
        errors = {}

        # Checked against the stored hash, never by querying for it, and never
        # echoed back in any message (CLAUDE.md rule 11).
        if not hashing.check(attrs["current_password"], self.actor.password):
            errors["current_password"] = ["That is not your current password."]

        if attrs.get("password_confirmation") != attrs["password"]:
            errors.setdefault("password", []).append(confirmation_does_not_match("password"))

        if attrs["password"] == attrs["current_password"]:
            errors.setdefault("password", []).append(
                "Choose a password you have not just been using."
            )

        if errors:
            raise serializers.ValidationError(errors)

        return attrs


# -- reports ----------------------------------------------------------------


class ReportRequest(serializers.Serializer):
    """ReportRequest: which school, over what range, in what format.

    Written as one pass over the fields rather than as field declarations,
    because two of its rules depend on others - `to` on `from`, and every date
    on which school's calendar "today" is read from - and DRF drops a
    cross-field check the moment any single field fails, where Laravel reports
    everything at once. `from` is also a Python keyword.

    Every check runs in Laravel's rule order, with its messages, including the
    four the form overrides.
    """

    def __init__(self, *args, actor=None, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        self.actor = actor

    def to_internal_value(self, data):
        errors: dict[str, list[str]] = {}
        values: dict = {}
        today = self._school_today(data.get("school_id"))

        school_messages = self._school_id_messages(data.get("school_id"))
        if school_messages:
            errors["school_id"] = school_messages

        for field, future_message in (
            ("from", "A report cannot start on a date that has not happened yet."),
            ("to", "A report cannot run past today."),
        ):
            if data.get(field) is None:
                continue

            try:
                values[field] = LaravelDateField(field).to_internal_value(data[field])
            except serializers.ValidationError:
                errors[field] = [not_a_date(field)]
                continue

            messages = []
            if values[field] > today:
                messages.append(future_message)

            # after_or_equal:from - measured only against a `from` that is a
            # date; Laravel compares with nothing, and so passes, otherwise.
            if field == "to" and "from" in values and values["to"] < values["from"]:
                messages.append("The end of the range must not be before its start.")

            if messages:
                errors[field] = messages

        for field, model in (("class_section_id", ClassSection), ("department_id", Department)):
            value = data.get(field)

            if value is None:
                continue

            if not PHP_INTEGER.match(str(value)):
                errors[field] = [must_be_an_integer(field)]
            elif not model.objects.filter(pk=int(value)).exists():
                errors[field] = [does_not_exist(field)]
            else:
                values[field] = int(value)

        # PDF is Phase 20's, and Python's alone - Laravel refuses it as it
        # always has.
        if data.get("format") is not None and data["format"] not in ("json", "csv", "pdf"):
            errors["format"] = [selected_is_invalid("format")]

        # Phase 20, Python only: both are opt-in, so a request without them
        # gets exactly the report Laravel gives.
        if data.get("compare") is not None and str(data["compare"]) not in ("0", "1", "true", "false"):
            errors["compare"] = ["The compare field must be true or false."]

        if data.get("below") is not None:
            try:
                below = float(data["below"])
            except (TypeError, ValueError):
                below = None
            if below is None or not 0 < below <= 100:
                errors["below"] = ["The below field must be a percentage greater than 0 and at most 100."]
            else:
                values["below"] = below

        if errors:
            raise serializers.ValidationError(errors)

        values["format"] = data.get("format") or "json"
        values["wants_csv"] = values["format"] == "csv"
        values["compare"] = str(data.get("compare")) in ("1", "true")

        return values

    def _school_id_messages(self, value) -> list[str]:
        """readableSchoolIdRules(): a Super Admin names a school that exists;
        anybody else may name one, as a number, or leave it out."""
        unrestricted = SchoolScope.for_actor(self.actor).is_unrestricted()

        if value is None:
            return ["Pick a school to report on."] if unrestricted else []

        if not PHP_INTEGER.match(str(value)):
            return [must_be_an_integer("school_id")]

        if unrestricted and not School.objects.filter(pk=int(value)).exists():
            return [does_not_exist("school_id")]

        return []

    def _school_today(self, school_id):
        """ChecksSchoolDates::schoolToday() - the acting school's date, or for
        a Super Admin the date at the school they named (the platform's when
        they named none, and UTC for one that does not exist)."""
        if self.actor.role != UserRole.SUPER_ADMIN:
            clock = SchoolClock.for_school(self.actor.school_id)
        elif school_id is None:
            clock = SchoolClock.platform()
        else:
            clock = SchoolClock.for_school(php_int(school_id))

        return clock.now().date()


# -- audit log (Phase 21) ------------------------------------------------------


class AuditLogFilterRequest(ScopedSerializer):
    """What the audit screen may filter by. Every filter narrows; the school
    scope is applied separately and cannot be widened by any of them."""

    school_id = LaravelIntegerField("school_id", required=False, allow_null=True)
    user_id = LaravelIntegerField("user_id", required=False, allow_null=True)
    module = LaravelCharField("module", required=False, allow_null=True)
    action = LaravelCharField("action", max_length=64, required=False, allow_null=True)
    entity_type = LaravelCharField("entity_type", max_length=64, required=False, allow_null=True)
    entity_id = LaravelIntegerField("entity_id", required=False, allow_null=True)
    # `from` is a Python keyword, so these are mapped from the query below.
    from_date = LaravelDateField("from", required=False, allow_null=True)
    to_date = LaravelDateField("to", required=False, allow_null=True)
    format = LaravelCharField("format", required=False, allow_null=True)

    def to_internal_value(self, data):
        data = dict(data)
        for outer, inner in (("from", "from_date"), ("to", "to_date")):
            if outer in data:
                data[inner] = data.pop(outer)

        # Every problem at once, the way Laravel reports them: DRF stops at
        # the field checks and would never reach the choices below.
        errors = {}
        values = {}
        try:
            values = super().to_internal_value(data)
        except serializers.ValidationError as error:
            errors = dict(error.detail)

        # Named as the client sent them, so a form marks the right field.
        for outer, inner in (("from", "from_date"), ("to", "to_date")):
            if inner in errors:
                errors[outer] = errors.pop(inner)

        if data.get("module") and data["module"] not in audit.MODULES:
            errors["module"] = [selected_is_invalid("module")]
        if data.get("format") and data["format"] not in ("json", "csv"):
            errors["format"] = [selected_is_invalid("format")]
        if values.get("from_date") and values.get("to_date") and values["to_date"] < values["from_date"]:
            errors["to"] = ["The end of the range must not be before its start."]
        if errors:
            raise serializers.ValidationError(errors)

        return values


# -- the Bus Attendant --------------------------------------------------------


class AttendantSetupRequest(serializers.Serializer):
    """Registering a phone: the attendant's mobile, the one-time setup code an
    administrator gave them, and the passcode they choose."""

    mobile = MobileField("mobile", required=True, allow_null=False, allow_blank=False)
    setup_code = LaravelCharField("setup_code", max_length=20)
    passcode = serializers.CharField(error_messages={"required": required("passcode"), "blank": required("passcode")})
    device_name = optional_text("device_name", 120)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def validate_passcode(self, value):
        problem = attendants.passcode_problem(value)

        if problem:
            raise serializers.ValidationError(problem)

        return value


class AttendantLoginRequest(serializers.Serializer):
    mobile = MobileField("mobile", required=True, allow_null=False, allow_blank=False)
    passcode = serializers.CharField(error_messages={"required": required("passcode"), "blank": required("passcode")})
    device_secret = serializers.CharField(
        max_length=200,
        error_messages={"required": "This phone is not registered yet. Enter the setup code from your school office."},
    )

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)


def parse_instant(field_name: str, value):
    """An ISO 8601 instant that says which timezone it is in - "2026-09-19T
    07:42:10Z" or "+05:30" - as an aware UTC datetime. A phone's clock time
    with no zone is refused: it could mean any of a dozen instants."""
    import datetime as dt

    if not isinstance(value, str) or not value.strip():
        raise serializers.ValidationError(f"The {attribute(field_name)} field is required.")

    try:
        parsed = dt.datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        raise serializers.ValidationError(f"The {attribute(field_name)} field must be a date and time.")

    if parsed.tzinfo is None:
        raise serializers.ValidationError(f"The {attribute(field_name)} field must say which timezone it is in.")

    return parsed.astimezone(dt.timezone.utc)


SYNC_TYPES = ("stop_reached", "boarded", "dropped", "absent", "guardian_called", "end")
CLIENT_ID = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
MAX_SYNC_OPERATIONS = 200


class TripSyncRequest(serializers.Serializer):
    """A batch of trip marks from the phone, in the order they were made.

    Only the shape is checked here; whether each mark can be applied - the
    trip still running, the child still waiting - is the service's answer,
    given per mark, because one mark that can no longer be applied must not
    lose the rest of the batch.
    """

    operations = serializers.ListField(
        child=serializers.DictField(), allow_empty=False, max_length=MAX_SYNC_OPERATIONS,
        error_messages={"empty": "Send at least one mark.", "not_a_list": "The operations field must be a list."},
    )

    def validate_operations(self, value):
        problems = []
        cleaned = []

        for index, op in enumerate(value, start=1):
            client_id = str(op.get("client_id") or "")
            kind = op.get("type")

            if not CLIENT_ID.match(client_id):
                problems.append(f"Mark {index}: client_id must be 8-64 letters, digits, - or _.")
                continue

            if kind not in SYNC_TYPES:
                problems.append(f"Mark {index}: {kind!r} is not a kind of trip mark.")
                continue

            try:
                occurred = parse_instant("occurred_at", op.get("occurred_at"))
            except serializers.ValidationError:
                problems.append(f"Mark {index}: occurred_at must be a date and time.")
                continue

            needs_stop = kind == "stop_reached"
            needs_student = kind in ("boarded", "dropped", "absent", "guardian_called")

            if needs_stop and not isinstance(op.get("stop_id"), int):
                problems.append(f"Mark {index}: stop_id is required.")
                continue

            if needs_student and not isinstance(op.get("student_id"), int):
                problems.append(f"Mark {index}: student_id is required.")
                continue

            cleaned.append({
                "client_id": client_id, "type": kind, "occurred_at": occurred,
                "stop_id": op.get("stop_id") if needs_stop else None,
                "student_id": op.get("student_id") if needs_student else None,
            })

        ids = [op["client_id"] for op in cleaned]

        if len(ids) != len(set(ids)):
            problems.append("Each mark in a batch needs its own client_id.")

        if problems:
            raise serializers.ValidationError(problems)

        return cleaned


MAX_LOCATION_POINTS = 100


class TripLocationsRequest(serializers.Serializer):
    """Positions from the phone of whoever runs the trip: a small batch, so
    a phone that lost signal can catch up in one request."""

    points = serializers.ListField(
        child=serializers.DictField(), allow_empty=False, max_length=MAX_LOCATION_POINTS,
        error_messages={"empty": "Send at least one position.", "not_a_list": "The points field must be a list."},
    )

    def validate_points(self, value):
        problems = []
        cleaned = []

        for index, point in enumerate(value, start=1):
            try:
                latitude = CoordinateField("latitude", -90, 90, required=True).to_internal_value(point.get("latitude"))
                longitude = CoordinateField("longitude", -180, 180, required=True).to_internal_value(point.get("longitude"))
                recorded_at = parse_instant("recorded_at", point.get("recorded_at"))
            except serializers.ValidationError as invalid:
                problems.append(f"Position {index}: {invalid.detail[0] if isinstance(invalid.detail, list) else invalid.detail}")
                continue

            if latitude is None or longitude is None:
                problems.append(f"Position {index}: latitude and longitude are required.")
                continue

            def number(key, low, high):
                raw = point.get(key)

                if raw is None:
                    return None

                try:
                    value = decimal.Decimal(str(raw))
                except (decimal.InvalidOperation, ValueError):
                    raise serializers.ValidationError(f"Position {index}: {key} must be a number.")

                if not low <= value <= high:
                    raise serializers.ValidationError(f"Position {index}: {key} must be between {low} and {high}.")

                return value.quantize(decimal.Decimal("0.01"))

            try:
                accuracy = number("accuracy", 0, 99999)
                speed = number("speed", 0, 9999)
                heading = number("heading", 0, 360)
            except serializers.ValidationError as invalid:
                problems.append(str(invalid.detail[0]))
                continue

            cleaned.append({
                "latitude": latitude, "longitude": longitude, "recorded_at": recorded_at,
                "accuracy_m": accuracy, "speed_mps": speed, "heading": heading,
            })

        if problems:
            raise serializers.ValidationError(problems)

        return cleaned
