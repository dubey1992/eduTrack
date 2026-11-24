"""What guardians and family accounts look like over the API
(docs/parent-student-app.md, F0). Never a passcode, setup code or device
secret - only whether one is set."""

from __future__ import annotations

from django.utils import timezone

from . import modules
from .fields import as_utc
from .models import FamilyCredential, FamilyDevice, Guardian, GuardianStudent, Student, StudentTransportAssignment, User
from .resources import timestamp


def guardian_link_resource(link: GuardianStudent) -> dict:
    """One of a student's guardians, for the office."""
    guardian = link.guardian

    return {
        "id": link.id,
        "guardian_id": guardian.id,
        "name": guardian.name,
        "mobile": guardian.login_mobile,
        "email": guardian.email,
        "relationship": link.relationship,
        "is_primary": link.is_primary,
        "consent_at": timestamp(guardian.consent_at),
        "has_family_account": guardian.user_id is not None,
        # How many of the school's students this person is linked to: a
        # sibling's guardian edited here is edited there too.
        "children": GuardianStudent.objects.filter(guardian_id=guardian.id).count(),
    }


def family_device_resource(device: FamilyDevice) -> dict:
    return {
        "id": device.id,
        "name": device.name,
        "last_used_at": timestamp(device.last_used_at),
        "revoked_at": timestamp(device.revoked_at),
    }


def family_access_resource(guardian: Guardian, credential: FamilyCredential | None, devices) -> dict:
    """A guardian's Family app sign-in, for the office."""
    pending = (
        credential is not None
        and credential.setup_code is not None
        and credential.setup_code_expires_at is not None
        and as_utc(credential.setup_code_expires_at) > timezone.now()
    )

    return {
        "guardian_id": guardian.id,
        "login_mobile": guardian.login_mobile,
        "consent_at": timestamp(guardian.consent_at),
        "has_account": credential is not None,
        "has_passcode": credential is not None and credential.passcode is not None,
        "is_locked": credential is not None and credential.locked_at is not None,
        "setup_code_pending": pending,
        "setup_code_expires_at": timestamp(credential.setup_code_expires_at) if pending else None,
        "devices": [family_device_resource(device) for device in devices],
    }


def family_child_resource(student: Student) -> dict:
    """One child, as the parent sees them in the Family app."""
    section = student.class_section

    return {
        "id": student.id,
        "first_name": student.first_name,
        "last_name": student.last_name,
        "class_section_id": student.class_section_id,
        "class_name": f"{section.school_class.name} {section.name}".strip() if section else None,
        "roll_number": student.roll_number,
        # Whether the school carries this child, so the app shows a Bus tab
        # only to a family it means something to.
        "has_transport": StudentTransportAssignment.objects.filter(student_id=student.id).exists(),
    }


def family_me_resource(user: User, children) -> dict:
    """Who is signed in to the Family app, and which children they see."""
    school = user.school

    return {
        "id": user.id,
        "role": user.role,
        "name": user.name,
        "mobile": user.mobile,
        "school": {
            "id": school.id,
            "name": school.name,
            "currency_code": school.currency_code,
            # For "Contact the school": the office's own details, nothing
            # about any member of staff.
            "phone": school.phone or None,
            "email": school.email or None,
            "address": ", ".join(part for part in (school.address, school.city, school.state) if part) or None,
        } if school else None,
        "children": [family_child_resource(child) for child in children],
        # Which parts of the app the school uses: a tab for something the
        # school has switched off would only ever say "nothing here".
        "features": {
            "fees": modules.is_enabled(user.school_id, "fees"),
            "transport": modules.is_enabled(user.school_id, "transport"),
            "results": modules.is_enabled(user.school_id, "assessments"),
            "timetable": modules.is_enabled(user.school_id, "timetable"),
            "syllabus": modules.is_enabled(user.school_id, "syllabus"),
            # Homework comes from the teaching reports (M8, 8.1).
            "homework": modules.is_enabled(user.school_id, "teaching_reports"),
        } if user.school_id else {},
    }


def family_notice_resource(message) -> dict:
    """One of the school's messages, as the Family app lists it. Only what a
    parent needs: never the channel log's addresses or statuses."""
    return {
        "id": message.id,
        "category": message.category,
        "title": message.subject or None,
        "body": message.body,
        "student_id": message.student_id,
        "student_name": message.student_name,
        "created_at": message.created_at.isoformat() if message.created_at else None,
        "read": message.read_at is not None,
    }
