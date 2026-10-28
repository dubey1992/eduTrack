"""The JSON the Fee Setup screens read (docs/fees.md).

Money goes out as strings with two decimals, as payroll and payments do - a
client that parsed it as a double would put a rounding error into what a
family is charged. Due dates are calendar dates (`2026-04-10`); instants are
timestamps in the form every other resource uses.
"""

from __future__ import annotations

from ..payroll.resources import cash
from ..resources import timestamp


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
