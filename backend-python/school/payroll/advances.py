"""Advances paid to staff, and their recovery from payslips
(docs/dashboard.md, D4, decided 2026-11-18).

An advance is logged once: how much, when and how it was paid, and how much
comes off each payslip from the month recovery starts. Each payroll run then
adds an "Advance recovery" deduction line for it - the monthly amount, or
what is left, or what the payslip can bear, whichever is least - until it is
repaid.

**Nothing is counted twice.** What has been recovered is the sum of those
lines on finalized and paid runs, read from the payslips themselves. A
draft's line is pending: it is deleted and rebuilt with the draft, and only
counts once the run is finalized - which cannot be undone.

It is not fee money. The fee books' date lock does not touch it, and it is
never added to collections.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from django.db import transaction
from django.db.models import Q, Sum
from django.utils import timezone

from .. import audit, dates, money
from ..enums import PayComponentType, PayrollRunStatus, PayslipLineSource, StaffAdvanceStatus
from ..models import PayrollRun, Payslip, PayslipLine, StaffAdvance, StaffProfile
from ..scope import SchoolScope
from . import calculator

MODULE = "payroll"
CLOSED_RUNS = (PayrollRunStatus.FINALIZED, PayrollRunStatus.PAID)
# After basic pay and the salary's components, before any adjustment.
SORT_FROM = 50


def recovered(advance_ids) -> dict[int, Decimal]:
    """What finalized and paid runs have taken back, per advance."""
    return _sums(advance_ids, Q(payslip__payroll_run__status__in=CLOSED_RUNS))


def pending(advance_ids) -> dict[int, Decimal]:
    """What drafts would take back, per advance - not yet recovered."""
    return _sums(advance_ids, Q(payslip__payroll_run__status=PayrollRunStatus.DRAFT))


def _sums(advance_ids, where: Q) -> dict[int, Decimal]:
    rows = (
        PayslipLine.objects.filter(where, staff_advance_id__in=list(advance_ids))
        .order_by()
        .values("staff_advance_id")
        .annotate(total=Sum("amount"))
    )

    return {row["staff_advance_id"]: row["total"] or calculator.ZERO for row in rows}


def status_of(advance: StaffAdvance, recovered_amount: Decimal) -> str:
    if advance.status == StaffAdvanceStatus.CANCELLED:
        return StaffAdvanceStatus.CANCELLED

    return StaffAdvanceStatus.REPAID if recovered_amount >= advance.amount else StaffAdvanceStatus.ACTIVE


def add_recovery_lines(slip: Payslip, run: PayrollRun, now) -> None:
    """The month's recovery of every advance the employee is still repaying,
    oldest first, as deduction lines on their (draft) payslip. Called by
    PayrollRunService.compute after basic pay and components, so the slip
    never goes below zero for it: each advance takes at most what is left of
    the net pay."""
    month_start = dt.date(run.year, run.month, 1)
    advances = list(
        StaffAdvance.objects.filter(
            school_id=run.school_id,
            staff_profile_id=slip.staff_profile_id,
            status=StaffAdvanceStatus.ACTIVE,
            recovery_starts__lte=month_start,
        ).order_by("paid_on", "id")
    )

    if not advances:
        return

    # Taken back by other closed runs - never this one, which is a draft.
    done = recovered(advance.id for advance in advances)
    available = calculator.totals(slip.lines.values_list("type", "amount")).net_pay

    for order, advance in enumerate(advances):
        left = advance.amount - done.get(advance.id, calculator.ZERO)
        take = min(advance.monthly_recovery, left, available)

        if take <= 0:
            continue

        PayslipLine.objects.create(
            payslip=slip,
            type=PayComponentType.DEDUCTION,
            source=PayslipLineSource.ADVANCE,
            name="Advance recovery",
            full_amount=None,
            amount=take,
            note=(
                f"Advance of {money.formatted(advance.amount, advance.currency_code)} paid "
                f"{dates.us(advance.paid_on)}: {money.formatted(left - take, advance.currency_code)} left after this"
            )[:255],
            staff_advance=advance,
            sort_order=SORT_FROM + order,
            created_at=now,
            updated_at=now,
        )
        available -= take


class StaffAdvanceService:
    WITH = ("staff_profile__user", "created_by", "cancelled_by", "school")

    @classmethod
    def visible_to(cls, actor, filters: dict):
        found = SchoolScope.for_actor(actor).apply_to(
            StaffAdvance.objects.select_related(*cls.WITH), filters.get("school_id")
        )

        if filters.get("staff_profile_id"):
            found = found.filter(staff_profile_id=filters["staff_profile_id"])

        state = filters.get("status")
        if state == StaffAdvanceStatus.CANCELLED:
            found = found.filter(status=StaffAdvanceStatus.CANCELLED)
        elif state in (StaffAdvanceStatus.ACTIVE, StaffAdvanceStatus.REPAID):
            # Repaid is worked out, so it is filtered in Python on a bounded
            # set: one school's active advances.
            active = list(found.filter(status=StaffAdvanceStatus.ACTIVE).values_list("id", "amount"))
            done = recovered(advance_id for advance_id, _ in active)
            repaid = [advance_id for advance_id, amount in active if done.get(advance_id, calculator.ZERO) >= amount]
            found = found.filter(status=StaffAdvanceStatus.ACTIVE)
            found = found.filter(pk__in=repaid) if state == StaffAdvanceStatus.REPAID else found.exclude(pk__in=repaid)

        return found.order_by("-paid_on", "-id")

    @staticmethod
    def create(profile: StaffProfile, data: dict, actor, request=None) -> StaffAdvance:
        now = timezone.now()

        with transaction.atomic():
            advance = StaffAdvance.objects.create(
                school_id=profile.school_id,
                staff_profile=profile,
                amount=data["amount"],
                # The school's, never the client's (CLAUDE.md rule 5).
                currency_code=profile.school.currency_code,
                paid_on=data["paid_on"],
                payment_mode=data["payment_mode"],
                reference=data.get("reference"),
                monthly_recovery=data["monthly_recovery"],
                recovery_starts=data["recovery_starts"],
                reason=data["reason"],
                status=StaffAdvanceStatus.ACTIVE,
                created_by=actor,
                created_at=now,
                updated_at=now,
            )

            audit.record(
                actor=actor, action="staff_advance.created", module=MODULE, entity_type="staff_advance",
                entity_id=advance.id, school_id=advance.school_id, new=snapshot(advance), request=request,
            )

        return advance

    @staticmethod
    def cancel(advance: StaffAdvance, reason: str, actor, request=None) -> StaffAdvance:
        """Only while nothing has been recovered: once a finalized payslip
        took money back, the advance is history and stays."""
        from ..errors import StaffAdvanceNotCancellable

        with transaction.atomic():
            advance = StaffAdvance.objects.select_for_update().get(pk=advance.pk)

            if advance.status == StaffAdvanceStatus.CANCELLED:
                raise StaffAdvanceNotCancellable("This advance is already cancelled.")

            if recovered([advance.id]).get(advance.id, calculator.ZERO) > 0:
                raise StaffAdvanceNotCancellable(
                    "Part of this advance has already been recovered from a finalized payslip, so it stays on record."
                )

            before = snapshot(advance)
            now = timezone.now()
            advance.status = StaffAdvanceStatus.CANCELLED
            advance.cancelled_at = now
            advance.cancelled_by = actor
            advance.cancel_reason = reason
            advance.updated_at = now
            advance.save(update_fields=["status", "cancelled_at", "cancelled_by", "cancel_reason", "updated_at"])

            # A draft that was going to recover it no longer does.
            from .service import PayslipService

            slips = set(
                PayslipLine.objects.filter(
                    staff_advance=advance, payslip__payroll_run__status=PayrollRunStatus.DRAFT
                ).values_list("payslip_id", flat=True)
            )
            PayslipLine.objects.filter(staff_advance=advance, payslip_id__in=slips).delete()
            for slip in Payslip.objects.filter(pk__in=slips):
                PayslipService.refresh_totals(slip)

            audit.record(
                actor=actor, action="staff_advance.cancelled", module=MODULE, entity_type="staff_advance",
                entity_id=advance.id, school_id=advance.school_id, old=before,
                new={**snapshot(advance), "cancel_reason": reason}, request=request,
            )

        return advance


def snapshot(advance: StaffAdvance) -> dict:
    return {
        "staff_profile_id": advance.staff_profile_id,
        "amount": str(advance.amount),
        "currency_code": advance.currency_code,
        "paid_on": advance.paid_on.isoformat(),
        "payment_mode": advance.payment_mode,
        "monthly_recovery": str(advance.monthly_recovery),
        "recovery_starts": advance.recovery_starts.isoformat(),
        "status": advance.status,
    }
