"""The forms behind guardians and the Family app's sign-in
(docs/parent-student-app.md, F0). Same field rules and messages as every
other form (school/validation.py)."""

from __future__ import annotations

from rest_framework import serializers

from . import family
from .requests import OptionalEmailField
from .validation import LaravelBooleanField, LaravelCharField, MobileField, normalise, optional_text, required


class _Normalised(serializers.Serializer):
    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)


class GuardianRequest(_Normalised):
    """A guardian of a student, as the office types them in. Sent whole to
    add one; any part of it to edit one."""

    name = LaravelCharField("name", max_length=150)
    mobile = MobileField("mobile")
    email = OptionalEmailField("email")
    relationship = serializers.ChoiceField(
        choices=family.RELATIONSHIPS, required=False,
        error_messages={"invalid_choice": "Choose mother, father, guardian or other."},
    )
    is_primary = LaravelBooleanField("is_primary", required=False)


class SetupCodeRequest(_Normalised):
    """Issuing a parent's setup code. The first time, the office confirms the
    guardian has agreed to use the Family app (DPDP Act 2023)."""

    consent = LaravelBooleanField("consent", required=False, default=False)


class FamilySetupRequest(_Normalised):
    """Registering a phone: the parent's mobile, the setup code from the
    school's letter, and the passcode they choose."""

    mobile = MobileField("mobile", required=True, allow_null=False, allow_blank=False)
    setup_code = LaravelCharField("setup_code", max_length=20)
    passcode = serializers.CharField(error_messages={"required": required("passcode"), "blank": required("passcode")})
    device_name = optional_text("device_name", 120)

    def validate_passcode(self, value):
        problem = family.passcode_problem(value)

        if problem:
            raise serializers.ValidationError(problem)

        return value


class FamilyLoginRequest(_Normalised):
    mobile = MobileField("mobile", required=True, allow_null=False, allow_blank=False)
    passcode = serializers.CharField(error_messages={"required": required("passcode"), "blank": required("passcode")})
    device_secret = serializers.CharField(
        max_length=200,
        error_messages={"required": "This phone is not registered yet. Enter the setup code from your school's letter."},
    )
