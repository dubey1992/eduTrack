"""The JSON the Fee Setup screens read (docs/fees.md).

Money goes out as strings with two decimals, as payroll and payments do - a
client that parsed it as a double would put a rounding error into what a
family is charged. Due dates are calendar dates (`2026-04-10`); instants are
timestamps in the form every other resource uses.
"""

from __future__ import annotations

from ..enums import FeePaymentMode
from ..models import StudentEnrollment
from ..payroll.resources import cash
from ..resources import timestamp
from .ledger import balance_of, is_overdue


def fee_head_resource(head) -> dict:
    return {
        "id": head.id,
        "school_id": head.school_id,
        "name": head.name,
        "is_transport": head.is_transport,
        "is_active": head.is_active,
        "structures_count": getattr(head, "structures_count", 0),
    }


def installment_resource(row) -> dict:
    return {
        "id": row.id,
        "sequence": row.sequence,
        "label": row.label,
        "due_date": row.due_date.isoformat(),
        "amount": cash(row.amount),
    }


def fee_structure_resource(structure) -> dict:
    school_class = structure.school_class if structure.school_class_id else None
    route = structure.transport_route if structure.transport_route_id else None
    head = structure.fee_head

    return {
        "id": structure.id,
        "school_id": structure.school_id,
        "academic_year_id": structure.academic_year_id,
        "kind": "class" if school_class is not None else "route",
        "school_class": None if school_class is None else {"id": school_class.id, "name": school_class.name},
        "transport_route": None if route is None else {"id": route.id, "name": route.name},
        "fee_head": {"id": head.id, "name": head.name, "is_transport": head.is_transport},
        "amount": cash(structure.amount),
        "currency_code": structure.currency_code,
        "frequency": structure.frequency,
        "status": structure.status,
        "published_at": timestamp(structure.published_at),
        # The students it charges now (F2): 0 for a draft.
        "students_count": getattr(structure, "students_count", 0),
        "installments": [
            installment_resource(row) for row in sorted(structure.installments.all(), key=lambda row: row.sequence)
        ],
        "updated_at": timestamp(structure.updated_at),
    }


def plan_resource(rows: list[dict]) -> dict:
    return {
        "installments": [
            {"label": row["label"], "due_date": row["due_date"].isoformat(), "amount": cash(row["amount"])}
            for row in rows
        ]
    }


# -- F2: what students owe -------------------------------------------------------


def _class_names(enrollment) -> tuple[str | None, str | None]:
    if enrollment is None:
        return None, None

    section = enrollment.class_section if enrollment.class_section_id else None

    return enrollment.school_class.name, None if section is None else section.name


def due_resource(due, today) -> dict:
    """One line of a statement - and what a waiver answers with."""
    return {
        "id": due.id,
        "fee_head": {"id": due.fee_head_id, "name": due.fee_head.name},
        "label": due.label,
        "due_date": due.due_date.isoformat(),
        "amount": cash(due.amount),
        "discount_amount": cash(due.discount_amount),
        "paid_amount": cash(due.paid_amount),
        "balance": cash(balance_of(due)),
        "status": due.status,
        "is_overdue": is_overdue(due, today),
        "cancelled_reason": due.cancelled_reason,
        # F4: an installment or a late fine (and the installment it is for),
        # and a waiver's reason and moment.
        "kind": due.kind,
        "fine_for_due_id": due.fine_for_due_id,
        "waive_reason": due.waive_reason,
        "waived_at": timestamp(due.waived_at),
    }


def statement_resource(found: dict) -> dict:
    """`GET fees/students/{id}`: one student's dues for one year."""
    student = found["student"]
    class_name, section_name = _class_names(found["enrollment"])
    today = found["today"]
    totals = found["totals"]
    enrollments = {(student.id, found["year"].id): found["enrollment"]}

    return {
        "student": {
            "id": student.id,
            "name": student.name,
            "admission_number": student.admission_number,
            "class_name": class_name,
            "section_name": section_name,
            "status": student.status,
            "admission_date": None if student.admission_date is None else student.admission_date.isoformat(),
        },
        "academic_year": {"id": found["year"].id, "name": found["year"].name},
        "currency_code": found["currency_code"],
        "dues": [due_resource(due, today) for due in found["dues"]],
        "totals": {
            key: cash(totals[key]) for key in ("charged", "discount", "paid", "balance", "overdue", "waived")
        },
        # F4: the discounts active for this year.
        "concessions": [
            fee_concession_resource(concession, enrollments) for concession in found.get("concessions", [])
        ],
        # F3: the student's receipts dated in this year, newest first.
        "receipts": [
            {
                "id": receipt.id,
                "receipt_number": receipt.receipt_number,
                "receipt_date": receipt.receipt_date.isoformat(),
                "amount": cash(receipt.amount),
                "payment_mode_label": mode_label(receipt.payment_mode),
                "status": receipt.status,
            }
            for receipt in found.get("receipts", [])
        ],
    }


def balance_row_resource(row) -> dict:
    """One row of `GET fees/balances`: an enrollment annotated by
    fees/ledger.py balances()."""
    student = row.student
    class_name, section_name = _class_names(row)

    return {
        "student": {
            "id": student.id,
            "name": student.name,
            "admission_number": student.admission_number,
            "class_name": class_name,
            "section_name": section_name,
            "status": student.status,
        },
        "charged": cash(row.charged),
        "paid": cash(row.paid),
        "balance": cash(row.balance),
        "overdue": cash(row.overdue),
        "next_due_date": None if row.next_due_date is None else row.next_due_date.isoformat(),
        "currency_code": row.currency,
    }


# -- F3: receipts ----------------------------------------------------------------


def mode_label(mode: str) -> str:
    return dict(FeePaymentMode.choices).get(mode, mode)


def person(user) -> dict | None:
    return None if user is None else {"id": user.id, "name": user.name}


def enrollments_for(receipts) -> dict[tuple[int, int], StudentEnrollment]:
    """(student, year) -> enrollment, for every receipt on a page, in one
    query - the class a receipt shows is the student's class in the year the
    receipt is numbered in."""
    receipts = list(receipts)
    student_ids = {receipt.student_id for receipt in receipts}
    year_ids = {receipt.academic_year_id for receipt in receipts}

    if not receipts:
        return {}

    return {
        (row.student_id, row.academic_year_id): row
        for row in StudentEnrollment.objects.filter(
            student_id__in=student_ids, academic_year_id__in=year_ids
        ).select_related("school_class", "class_section")
    }


def receipt_class(receipt, enrollments: dict | None = None) -> tuple[str | None, str | None]:
    """The student's class and section in the receipt's year."""
    if enrollments is None:
        enrollments = enrollments_for([receipt])

    return _class_names(enrollments.get((receipt.student_id, receipt.academic_year_id)))


def fee_receipt_resource(receipt, enrollments: dict | None = None) -> dict:
    """A receipt loaded by FeeReceiptService.query(): `student_balance`
    annotated, allocations prefetched with their dues."""
    student = receipt.student
    class_name, section_name = receipt_class(receipt, enrollments)
    allocations = sorted(
        receipt.allocations.all(), key=lambda row: (row.student_fee_due.due_date, row.student_fee_due_id)
    )

    return {
        "id": receipt.id,
        "receipt_number": receipt.receipt_number,
        "receipt_date": receipt.receipt_date.isoformat(),
        "amount": cash(receipt.amount),
        "currency_code": receipt.currency_code,
        "payment_mode": receipt.payment_mode,
        "payment_mode_label": mode_label(receipt.payment_mode),
        "reference": receipt.reference,
        "note": receipt.note,
        "status": receipt.status,
        "student": {
            "id": student.id,
            "name": student.name,
            "admission_number": student.admission_number,
            "class_name": class_name,
            "section_name": section_name,
        },
        "academic_year": {"id": receipt.academic_year.id, "name": receipt.academic_year.name},
        "received_by": person(receipt.received_by),
        "allocations": [
            {
                "due_id": row.student_fee_due_id,
                "label": row.student_fee_due.label,
                "due_date": row.student_fee_due.due_date.isoformat(),
                "amount": cash(row.amount),
            }
            for row in allocations
        ],
        "cancelled_at": timestamp(receipt.cancelled_at),
        "cancelled_by": person(receipt.cancelled_by),
        "cancel_reason": receipt.cancel_reason,
        "emailed_at": timestamp(receipt.emailed_at),
        # As at the receipt, in its currency: frozen when it was recorded.
        "balance_before": cash(receipt.balance_before),
        "balance_after": cash(receipt.balance_before - receipt.amount),
        # What the student still owes now, every year (pending and part-paid).
        "student_balance": cash(getattr(receipt, "student_balance", None)),
        "created_at": timestamp(receipt.created_at),
    }


# -- F4: discounts ----------------------------------------------------------------


def fee_concession_resource(concession, enrollments: dict | None = None) -> dict:
    """A discount loaded by ConcessionService.query(): `dues_affected`
    annotated. The class is the student's in the discount's year."""
    student = concession.student
    class_name, _ = receipt_class(concession, enrollments)
    head = concession.fee_head if concession.fee_head_id else None

    return {
        "id": concession.id,
        "student": {
            "id": student.id,
            "name": student.name,
            "admission_number": student.admission_number,
            "class_name": class_name,
        },
        "academic_year": {"id": concession.academic_year.id, "name": concession.academic_year.name},
        "fee_head": None if head is None else {"id": head.id, "name": head.name},
        "kind": concession.kind,
        "value": cash(concession.value),
        "reason": concession.reason,
        "created_by": person(concession.created_by),
        "created_at": timestamp(concession.created_at),
        "revoked_at": timestamp(concession.revoked_at),
        "revoked_by": person(concession.revoked_by),
        # The school's currency: a fixed discount is in it, as its dues are.
        "currency_code": concession.school.currency_code,
        "dues_affected": getattr(concession, "dues_affected", 0),
    }
