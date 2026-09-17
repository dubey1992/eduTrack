"""The other four spreadsheets: staff, subjects, vehicles and drivers.

Ports of StaffImporter, SubjectImporter, VehicleImporter and DriverImporter.
Each checks a row with Laravel's rules in Laravel's order (see rules.py) and
creates the record through the same service the single-record form uses, so
an imported employee is exactly what the Add Employee screen would have made.

Two things a spreadsheet does that a form does not, both handled here: people
type names rather than ids - a department called "Science", a lead teacher by
email - and they type roles and names in whatever case they like.
"""

from __future__ import annotations

import secrets
import string

from ..enums import UserRole
from ..models import Department, Driver, StaffProfile, Subject, User, Vehicle
from ..services import DriverService, StaffProfileService, SubjectService, VehicleService
from .rules import Row, matching, to_iso

STAFF_ROLES = ("HOD", "TEACHER", "STAFF", "TRANSPORT_MANAGER")


def names_to_ids(queryset, field: str) -> dict[str, int]:
    """A lookup by name or email, case-blind - a spreadsheet cell is not a
    dropdown."""
    return {str(name).lower(): pk for pk, name in queryset.values_list("id", field)}


def temporary_password(length: int = 14) -> str:
    """Laravel's Str::password: letters, numbers and symbols, at least one of
    each. Long, random, and seen once - by whoever ran the import, in the
    response - and changed at first sign-in."""
    symbols = "~!#$%^&*()-_.,<>?/\\{}[]|:;"
    pools = (string.ascii_letters, string.digits, symbols)
    everything = "".join(pools)

    characters = [secrets.choice(pool) for pool in pools]
    characters += [secrets.choice(everything) for _ in range(length - len(characters))]
    secrets.SystemRandom().shuffle(characters)

    return "".join(characters)


class StaffImporter:
    def __init__(self) -> None:
        self._departments: dict[str, int] | None = None

    def label(self) -> str:
        return "Teachers and Staff"

    def headings(self) -> list[str]:
        return [
            "employee_id", "first_name", "last_name", "email", "mobile",
            "role", "department", "designation", "joining_date", "address",
        ]

    def sample(self) -> list[str]:
        return [
            "EMP-1042", "Priya", "Nair", "priya.nair@example.com", "+91 98765 43210",
            "TEACHER", "Science", "Senior Teacher", "09/14/2026", "22 Hill Road, Pune",
        ]

    def unique_columns(self) -> list[str]:
        return ["employee_id", "email"]

    def check_fields(self, data: dict, school_id: int) -> list[str]:
        row = Row(data)

        if row.text("employee_id", 30):
            row.unique("employee_id", StaffProfile.objects.filter(school_id=school_id, employee_id=data["employee_id"]))

        row.text("first_name", 100)
        row.text("last_name", 100)

        if row.present("email"):
            row.email("email")
            row.text("email", 255)
            # Stored lowercase, so "Priya.Nair@" is the account "priya.nair@" holds.
            row.unique("email", matching(User.objects.all(), "email", data["email"]))

        if row.text("mobile", 20, is_required=False):
            row.phone("mobile")

        if row.present("role") and data["role"].strip().upper() not in STAFF_ROLES:
            row.fail("role", "The role must be one of: " + ", ".join(STAFF_ROLES) + ".")

        if row.present("department", is_required=False):
            row.exists("department", matching(Department.objects.filter(school_id=school_id), "name", data["department"]))

        row.text("designation", 100, is_required=False)

        if row.present("joining_date"):
            row.input_date("joining_date")

        row.text("address", 500, is_required=False)

        return row.messages

    def check(self, data: dict, school_id: int) -> list[str]:
        return []

    def import_row(self, data: dict, school_id: int, actor) -> dict:
        password = temporary_password()

        profile = StaffProfileService.create_employee(
            {
                "school_id": school_id,
                "first_name": data["first_name"],
                "last_name": data["last_name"],
                "email": data["email"],
                "mobile": data.get("mobile"),
                "password": password,
                "role": data["role"].strip().upper(),
                "must_change_password": True,
            },
            {
                "employee_id": data["employee_id"],
                "department_id": self._department_id(data.get("department"), school_id),
                "designation": data.get("designation"),
                "joining_date": to_iso(data["joining_date"]),
                "address": data.get("address"),
            },
            actor,
        )
        user = profile.user

        return {
            "id": profile.user_id,
            "name": f"{user.first_name} {user.last_name}",
            "email": user.email,
            "temporary_password": password,
        }

    def _department_id(self, name, school_id: int):
        if name is None:
            return None

        if self._departments is None:
            self._departments = names_to_ids(Department.objects.filter(school_id=school_id), "name")

        return self._departments.get(name.strip().lower())


class SubjectImporter:
    def __init__(self) -> None:
        self._departments: dict[str, int] | None = None
        self._teachers: dict[str, int] | None = None

    def label(self) -> str:
        return "Subjects"

    def headings(self) -> list[str]:
        return ["code", "name", "department", "min_class_level", "max_class_level", "lead_teacher_email"]

    def sample(self) -> list[str]:
        return ["SCI-05", "Science", "Science", "5", "8", "priya.nair@example.com"]

    def unique_columns(self) -> list[str]:
        return ["code"]

    def check_fields(self, data: dict, school_id: int) -> list[str]:
        row = Row(data)

        if row.text("code", 20):
            row.unique("code", Subject.objects.filter(school_id=school_id, code=data["code"]))

        row.text("name", 100)

        if row.present("department"):
            row.exists("department", matching(Department.objects.filter(school_id=school_id), "name", data["department"]))

        for field in ("min_class_level", "max_class_level"):
            if row.present(field):
                row.integer_between(field, 0, 12)

        if row.present("lead_teacher_email", is_required=False):
            row.email("lead_teacher_email")
            row.exists(
                "lead_teacher_email",
                matching(
                    User.objects.filter(school_id=school_id, role__in=(UserRole.HOD, UserRole.TEACHER)),
                    "email",
                    data["lead_teacher_email"],
                ),
            )

        return row.messages

    def check(self, data: dict, school_id: int) -> list[str]:
        if int(data["max_class_level"]) < int(data["min_class_level"]):
            return ["The max class level must be at or above the min class level."]

        return []

    def import_row(self, data: dict, school_id: int, actor) -> dict:
        if self._departments is None:
            self._departments = names_to_ids(Department.objects.filter(school_id=school_id), "name")

        subject = SubjectService.create(
            {
                "school_id": school_id,
                "department_id": self._departments.get(data["department"].strip().lower()),
                "code": data["code"],
                "name": data["name"],
                "min_class_level": int(data["min_class_level"]),
                "max_class_level": int(data["max_class_level"]),
                "lead_teacher_id": self._teacher_id(data.get("lead_teacher_email"), school_id),
            },
            actor,
        )

        return {"id": subject.id, "name": subject.name}

    def _teacher_id(self, email, school_id: int):
        if email is None:
            return None

        if self._teachers is None:
            self._teachers = names_to_ids(
                User.objects.filter(school_id=school_id, role__in=(UserRole.HOD, UserRole.TEACHER)), "email"
            )

        return self._teachers.get(email.strip().lower())


class VehicleImporter:
    def label(self) -> str:
        return "Vehicles"

    def headings(self) -> list[str]:
        return ["name", "registration_number", "capacity"]

    def sample(self) -> list[str]:
        return ["Bus 12", "MH 12 AB 3456", "42"]

    def unique_columns(self) -> list[str]:
        return ["registration_number"]

    def check_fields(self, data: dict, school_id: int) -> list[str]:
        row = Row(data)

        row.text("name", 50)

        if row.text("registration_number", 30):
            row.unique(
                "registration_number",
                Vehicle.objects.filter(school_id=school_id, registration_number=data["registration_number"]),
            )

        if row.present("capacity"):
            row.integer_between("capacity", 1, 200)

        return row.messages

    def check(self, data: dict, school_id: int) -> list[str]:
        return []

    def import_row(self, data: dict, school_id: int, actor) -> dict:
        vehicle = VehicleService.create({
            "school_id": school_id,
            "name": data["name"],
            "registration_number": data["registration_number"],
            "capacity": int(data["capacity"]),
        })

        return {"id": vehicle.id, "name": vehicle.name}


class DriverImporter:
    def label(self) -> str:
        return "Drivers"

    def headings(self) -> list[str]:
        return ["name", "mobile", "licence_number", "licence_expiry"]

    def sample(self) -> list[str]:
        return ["Ramesh Yadav", "+91 98765 43210", "MH1220260001234", "09/14/2029"]

    def unique_columns(self) -> list[str]:
        return ["licence_number"]

    def check_fields(self, data: dict, school_id: int) -> list[str]:
        row = Row(data)

        row.text("name", 150)

        if row.text("mobile", 20, is_required=False):
            row.phone("mobile")

        if row.text("licence_number", 50):
            row.unique("licence_number", Driver.objects.filter(school_id=school_id, licence_number=data["licence_number"]))

        if row.present("licence_expiry", is_required=False):
            row.input_date("licence_expiry")

        return row.messages

    def check(self, data: dict, school_id: int) -> list[str]:
        return []

    def import_row(self, data: dict, school_id: int, actor) -> dict:
        driver = DriverService.create({
            "school_id": school_id,
            "name": data["name"],
            "mobile": data.get("mobile"),
            "licence_number": data["licence_number"],
            "licence_expiry": to_iso(data.get("licence_expiry")),
        })

        return {"id": driver.id, "name": driver.name}
