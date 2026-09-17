"""The world the Flutter end-to-end tests run in.

    python manage.py integration_fixtures seed
    python manage.py integration_fixtures clean

One school, "Academy Integration Test School", with everybody the workflows in
CLAUDE.md §16 sign in as - all with the password "password" - and what each
of them needs to find waiting:

    itest-admin@example.com      School Admin   a class to admit into; a pending leave to approve
    itest-staff@example.com      Staff          the one whose leave is pending (in no department,
                                                so the HOD in the leave test never sees it)
    itest-teacher@example.com    Teacher        class teacher of Grade 8 A; a period today
    itest-hod@example.com        HOD            heads Science, which the teacher is in
    itest-transport@example.com  Transport Mgr  a route with a bus, a driver, a stop, two riders
    itest-root@example.com       Super Admin    the school to record a payment against

`seed` cleans first, so every run starts from the same place - a test that
approves "the" pending leave or starts "today's" trip can only do it once.

Refuses to run unless DEBUG is on: it creates accounts with a known password
and deletes a school, which is exactly what must never happen to a real
database. The Flutter tests also need today to be a working day at the school
- a weekday, not a holiday - because attendance, teaching reports and trips
all refuse the others.
"""

from __future__ import annotations

import datetime as dt

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from school import factories, hashing
from school.clock import SchoolClock
from school.enums import UserRole
from school.models import (
    AcademicYear,
    Announcement,
    Attendance,
    ClassSection,
    CommunicationSetting,
    DailyTeachingReport,
    Department,
    Driver,
    Holiday,
    Message,
    MessageTemplate,
    PasswordResetToken,
    Payment,
    Period,
    PersonalAccessToken,
    School,
    SchoolClass,
    StaffAttendance,
    StaffLeave,
    StaffProfile,
    Student,
    StudentTransportAssignment,
    Subject,
    SyllabusTopic,
    SyllabusTopicProgress,
    TimetableEntry,
    TransportRoute,
    TransportStop,
    TransportTrip,
    TransportTripEvent,
    TransportTripRider,
    User,
    Vehicle,
)

# Sorts first in every school picker, so a test never has to scroll a long
# menu to find it.
SCHOOL_NAME = "Academy Integration Test School"
PASSWORD = "password"
EMAILS = {
    "admin": "itest-admin@example.com",
    "teacher": "itest-teacher@example.com",
    "hod": "itest-hod@example.com",
    "staff": "itest-staff@example.com",
    "transport": "itest-transport@example.com",
    "root": "itest-root@example.com",
}
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday")


class Command(BaseCommand):
    help = "Seed or clean the fixtures the Flutter integration tests sign in to."

    def add_arguments(self, parser):
        parser.add_argument("action", choices=("seed", "clean"))

    def handle(self, *args, action, **options):
        if not settings.DEBUG:
            raise CommandError("Refusing to run with DEBUG off: this creates accounts with a known password.")

        with transaction.atomic():
            clean()

            if action == "seed":
                school = seed()
                today = SchoolClock.for_school(school).now().date()
                self.stdout.write(f"Seeded school #{school.id}; today at the school is {today:%A %Y-%m-%d}.")

                if today.weekday() >= 5:
                    self.stdout.write(self.style.WARNING("Today is a weekend: attendance, reports and trips will refuse it."))
            else:
                self.stdout.write("Cleaned up integration test fixtures.")


def seed() -> School:
    school = factories.SchoolFactory(name=SCHOOL_NAME, email="itest-school@example.com", currency_code="INR")
    password = hashing.make(PASSWORD)

    def person(key, role, first, last, school=school):
        return factories.UserFactory(
            email=EMAILS[key], password=password, role=role, school=school, first_name=first, last_name=last
        )

    person("admin", UserRole.SCHOOL_ADMIN, "Asha", "Admin")
    teacher = person("teacher", UserRole.TEACHER, "Tara", "Teacher")
    hod = person("hod", UserRole.HOD, "Harish", "Head")
    clerk = person("staff", UserRole.STAFF, "Sunil", "Staff")
    person("transport", UserRole.TRANSPORT_MANAGER, "Tomas", "Transport")
    person("root", UserRole.SUPER_ADMIN, "Rhea", "Root", school=None)

    science = factories.DepartmentFactory(school=school, name="Science", hod_user=hod)
    factories.StaffProfileFactory(user=hod, department=science, employee_id="ITEST-HOD")
    factories.StaffProfileFactory(user=teacher, department=science, employee_id="ITEST-TEACHER")
    clerk_profile = factories.StaffProfileFactory(user=clerk, department=None, employee_id="ITEST-STAFF", designation="Clerk")

    year = factories.AcademicYearFactory(school=school, name="2026-27", is_current=True)
    section = factories.ClassSectionFactory(
        school_class=factories.SchoolClassFactory(academic_year=year, school=school, name="Grade 8", level=8),
        name="A",
        class_teacher=teacher,
    )
    students = [
        factories.StudentFactory(class_section=section, first_name=first, last_name=last, admission_number=f"ITEST-{n}")
        for n, (first, last) in enumerate((("Aarav", "Sharma"), ("Bina", "Kapoor"), ("Chetan", "Rao")), start=1)
    ]

    # A period on today's weekday, so the teacher has something to report on.
    today = SchoolClock.for_school(school).now().date()
    subject = factories.SubjectFactory(department=science, name="Physics", code="ITEST-PHY")
    factories.TimetableEntryFactory(
        class_section=section,
        period=factories.PeriodFactory(school=school, period_number=1),
        subject=subject,
        teacher=teacher,
        day_of_week=WEEKDAYS[min(today.weekday(), 4)],
    )

    # A leave waiting for the admin, far enough ahead not to collide with the
    # leave the teacher applies for today in the leave test.
    start = today + dt.timedelta(days=14)
    factories.StaffLeaveFactory(
        staff_profile=clerk_profile, status="pending", leave_type="casual", start_date=start, end_date=start,
        reason="Integration test: waiting for the admin",
    )

    vehicle = factories.VehicleFactory(school=school, name="ITest Bus", registration_number="ITEST-BUS-1")
    driver = factories.DriverFactory(school=school, name="Dev Driver", licence_number="ITEST-DL-1")
    route = factories.TransportRouteFactory(school=school, name="ITest Route", vehicle=vehicle, driver=driver)
    stop = factories.TransportStopFactory(route=route, name="Main Gate", sequence_number=1)
    now = timezone.now()
    for student in students[:2]:
        StudentTransportAssignment.objects.create(
            school=school, student=student, route=route, transport_stop=stop, created_at=now, updated_at=now
        )

    return school


def clean() -> None:
    """Everything a run could have left behind, in the order foreign keys
    allow - the schema has no cascades to lean on."""
    users = list(User.objects.filter(email__in=EMAILS.values()).values_list("id", flat=True))
    schools = list(School.objects.filter(name=SCHOOL_NAME).values_list("id", flat=True))

    if not users and not schools:
        return

    in_school = Q(school_id__in=schools)
    trips = TransportTrip.objects.filter(in_school)
    students = Student.objects.filter(in_school)
    profiles = StaffProfile.objects.filter(Q(school_id__in=schools) | Q(user_id__in=users))
    sections = ClassSection.objects.filter(school_class__school_id__in=schools)

    TransportTripEvent.objects.filter(Q(trip__in=trips) | Q(school_id__in=schools)).delete()
    TransportTripRider.objects.filter(trip__in=trips).delete()
    trips.delete()
    StudentTransportAssignment.objects.filter(in_school).delete()
    TransportStop.objects.filter(in_school).delete()
    TransportRoute.objects.filter(in_school).delete()
    Vehicle.objects.filter(in_school).delete()
    Driver.objects.filter(in_school).delete()

    Message.objects.filter(Q(school_id__in=schools) | Q(user_id__in=users) | Q(created_by_id__in=users)).delete()
    Announcement.objects.filter(Q(school_id__in=schools) | Q(published_by_id__in=users)).delete()
    MessageTemplate.objects.filter(in_school).delete()
    CommunicationSetting.objects.filter(in_school).delete()

    Attendance.objects.filter(Q(school_id__in=schools) | Q(marked_by_id__in=users)).delete()
    StaffAttendance.objects.filter(Q(school_id__in=schools) | Q(staff_profile__in=profiles)).delete()
    StaffLeave.objects.filter(Q(school_id__in=schools) | Q(staff_profile__in=profiles)).delete()
    DailyTeachingReport.objects.filter(Q(school_id__in=schools) | Q(teacher_id__in=users)).delete()
    SyllabusTopicProgress.objects.filter(in_school).delete()
    SyllabusTopic.objects.filter(in_school).delete()
    TimetableEntry.objects.filter(Q(school_id__in=schools) | Q(teacher_id__in=users)).delete()
    Period.objects.filter(in_school).delete()
    Subject.objects.filter(in_school).delete()
    students.delete()
    sections.delete()
    SchoolClass.objects.filter(in_school).delete()
    AcademicYear.objects.filter(in_school).delete()
    Holiday.objects.filter(in_school).delete()
    profiles.delete()
    Department.objects.filter(in_school).delete()
    Payment.objects.filter(Q(school_id__in=schools) | Q(created_by_id__in=users)).delete()

    PersonalAccessToken.objects.filter(tokenable_id__in=users).delete()
    PasswordResetToken.objects.filter(email__in=EMAILS.values()).delete()
    User.objects.filter(Q(id__in=users) | Q(school_id__in=schools)).delete()
    School.objects.filter(id__in=schools).delete()
