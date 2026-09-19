"""Who a notice written in the Communication Center reaches, and how many of
them can actually be reached on each channel (docs/communication.md).

Only reading here. Sending is NoticeService in services.py, which turns an
audience into messages through notifications.py like every other module.
"""

from __future__ import annotations

from django.db.models import Q

from .enums import MessageChannel, NoticeAudience, NoticeRecipients, StudentStatus, UserRole, UserStatus
from .models import ClassSection, Department, Student, User
from .notifications import channel_enabled


def students_for(school_id: int, audience: str, target):
    """Active students of this school in the audience - none for an audience
    made of staff. A class from another school matches nobody, which is what
    a target that does not belong here should do."""
    if not NoticeAudience.reaches_students(audience):
        return Student.objects.none()

    students = Student.objects.filter(school_id=school_id, status=StudentStatus.ACTIVE)

    if audience == NoticeAudience.STUDENT:
        return students.filter(pk=target)

    if audience == NoticeAudience.CLASS_SECTION:
        return students.filter(class_section_id=target)

    return students


def users_for(school_id: int, audience: str, target):
    """Active accounts of this school in the audience - never the platform's
    Super Admins, who belong to none."""
    if not NoticeAudience.reaches_staff(audience):
        return User.objects.none()

    users = User.objects.filter(school_id=school_id, status=UserStatus.ACTIVE)

    if audience == NoticeAudience.STAFF_MEMBER:
        return users.filter(pk=target)

    if audience == NoticeAudience.TEACHERS:
        return users.filter(role__in=(UserRole.TEACHER, UserRole.HOD))

    if audience == NoticeAudience.DEPARTMENT:
        return users.filter(staffprofile__department_id=target)

    return users


def target_exists(school_id: int, audience: str, target) -> bool:
    """Whether the named person, class or department is this school's."""
    if audience == NoticeAudience.STUDENT:
        return Student.objects.filter(pk=target, school_id=school_id).exists()

    if audience == NoticeAudience.STAFF_MEMBER:
        return User.objects.filter(pk=target, school_id=school_id).exists()

    if audience == NoticeAudience.CLASS_SECTION:
        return ClassSection.objects.filter(pk=target, school_class__school_id=school_id).exists()

    if audience == NoticeAudience.DEPARTMENT:
        return Department.objects.filter(pk=target, school_id=school_id).exists()

    return True


def audience_label(school_id: int, audience: str, target) -> str:
    """The name the target goes by - looked up inside this school only, so a
    preview cannot be used to read another school's names."""
    if audience == NoticeAudience.STUDENT:
        student = Student.objects.filter(pk=target, school_id=school_id).first()

        return "Student" if student is None else student.name

    if audience == NoticeAudience.STAFF_MEMBER:
        user = User.objects.filter(pk=target, school_id=school_id).first()

        return "Staff member" if user is None else user.name

    if audience == NoticeAudience.CLASS_SECTION:
        section = (
            ClassSection.objects.select_related("school_class")
            .filter(pk=target, school_class__school_id=school_id)
            .first()
        )

        return "Class" if section is None else f"{section.school_class.name} {section.name}".strip()

    if audience == NoticeAudience.DEPARTMENT:
        department = Department.objects.filter(pk=target, school_id=school_id).first()

        return "Department" if department is None else department.name

    return NoticeAudience(audience).label


ADDRESS_COLUMNS = {
    # (who, channel) -> the column that must be filled for a copy to go out.
    ("guardian", MessageChannel.SMS): "guardian_mobile",
    ("guardian", MessageChannel.WHATSAPP): "guardian_mobile",
    ("guardian", MessageChannel.EMAIL): "guardian_email",
    ("student", MessageChannel.SMS): "student_mobile",
    ("student", MessageChannel.WHATSAPP): "student_mobile",
    ("student", MessageChannel.EMAIL): "student_email",
    ("user", MessageChannel.SMS): "mobile",
    ("user", MessageChannel.WHATSAPP): "mobile",
    ("user", MessageChannel.EMAIL): "email",
}


def count(school_id: int, audience: str, target, recipients: str, channels: list[str], setting) -> dict:
    """How many people the notice reaches, and how many copies per channel.

    A person counts as reached when at least one chosen channel that the
    school has on can carry a copy to them; the per-channel numbers say how
    many copies each channel would carry. A channel the school has not
    switched on carries nothing, whatever the form asked for.
    """
    live = [channel for channel in channels if channel_enabled(channel, setting)]
    external = [channel for channel in live if channel != MessageChannel.IN_APP]
    by_channel = {channel: 0 for channel in MessageChannel.values}
    reached = 0

    students = students_for(school_id, audience, target)
    recipients = NoticeRecipients.for_audience(audience, recipients)

    groups = []

    if NoticeRecipients.includes_guardians(recipients):
        groups.append(("guardian", students))

    if NoticeRecipients.includes_students(recipients):
        groups.append(("student", students))

    groups.append(("user", users_for(school_id, audience, target)))

    for who, rows in groups:
        reachable = Q(pk__in=[])

        for channel in external:
            column = ADDRESS_COLUMNS[(who, channel)]
            by_channel[channel] += rows.exclude(**{column: None}).exclude(**{column: ""}).count()
            reachable |= Q(**{f"{column}__isnull": False}) & ~Q(**{column: ""})

        if who == "user" and MessageChannel.IN_APP in live:
            inbox = rows.count()
            by_channel[MessageChannel.IN_APP] += inbox
            reached += inbox
        else:
            reached += rows.filter(reachable).count()

    return {"recipients": reached, "by_channel": by_channel, "channels": live}
