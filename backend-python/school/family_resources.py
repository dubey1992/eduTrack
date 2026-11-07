"""What guardians and family accounts look like over the API
(docs/parent-student-app.md, F0). Never a passcode, setup code or device
secret - only whether one is set."""

from __future__ import annotations

from django.utils import timezone

from .fields import as_utc
from .models import FamilyCredential, FamilyDevice, Guardian, GuardianStudent, Student, User
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
    }


def family_me_resource(user: User, children) -> dict:
    """Who is signed in to the Family app, and which children they see."""
    school = user.school

    return {
        "id": user.id,
        "role": user.role,
        "name": user.name,
        "mobile": user.mobile,
        "school": {"id": school.id, "name": school.name, "currency_code": school.currency_code} if school else None,
        "children": [family_child_resource(child) for child in children],
    }
