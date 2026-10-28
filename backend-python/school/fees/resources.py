"""The JSON the Fee Setup screens read (docs/fees.md).

Money goes out as strings with two decimals, as payroll and payments do - a
client that parsed it as a double would put a rounding error into what a
family is charged. Due dates are calendar dates (`2026-04-10`); instants are
timestamps in the form every other resource uses.
"""

from __future__ import annotations

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


def statement_resource(found: dict) -> dict:
    """`GET fees/students/{id}`: one student's dues for one year."""
    student = found["student"]
    class_name, section_name = _class_names(found["enrollment"])
    today = found["today"]
    totals = found["totals"]

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
        "dues": [
            {
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
            }
            for due in found["dues"]
        ],
        "totals": {key: cash(totals[key]) for key in ("charged", "discount", "paid", "balance", "overdue")},
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
