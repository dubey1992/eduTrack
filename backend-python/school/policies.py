"""Who may do what.

The Python half of app/Policies. Named `policies` rather than `permissions`
because these are ports of specific Laravel policies and reading the two side
by side is how they get reviewed - the migration plan calls this the dangerous
part, since every mistake here is one school reading another's records.

A policy answers a question and returns a bool. Raising the 403 is the view's
job, through `authorize()`, so the same policy can be asked without an
exception when a caller only wants to know.

**Two layers, since the permissions matrix (docs/settings.md).** Whether a
role may read or write a module is the matrix's answer, asked through
`permitted()`; it also refuses outright, with its own error, when the module
is switched off for the school in question. *Which* records the role reaches
- a teacher's own classes, a head's own department, an admin's own school
or group - is still decided here, in code, because that is knowledge about
the data rather than about roles. The matrix's defaults reproduce what these
policies allowed before it existed, so every ALLOW and DENY test in
tests/test_policies.py still holds with an empty matrix (CLAUDE.md rule 11).
"""

from __future__ import annotations

from rest_framework.exceptions import PermissionDenied

from . import modules, permissions
from .enums import PayrollRunStatus, UserRole
from .errors import ModuleDisabled
from .models import Department, Student, Subject, TimetableEntry, User
from .scope import SchoolScope

ADMIN_ROLES = (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN)


def authorize(allowed: bool) -> None:
    """Turns a policy's answer into the 403 the client expects."""
    if not allowed:
        raise PermissionDenied()


def permitted(actor: User, module: str, *, write: bool = False, school_id=None) -> bool:
    """The matrix's answer for this role and module - and, first, whether the
    module is on at all for the school concerned.

    `school_id` is the school the record belongs to; when a policy has no
    record yet (creating one, listing), the actor's own school is the one
    that matters. A switched-off module is refused with its own error so the
    app can say so, rather than a bare "not allowed".
    """
    concerned = school_id if school_id is not None else actor.school_id

    if not modules.is_enabled(concerned, module):
        raise ModuleDisabled(modules.get(module).label)

    return permissions.may_manage(actor, module) if write else permissions.may_view(actor, module)


def in_scope(actor: User, school_id) -> bool:
    """Whether the school is one the actor answers for: any school for a
    Super Admin, the group for its admins, their own for everybody else."""
    return actor.role == UserRole.SUPER_ADMIN or SchoolScope.for_actor(actor).allows(school_id)


def administers(actor: User) -> bool:
    return actor.role == UserRole.SUPER_ADMIN or UserRole.administers_school(actor.role)


class SchoolPolicy:
    """Schools are platform-level records - only SUPER_ADMIN manages them.

    A SCHOOL_ADMIN may view any school in their own group (the school details
    screen and the branch pickers need it) but never one outside it, and never
    edits the school record itself.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        # An admin who answers for several branches lists them so they can
        # pick one. Asked of the scope rather than the role, because a School
        # Admin has branches to pick from only when their school is in a
        # group; a standalone one has nothing to choose and is refused.
        return actor.role == UserRole.SUPER_ADMIN or SchoolScope.for_actor(actor).covers_a_group()

    @staticmethod
    def view(actor: User, school) -> bool:
        return actor.role == UserRole.SUPER_ADMIN or SchoolScope.for_actor(actor).allows(school.id)

    @staticmethod
    def create(actor: User) -> bool:
        return actor.role == UserRole.SUPER_ADMIN

    @staticmethod
    def update(actor: User, school=None) -> bool:
        return actor.role == UserRole.SUPER_ADMIN

    @staticmethod
    def set_status(actor: User, school=None) -> bool:
        return actor.role == UserRole.SUPER_ADMIN


class SchoolOwnedPolicy:
    """The shape most school-owned records share - the academic set-up.

    Admins manage their own school's records; everybody else may read them.
    Departments, subjects, classes, periods and holidays all answer exactly
    this, and writing it five times is how one of them quietly ends up
    different from the other four.

    Subclasses exist so a call site names the thing it is asking about, and so
    a record that later needs its own rule has somewhere to put it.
    """

    MODULE = "academics"

    @classmethod
    def view_any(cls, actor: User) -> bool:
        return permitted(actor, cls.MODULE)

    @classmethod
    def view(cls, actor: User, record) -> bool:
        return permitted(actor, cls.MODULE, school_id=record.school_id) and in_scope(actor, record.school_id)

    @classmethod
    def create(cls, actor: User) -> bool:
        return permitted(actor, cls.MODULE, write=True)

    @classmethod
    def update(cls, actor: User, record) -> bool:
        return cls._manages(actor, record)

    @classmethod
    def delete(cls, actor: User, record) -> bool:
        return cls._manages(actor, record)

    @classmethod
    def _manages(cls, actor: User, record) -> bool:
        return permitted(actor, cls.MODULE, write=True, school_id=record.school_id) and in_scope(
            actor, record.school_id
        )


class DepartmentPolicy(SchoolOwnedPolicy):
    """Departments, plus the department report the HOD screens need.

    The report is the one place this diverges: an admin sees any department of
    their school, an HOD only the ones they actually head.
    """

    @staticmethod
    def view_any_report(actor: User) -> bool:
        return permitted(actor, "hod")

    @staticmethod
    def view_report(actor: User, department) -> bool:
        if not permitted(actor, "hod", school_id=department.school_id):
            return False

        if not in_scope(actor, department.school_id):
            return False

        if actor.role == UserRole.HOD:
            return department.hod_user_id == actor.id

        return True


class SubjectPolicy(SchoolOwnedPolicy):
    pass


class StaffAttendancePolicy:
    """Who marks the staff register.

    An HOD marks it as well as an admin, which is the one place in the
    product an HOD writes something outside their own record - they run a
    department and its register is theirs. *Which* staff they may mark is
    narrowed to their own departments by the service, not here.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return permitted(actor, "staff_attendance")

    @staticmethod
    def manage(actor: User, school_id) -> bool:
        return permitted(actor, "staff_attendance", write=True, school_id=school_id) and in_scope(actor, school_id)


class StaffLeavePolicy:
    """Applying and reviewing, deliberately two abilities.

    Unlike the staff register's single `manage`: applying is self-service for
    anyone with an employment record, reviewing is an action on somebody
    else's request, and one actor is never both for the same leave.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        """What a role actually gets back is narrowed by
        StaffLeaveService.visible_to - own, department, school, everything -
        so the gate here is only the matrix's."""
        return permitted(actor, "leave")

    @staticmethod
    def apply(actor: User) -> bool:
        """Whether the actor has a StaffProfile to apply against is a data
        precondition, not an authorization question - the view answers that
        separately, with a sentence naming the fix.

        A Super Admin or Group Admin never applies - there is no one school
        to apply against.
        """
        if actor.role in (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN):
            return False

        return permitted(actor, "leave", write=True)

    @staticmethod
    def review(actor: User, leave) -> bool:
        if not permitted(actor, "leave", write=True, school_id=leave.school_id):
            return False

        # An HOD heads the department they belong to, so without this line
        # they would pass the department check below for their own request.
        # Nobody reviews their own leave, whatever their role.
        profile = actor.staff_profile

        if profile is not None and leave.staff_profile_id == profile.id:
            return False

        if administers(actor):
            return in_scope(actor, leave.school_id)

        if actor.role == UserRole.HOD:
            applicant = leave.staff_profile

            return (
                applicant is not None
                and applicant.department_id is not None
                and applicant.department.hod_user_id == actor.id
            )

        # Every other role's "manage" is applying for their own leave.
        return False


class TimetableEntryPolicy:
    """The grid: everybody reads it, admins edit it.

    Reading is open by role because a teacher needs the grid to find their own
    schedule; *whose* grid they get is checked against the target's school in
    the view.

    `manage` is asked about a school rather than an entry because an upsert
    may be creating the first one for that cell.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return permitted(actor, "timetable")

    @staticmethod
    def manage(actor: User, school_id) -> bool:
        return permitted(actor, "timetable", write=True, school_id=school_id) and in_scope(actor, school_id)

    @classmethod
    def delete(cls, actor: User, entry) -> bool:
        return cls.manage(actor, entry.school_id)


class DailyTeachingReportPolicy:
    """Filing and reviewing, deliberately two abilities - the same split as
    leave. Filing is self-service for whoever taught the period; reviewing is
    an action on somebody else's report.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        """What everyone gets back is narrowed further by the service."""
        return permitted(actor, "teaching_reports")

    @staticmethod
    def create(actor: User, entry) -> bool:
        """Permission *and* ownership, folded into one 403. Being allowed to
        file is not enough - it has to be their period, the same way a
        teacher of 8A is kept out of 9A's register."""
        if not permitted(actor, "teaching_reports", write=True, school_id=entry.school_id):
            return False

        return entry.teacher_id == actor.id

    @staticmethod
    def review(actor: User, report) -> bool:
        if not permitted(actor, "teaching_reports", write=True, school_id=report.school_id):
            return False

        # An HOD teaches in the department they head, so without this line
        # they would pass the department check below for their own report.
        if report.teacher_id == actor.id:
            return False

        if administers(actor):
            return in_scope(actor, report.school_id)

        if actor.role == UserRole.HOD:
            profile = report.teacher.staff_profile

            return (
                profile is not None
                and profile.department_id is not None
                and profile.department.hod_user_id == actor.id
            )

        return False


class SyllabusTopicPolicy:
    """Two concerns under one policy, the way Laravel registers it.

    **The outline** - which topics a subject has, in what order - is managed
    by whoever manages the subject: an admin of its school, or the HOD of its
    department.

    **Marking a topic done for one class section** is broader: also the
    teacher actually timetabled for that subject in that section. Checked
    against the live timetable rather than a stored assignment, so moving a
    subject to another teacher takes effect at once.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return permitted(actor, "syllabus")

    @classmethod
    def create(cls, actor: User, subject) -> bool:
        return cls.manages_subject(actor, subject)

    @classmethod
    def update(cls, actor: User, topic) -> bool:
        return cls.manages_subject(actor, topic.subject)

    @classmethod
    def delete(cls, actor: User, topic) -> bool:
        return cls.manages_subject(actor, topic.subject)

    @staticmethod
    def view_checklist(actor: User, section) -> bool:
        """Anyone who may read the outline, in the section's school. A teacher
        looking at another section's pace is not a concern the way editing it
        would be."""
        school_id = section.school_class.school_id

        return permitted(actor, "syllabus", school_id=school_id) and in_scope(actor, school_id)

    @staticmethod
    def mark(actor: User, topic, section) -> bool:
        school_id = section.school_class.school_id

        if not permitted(actor, "syllabus", write=True, school_id=school_id):
            return False

        if not in_scope(actor, school_id):
            return False

        if administers(actor):
            return True

        if actor.role == UserRole.HOD:
            department = topic.subject.department

            return department is not None and department.hod_user_id == actor.id

        if actor.role == UserRole.TEACHER:
            return TimetableEntry.objects.filter(
                class_section_id=section.id,
                subject_id=topic.subject_id,
                teacher_id=actor.id,
            ).exists()

        return False

    @staticmethod
    def manages_subject(actor: User, subject) -> bool:
        if not permitted(actor, "syllabus", write=True, school_id=subject.school_id):
            return False

        if not in_scope(actor, subject.school_id):
            return False

        if administers(actor):
            return True

        if actor.role == UserRole.HOD:
            department = subject.department

            return department is not None and department.hod_user_id == actor.id

        return False


class MessagePolicy:
    """The message log holds guardians' phone numbers and what was said to
    them, so only the admins who run the school read it. Everybody reads
    their own inbox, which is a different thing and is not gated here."""

    @staticmethod
    def view_any(actor: User) -> bool:
        return permitted(actor, "communication")

    @staticmethod
    def view(actor: User, message) -> bool:
        return permitted(actor, "communication", school_id=message.school_id) and in_scope(actor, message.school_id)

    @classmethod
    def retry(cls, actor: User, message) -> bool:
        return cls.manages(actor, message.school_id)

    @classmethod
    def configure(cls, actor: User, school_id) -> bool:
        """Reading or changing a school's templates and alert switches."""
        return cls.manages(actor, school_id)

    @classmethod
    def send(cls, actor: User, school_id) -> bool:
        """Writing a message to somebody in the school by hand. The same
        people who read the log: it names guardians and what they were told."""
        return cls.manages(actor, school_id)

    @staticmethod
    def manages(actor: User, school_id) -> bool:
        if not permitted(actor, "communication", write=True, school_id=school_id):
            return False

        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return school_id is not None and SchoolScope.for_actor(actor).allows(school_id)


class MailSettingPolicy:
    """The SMTP server is the platform's, not a school's: only SUPER_ADMIN
    reads or changes it. The password is never readable by anybody."""

    @staticmethod
    def manage(actor: User) -> bool:
        return actor.role == UserRole.SUPER_ADMIN


class ModuleSettingPolicy:
    """Which modules a school has on, and their settings (docs/settings.md).

    A Super Admin configures any school; a School or Group Admin the schools
    in their scope. Nobody else reads it - what a module's switch means for
    a teacher is already in /me.
    """

    @staticmethod
    def view(actor: User, school_id) -> bool:
        return administers(actor) and school_id is not None and in_scope(actor, school_id)

    @classmethod
    def update(cls, actor: User, school_id) -> bool:
        return cls.view(actor, school_id)


class RolePermissionPolicy:
    """The roles and permissions matrix: every administrator may read it,
    so a School Admin can see what their staff may do; only the Super Admin
    edits it, since it applies to every school."""

    @staticmethod
    def view(actor: User) -> bool:
        return administers(actor)

    @staticmethod
    def update(actor: User) -> bool:
        return actor.role == UserRole.SUPER_ADMIN


class AnnouncementPolicy:
    """Admins announce to anyone in their school. A Head of Department only
    reaches their own department - the boundary they already have over its
    teaching reports."""

    @staticmethod
    def view_any(actor: User) -> bool:
        return permitted(actor, "announcements")

    @classmethod
    def view(cls, actor: User, announcement) -> bool:
        if not permitted(actor, "announcements", school_id=announcement.school_id):
            return False

        return cls._reaches(actor, announcement)

    @classmethod
    def publish(cls, actor: User, audience: str, target, school_id) -> bool:
        """Checked against the audience, not just the role."""
        if not permitted(actor, "announcements", write=True, school_id=school_id):
            return False

        if school_id is not None and not in_scope(actor, school_id):
            return False

        if actor.role == UserRole.HOD:
            return audience == "department" and cls.heads_department(actor, target)

        return True

    @classmethod
    def delete(cls, actor: User, announcement) -> bool:
        if not permitted(actor, "announcements", write=True, school_id=announcement.school_id):
            return False

        return cls._reaches(actor, announcement)

    @classmethod
    def _reaches(cls, actor: User, announcement) -> bool:
        if not in_scope(actor, announcement.school_id):
            return False

        if actor.role == UserRole.HOD:
            return announcement.audience_type == "department" and cls.heads_department(
                actor, announcement.audience_id
            )

        return True

    @staticmethod
    def heads_department(actor: User, department_id) -> bool:
        if department_id is None:
            return False

        return SchoolScope.for_actor(actor).apply_to(
            Department.objects.filter(pk=department_id, hod_user_id=actor.id)
        ).exists()


def runs_route(actor: User, route) -> bool:
    """A Bus Attendant reaches the routes they are assigned to and nothing
    else - the way a teacher reaches their own class. Every other role
    reaches its school's routes."""
    if actor.role == UserRole.BUS_ATTENDANT:
        return route is not None and route.attendant_user_id == actor.id

    return True


class TransportMasterPolicy:
    """Vehicles, drivers and routes share one shape: read by anybody in
    transport at the same school, managed by that school's admins. The fleet
    is the school's, so even a role raised to "manage" transport runs trips
    (below) rather than buying buses.

    A Bus Attendant does not browse the fleet at all: their My Trip screen
    carries what they need about their own routes."""

    @staticmethod
    def view_any(actor: User) -> bool:
        return actor.role != UserRole.BUS_ATTENDANT and permitted(actor, "transport")

    @staticmethod
    def view(actor: User, record) -> bool:
        if actor.role == UserRole.BUS_ATTENDANT:
            return False

        return permitted(actor, "transport", school_id=record.school_id) and in_scope(actor, record.school_id)

    @staticmethod
    def create(actor: User) -> bool:
        return permitted(actor, "transport", write=True) and administers(actor)

    @staticmethod
    def manage(actor: User, record) -> bool:
        return (
            permitted(actor, "transport", write=True, school_id=record.school_id)
            and administers(actor)
            and in_scope(actor, record.school_id)
        )


class TransportRoutePolicy(TransportMasterPolicy):
    @staticmethod
    def view_students(actor: User, route) -> bool:
        """Who rides a route - guardians' numbers included - is for those who
        run transport, not every teacher who may look at the fleet."""
        return permitted(actor, "transport", write=True, school_id=route.school_id) and in_scope(
            actor, route.school_id
        )


class TransportTripPolicy:
    """Everybody in transport reads the day's trips; whoever manages
    transport runs them - start, stop by stop, board, drop, end."""

    @staticmethod
    def view_any(actor: User) -> bool:
        return permitted(actor, "transport")

    @staticmethod
    def view(actor: User, trip) -> bool:
        return (
            permitted(actor, "transport", school_id=trip.school_id)
            and in_scope(actor, trip.school_id)
            and runs_route(actor, trip.route)
        )

    @staticmethod
    def create(actor: User, route) -> bool:
        return (
            permitted(actor, "transport", write=True, school_id=route.school_id)
            and in_scope(actor, route.school_id)
            and runs_route(actor, route)
        )

    @staticmethod
    def manage(actor: User, trip) -> bool:
        return (
            permitted(actor, "transport", write=True, school_id=trip.school_id)
            and in_scope(actor, trip.school_id)
            and runs_route(actor, trip.route)
        )

    @staticmethod
    def my_routes(actor: User) -> bool:
        return actor.role == UserRole.BUS_ATTENDANT and permitted(actor, "transport")


class StaffProfilePolicy:
    """Employment records.

    Admins only, even to read: a teacher does not browse their colleagues'
    joining dates and addresses. That is the one way this differs from the
    school-owned shape, which lets every role read.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return permitted(actor, "staff")

    @staticmethod
    def view(actor: User, profile) -> bool:
        return permitted(actor, "staff", school_id=profile.school_id) and in_scope(actor, profile.school_id)

    @staticmethod
    def create(actor: User) -> bool:
        return permitted(actor, "staff", write=True)

    @classmethod
    def update(cls, actor: User, profile) -> bool:
        return cls._manages(actor, profile)

    @staticmethod
    def _manages(actor: User, profile) -> bool:
        return permitted(actor, "staff", write=True, school_id=profile.school_id) and in_scope(
            actor, profile.school_id
        )


class PayrollPolicy:
    """Payroll (docs/payroll.md): run by an Accountant for their own school,
    and by a School or Group Admin across their scope. A Super Admin reads any
    school's payroll and changes none of it. Every employee reads their own
    payslips once a run is finalized - never a draft, which can still change.

    Payroll is money and personal pay, so "may manage payroll" never falls
    back to a broader permission: a role not granted it in the matrix has
    none of it.
    """

    MANAGERS = (UserRole.ACCOUNTANT, UserRole.SCHOOL_ADMIN, UserRole.GROUP_ADMIN)

    @staticmethod
    def view_any(actor: User) -> bool:
        return permitted(actor, "payroll")

    @staticmethod
    def manage_any(actor: User) -> bool:
        return actor.role != UserRole.SUPER_ADMIN and permitted(actor, "payroll", write=True)

    @staticmethod
    def view(actor: User, school_id: int) -> bool:
        return permitted(actor, "payroll", school_id=school_id) and in_scope(actor, school_id)

    @staticmethod
    def manage(actor: User, school_id: int) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return False

        return permitted(actor, "payroll", write=True, school_id=school_id) and in_scope(actor, school_id)

    @classmethod
    def view_payslip(cls, actor: User, payslip) -> bool:
        if cls.view(actor, payslip.school_id):
            return True

        return (
            payslip.staff_profile.user_id == actor.id
            and payslip.payroll_run.status != PayrollRunStatus.DRAFT
        )


class PaymentPolicy:
    """Platform business, and nobody else's.

    Onboarding a school and recording what it paid are things the platform
    does, not things a school does - so this is the one module where a School
    Admin has no access at all, not even to their own school's rows.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return actor.role == UserRole.SUPER_ADMIN

    @staticmethod
    def view(actor: User, payment=None) -> bool:
        return actor.role == UserRole.SUPER_ADMIN

    @staticmethod
    def create(actor: User) -> bool:
        return actor.role == UserRole.SUPER_ADMIN

    @staticmethod
    def update(actor: User, payment=None) -> bool:
        return actor.role == UserRole.SUPER_ADMIN


class SchoolClassPolicy(SchoolOwnedPolicy):
    pass


class HolidayPolicy(SchoolOwnedPolicy):
    pass


class PeriodPolicy(SchoolOwnedPolicy):
    pass


class ClassSectionPolicy:
    """A section has no school of its own - it reaches one through its class.

    So this cannot inherit SchoolOwnedPolicy, which reads `record.school_id`.
    Written out rather than bent to fit, because a policy that silently read a
    missing attribute as None would allow everything for a scope that permits
    None, and that is the worst possible failure here.
    """

    @staticmethod
    def create(actor: User) -> bool:
        return permitted(actor, "academics", write=True)

    @classmethod
    def update(cls, actor: User, section) -> bool:
        return cls._manages(actor, section)

    @classmethod
    def delete(cls, actor: User, section) -> bool:
        return cls._manages(actor, section)

    @classmethod
    def view_attendance(cls, actor: User, section) -> bool:
        """Whoever may read attendance, and the teacher who actually has the
        class.

        Attendance is M10's work; the ability lives here because it is a
        question about a section and this is where those are answered.
        """
        school_id = section.school_class.school_id

        return permitted(actor, "attendance", school_id=school_id) and cls._reaches(actor, section)

    @classmethod
    def mark_attendance(cls, actor: User, section) -> bool:
        school_id = section.school_class.school_id

        return permitted(actor, "attendance", write=True, school_id=school_id) and cls._reaches(actor, section)

    @staticmethod
    def _manages(actor: User, section) -> bool:
        school_id = section.school_class.school_id

        return permitted(actor, "academics", write=True, school_id=school_id) and in_scope(actor, school_id)

    @staticmethod
    def _reaches(actor: User, section) -> bool:
        """A teacher reaches the section they are the class teacher of; every
        other role reaches its school."""
        if actor.role == UserRole.TEACHER:
            return actor.id == section.class_teacher_id

        return in_scope(actor, section.school_class.school_id)


class AcademicYearPolicy(SchoolOwnedPolicy):
    """The shared shape, plus the one action that is not a field edit.

    Making a year current makes another year stop being current, so it has its
    own ability rather than riding on `update` - the permission and the
    side effect belong together.
    """

    @classmethod
    def set_current(cls, actor: User, year) -> bool:
        return cls._manages(actor, year)


class AcademicTermPolicy(SchoolOwnedPolicy):
    """Terms are school configuration, so they answer the shared academic
    shape: an administrator writes them, everybody else reads them."""


class GradeScalePolicy(SchoolOwnedPolicy):
    """A grade scale is school configuration: an administrator writes it, and
    everybody else reads it - a teacher entering marks has to be able to see
    what an 81 will be called."""


class AssessmentPolicy:
    """Who may set a test, and for whom (docs/assessments.md).

    The matrix says a teacher may manage assessments at all. It does not say
    *which*, and that is the whole of this class.

    - A **teacher** reaches a section and subject only when a timetable entry
      says they teach it. Being the section's class teacher is not enough:
      the class teacher of 8A does not thereby teach 8A mathematics, and a
      mark in a subject somebody does not teach is exactly the loophole this
      rule exists to close.
    - An **HOD** reaches the subjects of the department they head, in any
      section of their school - which is what heading a department means.
    - An **administrator** reaches their school, and a Group Admin their
      group.
    - A **Super Admin** reads any school's tests and changes none of them,
      like payroll: the platform's owner is not a member of staff.

    Everything here answers about one assessment's section and subject, so
    creating and editing ask the same question about the values in the form,
    not about the record that already exists.
    """

    MODULE = "assessments"

    @staticmethod
    def view_any(actor: User) -> bool:
        return permitted(actor, AssessmentPolicy.MODULE)

    @classmethod
    def view(cls, actor: User, assessment) -> bool:
        if not permitted(actor, cls.MODULE, school_id=assessment.school_id):
            return False

        if not in_scope(actor, assessment.school_id):
            return False

        if administers(actor) or actor.role == UserRole.SUPER_ADMIN:
            return True

        # A teacher or an HOD reads what they could have set themselves. A
        # teacher browsing another class's tests would be reading marks that
        # are none of their business the moment marks exist.
        return cls._teaches(actor, assessment.class_section_id, assessment.subject_id)

    @classmethod
    def create(cls, actor: User, school_id, class_section_id, subject_id) -> bool:
        """Asked about the section and subject in the form, before anything
        is written."""
        return cls._manages(actor, school_id, class_section_id, subject_id)

    @classmethod
    def update(cls, actor: User, assessment) -> bool:
        return cls._manages(actor, assessment.school_id, assessment.class_section_id, assessment.subject_id)

    @classmethod
    def delete(cls, actor: User, assessment) -> bool:
        return cls._manages(actor, assessment.school_id, assessment.class_section_id, assessment.subject_id)

    @classmethod
    def create_in_bulk(cls, actor: User) -> bool:
        """May this person set tests for any class in their school?

        The gate for the spreadsheet import. A teacher's own tests are set one
        at a time, where the timetable answers "is this your class" for each
        one; a file crossing classes has no such answer per row, so bulk
        creation belongs to the people the question does not apply to.
        """
        if actor.role == UserRole.SUPER_ADMIN:
            return False

        return administers(actor) and permitted(actor, cls.MODULE, write=True)

    @classmethod
    def reopen(cls, actor: User, assessment) -> bool:
        """Who may take a published result back.

        Not the teacher who published it. Once guardians have been told, the
        undoing is a school decision: an administrator, or the HOD of the
        department the subject belongs to.
        """
        if actor.role == UserRole.SUPER_ADMIN:
            return False

        if not permitted(actor, cls.MODULE, write=True, school_id=assessment.school_id):
            return False

        if not in_scope(actor, assessment.school_id):
            return False

        if administers(actor):
            return True

        return actor.role == UserRole.HOD and cls._teaches(actor, assessment.class_section_id, assessment.subject_id)

    @classmethod
    def _manages(cls, actor: User, school_id, class_section_id, subject_id) -> bool:
        # The Super Admin reads every school's tests and sets none of them.
        # Checked before the matrix, which grants them everything.
        if actor.role == UserRole.SUPER_ADMIN:
            return False

        if not permitted(actor, cls.MODULE, write=True, school_id=school_id):
            return False

        if not in_scope(actor, school_id):
            return False

        if administers(actor):
            return True

        return cls._teaches(actor, class_section_id, subject_id)

    @staticmethod
    def _teaches(actor: User, class_section_id, subject_id) -> bool:
        """Whether this person is the one who teaches that subject to that
        section - by the timetable, or by heading the department the subject
        belongs to."""
        if actor.role == UserRole.HOD:
            subject = Subject.objects.select_related("department").filter(pk=subject_id).first()

            return (
                subject is not None
                and subject.department_id is not None
                and subject.department.hod_user_id == actor.id
            )

        if actor.role == UserRole.TEACHER:
            return TimetableEntry.objects.filter(
                class_section_id=class_section_id,
                subject_id=subject_id,
                teacher_id=actor.id,
            ).exists()

        return False


class UserPolicy:
    """Who may manage which accounts.

    SUPER_ADMIN manages every user, across every school. An admin manages
    non-admin accounts in their own school freely, and admin-tier accounts on
    a strict hierarchy: the head - a School Admin who is not themselves a Sub
    Admin - manages the Sub Admins in their own school, but never another
    head, and never themselves.

    `is_sub_admin` is two tiers of one role rather than a role of its own, so
    every other policy treats them identically. A School Admin a Super Admin
    onboarded can create further admin accounts for their school; a Sub Admin
    has the same permissions everywhere else but can create no admin account
    at all.

    Operational staff (HOD/TEACHER/STAFF/TRANSPORT_MANAGER/ACCOUNTANT) are onboarded
    through Teachers & Staff instead, which creates the login and the
    employment record together. One created here would have no StaffProfile
    and be invisible to Attendance and Leave, so that path is deliberately not
    offered.

    Not in the permissions matrix: accounts are administration, and handing
    a teacher the power to make admins is not a setting anybody should have.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return actor.role in ADMIN_ROLES

    @classmethod
    def view(cls, actor: User, target: User) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return cls._same_school(actor, target)

    @staticmethod
    def create(actor: User) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return UserRole.administers_school(actor.role) and not actor.is_sub_admin

    @classmethod
    def update(cls, actor: User, target: User) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return cls._manages(actor, target)

    @classmethod
    def set_status(cls, actor: User, target: User) -> bool:
        # Nobody deactivates their own account through this endpoint, whatever
        # their role - it is the one mistake that locks you out of fixing it.
        if actor.id == target.id:
            return False

        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return cls._manages(actor, target)

    @classmethod
    def _manages(cls, actor: User, target: User) -> bool:
        if not cls._same_school(actor, target):
            return False

        # Admin-tier targets follow the hierarchy; everybody else is managed
        # freely within the school.
        if not UserRole.administers_school(target.role):
            return True

        return not actor.is_sub_admin and target.is_sub_admin

    @staticmethod
    def _same_school(actor: User, target: User) -> bool:
        return UserRole.administers_school(actor.role) and SchoolScope.for_actor(actor).allows(
            target.school_id
        )


class StudentPolicy:
    """Admins manage every student in scope. A TEACHER reaches only students
    in a class section they are the class teacher of - the "a Teacher
    assigned to 8A must not access 9A" rule from CLAUDE.md - whatever level
    the matrix gives teachers. Any other role the matrix lets in reaches its
    own school.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return permitted(actor, "students")

    @classmethod
    def view(cls, actor: User, student: Student) -> bool:
        return permitted(actor, "students", school_id=student.school_id) and cls._reaches(actor, student)

    @staticmethod
    def create(actor: User) -> bool:
        return permitted(actor, "students", write=True)

    @classmethod
    def update(cls, actor: User, student: Student) -> bool:
        return cls._manages(actor, student)

    @classmethod
    def set_status(cls, actor: User, student: Student) -> bool:
        return cls._manages(actor, student)

    @classmethod
    def _manages(cls, actor: User, student: Student) -> bool:
        return permitted(actor, "students", write=True, school_id=student.school_id) and cls._reaches(
            actor, student
        )

    @staticmethod
    def _reaches(actor: User, student: Student) -> bool:
        if actor.role == UserRole.TEACHER:
            section = student.class_section

            return section is not None and section.class_teacher_id == actor.id

        return in_scope(actor, student.school_id)


class AuditLogPolicy:
    """Who may read the audit log (Phase 21, decided 2026-09-18).

    Administrators, each within their own scope - the Super Admin across every
    school, a Group Admin their group, a School Admin their school. Read-only
    for everybody: nothing in the API edits or deletes an entry. Which rows an
    administrator sees is SchoolScope's to decide, in views/audit_logs.py.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return actor.role in ADMIN_ROLES
