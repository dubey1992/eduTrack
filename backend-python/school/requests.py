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

from rest_framework import serializers

import re

from . import hashing
from .enums import HolidayType, UserRole
from .models import (
    AcademicYear,
    ClassSection,
    Department,
    Holiday,
    Period,
    EarlyAccessRequest,
    School,
    SchoolClass,
    Student,
    Subject,
    User,
)
from .scope import SchoolScope
from .validation import (
    CoordinateField,
    LaravelBooleanField,
    LaravelCharField,
    LaravelDateField,
    LaravelIntegerField,
    MobileField,
    TimezoneField,
    UrlField,
    already_taken,
    bad_format,
    confirmation_does_not_match,
    does_not_exist,
    must_be_after,
    normalise,
    not_an_email,
    optional_text,
    required,
    selected_is_invalid,
)

# ISO 4217: three upper-case letters and nothing else.
CURRENCY_PATTERN = re.compile(r"^[A-Z]{3}$")

# Deliberately permissive, matching Laravel's `email` rule rather than trying
# to be cleverer than it: something, an @, something with a dot in it. A
# stricter pattern here would refuse addresses the PHP backend accepts, which
# is a contract difference dressed up as a fix.
EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


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


# -- users ------------------------------------------------------------------

# What a School or Group Admin may assign when editing somebody. Not the admin
# roles: promoting a colleague to admin is the create path's business, and it
# derives the tier from who is doing the creating.
SCHOOL_ADMIN_ASSIGNABLE_ROLES = (
    UserRole.HOD,
    UserRole.TEACHER,
    UserRole.STAFF,
    UserRole.TRANSPORT_MANAGER,
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
    password = LaravelCharField("password", min_length=8)
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
    password = LaravelCharField("password", min_length=8, required=False)
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

        if "role" in attrs:
            if attrs["role"] not in UserRole.values:
                errors["role"] = [selected_is_invalid("role")]
            elif (
                self.actor.role == UserRole.SCHOOL_ADMIN
                and attrs["role"] not in SCHOOL_ADMIN_ASSIGNABLE_ROLES
            ):
                errors["role"] = [
                    "A school admin can only assign the HOD, Teacher, Staff, "
                    "or Transport Manager role."
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
    password = LaravelCharField("password", min_length=8)
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
