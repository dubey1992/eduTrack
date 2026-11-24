"""A second guardian, asked for by a parent (docs/mobile-apps-review.md, M8,
8.5).

Decided 2026-11-24: a parent asks from the Family app (name, mobile,
relationship); the school office approves or declines; nobody sees a
child's records until it approves. On approval the guardian is linked
exactly as the office links one by hand (GuardianService.add), with the same
rights as any other guardian - fees, absence notes, call requests - and the
set-up code then goes out from the student's Guardians, as for any guardian.

A parent may ask only for their own child; the same mobile cannot be asked
for twice while a request is pending, nor for somebody already a guardian
of the child.
"""

from __future__ import annotations

from django.db import transaction
from django.utils import timezone

from . import audit, family
from .errors import GuardianProblem
from .family_accounts import GuardianService
from .models import GuardianInvite, GuardianStudent, Student, User

PENDING = "pending"
APPROVED = "approved"
DECLINED = "declined"

# Enough for both parents and a grandparent; a long list of requests from
# one family is not a pattern a school expects.
MAX_PENDING_PER_CHILD = 3


def ask(student: Student, data: dict, parent: User) -> GuardianInvite:
    """The parent's request, checked and saved as pending."""
    login = family.login_mobile(data["mobile"])

    already_linked = GuardianStudent.objects.filter(student_id=student.id, guardian__login_mobile=login).exists()
    if already_linked:
        raise GuardianProblem("This person is already a guardian of your child.")

    pending = GuardianInvite.objects.filter(student_id=student.id, status=PENDING)
    if pending.filter(mobile=login).exists():
        raise GuardianProblem("You have already asked for this person. The school will decide soon.")
    if pending.count() >= MAX_PENDING_PER_CHILD:
        raise GuardianProblem("Wait for the school to answer your earlier requests first.")

    now = timezone.now()
    with transaction.atomic():
        invite = GuardianInvite.objects.create(
            school_id=student.school_id, student_id=student.id, requested_by_id=parent.id,
            name=data["name"], mobile=login, relationship=data["relationship"], status=PENDING,
            created_at=now, updated_at=now,
        )
        audit.record(action="guardian_invite.requested", module="students", entity_type="student",
                     entity_id=student.id, school_id=student.school_id,
                     new={"invite_id": invite.id, "name": invite.name, "relationship": invite.relationship})

    return invite


def approve(invite: GuardianInvite, actor: User) -> GuardianInvite:
    """Links the guardian as the office would by hand, and records who agreed."""
    _still_pending(invite)

    with transaction.atomic():
        link = GuardianService.add(
            invite.student,
            {"name": invite.name, "mobile": invite.mobile, "relationship": invite.relationship, "is_primary": False},
            actor,
        )
        _decide(invite, APPROVED, actor, link=link)

    return invite


def decline(invite: GuardianInvite, actor: User) -> GuardianInvite:
    _still_pending(invite)

    with transaction.atomic():
        _decide(invite, DECLINED, actor)

    return invite


def _still_pending(invite: GuardianInvite) -> None:
    if invite.status != PENDING:
        raise GuardianProblem(f"This request was already {invite.status}.")


def _decide(invite: GuardianInvite, outcome: str, actor: User, link: GuardianStudent | None = None) -> None:
    now = timezone.now()
    invite.status = outcome
    invite.decided_by = actor
    invite.decided_at = now
    invite.guardian_student = link
    invite.updated_at = now
    invite.save(update_fields=["status", "decided_by", "decided_at", "guardian_student", "updated_at"])
    audit.record(action=f"guardian_invite.{outcome}", module="students", entity_type="student",
                 entity_id=invite.student_id, school_id=invite.school_id,
                 new={"invite_id": invite.id, "name": invite.name})


def family_resource(invite: GuardianInvite) -> dict:
    """What the asking parent sees: who they asked for, and the answer."""
    return {
        "id": invite.id,
        "name": invite.name,
        "relationship": invite.relationship,
        "status": invite.status,
        "asked_at": invite.created_at.isoformat() if invite.created_at else None,
    }


def office_resource(invite: GuardianInvite) -> dict:
    """What the school office sees to decide."""
    student = invite.student
    section = student.class_section

    return {
        **family_resource(invite),
        "mobile": invite.mobile,
        "student_id": student.id,
        "student_name": student.name,
        "admission_number": student.admission_number,
        "class_section_name": f"{section.school_class.name} {section.name}".strip() if section else None,
        "requested_by_name": invite.requested_by.name,
        "decided_by_name": invite.decided_by.name if invite.decided_by_id else None,
        "guardian_link_id": invite.guardian_student_id,
    }
