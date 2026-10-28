"""The three fee reports (docs/fees.md, F5; docs/reports.md).

- **Fee collection** - every valid receipt dated in the range, one line
  each. Cancelled receipts are left out of the lines and the money, and
  counted beside it, so a cancelled one can never inflate what was taken.
- **Outstanding fees** - "as at" the range's end: every student still owing
  on dues that fell due on or before that day, with how long it has been
  overdue (1-30, 31-60, 61+ days past the due date). What is owed is what is
  owed *now* on those dues - a payment made after the day counts - because
  the ledger keeps balances, not their history. Beside it, the credit the
  school holds for families as at that day (F6) - money paid that nothing
  is owed against yet, which the school owes back if it is never used.
- **Discounts & waivers** - discounts given and dues waived in the range,
  each with who, why and how much.

Money, as payroll's report has it (CLAUDE.md rule 5): every line carries its
own `currency_code`, and every money total is a list with one entry per
currency - never one figure added across two. Money goes out as strings with
two decimals; dates as `YYYY-MM-DD`.

Nothing here has a working-day denominator, so these reports never ask the
ReportRange for one; their PDFs leave the working days out.
"""

from __future__ import annotations

import datetime as dt
import zoneinfo
from collections import defaultdict
from decimal import Decimal

from django.db.models import F, Min, Q, Sum

from .. import dates, money
from ..clock import SchoolClock
from ..enums import FeeConcessionKind, FeeDueKind, FeeDueStatus, FeeReceiptStatus
from ..models import (
    AcademicYear,
    FeeConcession,
    FeeReceipt,
    Student,
    StudentEnrollment,
    StudentFeeCredit,
    StudentFeeDue,
)
from ..services import php_number
from .range import ReportRange

ZERO = Decimal("0.00")
OPEN = (FeeDueStatus.PENDING, FeeDueStatus.PARTIAL)


def cash(value) -> str:
    return f"{(value or ZERO):.2f}"


def class_section(enrollment=None, section=None) -> str | None:
    """"Class 8 - A" from a year's enrollment, else from a current section."""
    if enrollment is not None:
        school_class = enrollment.school_class.name
        section = enrollment.class_section if enrollment.class_section_id else None

        return school_class if section is None else f"{school_class} - {section.name}"

    if section is not None:
        return f"{section.school_class.name} - {section.name}"

    return None


def enrollments_of(pairs) -> dict[tuple[int, int], StudentEnrollment]:
    """(student, year) -> enrollment, in one query."""
    pairs = set(pairs)

    if not pairs:
        return {}

    return {
        (row.student_id, row.academic_year_id): row
        for row in StudentEnrollment.objects.filter(
            student_id__in={student for student, _ in pairs}, academic_year_id__in={year for _, year in pairs}
        ).select_related("school_class", "class_section")
    }


def per_currency(entries, keys) -> list[dict]:
    """Money summed per currency, in currency order. Counts (ints) add up
    too; money stays a string with two decimals."""
    sums: dict[str, dict] = {}

    for entry in entries:
        total = sums.setdefault(entry["currency_code"], {})
        for key in keys:
            value = entry.get(key)
            if isinstance(value, int):
                total[key] = total.get(key, 0) + value
            elif value is not None:
                total[key] = total.get(key, ZERO) + Decimal(value)

    return [
        {
            "currency_code": code,
            **{
                key: total.get(key, 0) if isinstance(total.get(key), int) else cash(total.get(key, ZERO))
                for key in keys
            },
        }
        for code, total in sorted(sums.items())
    ]


def amount_or_none(value: str | None):
    """A money string as a number for the CSV and PDF, so it lines up."""
    return None if value is None else Decimal(value)


def instants(report_range: ReportRange) -> tuple[dt.datetime, dt.datetime]:
    """The range's first and last school-local days as UTC instants, the end
    exclusive - for timestamps, which are stored in UTC."""
    clock = SchoolClock.for_school(report_range.school_id)

    return clock.start_of_day_utc(report_range.start), clock.end_of_day_utc(report_range.end)


def money_line(label: str, entries: list[dict], key: str, previous: list[dict] | None) -> list[tuple]:
    """One PDF summary line per currency."""
    before = {entry["currency_code"]: entry for entry in previous or []}
    lines = []

    for entry in entries:
        code = entry["currency_code"]
        earlier = before.get(code)
        was = None if previous is None else (money.formatted(Decimal(earlier[key]), code) if earlier else "-")
        lines.append((f"{label} ({code})", money.formatted(Decimal(entry[key]), code), was))

    if not entries:
        lines.append((label, "-", None if previous is None else "-"))

    return lines


def count_line(label: str, value, previous) -> tuple:
    return (label, str(value), None if previous is None else str(previous))


# -- collection -------------------------------------------------------------------


class FeeCollectionReport:
    TITLE = "Fee collection"
    PDF_NOTE = (
        "Valid receipts dated in the period. Cancelled receipts are left out of the lines and the totals, "
        "and counted separately. Money is never added across currencies."
    )
    SHOWS_WORKING_DAYS = False
    COMPARED_ROWS: list = []

    @staticmethod
    def row_key(row: dict):
        return row["receipt_id"]

    def build(self, report_range: ReportRange, filters: dict) -> dict:
        receipts = list(
            FeeReceipt.objects.filter(
                school_id=report_range.school_id,
                receipt_date__gte=report_range.start,
                receipt_date__lte=report_range.end,
            )
            .select_related("student", "received_by")
            .order_by("receipt_date", "receipt_number", "id")
        )
        valid = [receipt for receipt in receipts if receipt.status != FeeReceiptStatus.CANCELLED]
        cancelled = [receipt for receipt in receipts if receipt.status == FeeReceiptStatus.CANCELLED]
        enrollments = enrollments_of((receipt.student_id, receipt.academic_year_id) for receipt in valid)
        labels = dict(_modes())

        rows = [
            {
                "receipt_id": receipt.id,
                "student_id": receipt.student_id,
                "receipt_date": receipt.receipt_date.isoformat(),
                "receipt_number": receipt.receipt_number,
                "admission_number": receipt.student.admission_number,
                "student": receipt.student.name,
                "class_section": class_section(enrollments.get((receipt.student_id, receipt.academic_year_id))),
                "payment_mode": labels.get(receipt.payment_mode, receipt.payment_mode),
                "reference": receipt.reference,
                "received_by": receipt.received_by.name if receipt.received_by_id else None,
                "amount": cash(receipt.amount),
                "currency_code": receipt.currency_code,
            }
            for receipt in valid
        ]

        by_mode: dict[tuple[str, str], dict] = {}
        for receipt in valid:
            line = by_mode.setdefault((receipt.payment_mode, receipt.currency_code), {
                "payment_mode": receipt.payment_mode,
                "label": labels.get(receipt.payment_mode, receipt.payment_mode),
                "currency_code": receipt.currency_code,
                "receipts": 0,
                "amount": ZERO,
            })
            line["receipts"] += 1
            line["amount"] += receipt.amount

        return {
            "range": report_range.to_dict(),
            "rows": rows,
            "totals": {
                "receipts": len(valid),
                "collected": per_currency(
                    [{"currency_code": r.currency_code, "amount": cash(r.amount)} for r in valid], ["amount"]
                ),
                "cancelled_receipts": len(cancelled),
                "cancelled_amount": per_currency(
                    [{"currency_code": r.currency_code, "amount": cash(r.amount)} for r in cancelled], ["amount"]
                ),
                "by_mode": [
                    {**line, "amount": cash(line["amount"])}
                    for _, line in sorted(by_mode.items(), key=lambda item: (item[0][1], item[1]["label"]))
                ],
            },
        }

    def headings(self) -> list[str]:
        return [
            "Date", "Receipt", "Admission no.", "Student", "Class", "Paid by", "Reference", "Received by",
            "Currency", "Amount",
        ]

    def csv_rows(self, report: dict) -> list[list]:
        return [
            [
                dates.us_from_iso(row["receipt_date"]), row["receipt_number"], row["admission_number"], row["student"],
                row["class_section"], row["payment_mode"], row["reference"], row["received_by"],
                row["currency_code"], amount_or_none(row["amount"]),
            ]
            for row in report["rows"]
        ]

    def combine_totals(self, branch_totals: list[dict]) -> dict:
        by_mode: dict[tuple[str, str], dict] = {}
        for totals in branch_totals:
            for line in totals["by_mode"]:
                merged = by_mode.setdefault((line["payment_mode"], line["currency_code"]), {**line, "receipts": 0,
                                                                                            "amount": ZERO})
                merged["receipts"] += line["receipts"]
                merged["amount"] += Decimal(line["amount"])

        return {
            "branches": len(branch_totals),
            "receipts": sum(totals["receipts"] for totals in branch_totals),
            "collected": per_currency([entry for totals in branch_totals for entry in totals["collected"]], ["amount"]),
            "cancelled_receipts": sum(totals["cancelled_receipts"] for totals in branch_totals),
            "cancelled_amount": per_currency(
                [entry for totals in branch_totals for entry in totals["cancelled_amount"]], ["amount"]
            ),
            "by_mode": [
                {**line, "amount": cash(line["amount"])}
                for _, line in sorted(by_mode.items(), key=lambda item: (item[0][1], item[1]["label"]))
            ],
        }

    def pdf_totals(self, totals: dict, previous: dict | None) -> list[tuple]:
        lines = [count_line("Receipts", totals["receipts"], None if previous is None else previous["receipts"])]
        lines += money_line("Collected", totals["collected"], "amount", None if previous is None else previous["collected"])

        for line in totals["by_mode"]:
            lines.append((
                f"{line['label']} ({line['currency_code']})",
                f"{money.formatted(Decimal(line['amount']), line['currency_code'])} - {line['receipts']} receipts",
                None,
            ))

        lines.append(count_line(
            "Cancelled receipts", totals["cancelled_receipts"],
            None if previous is None else previous["cancelled_receipts"],
        ))
        for entry in totals["cancelled_amount"]:
            lines.append((f"Cancelled ({entry['currency_code']})",
                          money.formatted(Decimal(entry["amount"]), entry["currency_code"]), None))

        return lines


def _modes():
    from ..enums import FeePaymentMode

    return FeePaymentMode.choices


# -- outstanding ------------------------------------------------------------------


class FeeOutstandingReport:
    TITLE = "Outstanding fees"
    PDF_NOTE = (
        "What each student still owes on dues that fell due on or before the end of the period, and how many days "
        "past its due date each part is. Payments made since are counted. Money is never added across currencies."
    )
    SHOWS_WORKING_DAYS = False
    COMPARED_ROWS: list = []
    MONEY = ("charged", "paid", "balance", "overdue_0_30", "overdue_31_60", "overdue_61_plus")
    TOTAL_MONEY = ("balance", "overdue_0_30", "overdue_31_60", "overdue_61_plus")

    @staticmethod
    def row_key(row: dict):
        return (row["student_id"], row["currency_code"])

    def build(self, report_range: ReportRange, filters: dict) -> dict:
        school_id = report_range.school_id
        as_of = report_range.end
        owing = F("amount") - F("discount_amount") - F("paid_amount")
        still_owed = Q(status__in=OPEN, amount__gt=F("discount_amount") + F("paid_amount"))
        day = dt.timedelta(days=1)

        # One grouped query: a line per student and currency. Waived and
        # cancelled dues owe nothing and were never money to collect.
        lines = list(
            StudentFeeDue.objects.filter(school_id=school_id, due_date__lte=as_of)
            .exclude(status__in=(FeeDueStatus.CANCELLED, FeeDueStatus.WAIVED))
            .order_by()
            .values("student_id", "currency_code")
            .annotate(
                charged=Sum(F("amount") - F("discount_amount")),
                paid=Sum("paid_amount"),
                balance=Sum(owing, filter=still_owed),
                # Days past due as at the day - due yesterday is 1 day, and
                # "0-30" holds 1 to 30 (due on the day is not overdue yet).
                overdue_0_30=Sum(owing, filter=still_owed & Q(due_date__lt=as_of, due_date__gte=as_of - 30 * day)),
                overdue_31_60=Sum(
                    owing, filter=still_owed & Q(due_date__lt=as_of - 30 * day, due_date__gte=as_of - 60 * day)
                ),
                overdue_61_plus=Sum(owing, filter=still_owed & Q(due_date__lt=as_of - 60 * day)),
                oldest_due_date=Min("due_date", filter=still_owed),
            )
            .filter(balance__gt=0)
        )

        students = {
            student.id: student
            for student in Student.objects.filter(pk__in={line["student_id"] for line in lines}).select_related(
                "class_section__school_class"
            )
        }
        year = (
            AcademicYear.objects.filter(school_id=school_id, start_date__lte=as_of, end_date__gte=as_of)
            .order_by("-start_date", "-id").first()
        )
        enrollments = {} if year is None else enrollments_of((student_id, year.id) for student_id in students)

        rows = []
        for line in lines:
            student = students[line["student_id"]]
            enrollment = None if year is None else enrollments.get((student.id, year.id))
            section = student.class_section if student.class_section_id else None
            rows.append({
                "student_id": student.id,
                "admission_number": student.admission_number,
                "student": student.name,
                "class_section": class_section(enrollment, None if enrollment else section),
                "guardian": student.guardian_name,
                "guardian_mobile": student.guardian_mobile,
                **{key: cash(line[key]) for key in self.MONEY},
                "oldest_due_date": None if line["oldest_due_date"] is None else line["oldest_due_date"].isoformat(),
                "currency_code": line["currency_code"],
            })

        rows.sort(key=lambda row: (-Decimal(row["balance"]), row["student"].lower(), row["student_id"]))

        return {
            "range": {**report_range.to_dict(), "as_of": as_of.isoformat()},
            "rows": rows,
            "totals": {
                "students": len({row["student_id"] for row in rows}),
                "by_currency": per_currency(
                    [{**row, "students": 1} for row in rows], ["students", *self.TOTAL_MONEY]
                ),
                "credit_held": self.credit_held(school_id, as_of),
            },
        }

    @staticmethod
    def credit_held(school_id: int, as_of: dt.date) -> list[dict]:
        """The credit families hold at the school as at the day, per
        currency: every movement up to and including it, added up."""
        rows = (
            StudentFeeCredit.objects.filter(school_id=school_id, entry_date__lte=as_of)
            .order_by()
            .values("currency_code")
            .annotate(amount=Sum("amount"))
        )

        return per_currency([row for row in rows if row["amount"]], ["amount"])

    def headings(self) -> list[str]:
        return [
            "Admission no.", "Student", "Class", "Guardian", "Guardian mobile", "Currency", "Charged", "Paid",
            "Balance", "Overdue 0-30 days", "Overdue 31-60 days", "Overdue 61+ days", "Oldest due",
        ]

    def csv_rows(self, report: dict) -> list[list]:
        return [
            [
                row["admission_number"], row["student"], row["class_section"], row["guardian"],
                row["guardian_mobile"], row["currency_code"],
                *[amount_or_none(row[key]) for key in self.MONEY],
                dates.us_from_iso(row["oldest_due_date"]) if row["oldest_due_date"] else None,
            ]
            for row in report["rows"]
        ]

    def combine_totals(self, branch_totals: list[dict]) -> dict:
        return {
            "branches": len(branch_totals),
            "students": sum(totals["students"] for totals in branch_totals),
            "by_currency": per_currency(
                [entry for totals in branch_totals for entry in totals["by_currency"]],
                ["students", *self.TOTAL_MONEY],
            ),
            "credit_held": per_currency(
                [entry for totals in branch_totals for entry in totals.get("credit_held", [])], ["amount"]
            ),
        }

    def pdf_totals(self, totals: dict, previous: dict | None) -> list[tuple]:
        before = None if previous is None else previous["by_currency"]
        lines = [count_line("Students owing", totals["students"], None if previous is None else previous["students"])]
        lines += money_line("Outstanding", totals["by_currency"], "balance", before)

        for key, label in (
            ("overdue_0_30", "Overdue 0-30 days"), ("overdue_31_60", "Overdue 31-60 days"),
            ("overdue_61_plus", "Overdue 61+ days"),
        ):
            lines += money_line(label, totals["by_currency"], key, before)

        if totals.get("credit_held"):
            lines += money_line(
                "Credit held for families", totals["credit_held"], "amount",
                None if previous is None else previous.get("credit_held", []),
            )

        return lines


# -- discounts and waivers ----------------------------------------------------------


class FeeConcessionsReport:
    TITLE = "Discounts & waivers"
    PDF_NOTE = (
        "Discounts given and dues waived in the period. A discount's amount is what it takes off the student's "
        "fees that year as they stand today; an ended discount takes nothing off any more. "
        "Money is never added across currencies."
    )
    SHOWS_WORKING_DAYS = False
    COMPARED_ROWS: list = []

    @staticmethod
    def row_key(row: dict):
        return (row["type"], row["id"])

    def build(self, report_range: ReportRange, filters: dict) -> dict:
        school_id = report_range.school_id
        clock = SchoolClock.for_school(school_id)
        start, end = instants(report_range)

        concessions = list(
            FeeConcession.objects.filter(school_id=school_id, created_at__gte=start, created_at__lt=end)
            .select_related("student", "fee_head", "created_by", "school")
        )
        waivers = list(
            StudentFeeDue.objects.filter(
                school_id=school_id, status=FeeDueStatus.WAIVED, waived_at__gte=start, waived_at__lt=end
            ).select_related("student", "fee_head", "waived_by")
        )
        enrollments = enrollments_of(
            [(c.student_id, c.academic_year_id) for c in concessions]
            + [(w.student_id, w.academic_year_id) for w in waivers]
        )
        given = discounts_given([c for c in concessions if c.revoked_at is None])

        rows = []
        for concession in concessions:
            currency = concession.school.currency_code
            rows.append({
                "id": concession.id,
                "student_id": concession.student_id,
                "date": local_date(clock, concession.created_at),
                "type": "Discount",
                "admission_number": concession.student.admission_number,
                "student": concession.student.name,
                "class_section": class_section(enrollments.get((concession.student_id, concession.academic_year_id))),
                "fee_type": concession.fee_head.name if concession.fee_head_id else "All fee types",
                "detail": discount_detail(concession, currency),
                "amount": None if concession.revoked_at is not None else cash(given.get(concession.id, ZERO)),
                "reason": concession.reason,
                "by": concession.created_by.name if concession.created_by_id else None,
                "status": "Ended" if concession.revoked_at is not None else "Active",
                "currency_code": currency,
            })

        for due in waivers:
            rows.append({
                "id": due.id,
                "student_id": due.student_id,
                "date": local_date(clock, due.waived_at),
                "type": "Waiver",
                "admission_number": due.student.admission_number,
                "student": due.student.name,
                "class_section": class_section(enrollments.get((due.student_id, due.academic_year_id))),
                "fee_type": due.fee_head.name,
                "detail": due.label,
                # What was still owed on it: a waived due takes no more money.
                "amount": cash(max(ZERO, due.amount - due.discount_amount - due.paid_amount)),
                "reason": due.waive_reason,
                "by": due.waived_by.name if due.waived_by_id else None,
                "status": "Waived",
                "currency_code": due.currency_code,
            })

        rows.sort(key=lambda row: (row["date"], row["type"], row["student"].lower(), row["id"]))

        return {
            "range": report_range.to_dict(),
            "rows": rows,
            "totals": {
                "discounts": len(concessions),
                "discounts_active": sum(1 for c in concessions if c.revoked_at is None),
                "waivers": len(waivers),
                "discounted": per_currency(
                    [row for row in rows if row["type"] == "Discount" and row["amount"] is not None], ["amount"]
                ),
                "waived": per_currency([row for row in rows if row["type"] == "Waiver"], ["amount"]),
            },
        }

    def headings(self) -> list[str]:
        return [
            "Date", "Type", "Admission no.", "Student", "Class", "Fee type", "Detail", "Currency", "Amount", "Reason",
            "By", "Status",
        ]

    def csv_rows(self, report: dict) -> list[list]:
        return [
            [
                dates.us_from_iso(row["date"]), row["type"], row["admission_number"], row["student"],
                row["class_section"], row["fee_type"], row["detail"], row["currency_code"],
                amount_or_none(row["amount"]), row["reason"], row["by"], row["status"],
            ]
            for row in report["rows"]
        ]

    def combine_totals(self, branch_totals: list[dict]) -> dict:
        return {
            "branches": len(branch_totals),
            "discounts": sum(totals["discounts"] for totals in branch_totals),
            "discounts_active": sum(totals["discounts_active"] for totals in branch_totals),
            "waivers": sum(totals["waivers"] for totals in branch_totals),
            "discounted": per_currency([e for totals in branch_totals for e in totals["discounted"]], ["amount"]),
            "waived": per_currency([e for totals in branch_totals for e in totals["waived"]], ["amount"]),
        }

    def pdf_totals(self, totals: dict, previous: dict | None) -> list[tuple]:
        def earlier(key):
            return None if previous is None else previous[key]

        lines = [
            count_line("Discounts given", totals["discounts"], earlier("discounts")),
            count_line("Still active", totals["discounts_active"], earlier("discounts_active")),
        ]
        lines += money_line("Discounted", totals["discounted"], "amount", earlier("discounted"))
        lines.append(count_line("Waivers", totals["waivers"], earlier("waivers")))
        lines += money_line("Waived", totals["waived"], "amount", earlier("waived"))

        return lines


def local_date(clock: SchoolClock, instant) -> str | None:
    """The school-local day of a stored instant, ISO."""
    if instant is None:
        return None

    return instant.astimezone(zoneinfo.ZoneInfo(clock.timezone())).date().isoformat()


def discount_detail(concession, currency: str) -> str:
    """"INR 500.00 off each installment" / "10% off each installment"."""
    if concession.kind == FeeConcessionKind.PERCENT:
        value = php_number(float(concession.value))
        return f"{value}% off each installment"

    return f"{money.formatted(concession.value, currency)} off each installment"


def discounts_given(concessions) -> dict[int, Decimal]:
    """What each active discount takes off its student's installment dues
    that year, as they stand: on each due it applies to (its fee type, or
    every type), its own share - what it alone would take off, never more
    than the discount the due actually carries (several discounts on one due
    are capped together at what is left to pay). Cancelled dues and late
    fines take no discount. Two queries for the lot, whatever its size."""
    from ..fees.dues import discount_for

    if not concessions:
        return {}

    dues = defaultdict(list)
    for due in StudentFeeDue.objects.filter(
        student_id__in={c.student_id for c in concessions},
        academic_year_id__in={c.academic_year_id for c in concessions},
        kind=FeeDueKind.INSTALLMENT,
    ).exclude(status=FeeDueStatus.CANCELLED):
        dues[(due.student_id, due.academic_year_id)].append(due)

    given = {}
    for concession in concessions:
        total = ZERO
        for due in dues[(concession.student_id, concession.academic_year_id)]:
            if concession.fee_head_id is not None and concession.fee_head_id != due.fee_head_id:
                continue
            total += min(discount_for(due, [concession]), due.discount_amount)
        given[concession.id] = total

    return given
