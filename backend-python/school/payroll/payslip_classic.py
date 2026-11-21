"""The classic printed payslip (asked for 2026-11-21, beside the classic fee
receipt and report card - docs/document-styles.md): the salary slip a school
prints from its own register, for schools that choose it under Module
Settings -> Payroll -> Payslip layout.

Black on white, no brand colour, in the classic receipt's own type and rules
(fees/receipt_classic.py): the school's logo and name centred over its
address and phone, "Salary Slip", the pay period, the employee in two compact
"Key : value" columns with the month's days, a bordered Earnings | Rate |
Amount | Deductions | Amount table - the rate being the full month's figure
a pro-rated line was cut from - the gross, deductions and net pay lines, the
net pay in words, how and when it was paid, and two signature lines.

Every figure is the payslip's own snapshot, as on the standard layout
(payslips.py): a reprint months later says what the employee was told. A
draft carries the DRAFT box.
"""

from __future__ import annotations

import calendar
import datetime as dt

from .. import dates
from ..enums import PayComponentType, PaymentMode, PayrollRunStatus
from ..fees.receipt_classic import CLASSIC_STYLES, amount, header, info_rows, spacer
from ..fees.words import amount_in_words
from ..receipts import e, label
from . import bank
from .service import period_label

PAYSLIP_CLASSIC_STYLES = """
.pay th { border: 1px solid #444444; padding: 6px 7px; font-size: 9.5pt; font-weight: bold; text-align: left; }
.pay td { border: 1px solid #444444; padding: 5px 7px; font-size: 9.5pt; }
.pay .amt { text-align: right; }
.pay .total td { font-weight: bold; }
.pay .sub { font-size: 7.5pt; color: #555555; }
.draft td { border: 2px solid #b45309; color: #b45309; padding: 8px 12px; }
.draft-word { font-size: 18pt; font-weight: bold; letter-spacing: 5px; }
.draft-line { font-size: 9pt; }
.short td { border: 1px solid #9a3412; color: #9a3412; padding: 6px 10px; font-size: 9.5pt; }
.sign .left { width: 200px; text-align: center; border-top: 1px solid #555555; padding-top: 5px; font-size: 9.5pt; }
.sign .gap { width: auto; }
"""


def days(value) -> str:
    """26.0 -> "26", 25.5 -> "25.5"."""
    from .payslips import days as as_written

    return as_written(value)


def period_range(year: int, month: int) -> str:
    last = calendar.monthrange(year, month)[1]

    return dates.range_label(dt.date(year, month, 1), dt.date(year, month, last))


def pay_rows(slip) -> str:
    """Earnings and deductions side by side, one pair to a row; the shorter
    side's cells stay blank - a non-breaking space each, since xhtml2pdf
    collapses an empty cell and the columns slide out of line. A pro-rated earning shows the full month's
    figure as its rate; an adjustment or an advance recovery has none."""
    earnings, deductions = [], []

    for line in slip.lines.order_by("sort_order", "id"):
        (earnings if line.type == PayComponentType.EARNING else deductions).append(line)

    def name(line) -> str:
        note = f'<div class="sub">{e(line.note)}</div>' if line.note else ""
        return f"{e(line.name)}{note}"

    rows = []
    for index in range(max(len(earnings), len(deductions), 1)):
        earning = earnings[index] if index < len(earnings) else None
        deduction = deductions[index] if index < len(deductions) else None

        if earning is not None:
            rate = amount(earning.full_amount) if earning.full_amount is not None else "&nbsp;"
            left = f'<td>{name(earning)}</td><td class="amt">{rate}</td><td class="amt">{amount(earning.amount)}</td>'
        else:
            left = "<td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td>"

        if deduction is not None:
            right = f'<td>{name(deduction)}</td><td class="amt">{amount(deduction.amount)}</td>'
        else:
            right = "<td>&nbsp;</td><td>&nbsp;</td>"

        rows.append(f"<tr>{left}{right}</tr>")

    return "".join(rows)


# One line to a row: xhtml2pdf mis-sizes a table whose cells are separated
# by line breaks, and the widths go on as styles.
PAY_HEAD = (
    '<tr><th style="width: 26%">Earnings</th><th class="amt" style="width: 14%">Rate</th>'
    '<th class="amt" style="width: 14%">Amount</th><th style="width: 30%">Deductions</th>'
    '<th class="amt" style="width: 16%">Amount</th></tr>'
)


def total_row(slip) -> str:
    return (
        f'<tr class="total"><td>Gross Earnings</td><td>&nbsp;</td><td class="amt">{amount(slip.gross_earnings)}</td>'
        f'<td>Total Deductions</td><td class="amt">{amount(slip.total_deductions)}</td></tr>'
    )


def draft_box(slip) -> str:
    if slip.payroll_run.status != PayrollRunStatus.DRAFT:
        return ""

    return f"""{spacer(8)}<table class="draft"><tr><td><div class="draft-word">DRAFT</div>
        <div class="draft-line">This payslip is a draft: the payroll for the month is not final and may still change.</div>
        </td></tr></table>"""


def payment_line(slip) -> str:
    if slip.paid_on:
        return pay_joined(
            f"PAID ON {dates.us(slip.paid_on)}",
            label(PaymentMode, slip.payment_mode).upper() if slip.payment_mode else None,
            slip.payment_reference,
        )

    if slip.payroll_run.status == PayrollRunStatus.DRAFT:
        return "DRAFT - NOT PAID"

    return "NOT PAID YET"


def pay_joined(*parts) -> str:
    return " - ".join(str(part) for part in parts if part)


def document(slip) -> str:
    """The classic payslip as HTML. Separate from render() so a test can read it."""
    from .payslips import payslip_number

    run = slip.payroll_run
    school = slip.school
    profile = slip.staff_profile
    salary = getattr(profile, "salary", None) if profile is not None else None
    number = payslip_number(slip)
    period = period_label(run.year, run.month)

    info = info_rows([
        (("Payslip No", number), ("Pay Period", period)),
        (("Employee Name", (slip.employee_name or "").upper() or None), ("Employee ID", slip.employee_code)),
        (("Designation", slip.designation or None), ("Department", slip.department_name or None)),
        (("Date Of Joining", dates.us(profile.joining_date) if profile is not None and profile.joining_date else None),
         ("Tax ID", salary.tax_id if salary else None)),
        (("Bank", salary.bank_name if salary else None), ("Account No", bank.masked_of(salary) if salary else None)),
        (("Working Days", days(slip.working_days)), ("Paid Days", days(slip.paid_days))),
        (("Absent Days", days(slip.absent_days)), ("Half Days", str(slip.half_days or 0))),
    ])

    shortfall = ""
    if slip.shortfall and slip.shortfall > 0:
        shortfall = (
            f'{spacer(8)}<table class="short"><tr><td>Deductions beyond earnings, not taken this month: '
            f"<b>{amount(slip.shortfall)}</b></td></tr></table>"
        )

    try:
        words = amount_in_words(slip.net_pay, slip.currency_code, local_scale=True)
    except ValueError:
        words = None

    words_row = f'<table class="words"><tr><td>Net Pay In Words : {e(words)}</td></tr></table>' if words else ""

    body = f"""
    {header(school, "Salary Slip")}
    <div class="period">Pay Period : {e(period.upper())} ({e(period_range(run.year, run.month))})</div>
    <table class="rule"><tr><td>&nbsp;</td></tr></table>
    {draft_box(slip)}
    {spacer(6)}
    <table class="info">{info}</table>
    {spacer(12)}
    <table class="pay">{PAY_HEAD}{pay_rows(slip)}{total_row(slip)}</table>
    {shortfall}
    {spacer(10)}
    <table class="final">
        <tr><td class="top bottom">Net Pay</td><td class="v top bottom">{amount(slip.net_pay)}</td></tr>
    </table>
    {spacer(10)}
    {words_row}
    <table class="remarks"><tr><td>Payment : {e(payment_line(slip))}</td></tr></table>
    {spacer(60)}
    <table class="sign"><tr>
        <td class="left">Employee Signature</td>
        <td class="gap"></td>
        <td class="line">Authorised Signatory</td>
    </tr></table>
    {spacer(10)}
    <table class="sign"><tr>
        <td class="note">Amounts in {e(slip.currency_code)}. Pay is pro-rated by paid days over the month's working days.
            Computer-generated payslip.</td>
    </tr></table>
    <div class="foot">{e(school.name)} - Payslip {e(number)} - {e(slip.employee_name)} - {e(period)} - Powered by School365ai</div>"""

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>{e(number)} - {e(slip.employee_name)}</title>
<style>{CLASSIC_STYLES}{PAYSLIP_CLASSIC_STYLES}</style></head>
<body>{body}</body></html>"""


def render(slip) -> bytes:
    from .. import pdf_design
    from .payslips import file_name

    return pdf_design.render(document(slip), file_name(slip))

