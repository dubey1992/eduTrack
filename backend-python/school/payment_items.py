"""The services on a Super Admin payment.

A payment covers one or more services, each with its own amount: Setup Fee,
Annual Maintenance and Additional Service at most once each, and any number
of "other" fees the Super Admin names. The payment's amount is the sum of its
lines, worked out here and never taken from the client.
"""

from __future__ import annotations

import decimal
from decimal import Decimal

from django.utils import timezone

from .enums import PaymentType
from .models import Payment, PaymentItem

# More than anyone would put on one receipt, and few enough to keep it one page.
MAX_LINES = 20
NAME_LENGTH = 100
LARGEST = Decimal("9999999999.99")


def label_of(service: str, name: str | None) -> str:
    """What a line is called: an "other" fee by its own name."""
    if service == PaymentType.OTHER and name:
        return name

    return PaymentType(service).label if service in PaymentType.values else service


def summary(lines) -> str:
    """One phrase for a list's "Type" column: "Setup Fee + 2 more"."""
    labels = [label_of(line.service, line.name) for line in lines]

    if not labels:
        return ""

    if len(labels) == 1:
        return labels[0]

    return f"{labels[0]} + {len(labels) - 1} more"


def read(raw, errors: dict) -> list[dict]:
    """The lines a form sent, checked one by one.

    Problems go into `errors` under `items.<n>.<field>`, so the form can
    point at the very box that is wrong.
    """
    if not isinstance(raw, list):
        errors["items"] = ["The services must be a list."]
        return []

    if not raw:
        errors["items"] = ["Choose at least one service."]
        return []

    if len(raw) > MAX_LINES:
        errors["items"] = [f"A payment can list at most {MAX_LINES} services."]
        return []

    lines, seen = [], set()

    for index, item in enumerate(raw):
        prefix = f"items.{index}"
        item = item if isinstance(item, dict) else {}
        service = item.get("service")

        if service not in PaymentType.values:
            errors[f"{prefix}.service"] = ["Choose a service from the list."]
            continue

        name = item.get("name")
        name = name.strip() if isinstance(name, str) else ""

        if service == PaymentType.OTHER:
            if not name:
                errors[f"{prefix}.name"] = ["Say what this fee is for."]
            elif len(name) > NAME_LENGTH:
                errors[f"{prefix}.name"] = [f"Keep the fee's name to {NAME_LENGTH} characters."]
        else:
            # A fixed service names itself; it appears at most once.
            if service in seen:
                errors[f"{prefix}.service"] = [f"{PaymentType(service).label} is listed twice."]
            seen.add(service)
            name = ""

        amount = money_of(item.get("amount"), f"{prefix}.amount", errors)

        lines.append({"service": service, "name": name or None, "amount": amount})

    return lines


def money_of(value, field: str, errors: dict) -> Decimal | None:
    """Above zero, two decimals at most, and small enough for the column."""
    if value is None or value == "":
        errors[field] = ["Enter an amount."]
        return None

    try:
        parsed = Decimal(str(value))
    except (decimal.InvalidOperation, TypeError, ValueError):
        errors[field] = ["Enter the amount as a number."]
        return None

    if not parsed.is_finite():
        errors[field] = ["Enter the amount as a number."]
        return None

    if parsed.as_tuple().exponent < -2:
        errors[field] = ["Use at most two decimal places."]
        return None

    if parsed <= 0:
        errors[field] = ["The amount must be more than 0."]
        return None

    if parsed > LARGEST:
        errors[field] = ["That amount is too large."]
        return None

    return parsed.quantize(Decimal("0.01"))


def total_of(lines: list[dict]) -> Decimal:
    return sum((line["amount"] for line in lines), Decimal("0.00"))


def write(payment: Payment, lines: list[dict]) -> None:
    """Replaces the payment's lines with these, in this order."""
    now = timezone.now()

    payment.items.all().delete()
    PaymentItem.objects.bulk_create([
        PaymentItem(
            payment=payment,
            service=line["service"],
            name=line["name"],
            amount=line["amount"],
            # Always the payment's own currency (CLAUDE.md rule 5).
            currency_code=payment.currency_code,
            position=position,
            created_at=now,
            updated_at=now,
        )
        for position, line in enumerate(lines)
    ])


def described(lines) -> list[dict]:
    """The lines as an audit log records them."""
    return [
        {"service": line.service, "name": line.name, "amount": str(line.amount)}
        for line in lines
    ]
