"""What each fee set-up form must hold before anything is saved (docs/fees.md).

Every failure is reported at once, field by field, in the envelope every
other form uses (422 VALIDATION_ERROR, details.errors keyed by field). Money
is Decimal throughout and never more than the DECIMAL(12,2) column holds.

Installment problems are all reported under `installments`, each sentence
naming the installment by its number, because the screen shows them as one
list under the installments table rather than beside a cell.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from rest_framework import serializers

from ..clock import SchoolClock
from ..enums import FeeConcessionKind, FeeFrequency, FeePaymentMode, FeeReceiptStatus
from ..models import (
    AcademicYear,
    ClassSection,
    FeeHead,
    FeeStructure,
    SchoolClass,
    Student,
    StudentEnrollment,
    StudentFeeDue,
    TransportRoute,
)
from ..requests import MoneyField, ScopedSerializer
from ..scope import SchoolScope
from ..validation import (
    LaravelBooleanField,
    LaravelCharField,
    LaravelIntegerField,
    at_most,
    does_not_exist,
    must_be_a_string,
    must_be_after,
    normalise,
    not_a_date,
    prohibits,
    required,
    required_without,
    selected_is_invalid,
    too_long,
    too_short,
)
from . import plan

# The most a DECIMAL(12,2) holds.
MAX_AMOUNT = Decimal("9999999999.99")
MAX_INSTALLMENTS = 24
LABEL_MAX = 60
NAME_MAX = 100


def plain(value: Decimal) -> str:
    """12000 -> "12,000.00": how a sentence prints an amount. No currency
    symbol - the screen shows the fee's currency beside it already."""
    return f"{value:,.2f}"


def money(field: str, raw, errors: dict, minimum: str = "0.01") -> Decimal | None:
    """A required money field, its problems added to `errors[field]`."""
    try:
        value = MoneyField(field, minimum=minimum).to_internal_value(raw)
    except serializers.ValidationError as failure:
        errors.setdefault(field, []).extend(str(message) for message in failure.detail)
        return None

    if value is None:
        errors.setdefault(field, []).append(required(field))
        return None

    if value > MAX_AMOUNT:
        errors.setdefault(field, []).append(at_most(field, "9,999,999,999.99"))
        return None

    return value


def integer(field: str, raw, errors: dict, *, optional: bool = False) -> int | None:
    if raw is None or raw == "":
        if not optional:
            errors.setdefault(field, []).append(required(field))
        return None

    try:
        return LaravelIntegerField(field).to_internal_value(raw)
    except serializers.ValidationError as failure:
        errors.setdefault(field, []).extend(str(message) for message in failure.detail)
        return None


def frequency_of(raw, errors: dict) -> str | None:
    if raw is None or raw == "":
        errors.setdefault("frequency", []).append(required("frequency"))
        return None

    if raw not in FeeFrequency.values:
        errors.setdefault("frequency", []).append(selected_is_invalid("frequency"))
        return None

    return raw


def installment_problems(raw, amount: Decimal | None, start: dt.date, end: dt.date) -> tuple[list[dict], list[str]]:
    """Checks a structure's installments against its academic year and its
    amount. Returns the cleaned installments (sequence = position, 1-based)
    and every problem found, each naming the installment it is about.

    `amount` None means the fee's own amount was invalid, so the sum is not
    compared - one mistake is not reported twice.
    """
    if raw is None:
        return [], [required("installments")]

    if not isinstance(raw, list):
        return [], ["The installments must be a list."]

    if not raw:
        return [], ["Add at least one installment."]

    if len(raw) > MAX_INSTALLMENTS:
        return [], [f"A fee can have at most {MAX_INSTALLMENTS} installments."]

    problems: list[str] = []
    cleaned: list[dict] = []
    every_amount_valid = True
    previous: tuple[int, dt.date] | None = None

    for index, item in enumerate(raw):
        number = index + 1
        item = item if isinstance(item, dict) else {}

        label = item.get("label")
        label = label.strip() if isinstance(label, str) else None

        if not label:
            problems.append(f"Installment {number} needs a label.")
        elif len(label) > LABEL_MAX:
            problems.append(f"Installment {number}'s label must not be longer than {LABEL_MAX} characters.")

        due = parse_date(item.get("due_date"))

        if item.get("due_date") in (None, ""):
            problems.append(f"Installment {number} needs a due date.")
        elif due is None:
            problems.append(f"Installment {number}'s due date must be a valid date, like {start.isoformat()}.")
        elif due < start:
            problems.append(
                f"Installment {number} is due on {due.isoformat()}, before the academic year starts "
                f"({start.isoformat()})."
            )
        elif due > end:
            problems.append(
                f"Installment {number} is due on {due.isoformat()}, after the academic year ends ({end.isoformat()})."
            )

        if due is not None:
            if previous is not None and due < previous[1]:
                problems.append(
                    f"Installment {number} is due before installment {previous[0]}. "
                    "List the installments in the order they fall due."
                )
            previous = (number, due)

        part = installment_amount(number, item.get("amount"), problems)
        every_amount_valid = every_amount_valid and part is not None

        cleaned.append({"sequence": number, "label": label, "due_date": due, "amount": part})

    if amount is not None and every_amount_valid:
        total = sum((row["amount"] for row in cleaned), Decimal("0.00"))

        if total != amount:
            problems.append(f"The installments add up to {plain(total)} but the fee is {plain(amount)}.")

    return cleaned, problems


def installment_amount(number: int, raw, problems: list[str]) -> Decimal | None:
    if raw is None or raw == "":
        problems.append(f"Installment {number} needs an amount.")
        return None

    if isinstance(raw, bool):
        problems.append(f"Installment {number}'s amount must be a number.")
        return None

    try:
        value = Decimal(str(raw).strip())
    except Exception:  # noqa: BLE001 - decimal raises InvalidOperation, or ValueError for odd input
        problems.append(f"Installment {number}'s amount must be a number.")
        return None

    if not value.is_finite():
        problems.append(f"Installment {number}'s amount must be a number.")
        return None

    if value.as_tuple().exponent < -2:
        problems.append(f"Installment {number}'s amount can have at most 2 decimal places.")
        return None

    if value <= 0:
        problems.append(f"Installment {number}'s amount must be more than zero.")
        return None

    if value > MAX_AMOUNT:
        problems.append(f"Installment {number}'s amount must not be greater than 9,999,999,999.99.")
        return None

    return value.quantize(Decimal("0.01"))


def parse_date(raw) -> dt.date | None:
    """An ISO calendar date - `2026-04-10` - and nothing looser."""
    if not isinstance(raw, str):
        return None

    try:
        return dt.date.fromisoformat(raw.strip()) if len(raw.strip()) == 10 else None
    except ValueError:
        return None


def year_in_scope(actor, raw, errors: dict, requested_school=None) -> AcademicYear | None:
    """The academic year named by `academic_year_id`, if the actor can reach
    it. Another school's year reads as "invalid", exactly like one that does
    not exist - an id is not a way to learn what another school has."""
    year_id = integer("academic_year_id", raw, errors)

    if year_id is None:
        return None

    years = SchoolScope.for_actor(actor).apply_to(AcademicYear.objects.select_related("school"), requested_school)
    year = years.filter(pk=year_id).first()

    if year is None:
        errors.setdefault("academic_year_id", []).append(does_not_exist("academic_year_id"))

    return year


def raise_if(errors: dict) -> None:
    if errors:
        raise serializers.ValidationError(errors)


# -- fee heads --------------------------------------------------------------


class StoreFeeHeadRequest(ScopedSerializer):
    """A new fee type. The school is the actor's own unless they span several,
    when they name it - see ScopedSerializer. Uniqueness and the 50-head cap
    are checked by the service, under a lock on the school."""

    name = LaravelCharField("name", max_length=NAME_MAX)

    def validate(self, attrs):
        self.validate_school_id_field()
        attrs["school_id"] = self.resolved_school_id()

        return attrs


class UpdateFeeHeadRequest(serializers.Serializer):
    name = LaravelCharField("name", max_length=NAME_MAX, required=False)
    is_active = LaravelBooleanField("is_active", required=False)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)


# -- fee structures ---------------------------------------------------------


class FeeStructureRequest:
    """A new fee (`store`) or a changed one (`update`).

    Not a DRF serializer: the fields depend on each other - the class on the
    year, the head on the route, the installments on the amount and the year -
    and every problem has to be reported in one answer.
    """

    def __init__(self, data, actor) -> None:
        self.data = normalise(data) if isinstance(data, dict) else {}
        self.raw = data if isinstance(data, dict) else {}
        self.actor = actor

    def store(self) -> dict:
        errors: dict[str, list[str]] = {}
        data = self.data

        year = year_in_scope(self.actor, data.get("academic_year_id"), errors)
        class_id = integer("school_class_id", data.get("school_class_id"), errors, optional=True)
        route_id = integer("transport_route_id", data.get("transport_route_id"), errors, optional=True)
        head_id = integer("fee_head_id", data.get("fee_head_id"), errors)
        amount = money("amount", data.get("amount"), errors)
        frequency = frequency_of(data.get("frequency"), errors)

        given_class = data.get("school_class_id") not in (None, "")
        given_route = data.get("transport_route_id") not in (None, "")

        if not given_class and not given_route:
            errors.setdefault("school_class_id", []).append(required_without("school_class_id", "transport_route_id"))
        elif given_class and given_route:
            errors.setdefault("school_class_id", []).append(prohibits("school_class_id", "transport_route_id"))

        school_class = route = head = None

        if year is not None:
            if class_id is not None and not given_route:
                school_class = SchoolClass.objects.filter(
                    pk=class_id, academic_year_id=year.id, school_id=year.school_id
                ).first()
                if school_class is None:
                    errors.setdefault("school_class_id", []).append(does_not_exist("school_class_id"))

            if route_id is not None and not given_class:
                route = TransportRoute.objects.filter(pk=route_id, school_id=year.school_id).first()
                if route is None:
                    errors.setdefault("transport_route_id", []).append(does_not_exist("transport_route_id"))

            if head_id is not None:
                head = FeeHead.objects.filter(pk=head_id, school_id=year.school_id).first()
                if head is None:
                    errors.setdefault("fee_head_id", []).append(does_not_exist("fee_head_id"))

        if head is not None:
            if not head.is_active:
                errors.setdefault("fee_head_id", []).append(
                    f"The {head.name} fee type is retired. Bring it back before setting up fees with it."
                )
            elif head.is_transport and school_class is not None:
                errors.setdefault("fee_head_id", []).append(
                    "The Transport fee type is for bus routes. Choose a route instead of a class."
                )
            elif not head.is_transport and route is not None:
                errors.setdefault("fee_head_id", []).append("A bus route's fee uses the Transport fee type.")
            elif "fee_head_id" not in errors:
                self.check_unique(year, school_class, route, head, errors)

        installments = []

        if year is not None:
            installments, problems = installment_problems(data.get("installments"), amount, year.start_date, year.end_date)
            if problems:
                errors["installments"] = problems

        raise_if(errors)

        return {
            "academic_year": year,
            "school_class": school_class,
            "transport_route": route,
            "fee_head": head,
            "amount": amount,
            "frequency": frequency,
            "installments": installments,
        }

    def update(self, structure: FeeStructure) -> dict:
        """What a PUT may change: the amount, the frequency and the
        installments. The year, the class or route and the head are what the
        fee *is*; a different one is a different fee."""
        errors: dict[str, list[str]] = {}
        data = self.data
        year = structure.academic_year

        amount = money("amount", data.get("amount"), errors)
        frequency = frequency_of(data.get("frequency"), errors)
        installments, problems = installment_problems(data.get("installments"), amount, year.start_date, year.end_date)

        if problems:
            errors["installments"] = problems

        raise_if(errors)

        return {"amount": amount, "frequency": frequency, "installments": installments}

    @staticmethod
    def check_unique(year, school_class, route, head, errors: dict) -> None:
        """One fee per head per class, and per head per route, each year."""
        if school_class is not None:
            taken = FeeStructure.objects.filter(academic_year_id=year.id, school_class_id=school_class.id, fee_head_id=head.id)
        elif route is not None:
            taken = FeeStructure.objects.filter(academic_year_id=year.id, transport_route_id=route.id, fee_head_id=head.id)
        else:
            return

        if taken.exists():
            errors.setdefault("fee_head_id", []).append(duplicate_message(year, school_class, route, head))


def duplicate_message(year, school_class, route, head) -> str:
    """"Class 8 already has a Tuition fee for 2026-27." """
    subject = school_class.name if school_class is not None else route.name

    return f"{subject} already has a {head.name} fee for {year.name}."


# -- the installment-plan helper ----------------------------------------------


class InstallmentPlanRequest:
    """`GET fees/installment-plan`: a year, a frequency, an amount and the
    day of the month installments fall due (10th by default)."""

    def __init__(self, params, actor) -> None:
        self.params = params
        self.actor = actor

    def validate(self) -> dict:
        errors: dict[str, list[str]] = {}
        params = {key: self.params.get(key) for key in ("academic_year_id", "school_id", "frequency", "amount", "due_day")}
        params = normalise(params)

        year = year_in_scope(self.actor, params["academic_year_id"], errors, params.get("school_id"))
        frequency = frequency_of(params["frequency"], errors)
        amount = money("amount", params["amount"], errors)
        due_day = 10

        if params["due_day"] is not None:
            due_day = integer("due_day", params["due_day"], errors)
            if due_day is not None and not 1 <= due_day <= 31:
                errors.setdefault("due_day", []).append("The due day field must be between 1 and 31.")

        raise_if(errors)

        return {"academic_year": year, "frequency": frequency, "amount": amount, "due_day": due_day}


def terms_of(year) -> list[plan.Term]:
    return [
        plan.Term(term.name, term.start_date)
        for term in year.terms.order_by("sequence_number", "id")
    ]


# -- the balances list (F2) ---------------------------------------------------

TRUTHY = ("1", "true", "yes", "on")


class BalancesRequest:
    """`GET fees/balances`: a year (required), and optionally a class and a
    section of that year, a search, and `owing` / `overdue` switches. A Super
    Admin or Group Admin reaches the school through the year, as the
    structures list does. Another school's class or section is "invalid"."""

    def __init__(self, params, actor) -> None:
        self.params = params
        self.actor = actor

    def validate(self) -> dict:
        errors: dict[str, list[str]] = {}
        keys = ("academic_year_id", "school_id", "school_class_id", "class_section_id", "search", "owing", "overdue")
        params = normalise({key: self.params.get(key) for key in keys})

        year = year_in_scope(self.actor, params["academic_year_id"], errors, params["school_id"])
        class_id = integer("school_class_id", params["school_class_id"], errors, optional=True)
        section_id = integer("class_section_id", params["class_section_id"], errors, optional=True)

        if year is not None:
            if class_id is not None and not SchoolClass.objects.filter(pk=class_id, academic_year_id=year.id).exists():
                errors.setdefault("school_class_id", []).append(does_not_exist("school_class_id"))

            if section_id is not None and not ClassSection.objects.filter(
                pk=section_id, school_class__academic_year_id=year.id
            ).exists():
                errors.setdefault("class_section_id", []).append(does_not_exist("class_section_id"))

        raise_if(errors)

        search = params["search"]

        return {
            "academic_year": year,
            "school_class_id": class_id,
            "class_section_id": section_id,
            "search": search.strip() if isinstance(search, str) and search.strip() else None,
            "owing": str(params["owing"]).lower() in TRUTHY,
            "overdue": str(params["overdue"]).lower() in TRUTHY,
        }


# -- receipts (F3) --------------------------------------------------------------

REFERENCE_MAX = 100
NOTE_MAX = 500
REASON_MIN = 3
REASON_MAX = 500
MAX_ALLOCATIONS = 200


def text(field: str, raw, errors: dict, maximum: int) -> str | None:
    """An optional free-text field: a string no longer than `maximum`."""
    if raw is None:
        return None

    if not isinstance(raw, str):
        errors.setdefault(field, []).append(must_be_a_string(field))
        return None

    if len(raw) > maximum:
        errors.setdefault(field, []).append(too_long(field, maximum))
        return None

    return raw


def student_in_scope(actor, raw, errors: dict, requested_school=None) -> Student | None:
    """The student named by `student_id`, if the actor can reach them.
    Another school's student reads as invalid, like one that does not exist."""
    student_id = integer("student_id", raw, errors)

    if student_id is None:
        return None

    students = SchoolScope.for_actor(actor).apply_to(Student.objects.select_related("school"), requested_school)
    student = students.filter(pk=student_id).first()

    if student is None:
        errors.setdefault("student_id", []).append(does_not_exist("student_id"))

    return student


def year_covering(school_id: int, day: dt.date) -> AcademicYear | None:
    """The school's academic year whose dates contain `day` - the year a
    receipt dated that day is numbered in. Should two ever overlap, the one
    that started later wins."""
    return (
        AcademicYear.objects.filter(school_id=school_id, start_date__lte=day, end_date__gte=day)
        .order_by("-start_date", "-id")
        .first()
    )


class FeeReceiptRequest:
    """`POST fees/receipts`: everything that can be checked without the
    student's dues in hand. What the dues allow - how much is owed, whether a
    part payment leaves an installment half paid - is checked by
    fees/receipts.py under the lock, where the answer cannot change before the
    payment is written."""

    def __init__(self, data, actor) -> None:
        self.raw = data if isinstance(data, dict) else {}
        self.data = normalise(self.raw)
        self.actor = actor

    def validate(self) -> dict:
        errors: dict[str, list[str]] = {}
        data = self.data

        student = student_in_scope(self.actor, data.get("student_id"), errors)
        amount = money("amount", data.get("amount"), errors)
        receipt_date = self.date(data.get("receipt_date"), student, errors)
        mode = self.mode(data.get("payment_mode"), errors)
        reference = text("reference", data.get("reference"), errors, REFERENCE_MAX)
        note = text("note", data.get("note"), errors, NOTE_MAX)
        allocations = self.allocations(data.get("allocations"), errors)

        if mode == FeePaymentMode.CHEQUE and reference is None and "reference" not in errors:
            errors.setdefault("reference", []).append("Enter the cheque number.")

        email = False

        if data.get("email_to_guardian") is not None:
            try:
                email = LaravelBooleanField("email_to_guardian").to_internal_value(data["email_to_guardian"])
            except serializers.ValidationError as failure:
                errors.setdefault("email_to_guardian", []).extend(str(message) for message in failure.detail)

        year = None

        if student is not None and receipt_date is not None:
            year = year_covering(student.school_id, receipt_date)

            if year is None:
                errors.setdefault("receipt_date", []).append(
                    "No academic year covers this date. Add one under Academic Years first."
                )

        raise_if(errors)

        return {
            "student": student,
            "academic_year": year,
            "receipt_date": receipt_date,
            "amount": amount,
            "payment_mode": mode,
            "reference": reference,
            "note": note,
            "allocations": allocations,
            "email_to_guardian": email,
        }

    @staticmethod
    def date(raw, student, errors: dict) -> dt.date | None:
        if raw is None:
            errors.setdefault("receipt_date", []).append(required("receipt_date"))
            return None

        day = parse_date(raw)

        if day is None:
            errors.setdefault("receipt_date", []).append(not_a_date("receipt_date"))
            return None

        # The school's today, not the server's (docs/timezones.md).
        if student is not None and day > SchoolClock.for_school(student.school_id).now().date():
            errors.setdefault("receipt_date", []).append("The receipt date can't be in the future.")
            return None

        return day

    @staticmethod
    def mode(raw, errors: dict) -> str | None:
        if raw is None:
            errors.setdefault("payment_mode", []).append(required("payment_mode"))
            return None

        if raw not in FeePaymentMode.values:
            errors.setdefault("payment_mode", []).append(selected_is_invalid("payment_mode"))
            return None

        return raw

    @staticmethod
    def allocations(raw, errors: dict) -> list[tuple[int, Decimal]] | None:
        """[(due id, amount)], or None when the payment is to be spread
        oldest first. Shape only: whose dues they are, and what is left on
        them, is the service's to check under the lock."""
        if raw is None:
            return None

        if not isinstance(raw, list) or not raw:
            errors.setdefault("allocations", []).append(
                "Choose at least one installment to pay, or leave the list out."
            )
            return None

        if len(raw) > MAX_ALLOCATIONS:
            errors.setdefault("allocations", []).append(f"A receipt can pay at most {MAX_ALLOCATIONS} installments.")
            return None

        cleaned: list[tuple[int, Decimal]] = []
        problems: list[str] = []

        for index, item in enumerate(raw, start=1):
            item = item if isinstance(item, dict) else {}
            local: dict[str, list[str]] = {}
            due_id = integer("due_id", item.get("due_id"), local)
            part = money("amount", item.get("amount"), local)

            if local:
                problems.append(f"Line {index} needs an installment (due_id) and an amount more than zero.")
                continue

            cleaned.append((due_id, part))

        if problems:
            errors.setdefault("allocations", []).extend(problems)
            return None

        # Duplicates are named by the service, which knows the installment's
        # label.
        return cleaned


class CancelFeeReceiptRequest:
    """`POST fees/receipts/{id}/cancel`: a reason, 3 to 500 characters."""

    def __init__(self, data) -> None:
        self.data = normalise(data) if isinstance(data, dict) else {}

    def validate(self) -> str:
        reason = self.data.get("reason")
        errors: dict[str, list[str]] = {}

        if reason is None:
            errors["reason"] = [required("reason")]
        elif not isinstance(reason, str):
            errors["reason"] = [must_be_a_string("reason")]
        elif len(reason) < REASON_MIN:
            errors["reason"] = [too_short("reason", REASON_MIN)]
        elif len(reason) > REASON_MAX:
            errors["reason"] = [too_long("reason", REASON_MAX)]

        raise_if(errors)

        return reason


class FeeCreditRefundRequest:
    """`POST fees/students/{id}/credit/refund`: money handed back to the
    family out of their credit (F6). Whether the credit holds that much is
    fees/credit.py's to check under the lock. The currency is the school's
    unless named - a student's credit is in the currency their fees are."""

    def __init__(self, data, student: Student) -> None:
        self.data = normalise(data) if isinstance(data, dict) else {}
        self.student = student

    def validate(self) -> dict:
        errors: dict[str, list[str]] = {}
        data = self.data

        amount = money("amount", data.get("amount"), errors)
        refund_date = self.date(data.get("refund_date"), errors)
        mode = FeeReceiptRequest.mode(data.get("payment_mode"), errors)
        reference = text("reference", data.get("reference"), errors, REFERENCE_MAX)
        reason = data.get("reason")
        currency = data.get("currency_code") or self.student.school.currency_code

        if not isinstance(currency, str) or len(currency) != 3:
            errors.setdefault("currency_code", []).append(selected_is_invalid("currency_code"))

        if reason is None:
            errors.setdefault("reason", []).append(required("reason"))
        elif not isinstance(reason, str):
            errors.setdefault("reason", []).append(must_be_a_string("reason"))
        elif len(reason) < REASON_MIN:
            errors.setdefault("reason", []).append(too_short("reason", REASON_MIN))
        elif len(reason) > REASON_MAX:
            errors.setdefault("reason", []).append(too_long("reason", REASON_MAX))

        if mode == FeePaymentMode.CHEQUE and reference is None and "reference" not in errors:
            errors.setdefault("reference", []).append("Enter the cheque number.")

        raise_if(errors)

        return {
            "amount": amount,
            "currency_code": currency.upper(),
            "refund_date": refund_date,
            "payment_mode": mode,
            "reference": reference,
            "reason": reason,
        }

    def date(self, raw, errors: dict) -> dt.date | None:
        if raw is None:
            errors.setdefault("refund_date", []).append(required("refund_date"))
            return None

        day = parse_date(raw)

        if day is None:
            errors.setdefault("refund_date", []).append(not_a_date("refund_date"))
            return None

        # The school's today, not the server's (docs/timezones.md).
        if day > SchoolClock.for_school(self.student.school_id).now().date():
            errors.setdefault("refund_date", []).append("The refund date can't be in the future.")
            return None

        return day


class FeeReceiptListRequest:
    """`GET fees/receipts`: which school's receipts, and the filters.

    The school: a school-bound actor's own. A Super Admin or Group Admin
    reaches one through `academic_year_id` when given (as the balances list
    does), else `school_id`; naming neither lists every school in their
    scope that has fees on, as the fee types list does. Another school's
    year or student is "invalid"."""

    KEYS = ("academic_year_id", "school_id", "student_id", "search", "payment_mode", "status", "from", "to")

    def __init__(self, params, actor) -> None:
        self.params = params
        self.actor = actor

    def validate(self) -> dict:
        errors: dict[str, list[str]] = {}
        params = normalise({key: self.params.get(key) for key in self.KEYS})

        year = None

        if params["academic_year_id"] is not None:
            year = year_in_scope(self.actor, params["academic_year_id"], errors, params["school_id"])

        student = None

        if params["student_id"] is not None:
            narrowed = year.school_id if year is not None else params["school_id"]
            student = student_in_scope(self.actor, params["student_id"], errors, narrowed)

        mode = params["payment_mode"]

        if mode is not None and mode not in FeePaymentMode.values:
            errors.setdefault("payment_mode", []).append(selected_is_invalid("payment_mode"))

        state = params["status"]

        if state is not None and state not in FeeReceiptStatus.values:
            errors.setdefault("status", []).append(selected_is_invalid("status"))

        start = end = None

        for key in ("from", "to"):
            if params[key] is None:
                continue

            day = parse_date(params[key])

            if day is None:
                errors.setdefault(key, []).append(not_a_date(key))
            elif key == "from":
                start = day
            else:
                end = day

        if start is not None and end is not None and end < start:
            errors.setdefault("to", []).append(must_be_after("to", "from"))

        raise_if(errors)

        search = params["search"]

        return {
            "academic_year": year,
            "school_id": params["school_id"],
            "student": student,
            "payment_mode": mode,
            "status": state,
            "from": start,
            "to": end,
            "search": search if isinstance(search, str) and search else None,
        }


# -- discounts and waivers (F4) ---------------------------------------------------

ADJUSTMENT_REASON_MAX = 255


def reason_of(raw, errors: dict, *, optional: bool = False) -> str | None:
    """A reason: 3 to 255 characters once trimmed. Optional on a revoke."""
    if raw is None:
        if not optional:
            errors.setdefault("reason", []).append(required("reason"))
        return None

    if not isinstance(raw, str):
        errors.setdefault("reason", []).append(must_be_a_string("reason"))
        return None

    reason = raw.strip()

    if optional and reason == "":
        return None

    if len(reason) < REASON_MIN:
        errors.setdefault("reason", []).append(too_short("reason", REASON_MIN))
        return None

    if len(reason) > ADJUSTMENT_REASON_MAX:
        errors.setdefault("reason", []).append(too_long("reason", ADJUSTMENT_REASON_MAX))
        return None

    return reason


class FeeConcessionRequest:
    """`POST fees/concessions`: a discount for one student and one academic
    year, off one fee type (or every one, `fee_head_id` null), fixed or a
    percentage, with a reason.

    The student and the year must be the actor's to reach and belong to one
    school; another school's student, year or fee type is "invalid", as if
    it did not exist. The student must be enrolled in the year or owe
    something in it - a discount on nothing would be a lie on a screen."""

    def __init__(self, data, actor) -> None:
        self.data = normalise(data) if isinstance(data, dict) else {}
        self.actor = actor

    def validate(self) -> dict:
        errors: dict[str, list[str]] = {}
        data = self.data

        student = student_in_scope(self.actor, data.get("student_id"), errors)
        year_id = integer("academic_year_id", data.get("academic_year_id"), errors)
        head_id = integer("fee_head_id", data.get("fee_head_id"), errors, optional=True)
        kind = data.get("kind")
        reason = reason_of(data.get("reason"), errors)

        if kind is None:
            errors.setdefault("kind", []).append(required("kind"))
        elif kind not in FeeConcessionKind.values:
            errors.setdefault("kind", []).append(selected_is_invalid("kind"))
            kind = None

        value = money("value", data.get("value"), errors)

        if value is not None and kind == FeeConcessionKind.PERCENT and value > 100:
            errors.setdefault("value", []).append("A percentage can't be more than 100.")

        year = head = None

        if student is not None and year_id is not None:
            year = AcademicYear.objects.filter(pk=year_id, school_id=student.school_id).first()

            if year is None:
                errors.setdefault("academic_year_id", []).append(does_not_exist("academic_year_id"))
        elif year_id is not None:
            # No student to check it against: still never say whether another
            # school's year exists.
            year = year_in_scope(self.actor, year_id, errors)

        if student is not None and head_id is not None:
            head = FeeHead.objects.filter(pk=head_id, school_id=student.school_id).first()

            if head is None:
                errors.setdefault("fee_head_id", []).append(does_not_exist("fee_head_id"))
            elif not head.is_active:
                errors.setdefault("fee_head_id", []).append(
                    f"The {head.name} fee type is retired. Bring it back before giving a discount on it."
                )

        if student is not None and year is not None and "academic_year_id" not in errors:
            enrolled = StudentEnrollment.objects.filter(student_id=student.id, academic_year_id=year.id).exists()
            owes = StudentFeeDue.objects.filter(student_id=student.id, academic_year_id=year.id).exists()

            if not enrolled and not owes:
                errors.setdefault("student_id", []).append(
                    f"{student.name} is not enrolled in {year.name} and has no fees in it."
                )

        raise_if(errors)

        return {
            "student": student,
            "academic_year": year,
            "fee_head": head,
            "kind": kind,
            "value": value,
            "reason": reason,
        }


class RevokeFeeConcessionRequest:
    """`DELETE fees/concessions/{id}`: an optional reason, kept in the audit
    trail."""

    def __init__(self, data) -> None:
        self.data = normalise(data) if isinstance(data, dict) else {}

    def validate(self) -> str | None:
        errors: dict[str, list[str]] = {}
        reason = reason_of(self.data.get("reason"), errors, optional=True)
        raise_if(errors)

        return reason


class WaiveFeeDueRequest:
    """`POST fees/dues/{id}/waive`: a reason, 3 to 255 characters."""

    def __init__(self, data) -> None:
        self.data = normalise(data) if isinstance(data, dict) else {}

    def validate(self) -> str:
        errors: dict[str, list[str]] = {}
        reason = reason_of(self.data.get("reason"), errors)
        raise_if(errors)

        return reason


class FeeConcessionListRequest:
    """`GET fees/concessions`: which school's discounts, and the filters -
    the school found as the receipts list finds it (through the year, else
    `school_id`, else every school in the actor's scope with fees on)."""

    KEYS = ("academic_year_id", "school_id", "student_id", "include_revoked")

    def __init__(self, params, actor) -> None:
        self.params = params
        self.actor = actor

    def validate(self) -> dict:
        errors: dict[str, list[str]] = {}
        params = normalise({key: self.params.get(key) for key in self.KEYS})

        year = None

        if params["academic_year_id"] is not None:
            year = year_in_scope(self.actor, params["academic_year_id"], errors, params["school_id"])

        student = None

        if params["student_id"] is not None:
            narrowed = year.school_id if year is not None else params["school_id"]
            student = student_in_scope(self.actor, params["student_id"], errors, narrowed)

        raise_if(errors)

        return {
            "academic_year": year,
            "school_id": params["school_id"],
            "student": student,
            "include_revoked": str(params["include_revoked"]).lower() in TRUTHY,
        }
