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
    itest-accountant@example.com Accountant     staff to set salaries for and run payroll on
    Bus Attendant (+91 90000 77777, no email)   runs ITest Route; signs in on a phone
                                                with the setup code 24681357

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

from school import attendants, factories, hashing
from school.clock import SchoolClock
from school.enums import UserRole
from school.models import (
    AttendantCredential,
    AttendantDevice,
    TransportTripLocation,
    AcademicYear,
    AuditLog,
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
    WhatsappTemplate,
    PasswordResetToken,
    Payment,
    PayrollRun,
    Payslip,
    PayslipLine,
    Period,
    PersonalAccessToken,
    SalaryComponent,
    SalaryProfile,
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
ATTENDANT_MOBILE = "+91 90000 77777"
ATTENDANT_SETUP_CODE = "24681357"

EMAILS = {
    "admin": "itest-admin@example.com",
    "teacher": "itest-teacher@example.com",
    "hod": "itest-hod@example.com",
    "staff": "itest-staff@example.com",
    "transport": "itest-transport@example.com",
    "root": "itest-root@example.com",
    "accountant": "itest-accountant@example.com",
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
    accountant = person("accountant", UserRole.ACCOUNTANT, "Anita", "Accountant")

    science = factories.DepartmentFactory(school=school, name="Science", hod_user=hod)
    factories.StaffProfileFactory(user=hod, department=science, employee_id="ITEST-HOD")
    factories.StaffProfileFactory(user=teacher, department=science, employee_id="ITEST-TEACHER")
    clerk_profile = factories.StaffProfileFactory(user=clerk, department=None, employee_id="ITEST-STAFF", designation="Clerk")
    factories.StaffProfileFactory(user=accountant, department=None, employee_id="ITEST-ACC", designation="Accountant")

    year = factories.AcademicYearFactory(school=school, name="2026-27", is_current=True)
    section = factories.ClassSectionFactory(
        school_class=factories.SchoolClassFactory(academic_year=year, school=school, name="Grade 8", level=8),
        name="A",
        class_teacher=teacher,
    )
    # With a guardian's number and address, so the Send Message dialog and the
    # email channel have somebody to reach in the demo.
    students = [
        factories.StudentFactory(
            class_section=section, first_name=first, last_name=last, admission_number=f"ITEST-{n}",
            guardian_mobile=f"+91 90000000{n:02d}", guardian_email=f"itest-guardian{n}@example.com",
        )
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
    # The Bus Attendant who runs the route, with no email and a setup code
    # the attendant flow types in to register its phone (docs/maps.md).
    attendant = factories.UserFactory(
        email=attendants.placeholder_email(), password=password, role=UserRole.BUS_ATTENDANT, school=school,
        first_name="Ravi", last_name="Attendant", mobile=ATTENDANT_MOBILE,
    )
    factories.StaffProfileFactory(school=school, user=attendant, employee_id="ITEST-ATT", designation="Bus Attendant")
    now = timezone.now()
    AttendantCredential.objects.create(
        user=attendant, school=school, login_mobile=attendants.login_mobile(ATTENDANT_MOBILE),
        setup_code=hashing.make(ATTENDANT_SETUP_CODE), setup_code_expires_at=now + dt.timedelta(days=1),
        failed_attempts=0, created_at=now, updated_at=now,
    )

    route = factories.TransportRouteFactory(
        school=school, name="ITest Route", vehicle=vehicle, driver=driver, attendant_user=attendant
    )
    stop = factories.TransportStopFactory(route=route, name="Main Gate", sequence_number=1)
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

    runs = PayrollRun.objects.filter(in_school)
    PayslipLine.objects.filter(payslip__payroll_run__in=runs).delete()
    Payslip.objects.filter(Q(payroll_run__in=runs) | Q(school_id__in=schools)).delete()
    runs.delete()
    SalaryComponent.objects.filter(salary_profile__school_id__in=schools).delete()
    SalaryProfile.objects.filter(in_school).delete()
    AuditLog.objects.filter(Q(school_id__in=schools) | Q(user_id__in=users)).delete()

    TransportTripLocation.objects.filter(Q(trip__in=trips) | Q(school_id__in=schools)).delete()
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
    WhatsappTemplate.objects.filter(in_school).delete()
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

    school_users = list(User.objects.filter(school_id__in=schools).values_list("id", flat=True))
    AttendantDevice.objects.filter(user_id__in=users + school_users).delete()
    AttendantCredential.objects.filter(Q(user_id__in=users + school_users) | Q(school_id__in=schools)).delete()
    PersonalAccessToken.objects.filter(tokenable_id__in=users + school_users).delete()
    PasswordResetToken.objects.filter(email__in=EMAILS.values()).delete()
    User.objects.filter(Q(id__in=users) | Q(school_id__in=schools)).delete()
    School.objects.filter(id__in=schools).delete()
