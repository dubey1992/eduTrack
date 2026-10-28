"""An employee's bank details (docs/pdf-design.md, the payslip).

The account number is a secret the school holds for the employee: it is
encrypted at rest with the key that guards the schools' messaging
credentials, and nothing the server sends - the Salaries screen, the
payslip, the audit trail - carries more than its last four characters.
"""

from __future__ import annotations

import logging

from .. import crypto

logger = logging.getLogger(__name__)

# The fields, as the API names them.
FIELDS = ("bank_name", "bank_account_number", "bank_branch_code", "tax_id")


def account_number(salary) -> str | None:
    """The account number in clear, or None - also when it cannot be read
    because the key changed, which is logged rather than raised: a payslip
    that cannot show the account still shows the pay."""
    stored = getattr(salary, "bank_account_number", None)

    if not stored:
        return None

    try:
        return crypto.decrypt(stored)
    except crypto.CannotDecrypt as error:
        logger.warning("Salary %s: the bank account number cannot be read (%s)", salary.id, error)
        return None


def masked(number: str | None) -> str | None:
    """"XXXXXX1234": as many Xs as there were characters before the last four."""
    if not number:
        return None

    clean = number.replace(" ", "")

    if len(clean) <= 4:
        return "X" * len(clean)

    return "X" * (len(clean) - 4) + clean[-4:]


def masked_of(salary) -> str | None:
    return masked(account_number(salary))


def details(salary) -> dict:
    """What the screen and the audit trail may see."""
    if salary is None:
        return {"bank_name": None, "bank_account_masked": None, "bank_branch_code": None, "tax_id": None}

    return {
        "bank_name": salary.bank_name,
        "bank_account_masked": masked_of(salary),
        "bank_branch_code": salary.bank_branch_code,
        "tax_id": salary.tax_id,
    }


def apply(salary, data: dict) -> None:
    """Writes what the form sent onto the salary. A field the form left out
    keeps its value; the account number is kept unless a new one is typed,
    and taken off with an explicit null."""
    for field in ("bank_name", "bank_branch_code", "tax_id"):
        if field in data:
            setattr(salary, field, data[field])

    if "bank_account_number" in data:
        number = data["bank_account_number"]
        salary.bank_account_number = crypto.encrypt(number) if number else None
