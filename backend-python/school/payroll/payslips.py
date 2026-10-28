"""The payslip as a PDF: what an employee files, and what their email carries.

Wears the platform's shared PDF look (school/pdf_design.py, docs/pdf-design.md)
on one A4 page: the school's blue band with its logo and contact lines and
the payslip's number and pay period; a DRAFT stamp while the run can still
change; the employee and the payment side by side; the month's attendance as
headline tiles; earnings and deductions side by side, each line showing what
it would have been for a full month when it was pro-rated; net pay in figures
and in words; and closing lines saying how pay is worked out and when the
document was issued, in the school's own timezone.

Every figure is the payslip's own snapshot - name, designation, department
and amounts were copied onto it when the run was generated - so a reprint
months later says what the employee was told. Only the joining date, email
and mobile are read live, and each is printed only when it has a value.
"""

from __future__ import annotations

import calendar
import datetime as dt
from decimal import Decimal

from .. import dates, money, pdf_design
from ..clock import DATE_TIME, SchoolClock
from ..enums import PayComponentType, PaymentMode, PayrollRunStatus
from ..fees.words import amount_in_words
from ..receipts import e, label
from .service import period_label

PAYSLIP_STYLES = """
table.pay th { font-size: 8pt; padding: 6px 8px; }
table.pay td { font-size: 9pt; padding: 5px 8px; }
.pay .sub { font-size: 7.5pt; color: #6b7280; }
.short td { background-color: #fff7ed; color: #9a3412; padding: 6px 12px; font-size: 9pt; }
"""


def payslip_number(slip) -> str:
    return f"PSL-{slip.id:06d}"


def file_name(slip) -> str:
    run = slip.payroll_run
    return f"{payslip_number(slip)}-{run.year}-{run.month:02d}.pdf"


def render(slip) -> bytes:
    return pdf_design.render(document(slip), file_name(slip))


def days(value) -> str:
    """26.0 -> "26", 25.5 -> "25.5": days as a person writes them."""
    if value is None:
        return "0"

    return f"{Decimal(value).normalize():f}"


def period_range(year: int, month: int) -> str:
    last = calendar.monthrange(year, month)[1]

    return dates.range_label(dt.date(year, month, 1), dt.date(year, month, last))


def component_table(slip, type_, heading: str, total_label: str, total) -> str:
    """One side - earnings or deductions - as a table with its total under it."""
    def cash(value) -> str:
        return e(money.formatted(value, slip.currency_code))

    rows = []

    for line in slip.lines.order_by("sort_order", "id"):
        if line.type != type_:
            continue

        notes = []
        if line.full_amount is not None and line.full_amount != line.amount:
            notes.append(f"of {money.formatted(line.full_amount, slip.currency_code)} for the full month")
        if line.note:
            notes.append(line.note)
        sub = "".join(f'<div class="sub">{e(note)}</div>' for note in notes)
        rows.append([f"{e(line.name)}{sub}", cash(line.amount)])

    if not rows:
        rows.append(['<span class="muted">None</span>', "-"])

    body = pdf_design.table([(heading, "62%", False), ("Amount", "38%", True)], rows, table_class="items pay")
    total_line = pdf_design.total_row([(e(total_label), "62%", False), (cash(total), "38%", True)], "items pay")

    return body + total_line


def document(slip) -> str:
    """The payslip as HTML. Separate from render() so a test can read it."""
    run = slip.payroll_run
    school = slip.school
    clock = SchoolClock.for_school(school)
    profile = slip.staff_profile
    user = profile.user if profile is not None and profile.user_id else None
    period = period_label(run.year, run.month)
    number = payslip_number(slip)
    draft = run.status == PayrollRunStatus.DRAFT

    def cash(value) -> str:
        return money.formatted(value, slip.currency_code)

    employee = pdf_design.facts([
        ("Name", slip.employee_name),
        ("Employee ID", slip.employee_code),
        ("Designation", slip.designation),
        ("Department", slip.department_name),
        ("Joined", dates.us(profile.joining_date) if profile is not None and profile.joining_date else None),
        ("Email", user.email if user else None),
        ("Mobile", user.mobile if user else None),
    ])

    if slip.paid_on:
        status = "Paid"
    elif draft:
        status = "Draft"
    else:
        status = "Not paid yet"

    payment = pdf_design.facts([
        ("Payslip no.", number),
        ("Pay period", period),
        ("Period", period_range(run.year, run.month)),
        ("Status", status),
        ("Paid on", dates.us(slip.paid_on) if slip.paid_on else None),
        ("Paid by", label(PaymentMode, slip.payment_mode) if slip.payment_mode else None),
        ("Reference", slip.payment_reference),
        ("Currency", slip.currency_code),
    ])

    stamp = ""
    if draft:
        stamp = pdf_design.stamp(
            "DRAFT", ["This payslip is a draft: the payroll for the month is not final and may still change."],
            tone="warning",
        )

    attendance = pdf_design.tiles([
        {"label": "Working days", "value": days(slip.working_days), "tone": "info"},
        {"label": "Paid days", "value": days(slip.paid_days), "tone": "success"},
        {"label": "Absent", "value": days(slip.absent_days),
         "tone": "danger" if slip.absent_days else "neutral"},
        {"label": "Half days", "value": slip.half_days or 0},
        {"label": "Not marked (paid)", "value": slip.unmarked_days or 0},
    ], per_row=5)

    earnings = component_table(slip, PayComponentType.EARNING, "Earnings", "Gross earnings", slip.gross_earnings)
    deductions = component_table(
        slip, PayComponentType.DEDUCTION, "Deductions", "Total deductions", slip.total_deductions
    )

    shortfall = ""
    if slip.shortfall and slip.shortfall > 0:
        shortfall = (
            f'{pdf_design.spacer(8)}<table class="short"><tr><td>Deductions beyond earnings, not taken this month: '
            f"<b>{e(cash(slip.shortfall))}</b></td></tr></table>"
        )

    try:
        words = amount_in_words(slip.net_pay, slip.currency_code)
    except ValueError:
        words = None

    issued = clock.format(clock.now(), DATE_TIME)
    closing = [
        "Pay is pro-rated by paid days over the month's working days. A working day nobody marked counts as paid.",
        "This is a draft and may still change." if draft
        else "This payslip is computer-generated and is valid without a signature.",
        f"Issued {issued} ({school.timezone})" if issued else "",
        "Powered by School365ai",
    ]

    body = f"""
    {pdf_design.school_band(school, "PAYSLIP", "DRAFT" if draft else number, f"Pay period {period}")}
    {stamp}
    {pdf_design.spacer(16)}
    {pdf_design.side_by_side(employee, payment, "Employee", "Pay period and payment")}

    {pdf_design.section("Attendance this month")}
    {attendance}

    {pdf_design.section("Pay")}
    {pdf_design.side_by_side(earnings, deductions)}
    {shortfall}

    {pdf_design.spacer(14)}
    {pdf_design.totals_panel("Net pay", cash(slip.net_pay), words)}
    {pdf_design.closing([line for line in closing if line])}
"""

    return pdf_design.page(
        f"{number} - {slip.employee_name}", body,
        footer=f"{school.name} - Payslip {number} - {slip.employee_name} - {period}",
        extra_styles=PAYSLIP_STYLES,
    )
