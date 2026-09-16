"""The data the contract tests need, built through the API itself.

A contract suite that only speaks HTTP cannot seed a database, and should not
want to: needing database access to set up would tie it to one backend's
schema, which is the thing it exists not to be tied to. So it creates what it
needs through the same endpoints it is testing.

That has a pleasant side effect. Setting up exercises the write endpoints for
real, so a backend that cannot create a school fails before a single assertion
about reading one.

**This suite needs a disposable database, and refuses to run without being told
it has one.**

It creates schools, accounts, classes and students, and it cannot remove them
afterwards. That is not an oversight here - the API has no delete-a-school
endpoint on purpose, because erasing a school's records is not something a
school management system should offer. Deactivating is as far as any caller can
go, so every run leaves data behind for good.

Which makes pointing this at a database anybody cares about a one-way mistake.
See README.md for how to stand up a throwaway one.
"""

from __future__ import annotations

import os
import random
import string
from dataclasses import dataclass, field

from client import Client, base_url, sign_in

SUPER_ADMIN_EMAIL = os.environ.get("CONTRACT_SUPER_ADMIN_EMAIL", "")
SUPER_ADMIN_PASSWORD = os.environ.get("CONTRACT_SUPER_ADMIN_PASSWORD", "")

# Every account this suite creates gets this password. It only ever exists on
# throwaway records in a throwaway database.
TEST_PASSWORD = "ContractSuite!2026"

REFUSAL = """Refusing to run against {url}.

This suite creates schools, accounts and students and CANNOT remove them: the
API has no delete-a-school endpoint, by design. Every run leaves records behind
permanently.

Point it at a throwaway database - never a development one you use, and never
production - then set CONTRACT_DISPOSABLE_DB=yes.

contract/README.md has a recipe for standing one up."""


def _tag() -> str:
    """A suffix that keeps two runs from colliding."""
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=8))


def guard_the_target() -> None:
    """Refuse to run against a database whose contents matter.

    Deliberately not satisfied by "it is localhost". The first time this suite
    ran it was pointed at a perfectly ordinary local development database and
    left four schools, four accounts and three students in it that no endpoint
    could remove. The guard has to be about what the database is *for*, not
    where it happens to live.
    """
    if os.environ.get("CONTRACT_DISPOSABLE_DB") != "yes":
        raise AssertionError(REFUSAL.format(url=base_url()))


def require_credentials() -> None:
    if not SUPER_ADMIN_EMAIL or not SUPER_ADMIN_PASSWORD:
        raise AssertionError(
            "Set CONTRACT_SUPER_ADMIN_EMAIL and CONTRACT_SUPER_ADMIN_PASSWORD. "
            "The suite signs in as a Super Admin to create the school it works in."
        )


@dataclass
class World:
    """Two unrelated schools, their people, and the clients that speak for them."""

    super_admin: Client
    school_id: int
    admin: Client
    admin_email: str
    other_school_id: int
    other_admin: Client
    academic_year_id: int
    department_id: int
    staff_profile_id: int
    staff_email: str
    staff_client: Client
    school_class_id: int
    class_section_id: int
    student_id: int
    created_user_ids: list[int] = field(default_factory=list)


def build() -> World:
    """Two schools, so isolation can be asserted rather than hoped."""
    guard_the_target()
    require_credentials()

    root = sign_in(SUPER_ADMIN_EMAIL, SUPER_ADMIN_PASSWORD)
    tag = _tag()

    school_id = _make_school(root, "Contract School " + tag)
    other_school_id = _make_school(root, "Contract Outsider " + tag)

    admin_email = "contract.admin." + tag + "@example.invalid"
    admin_id = _make_admin(root, school_id, admin_email)

    other_email = "contract.outsider." + tag + "@example.invalid"
    other_id = _make_admin(root, other_school_id, other_email)

    admin = sign_in(admin_email, TEST_PASSWORD)
    other_admin = sign_in(other_email, TEST_PASSWORD)

    department_id = _make_department(admin, school_id, tag)
    staff_email = "contract.staff." + tag + "@example.invalid"
    staff_id = _make_staff(admin, school_id, department_id, tag, staff_email)
    staff_client = sign_in(staff_email, TEST_PASSWORD)
    year_id, class_id, section_id = _make_class_section(admin, school_id, tag)
    student_id = _make_student(admin, school_id, section_id, tag)

    return World(
        super_admin=root,
        school_id=school_id,
        admin=admin,
        admin_email=admin_email,
        other_school_id=other_school_id,
        other_admin=other_admin,
        academic_year_id=year_id,
        department_id=department_id,
        staff_profile_id=staff_id,
        staff_email=staff_email,
        staff_client=staff_client,
        school_class_id=class_id,
        class_section_id=section_id,
        student_id=student_id,
        created_user_ids=[admin_id, other_id],
    )


_SHARED: World | None = None


def shared() -> World:
    """One world for the whole run, however many files ask for it.

    Building per file looked tidier and is not: every build signs in three
    times, login is rate limited at five a minute per address, and a suite
    that grows past two files starts failing with 429s that look like the
    backend refusing perfectly good credentials.

    It also means the schools, classes and accounts each run leaves behind
    stay a fixed handful rather than multiplying by the number of test files.
    """
    global _SHARED

    if _SHARED is None:
        _SHARED = build()

    return _SHARED


def demolish(world: World) -> None:
    """Deactivate what was built. It cannot be deleted.

    This is as far as the API goes, and saying so plainly is better than a
    teardown that looks thorough and is not: an earlier version of this called
    DELETE /schools/{id} - a route that does not exist - and ignored the
    answer, so everything it claimed to clean up was still sitting there.

    The records stay. That is what guard_the_target() is protecting.
    """
    for school_id in (world.school_id, world.other_school_id):
        response = world.super_admin.patch("/schools/" + str(school_id) + "/deactivate")

        if response.status != 200:
            print("  note: could not deactivate school " + str(school_id) + " (HTTP " + str(response.status) + ")")


# -- the individual steps, each failing loudly -------------------------------


def _created(response, what: str) -> dict:
    if response.status not in (200, 201):
        raise AssertionError("Could not create " + what + ": HTTP " + str(response.status) + " " + str(response.body))
    return response.body


def _make_school(root: Client, name: str) -> int:
    body = _created(
        root.post(
            "/schools",
            {
                "name": name,
                "email": name.lower().replace(" ", ".") + "@example.invalid",
                "phone": "+91 9000000000",
                "address": "1 Contract Road",
                "city": "Testville",
                "state": "Testing",
                "country": "India",
                "postal_code": "000000",
                "currency_code": "INR",
                "timezone": "Asia/Kolkata",
            },
        ),
        "the school " + name,
    )

    return body["id"]


def _make_admin(root: Client, school_id: int, email: str) -> int:
    body = _created(
        root.post(
            "/users",
            {
                "first_name": "Contract",
                "last_name": "Admin",
                "email": email,
                "password": TEST_PASSWORD,
                "role": "SCHOOL_ADMIN",
                "school_id": school_id,
            },
        ),
        "the admin " + email,
    )

    return body["id"]


def _make_department(admin: Client, school_id: int, tag: str) -> int:
    """A subject has to belong to one, so the world needs one before it can
    have subjects."""
    body = _created(
        admin.post("/departments", {"school_id": school_id, "name": "Contract Dept " + tag}),
        "a department",
    )

    return body["id"]


def _make_staff(admin: Client, school_id: int, department_id: int, tag: str, email: str) -> int:
    """One employee, so leave and staff attendance have somebody to be about.

    In the world rather than in a test, because tests run in whatever order the
    loader chooses: a leave test that depends on a staff test having run first
    passes or skips depending on the alphabet.
    """
    body = _created(
        admin.post(
            "/staff",
            {
                "school_id": school_id,
                "first_name": "Rahul",
                "last_name": "Verma",
                "email": email,
                "password": TEST_PASSWORD,
                "role": "TEACHER",
                "employee_id": "EMP-" + tag[:6].upper(),
                "department_id": department_id,
                "designation": "Teacher",
                "joining_date": "2026-04-01",
            },
        ),
        "an employee",
    )

    return body["id"]


def _make_class_section(admin: Client, school_id: int, tag: str) -> tuple[int, int, int]:
    """The year, the class and the section - all three, because the academic
    tests need to hang things off each of them."""
    year = _created(
        admin.post(
            "/academic-years",
            {
                "school_id": school_id,
                "name": "2026-27 " + tag,
                "start_date": "2026-04-01",
                "end_date": "2027-03-31",
                "is_current": True,
            },
        ),
        "an academic year",
    )

    school_class = _created(
        admin.post(
            "/classes",
            {
                "school_id": school_id,
                "academic_year_id": year["id"],
                "name": "Grade " + tag[:2],
                "level": 8,
            },
        ),
        "a class",
    )

    # Sections are their own endpoint rather than an array on the class: a
    # class is created first and then filled, the way a school actually does it.
    section = _created(
        admin.post("/classes/" + str(school_class["id"]) + "/sections", {"name": "A"}),
        "a class section",
    )

    return year["id"], school_class["id"], section["id"]


def _make_student(admin: Client, school_id: int, section_id: int, tag: str) -> int:
    body = _created(
        admin.post(
            "/students",
            {
                "school_id": school_id,
                "class_section_id": section_id,
                "admission_number": "CON-" + tag[:6].upper(),
                "first_name": "Aarav",
                "last_name": "Sharma",
                "guardian_name": "Meera Sharma",
            },
        ),
        "a student",
    )

    return body["id"]
