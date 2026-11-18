"""The fee books' date lock (docs/dashboard.md, D3, decided 2026-11-18).

One "locked up to" date per school. Nothing dated on or before it can be
recorded in the fee books: no receipt, cancellation, discount, waiver,
late fine or refund. Attendance, exams and every other module are
untouched - only the money this module keeps.

What "dated" means for each:

- a receipt - its receipt date; cancelling one - that receipt's date, since
  it changes a closed day's money;
- a refund - its refund date;
- a discount, a revoked discount, a waiver, a late fine - today at the
  school, the day it is recorded.

The lock is never in the future: it closes days that are over. Moving it
back, or clearing it, needs a reason. Every change is in the audit log,
which is its history.
"""

from __future__ import annotations

import datetime as dt

from django.db import transaction
from django.utils import timezone

from .. import audit
from ..clock import SchoolClock
from ..enums import UserRole
from ..errors import FeesLocked
from ..models import School

MODULE = "fees"

# Who may move the lock: whoever keeps the books (decided 2026-11-18). A
# Group Admin is a School Admin over branches. Not the Super Admin, who
# changes no school's fees.
LOCKERS = (UserRole.SCHOOL_ADMIN, UserRole.GROUP_ADMIN, UserRole.ACCOUNTANT)


def locked_until(school_id: int) -> dt.date | None:
    return School.objects.filter(pk=school_id).values_list("fees_locked_until", flat=True).first()


def today(school_id: int) -> dt.date:
    return SchoolClock.for_school(school_id).now().date()


def is_closed(school_id: int, day: dt.date) -> bool:
    lock = locked_until(school_id)

    return lock is not None and day <= lock


def ensure_open(school_id: int, day: dt.date | None, what: str) -> None:
    """Refuses `what`, dated `day`, when the books are closed for that day.
    No day means today at the school."""
    lock = locked_until(school_id)
    day = day or today(school_id)

    if lock is not None and day <= lock:
        raise FeesLocked(lock, what)


def change(school: School, until: dt.date | None, reason: str | None, actor, request=None) -> School:
    """Moves the lock; the request has already checked the date and the
    reason. Audited either way, with the reason."""
    with transaction.atomic():
        school = School.objects.select_for_update().get(pk=school.pk)
        before = school.fees_locked_until

        if before == until:
            return school

        school.fees_locked_until = until
        school.updated_at = timezone.now()
        school.save(update_fields=["fees_locked_until", "updated_at"])

        unlocking = until is None or (before is not None and until < before)
        audit.record(
            actor=actor,
            action="fees.unlocked" if unlocking else "fees.locked",
            module=MODULE,
            entity_type="school",
            entity_id=school.id,
            school_id=school.id,
            old={"locked_until": before.isoformat() if before else None},
            new={"locked_until": until.isoformat() if until else None, "reason": reason},
            request=request,
        )

    return school
