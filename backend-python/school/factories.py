"""Test data, the way Laravel's factories make it.

The Laravel suite has 31 of these and leans on them in almost every test; the
Python suite will do the same, so they arrive with the skeleton rather than
being invented one at a time as each module is ported.

Everything defaults to something valid, and any of it can be overridden -
`SchoolFactory(name="St Mary's North", parent_school=group)` reads the same way
`School::factory()->branchOf($group)` does, which matters because these tests
are being written by people holding the old ones in their heads.
"""

from __future__ import annotations

import datetime as dt

import factory
# Imported as a bare name, not as `timezone`: SchoolFactory has a field
# called `timezone`, and inside a class body that shadows the module - so
# `timezone.now` would resolve to the string "Asia/Kolkata".
from django.utils.timezone import now
from factory.django import DjangoModelFactory

from . import hashing, models

# Anything this suite writes is throwaway, and the password is only ever set on
# a row that a test created. It is not a credential for anything.
#
# Hashed once, at import, and shared by every account the factories build.
# Laravel's cost of 12 takes about a fifth of a second, and a suite that hashed
# per user would spend most of its runtime doing it - but hashing it for real
# is what lets the auth tests sign in, which a placeholder could not.
TEST_PASSWORD = "FactoryPassword!2026"
TEST_PASSWORD_HASH = hashing.make(TEST_PASSWORD)


class SchoolFactory(DjangoModelFactory):
    class Meta:
        model = models.School

    name = factory.Sequence(lambda n: f"Test School {n}")
    email = factory.Sequence(lambda n: f"school{n}@example.invalid")
    phone = "+91 9000000000"
    address = "1 Test Road"
    city = "Testville"
    state = "Testing"
    country = "India"
    postal_code = "000000"
    currency_code = "INR"
    timezone = "Asia/Kolkata"
    status = "active"

    # Null for a standalone school, which is most of them. A branch is made by
    # passing the parent: SchoolFactory(parent_school=group). See
    # ../../docs/branches.md - a branch is a school row with a parent, and
    # nothing else distinguishes it.
    parent_school = None

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class UserFactory(DjangoModelFactory):
    class Meta:
        model = models.User

    first_name = "Test"
    last_name = factory.Sequence(lambda n: f"User {n}")
    email = factory.Sequence(lambda n: f"user{n}@example.invalid")
    password = TEST_PASSWORD_HASH
    mobile = None
    role = "SCHOOL_ADMIN"
    status = "active"
    is_sub_admin = False
    must_change_password = False
    school = factory.SubFactory(SchoolFactory)

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class DepartmentFactory(DjangoModelFactory):
    class Meta:
        model = models.Department

    school = factory.SubFactory(SchoolFactory)
    name = factory.Sequence(lambda n: f"Department {n}")
    hod_user = None

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class StaffProfileFactory(DjangoModelFactory):
    class Meta:
        model = models.StaffProfile

    # The login and the employment record are created together, the way the
    # Add Employee screen does it - a profile without an account is somebody
    # who exists on a roster and cannot sign in.
    user = factory.SubFactory(UserFactory, role="TEACHER")
    school = factory.LazyAttribute(lambda o: o.user.school)
    employee_id = factory.Sequence(lambda n: f"EMP-{n:04d}")
    department = None
    designation = "Teacher"
    joining_date = dt.date(2026, 4, 1)
    address = None

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class AcademicYearFactory(DjangoModelFactory):
    class Meta:
        model = models.AcademicYear

    school = factory.SubFactory(SchoolFactory)
    name = factory.Sequence(lambda n: f"20{26 + n % 5}-{27 + n % 5}")
    start_date = dt.date(2026, 4, 1)
    end_date = dt.date(2027, 3, 31)
    is_current = True

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class SchoolClassFactory(DjangoModelFactory):
    class Meta:
        model = models.SchoolClass

    academic_year = factory.SubFactory(AcademicYearFactory)
    school = factory.LazyAttribute(lambda o: o.academic_year.school)
    name = factory.Sequence(lambda n: f"Grade {n % 12 + 1}")
    level = factory.Sequence(lambda n: n % 12 + 1)

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class ClassSectionFactory(DjangoModelFactory):
    class Meta:
        model = models.ClassSection

    school_class = factory.SubFactory(SchoolClassFactory)
    name = "A"
    room_number = None
    class_teacher = None

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class StudentFactory(DjangoModelFactory):
    class Meta:
        model = models.Student

    class_section = factory.SubFactory(ClassSectionFactory)
    school = factory.LazyAttribute(lambda o: o.class_section.school_class.school)
    admission_number = factory.Sequence(lambda n: f"STU-{n:04d}")
    first_name = "Aarav"
    last_name = factory.Sequence(lambda n: f"Sharma {n}")
    roll_number = None
    guardian_name = "Meera Sharma"
    guardian_mobile = None
    address = None
    status = "active"

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class StaffLeaveFactory(DjangoModelFactory):
    class Meta:
        model = models.StaffLeave

    staff_profile = factory.SubFactory(StaffProfileFactory)
    school = factory.LazyAttribute(lambda o: o.staff_profile.school)
    leave_type = "casual"
    start_date = dt.date(2026, 9, 21)
    end_date = dt.date(2026, 9, 22)
    reason = "Family function."
    status = "pending"
    applied_by = factory.LazyAttribute(lambda o: o.staff_profile.user)
    reviewed_by = None
    review_remarks = None

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class PeriodFactory(DjangoModelFactory):
    class Meta:
        model = models.Period

    school = factory.SubFactory(SchoolFactory)
    period_number = factory.Sequence(lambda n: n % 8 + 1)
    start_time = dt.time(9, 0)
    end_time = dt.time(9, 45)

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class SubjectFactory(DjangoModelFactory):
    class Meta:
        model = models.Subject

    department = factory.SubFactory(DepartmentFactory)
    school = factory.LazyAttribute(lambda o: o.department.school)
    code = factory.Sequence(lambda n: f"SUB{n:03d}")
    name = "Mathematics"
    min_class_level = 1
    max_class_level = 12
    lead_teacher = None

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class TimetableEntryFactory(DjangoModelFactory):
    class Meta:
        model = models.TimetableEntry

    class_section = factory.SubFactory(ClassSectionFactory)
    school = factory.LazyAttribute(lambda o: o.class_section.school_class.school)
    period = factory.SubFactory(PeriodFactory)
    day_of_week = "monday"
    subject = factory.SubFactory(SubjectFactory)
    teacher = factory.SubFactory(UserFactory, role="TEACHER")

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class DailyTeachingReportFactory(DjangoModelFactory):
    class Meta:
        model = models.DailyTeachingReport

    timetable_entry = factory.SubFactory(TimetableEntryFactory)
    school = factory.LazyAttribute(lambda o: o.timetable_entry.school)
    teacher = factory.LazyAttribute(lambda o: o.timetable_entry.teacher)
    report_date = dt.date(2026, 9, 14)
    topic_taught = "Linear equations"
    homework = None
    remarks = None
    reviewed_by = None
    reviewed_at = None

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class SyllabusTopicFactory(DjangoModelFactory):
    class Meta:
        model = models.SyllabusTopic

    subject = factory.SubFactory(SubjectFactory)
    school = factory.LazyAttribute(lambda o: o.subject.school)
    title = factory.Sequence(lambda n: f"Chapter {n}")
    sequence_number = factory.Sequence(lambda n: n + 1)

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class MessageFactory(DjangoModelFactory):
    class Meta:
        model = models.Message

    school = factory.SubFactory(SchoolFactory)
    event = "leave.approved"
    category = "leave"
    channel = "sms"
    recipient_name = "Rahul Verma"
    recipient_mobile = "+919800000001"
    user = None
    student = None
    student_name = None
    body = "Your casual leave from 09/07/2026 to 09/08/2026 has been approved."
    status = "sent"
    provider = "log"
    failure_reason = None
    created_by = None
    sent_at = factory.LazyFunction(now)
    read_at = None
    announcement = None
    subject = None

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class VehicleFactory(DjangoModelFactory):
    class Meta:
        model = models.Vehicle

    school = factory.SubFactory(SchoolFactory)
    name = factory.Sequence(lambda n: f"Bus {n}")
    registration_number = factory.Sequence(lambda n: f"KA-01-{n:04d}")
    capacity = 40
    status = "active"

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class DriverFactory(DjangoModelFactory):
    class Meta:
        model = models.Driver

    school = factory.SubFactory(SchoolFactory)
    name = factory.Sequence(lambda n: f"Driver {n}")
    mobile = "+91 9876543210"
    licence_number = factory.Sequence(lambda n: f"DL-{n:05d}")
    licence_expiry = None
    status = "active"

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class TransportRouteFactory(DjangoModelFactory):
    class Meta:
        model = models.TransportRoute

    school = factory.SubFactory(SchoolFactory)
    name = factory.Sequence(lambda n: f"Route {n}")
    vehicle = None
    driver = None
    status = "active"

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)


class TransportStopFactory(DjangoModelFactory):
    class Meta:
        model = models.TransportStop

    route = factory.SubFactory(TransportRouteFactory)
    school = factory.LazyAttribute(lambda o: o.route.school)
    name = factory.Sequence(lambda n: f"Stop {n}")
    sequence_number = factory.Sequence(lambda n: n + 1)
    pickup_time = None
    drop_time = None

    created_at = factory.LazyFunction(now)
    updated_at = factory.LazyFunction(now)
