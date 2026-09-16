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

from . import hashing
from .models import ClassSection, School, SchoolClass, Student
from .scope import SchoolScope
from .validation import (
    LaravelCharField,
    LaravelIntegerField,
    MobileField,
    already_taken,
    confirmation_does_not_match,
    does_not_exist,
    normalise,
    optional_text,
    required,
)


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
