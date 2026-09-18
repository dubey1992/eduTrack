"""Laravel's validation messages, in Laravel's words.

A 422 is not just a status code here. The Flutter client renders
`details.errors[field][0]` straight into the form, so the sentence a school
admin reads when they leave the admission number blank is part of what this
migration must not change. DRF's own wording ("This field is required.") is
not that sentence.

So the handful of rules M8 needs are written out with the templates from
Laravel's own validation lang file, and the attribute name is derived the way
Laravel derives it: `admission_number` becomes "admission number".

Checked against the running Laravel app rather than copied from memory - the
exact strings were printed from Validator::make and pasted here.
"""

from __future__ import annotations

import decimal
import re
import urllib.parse

from rest_framework import serializers

from .zones import ZONES

# Laravel's regex for a mobile number: a country code and then digits or
# spaces. The same expression guards the same field in the Flutter form, so
# loosening it here would let through something no client would have sent.
MOBILE_PATTERN = re.compile(r"^\+[1-9][0-9 ]{6,17}$")


# Laravel trims every incoming string except these three, because a password
# may legitimately begin or end with a space and silently eating it would lock
# somebody out of their own account. See TrimStrings::$except.
NEVER_TRIMMED = ("current_password", "password", "password_confirmation")


def normalise(data):
    """What Laravel's global middleware does to a request before any rule sees
    it: trim every string, then turn the empty ones into null.

    This is easy to miss and changes behaviour everywhere. `guardian_mobile:
    ""` reaches Laravel's validator as null and passes a `nullable` rule; the
    same payload reaching an untouched DRF serializer is an empty string that
    fails a format rule. Two backends, one request, different answers - so the
    normalisation comes across rather than being left as an accident of
    framework defaults.

    See TrimStrings and ConvertEmptyStringsToNull, which sit in Laravel's
    global middleware stack and therefore apply to every API route.
    """
    if not isinstance(data, dict):
        return data

    normalised = {}

    for key, value in data.items():
        if isinstance(value, str) and key not in NEVER_TRIMMED:
            value = value.strip()

        normalised[key] = None if value == "" else value

    return normalised


def attribute(field: str) -> str:
    """`class_section_id` -> "class section id", which is how Laravel prints a
    field name into a message."""
    return field.replace("_", " ")


def required(field: str) -> str:
    return f"The {attribute(field)} field is required."


def must_be_a_string(field: str) -> str:
    return f"The {attribute(field)} field must be a string."


# PHP's FILTER_VALIDATE_INT, which is what Laravel's `integer` rule uses on a
# string: an optional sign, and no leading zeros, decimals or exponent.
PHP_INTEGER = re.compile(r"^[+-]?(0|[1-9][0-9]*)$")


def must_be_an_integer(field: str) -> str:
    return f"The {attribute(field)} field must be an integer."


def too_long(field: str, maximum: int) -> str:
    return f"The {attribute(field)} field must not be greater than {maximum} characters."


def too_short(field: str, minimum: int) -> str:
    return f"The {attribute(field)} field must be at least {minimum} characters."


def bad_format(field: str) -> str:
    return f"The {attribute(field)} field format is invalid."


def not_an_email(field: str) -> str:
    return f"The {attribute(field)} field must be a valid email address."


def does_not_exist(field: str) -> str:
    return f"The selected {attribute(field)} is invalid."


# Laravel gives `exists`, `in` and `Enum` the same sentence. Two names for it
# so a call site reads as what it meant - "this id is not in the table" and
# "this is not one of the allowed values" are different mistakes to make.
selected_is_invalid = does_not_exist


def already_taken(field: str) -> str:
    return f"The {attribute(field)} has already been taken."


def must_be_a_number(field: str) -> str:
    return f"The {attribute(field)} field must be a number."


def must_be_between(field: str, low, high) -> str:
    return f"The {attribute(field)} field must be between {low} and {high}."


def not_a_url(field: str) -> str:
    # "logo url", not "logo URL" - Laravel lowercases the attribute and leaves
    # the word URL capitalised only where it appears in the template.
    return f"The {attribute(field)} field must be a valid URL."


def not_a_timezone(field: str) -> str:
    return f"The {attribute(field)} field must be a valid timezone."


def at_least(field: str, minimum) -> str:
    return f"The {attribute(field)} field must be at least {minimum}."


def at_most(field: str, maximum) -> str:
    return f"The {attribute(field)} field must not be greater than {maximum}."


def not_a_date(field: str) -> str:
    return f"The {attribute(field)} field must be a valid date."


def must_be_after(field: str, other: str) -> str:
    return f"The {attribute(field)} field must be a date after {attribute(other)}."


def required_without(field: str, other: str) -> str:
    return f"The {attribute(field)} field is required when {attribute(other)} is not present."


def prohibits(field: str, other: str) -> str:
    return f"The {attribute(field)} field prohibits {attribute(other)} from being present."


def not_a_boolean(field: str) -> str:
    return f"The {attribute(field)} field must be true or false."


def must_differ(field: str, other: str) -> str:
    return f"The {attribute(field)} field and {attribute(other)} must be different."


def confirmation_does_not_match(field: str) -> str:
    return f"The {attribute(field)} field confirmation does not match."


# -- the field types themselves ---------------------------------------------
#
# Thin subclasses whose only job is to say what Laravel would say. Declaring
# `error_messages` at every call site instead would be five lines per field
# and a chance to get one of them subtly different.


class LaravelCharField(serializers.CharField):
    """A `string` field that fails the way Laravel's would.

    `max_length` may be None for a field Laravel does not cap - a password,
    where the bcrypt input limit is the only ceiling and the message would be
    about a number nobody wrote down.
    """

    def __init__(self, field_name: str, max_length: int | None = None, min_length: int | None = None, **kwargs) -> None:
        messages = {
            "required": required(field_name),
            "null": required(field_name),
            "blank": required(field_name),
            "invalid": must_be_a_string(field_name),
        }

        if max_length is not None:
            kwargs["max_length"] = max_length
            messages["max_length"] = too_long(field_name, max_length)

        if min_length is not None:
            kwargs["min_length"] = min_length
            messages["min_length"] = too_short(field_name, min_length)

        # Trimming already happened, once, in normalise() - the way Laravel's
        # global middleware does it, with passwords excepted. Letting DRF trim
        # again here would quietly undo that exception.
        kwargs.setdefault("trim_whitespace", False)

        super().__init__(error_messages=messages, **kwargs)
        # Kept so subclasses can name the field in a message of their own.
        self._field_name = field_name

    def to_internal_value(self, data):
        # Laravel's `string` rule rejects a number; DRF's CharField would
        # happily coerce 123 into "123". A student named 123 is not what the
        # form meant, and the two backends must refuse the same payloads.
        if not isinstance(data, str):
            self.fail("invalid")

        return super().to_internal_value(data)


class LaravelIntegerField(serializers.IntegerField):
    def __init__(self, field_name: str, **kwargs) -> None:
        messages = {
            "required": required(field_name),
            "null": required(field_name),
            "invalid": must_be_an_integer(field_name),
        }

        if "min_value" in kwargs:
            messages["min_value"] = at_least(field_name, kwargs["min_value"])

        if "max_value" in kwargs:
            messages["max_value"] = at_most(field_name, kwargs["max_value"])

        super().__init__(error_messages=messages, **kwargs)


class MobileField(LaravelCharField):
    """A phone number, or nothing.

    An empty string is nothing, not an invalid number: a form that clears the
    field posts "" and the school means "no number on file", which is what
    Laravel's `nullable` does with it.
    """

    def __init__(self, field_name: str, **kwargs) -> None:
        kwargs.setdefault("required", False)
        kwargs.setdefault("allow_null", True)
        kwargs.setdefault("allow_blank", True)
        super().__init__(field_name, max_length=20, **kwargs)

    def to_internal_value(self, data):
        if data is None or data == "":
            return None

        value = super().to_internal_value(data)

        if not MOBILE_PATTERN.match(value):
            raise serializers.ValidationError(bad_format(self._field_name))

        return value


class CoordinateField(serializers.Field):
    """A latitude or longitude, or nothing.

    Kept as a string all the way to the column, which is `decimal(10,7)`.
    Going through a float would round the seventh decimal place - about a
    centimetre - and a coordinate that changes every time it is read is a
    coordinate nobody can trust.
    """

    def __init__(self, field_name: str, low, high, **kwargs) -> None:
        kwargs.setdefault("required", False)
        kwargs.setdefault("allow_null", True)
        super().__init__(**kwargs)
        self._field_name = field_name
        self._low = low
        self._high = high

    def to_internal_value(self, data):
        if data is None or data == "":
            return None

        try:
            number = decimal.Decimal(str(data))
        except (decimal.InvalidOperation, TypeError, ValueError):
            raise serializers.ValidationError(must_be_a_number(self._field_name))

        if not number.is_finite() or not (self._low <= number <= self._high):
            raise serializers.ValidationError(
                must_be_between(self._field_name, self._low, self._high)
            )

        return number

    def to_representation(self, value):
        return None if value is None else str(value)


class UrlField(LaravelCharField):
    def to_internal_value(self, data):
        if data is None or data == "":
            return None

        value = super().to_internal_value(data)
        parsed = urllib.parse.urlparse(value)

        # Laravel's `url` rule wants a scheme and a host, and nothing more
        # clever than that.
        if not parsed.scheme or not parsed.netloc:
            raise serializers.ValidationError(not_a_url(self._field_name))

        return value


class TimezoneField(LaravelCharField):
    """An IANA name such as Asia/Kolkata.

    This decides what "today" means for everything the school records, so an
    unknown name has to be refused rather than quietly defaulted - a school
    whose day boundary is wrong marks the wrong register.
    """

    def to_internal_value(self, data):
        value = super().to_internal_value(data)

        # Checked against the list PHP accepts, not Python's - they differ by
        # 179 backward-compatibility aliases, and accepting one here would
        # store a name Laravel's SchoolClock rejects, silently moving that
        # school's day boundary to UTC. See school/zones.py.
        if value not in ZONES:
            raise serializers.ValidationError(not_a_timezone(self._field_name))

        return value


class LaravelDateField(serializers.DateField):
    """A calendar date - `2026-04-01`, never an instant.

    A school year starts on a date, not at a moment: the day it begins is the
    same day everywhere, and attaching a time to it would drag it across a
    boundary for a school far enough east or west. The column is a DATE and
    this keeps it one.
    """

    def __init__(self, field_name: str, **kwargs) -> None:
        super().__init__(
            error_messages={
                "required": required(field_name),
                "null": required(field_name),
                "invalid": not_a_date(field_name),
                "datetime": not_a_date(field_name),
            },
            **kwargs,
        )


class LaravelBooleanField(serializers.BooleanField):
    """Laravel's `boolean` rule: true, false, 0, 1, "0" or "1", and nothing
    else.

    DRF's own BooleanField is far more forgiving - "yes", "true", "on", "t"
    all pass - so a request Laravel answers with a 422 used to be quietly
    accepted here. A float is refused too, as PHP's strict in_array refuses
    1.0.
    """

    ACCEPTED = {True: True, False: False, 1: True, 0: False, "1": True, "0": False}

    def __init__(self, field_name: str, **kwargs) -> None:
        super().__init__(
            error_messages={
                "required": required(field_name),
                "null": required(field_name),
                "invalid": not_a_boolean(field_name),
            },
            **kwargs,
        )

    def to_internal_value(self, data):
        if isinstance(data, bool):
            return data

        if (type(data) is int or isinstance(data, str)) and data in self.ACCEPTED:
            return self.ACCEPTED[data]

        self.fail("invalid")


def optional_text(field_name: str, max_length: int) -> serializers.CharField:
    """A `nullable|string|max:n` field, where blank means null."""
    return LaravelCharField(
        field_name,
        max_length=max_length,
        required=False,
        allow_null=True,
        allow_blank=True,
    )


# -- passwords (Phase 21, docs/security.md) ------------------------------------

PASSWORD_MIN_LENGTH = 8


def _common_passwords() -> frozenset[str]:
    """Django's list of 20,000 passwords people actually choose, read once.

    Only the list is borrowed - Django's auth app is not installed, and its
    validator is used for the file it knows how to find, nothing else.
    """
    from django.contrib.auth.password_validation import CommonPasswordValidator

    return frozenset(CommonPasswordValidator().passwords)


_COMMON: frozenset[str] | None = None


def password_rules(value: str) -> None:
    """A new password: a letter and a number, and not one everybody uses.

    Applies to passwords being chosen, never to signing in - an existing
    password keeps working until its owner next changes it. Length is the
    field's own min_length, so its message stays Laravel's.
    """
    global _COMMON
    if _COMMON is None:
        _COMMON = _common_passwords()

    problems = []
    if not (re.search(r"[A-Za-z]", value) and re.search(r"[0-9]", value)):
        problems.append("The password must contain at least one letter and one number.")
    if value.lower().strip() in _COMMON:
        problems.append("This password is too common. Choose one that is harder to guess.")

    if problems:
        raise serializers.ValidationError(problems)


class PasswordField(LaravelCharField):
    """A password being chosen: at least 8 characters, then password_rules."""

    def __init__(self, field_name: str = "password", **kwargs) -> None:
        kwargs.setdefault("min_length", PASSWORD_MIN_LENGTH)
        super().__init__(field_name, **kwargs)
        self.validators.append(password_rules)
