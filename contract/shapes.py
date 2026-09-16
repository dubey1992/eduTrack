"""The shapes the API promises, and the assertions that check them.

A contract test is not "did it return 200". It is "did it return the thing the
Flutter app knows how to read", and the app reads by field name and field type.
A backend that renames `first_name` to `firstName`, or starts sending an id as
a string, is a broken backend even though every one of its own tests passes.

So the assertions here are about names and types, and they are deliberately
strict in one direction only: every promised field must be present and of the
promised type. Extra fields are allowed, because adding one cannot break a
client that ignores what it does not recognise - and forbidding them would make
every additive change a contract failure.
"""

from __future__ import annotations

from typing import Any

# Type names used in the shapes below, kept as strings so a shape reads like a
# description rather than like code.
CHECKS = {
    "int": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "float": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "str": lambda v: isinstance(v, str),
    "bool": lambda v: isinstance(v, bool),
    "list": lambda v: isinstance(v, list),
    "dict": lambda v: isinstance(v, dict),
    "any": lambda v: True,
}


def check(value: Any, expected: str) -> bool:
    """Does `value` satisfy `expected`? A trailing ? allows null."""
    if expected.endswith("?"):
        if value is None:
            return True
        expected = expected[:-1]

    if expected not in CHECKS:
        raise ValueError(f"Unknown type in a shape: {expected!r}")

    return CHECKS[expected](value)


def assert_shape(test, body: Any, shape: dict[str, str], where: str) -> None:
    """Every field in `shape` is present on `body`, with the right type."""
    test.assertIsInstance(body, dict, f"{where}: expected an object, got {type(body).__name__}")

    missing = [name for name in shape if name not in body]
    test.assertEqual([], missing, f"{where}: fields the client needs are missing: {missing}")

    wrong = [
        f"{name} is {type(body[name]).__name__} ({body[name]!r}), expected {expected}"
        for name, expected in shape.items()
        if not check(body[name], expected)
    ]
    test.assertEqual([], wrong, f"{where}: fields of the wrong type: {wrong}")


def assert_error(test, response, status: int, where: str) -> None:
    """The error envelope, which every failure in this API shares.

    `{code, message, details}` - CLAUDE.md rule 12. The client renders
    `message` to the user and reads `details.errors` to mark up a form, so an
    error that arrives in a different shape is an error the user never sees
    properly.
    """
    test.assertEqual(status, response.status, f"{where}: expected HTTP {status}\n{response!r}")

    assert_shape(
        test,
        response.body,
        {"code": "str", "message": "str"},
        f"{where}: error envelope",
    )


def assert_validation_error(test, response, field: str, where: str) -> None:
    """A 422 that names the field the client has to mark up."""
    assert_error(test, response, 422, where)

    details = response.body.get("details") or {}
    errors = details.get("errors") or {}

    test.assertIn(
        field,
        errors,
        f"{where}: expected a validation error naming {field!r}, got {list(errors.keys())}",
    )


def assert_paginated(test, response, where: str) -> None:
    """The list envelope: `{data: [...], meta: {...}}`.

    The client reads `meta` to drive its pagination controls, so a list that
    forgets it renders as a single page whatever the total.
    """
    test.assertEqual(200, response.status, f"{where}: expected HTTP 200\n{response!r}")
    test.assertIsInstance(response.body, dict, f"{where}: a list response must be an object")

    test.assertIn("data", response.body, f"{where}: no data array")
    test.assertIsInstance(response.body["data"], list, f"{where}: data must be an array")

    test.assertIn("meta", response.body, f"{where}: no meta - the client cannot paginate without it")
    assert_shape(
        test,
        response.body["meta"],
        {"current_page": "int", "last_page": "int", "per_page": "int", "total": "int"},
        f"{where}: pagination meta",
    )


# ---------------------------------------------------------------------------
# The resource shapes themselves.
#
# Each one lists what the Flutter client reads off that resource. They are the
# actual contract: the Python backend is finished, for a given endpoint, when
# these pass against it unchanged.
# ---------------------------------------------------------------------------

SESSION_USER = {
    "id": "int",
    "name": "str",
    "email": "str",
    "role": "str",
    "is_sub_admin": "bool",
    "must_change_password": "bool",
    "timezone": "str",
    "current_time": "str",
}

STUDENT = {
    "id": "int",
    "school_id": "int",
    "class_section_id": "int",
    "admission_number": "str",
    "first_name": "str",
    "last_name": "str",
    "name": "str",
    "roll_number": "str?",
    "guardian_name": "str",
    "guardian_mobile": "str?",
    "address": "str?",
    "status": "str",
}

SCHOOL = {
    "id": "int",
    "name": "str",
    "email": "str?",
    "currency_code": "str",
    "timezone": "str",
    "status": "str",
    "parent_school_id": "int?",
}

STAFF = {
    "id": "int",
    "user_id": "int",
    "school_id": "int",
    "employee_id": "str",
    "first_name": "str",
    "last_name": "str",
    "name": "str",
    "email": "str",
    "role": "str",
    "status": "str",
}

# -- academic configuration --------------------------------------------------
#
# Taken from the API resources rather than guessed at, which is the difference
# between a contract and a hope. `?` means the field may be null - the client
# reads it either way, and a field that vanishes entirely is a break.

ACADEMIC_YEAR = {
    "id": "int",
    "school_id": "int",
    "school_name": "str?",
    "name": "str",
    "start_date": "str",
    "end_date": "str",
    "is_current": "bool",
}

DEPARTMENT = {
    "id": "int",
    "school_id": "int",
    "school_name": "str?",
    "name": "str",
    "hod_user_id": "int?",
    "hod_name": "str?",
}

SUBJECT = {
    "id": "int",
    "school_id": "int",
    "code": "str",
    "name": "str",
    "department_id": "int?",
    "department_name": "str?",
    "min_class_level": "int?",
    "max_class_level": "int?",
    "lead_teacher_id": "int?",
    "lead_teacher_name": "str?",
}

SCHOOL_CLASS = {
    "id": "int",
    "school_id": "int",
    "academic_year_id": "int",
    "academic_year_name": "str?",
    "name": "str",
    "level": "int",
    "sections": "list",
}

CLASS_SECTION = {
    "id": "int",
    "school_class_id": "int",
    "name": "str",
    "room_number": "str?",
    "class_teacher_id": "int?",
    "class_teacher_name": "str?",
}

PERIOD = {
    "id": "int",
    "school_id": "int",
    "period_number": "int",
    "start_time": "str",
    "end_time": "str",
}

HOLIDAY = {
    "id": "int",
    "school_id": "int",
    "school_name": "str?",
    "name": "str",
    "type": "str",
    "start_date": "str",
    "end_date": "str",
    "days": "int",
}

# -- people and daily operations ---------------------------------------------

USER = {
    "id": "int",
    "first_name": "str",
    "last_name": "str",
    "name": "str",
    "email": "str",
    "mobile": "str?",
    "role": "str",
    "is_sub_admin": "bool",
    "status": "str",
    "school_id": "int?",
}

ATTENDANCE = {
    "id": "int",
    "school_id": "int",
    "class_section_id": "int",
    "student_id": "int",
    "student_name": "str?",
    "attendance_date": "str",
    "status": "str",
    "remarks": "str?",
    "marked_by": "int?",
}

# One name on a register, with whatever was recorded against it. Status is
# nullable on purpose: an unmarked name is the normal state at 8am, and a
# client that cannot represent "not yet" cannot draw the screen.
REGISTER_ENTRY = {
    "student_id": "int",
    "name": "str",
    "status": "str?",
}

STAFF_ATTENDANCE = {
    "id": "int",
    "school_id": "int",
    "staff_profile_id": "int",
    "employee_id": "str?",
    "staff_name": "str?",
    "attendance_date": "str",
    "status": "str",
    "check_in": "str?",
    "check_out": "str?",
}

LEAVE = {
    "id": "int",
    "school_id": "int",
    "staff_profile_id": "int",
    "employee_id": "str?",
    "staff_name": "str?",
    "leave_type": "str",
    "start_date": "str",
    "end_date": "str",
    "reason": "str?",
    "status": "str",
}
