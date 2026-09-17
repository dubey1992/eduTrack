"""Who may do what.

The Python half of app/Policies. Named `policies` rather than `permissions`
because these are ports of specific Laravel policies and reading the two side
by side is how they get reviewed - the migration plan calls this the dangerous
part, since every mistake here is one school reading another's records.

A policy answers a question and returns a bool. Raising the 403 is the view's
job, through `authorize()`, so the same policy can be asked without an
exception when a caller only wants to know.

Every rule below has an ALLOW test and a DENY test in tests/test_policies.py
(CLAUDE.md rule 11).
"""

from __future__ import annotations

from rest_framework.exceptions import PermissionDenied

from .enums import UserRole
from .models import Student, TimetableEntry, User
from .scope import SchoolScope

ADMIN_ROLES = (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN)


def authorize(allowed: bool) -> None:
    """Turns a policy's answer into the 403 the client expects."""
    if not allowed:
        raise PermissionDenied()


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
    """The shape most school-owned records share.

    Admins manage their own school's records; everybody else may read them.
    Departments, subjects, classes, periods and holidays all answer exactly
    this, and writing it five times is how one of them quietly ends up
    different from the other four.

    Subclasses exist so a call site names the thing it is asking about, and so
    a record that later needs its own rule has somewhere to put it.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return True

    @staticmethod
    def view(actor: User, record) -> bool:
        return actor.role == UserRole.SUPER_ADMIN or SchoolScope.for_actor(actor).allows(
            record.school_id
        )

    @staticmethod
    def create(actor: User) -> bool:
        return actor.role in ADMIN_ROLES

    @classmethod
    def update(cls, actor: User, record) -> bool:
        return cls._manages(actor, record)

    @classmethod
    def delete(cls, actor: User, record) -> bool:
        return cls._manages(actor, record)

    @staticmethod
    def _manages(actor: User, record) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return UserRole.administers_school(actor.role) and SchoolScope.for_actor(actor).allows(
            record.school_id
        )


class DepartmentPolicy(SchoolOwnedPolicy):
    """Departments, plus the department report the HOD screens need.

    The report is the one place this diverges: an admin sees any department of
    their school, an HOD only the ones they actually head.
    """

    @staticmethod
    def view_any_report(actor: User) -> bool:
        return actor.role in ADMIN_ROLES or actor.role == UserRole.HOD

    @staticmethod
    def view_report(actor: User, department) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        if not SchoolScope.for_actor(actor).allows(department.school_id):
            return False

        if UserRole.administers_school(actor.role):
            return True

        if actor.role == UserRole.HOD:
            return department.hod_user_id == actor.id

        return False


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
        return actor.role in ADMIN_ROLES or actor.role == UserRole.HOD

    @staticmethod
    def manage(actor: User, school_id) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        marks_the_register = UserRole.administers_school(actor.role) or actor.role == UserRole.HOD

        return marks_the_register and SchoolScope.for_actor(actor).allows(school_id)


class StaffLeavePolicy:
    """Applying and reviewing, deliberately two abilities.

    Unlike the staff register's single `manage`: applying is self-service for
    anyone with an employment record, reviewing is an action on somebody
    else's request, and one actor is never both for the same leave.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        """Every role reads leave. What they actually get back is narrowed by
        StaffLeaveService.visible_to - own, department, school, everything -
        so a coarse role gate here would only duplicate it badly."""
        return True

    @staticmethod
    def apply(actor: User) -> bool:
        """Role only. Whether the actor has a StaffProfile to apply against is
        a data precondition, not an authorization question - the view answers
        that separately, with a sentence naming the fix.

        SCHOOL_ADMIN is in the list because a School Admin takes leave too;
        they get a minimal profile on account creation for exactly this. A
        Super Admin never applies - there is no school to apply against.
        """
        return actor.role in (
            UserRole.TEACHER,
            UserRole.STAFF,
            UserRole.HOD,
            UserRole.TRANSPORT_MANAGER,
            UserRole.SCHOOL_ADMIN,
        )

    @staticmethod
    def review(actor: User, leave) -> bool:
        # An HOD heads the department they belong to, so without this line
        # they would pass the department check below for their own request.
        # Nobody reviews their own leave, whatever their role.
        profile = actor.staff_profile

        if profile is not None and leave.staff_profile_id == profile.id:
            return False

        if actor.role == UserRole.SUPER_ADMIN:
            return True

        if UserRole.administers_school(actor.role):
            return SchoolScope.for_actor(actor).allows(leave.school_id)

        if actor.role == UserRole.HOD:
            applicant = leave.staff_profile

            return (
                applicant is not None
                and applicant.department_id is not None
                and applicant.department.hod_user_id == actor.id
            )

        return False



class TimetableEntryPolicy:
    """The grid: everybody reads it, admins edit it.

    Reading is open by role because a teacher needs the grid to find their own
    schedule; *whose* grid they get is checked against the target's school in
    the view. Editing follows the other academic-config policies - a class, a
    subject and a period are all admin-only, and the grid that arranges them
    is no different.

    `manage` is asked about a school rather than an entry because an upsert
    may be creating the first one for that cell.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return True

    @staticmethod
    def manage(actor: User, school_id) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return UserRole.administers_school(actor.role) and SchoolScope.for_actor(
            actor
        ).allows(school_id)

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
        """Not every role, unlike leave. Staff and Transport Managers are never
        a scheduled teacher and have no reason to browse these; what everyone
        else gets back is narrowed further by the service."""
        return actor.role in (*ADMIN_ROLES, UserRole.HOD, UserRole.TEACHER)

    @staticmethod
    def create(actor: User, entry) -> bool:
        """Role *and* ownership, folded into one 403. Being a teacher is not
        enough - it has to be their period, the same way a teacher of 8A is
        kept out of 9A's register."""
        if actor.role not in (UserRole.TEACHER, UserRole.HOD):
            return False

        return entry.teacher_id == actor.id

    @staticmethod
    def review(actor: User, report) -> bool:
        # An HOD teaches in the department they head, so without this line
        # they would pass the department check below for their own report.
        if report.teacher_id == actor.id:
            return False

        if actor.role == UserRole.SUPER_ADMIN:
            return True

        if UserRole.administers_school(actor.role):
            return SchoolScope.for_actor(actor).allows(report.school_id)

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

    Staff and Transport Managers read neither; nothing here is theirs.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return actor.role in (*ADMIN_ROLES, UserRole.HOD, UserRole.TEACHER)

    @classmethod
    def create(cls, actor: User, subject) -> bool:
        return cls.manages_subject(actor, subject)

    @classmethod
    def update(cls, actor: User, topic) -> bool:
        return cls.manages_subject(actor, topic.subject)

    @classmethod
    def delete(cls, actor: User, topic) -> bool:
        return cls.manages_subject(actor, topic.subject)

    @classmethod
    def view_checklist(cls, actor: User, section) -> bool:
        """Anyone who may read the outline, in the section's school. A teacher
        looking at another section's pace is not a concern the way editing it
        would be."""
        if not cls.view_any(actor):
            return False

        return actor.role == UserRole.SUPER_ADMIN or SchoolScope.for_actor(actor).allows(
            section.school_class.school_id
        )

    @staticmethod
    def mark(actor: User, topic, section) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        if not SchoolScope.for_actor(actor).allows(section.school_class.school_id):
            return False

        if UserRole.administers_school(actor.role):
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
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        if not SchoolScope.for_actor(actor).allows(subject.school_id):
            return False

        if UserRole.administers_school(actor.role):
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
        return actor.role in ADMIN_ROLES

    @classmethod
    def view(cls, actor: User, message) -> bool:
        return cls.manages(actor, message.school_id)

    @classmethod
    def retry(cls, actor: User, message) -> bool:
        return cls.manages(actor, message.school_id)

    @classmethod
    def configure(cls, actor: User, school_id) -> bool:
        """Reading or changing a school's templates and alert switches."""
        return cls.manages(actor, school_id)

    @staticmethod
    def manages(actor: User, school_id) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return (
            UserRole.administers_school(actor.role)
            and school_id is not None
            and SchoolScope.for_actor(actor).allows(school_id)
        )


class StaffProfilePolicy:
    """Employment records.

    Admins only, even to read: a teacher does not browse their colleagues'
    joining dates and addresses. That is the one way this differs from the
    school-owned shape, which lets every role read.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return actor.role in ADMIN_ROLES

    @classmethod
    def view(cls, actor: User, profile) -> bool:
        return cls._manages(actor, profile)

    @staticmethod
    def create(actor: User) -> bool:
        return actor.role in ADMIN_ROLES

    @classmethod
    def update(cls, actor: User, profile) -> bool:
        return cls._manages(actor, profile)

    @staticmethod
    def _manages(actor: User, profile) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return UserRole.administers_school(actor.role) and SchoolScope.for_actor(actor).allows(
            profile.school_id
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
        return actor.role in ADMIN_ROLES

    @classmethod
    def update(cls, actor: User, section) -> bool:
        return cls._manages(actor, section)

    @classmethod
    def delete(cls, actor: User, section) -> bool:
        return cls._manages(actor, section)

    @classmethod
    def view_attendance(cls, actor: User, section) -> bool:
        """Admins, and the teacher who actually has the class.

        Attendance is M10's work; the ability lives here because it is a
        question about a section and this is where those are answered.
        """
        return cls._manages(actor, section) or cls._is_class_teacher(actor, section)

    @classmethod
    def mark_attendance(cls, actor: User, section) -> bool:
        return cls.view_attendance(actor, section)

    @staticmethod
    def _manages(actor: User, section) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return UserRole.administers_school(actor.role) and SchoolScope.for_actor(actor).allows(
            section.school_class.school_id
        )

    @staticmethod
    def _is_class_teacher(actor: User, section) -> bool:
        return actor.role == UserRole.TEACHER and actor.id == section.class_teacher_id


class AcademicYearPolicy(SchoolOwnedPolicy):
    """The shared shape, plus the one action that is not a field edit.

    Making a year current makes another year stop being current, so it has its
    own ability rather than riding on `update` - the permission and the
    side effect belong together.
    """

    @classmethod
    def set_current(cls, actor: User, year) -> bool:
        return cls._manages(actor, year)


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

    Operational staff (HOD/TEACHER/STAFF/TRANSPORT_MANAGER) are onboarded
    through Teachers & Staff instead, which creates the login and the
    employment record together. One created here would have no StaffProfile
    and be invisible to Attendance and Leave, so that path is deliberately not
    offered.
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
    """SUPER_ADMIN, GROUP_ADMIN and SCHOOL_ADMIN manage every student in
    scope. TEACHER gets read-only access, and only to students in a class
    section they are the class teacher of - the "a Teacher assigned to 8A must
    not access 9A" rule from CLAUDE.md. HOD/STAFF/TRANSPORT_MANAGER have no
    student access.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return actor.role in ADMIN_ROLES or actor.role == UserRole.TEACHER

    @staticmethod
    def view(actor: User, student: Student) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        if UserRole.administers_school(actor.role):
            return SchoolScope.for_actor(actor).allows(student.school_id)

        if actor.role == UserRole.TEACHER:
            section = student.class_section

            return section is not None and section.class_teacher_id == actor.id

        return False

    @staticmethod
    def create(actor: User) -> bool:
        return actor.role in ADMIN_ROLES

    @classmethod
    def update(cls, actor: User, student: Student) -> bool:
        return cls._manages(actor, student)

    @classmethod
    def set_status(cls, actor: User, student: Student) -> bool:
        return cls._manages(actor, student)

    @staticmethod
    def _manages(actor: User, student: Student) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return UserRole.administers_school(actor.role) and SchoolScope.for_actor(actor).allows(
            student.school_id
        )
