"""One student's fee statement for an academic year, as a PDF to hand the
family (docs/fees.md, F5).

The F3 receipt's look and engine (receipt_pdf.py): A4, the blue band with the
school's logo and contact lines, then the student and the year side by side,
the account in a few figures, every due of the year - installments and late
fines, waived and cancelled ones marked rather than hidden - the discounts in
force, every receipt dated in the year (cancelled ones struck through), and
a footer with the moment it was issued in the school's own timezone.

The figures are exactly the statement's (fees/ledger.py statement()), so the
PDF and the screen cannot disagree: charged less discounts, less paid, less
waived is what is still owed, and cancelled dues are listed but counted
nowhere. Every optional detail is printed only when it has a value.
"""

from __future__ import annotations

import io
import re

from xhtml2pdf import pisa

from .. import dates, money
from ..clock import DATE, DATE_TIME, SchoolClock
from ..enums import FeeDueCancelReason, FeeDueKind, FeeDueStatus, FeeReceiptStatus, StudentStatus
from ..models import FeeReceipt
from ..receipts import e
from .ledger import balance_of, is_overdue
from .receipt_pdf import STYLESHEET, fact, header, joined
from .resources import _class_names, mode_label

STATEMENT_STYLES = f"""
.items th {{ font-size: 7.5pt; padding: 6px 5px; }}
.items td {{ font-size: 8.5pt; padding: 4px 5px; }}
.items .sub {{ font-size: 7.5pt; color: #6b7280; }}
.items .void td {{ color: #9ca3af; }}
.items .void .strike {{ text-decoration: line-through; }}
.items .fine td {{ background-color: #fff7ed; }}
.items .total td {{ background-color: #eff6ff; font-weight: bold; color: #1e3a8a; border-top: 1px solid #c7d2fe; }}

.summary td {{ padding: 4px 12px; font-size: 9.5pt; border-bottom: 1px solid #e5e7eb; }}
.summary .value {{ text-align: right; font-weight: bold; }}
.summary .owed td {{ background-color: #fff7ed; color: #9a3412; font-weight: bold; font-size: 11pt; }}
.summary .settled td {{ background-color: #ecfdf5; color: #065f46; font-weight: bold; font-size: 11pt; }}
.summary .overdue td {{ color: #b91c1c; font-weight: bold; }}

.pill-overdue {{ color: #b91c1c; font-weight: bold; }}
.pill-paid {{ color: #047857; font-weight: bold; }}
.pill-waived {{ color: #7c3aed; font-weight: bold; }}
.pill-void {{ color: #9ca3af; }}
.legend {{ font-size: 7.5pt; color: #6b7280; padding-top: 4px; }}
.empty {{ font-size: 9pt; color: #6b7280; padding: 6px 8px; border-bottom: 1px solid #e5e7eb; }}
.band-year {{ font-size: 9pt; color: #dbeafe; padding-top: 2px; }}
"""


def year_token(year) -> str:
    """"2026-27" -> "2026-27"; every run of other characters one hyphen, as
    receipt numbers have it."""
    return "-".join("".join(char if char.isalnum() else " " for char in year.name).split()) or str(year.id)


def file_name(student, year) -> str:
    admission = re.sub(r"[^A-Za-z0-9]+", "-", student.admission_number or "").strip("-") or str(student.id)

    return f"statement-{admission}-{year_token(year)}.pdf"


def render(found: dict) -> bytes:
    out = io.BytesIO()
    result = pisa.CreatePDF(document(found), dest=out, encoding="utf-8")

    if result.err:
        raise RuntimeError(f"Could not render {file_name(found['student'], found['year'])}")

    return out.getvalue()


def item_name(due) -> str:
    """The due's own name beside its fee-type column: "April" for
    "Tuition - April"; a late fine keeps its whole label."""
    if due.kind == FeeDueKind.LATE_FINE:
        return due.label

    prefix = f"{due.fee_head.name} - "
    return due.label[len(prefix):] if due.label.startswith(prefix) else due.label


def status_of(due, today) -> tuple[str, str]:
    """(words, css class) for a due's status column."""
    if due.status == FeeDueStatus.CANCELLED:
        return "Cancelled", "pill-void"

    if due.status == FeeDueStatus.WAIVED:
        return "Waived", "pill-waived"

    if due.status == FeeDueStatus.PAID:
        return "Paid", "pill-paid"

    if balance_of(due) <= 0:
        return "Covered by discount", "pill-paid"

    words = "Part paid" if due.status == FeeDueStatus.PARTIAL else "Pending"

    if is_overdue(due, today):
        return f"{words}, overdue", "pill-overdue"

    return words, ""


def note_under(due) -> str:
    """The small line under a due that says why it reads as it does."""
    if due.status == FeeDueStatus.CANCELLED:
        reason = dict(FeeDueCancelReason.choices).get(due.cancelled_reason, "")
        return f"Not charged: {reason[:1].lower()}{reason[1:]}" if reason else "Not charged"

    if due.status == FeeDueStatus.WAIVED:
        return f"Waived: {due.waive_reason}" if due.waive_reason else "Waived"

    if due.kind == FeeDueKind.LATE_FINE:
        return "Late fine"

    return ""


def section(title: str) -> str:
    return f"""
    <table><tr><td style="height: 16px; font-size: 1pt;">&nbsp;</td></tr></table>
    <div class="section-title">{e(title)}</div>
    <table><tr><td style="height: 6px; font-size: 1pt;">&nbsp;</td></tr></table>"""


def document(found: dict) -> str:
    """The statement as HTML - separate from render() so a test can read it.
    `found` is fees/ledger.py statement()."""
    student = found["student"]
    school = student.school
    year = found["year"]
    today = found["today"]
    totals = found["totals"]
    currency = found["currency_code"]
    clock = SchoolClock.for_school(school)
    class_name, section_name = _class_names(found["enrollment"])
    enrollment = found["enrollment"]

    def cash(value) -> str:
        return e(money.formatted(money.amount(value), currency))

    def cash_in(value, code) -> str:
        """A figure in a table, whose header names the currency: the code is
        printed only on a line in another one."""
        amount = money.amount(value)
        return e(f"{amount:,.2f}" if code == currency else money.formatted(amount, code))

    statement_facts = "".join([
        fact("Academic year", year.name),
        fact("Year runs", dates.range_label(year.start_date, year.end_date)),
        fact("Statement date", dates.us(today)),
        fact("Currency", currency),
    ])
    student_facts = "".join([
        fact("Student", student.name),
        fact("Admission no.", student.admission_number),
        fact("Class", joined(class_name, section_name).replace(", ", " - ") or None),
        fact("Roll no.", (enrollment.roll_number if enrollment else None) or student.roll_number),
        fact("Status", None if student.status == StudentStatus.ACTIVE else dict(StudentStatus.choices).get(
            student.status, student.status)),
        fact("Admitted", dates.us(student.admission_date) if student.admission_date else None),
        fact("Guardian", student.guardian_name),
        fact("Guardian mobile", student.guardian_mobile),
        fact("Guardian email", student.guardian_email),
    ])

    # -- the account in figures -------------------------------------------------
    balance = totals["balance"]
    summary_rows = [
        ("Total charged", cash(totals["charged"]), ""),
        ("Less discounts", cash(totals["discount"]), ""),
        ("Less paid", cash(totals["paid"]), ""),
    ]
    if totals["waived"]:
        summary_rows.append(("Less waived", cash(totals["waived"]), ""))
    summary = "".join(f'<tr class="{css}"><td>{e(label)}</td><td class="value">{value}</td></tr>'
                      for label, value, css in summary_rows)
    summary += (
        f'<tr class="{"settled" if balance <= 0 else "owed"}"><td>Balance due</td>'
        f'<td class="value">{cash(balance)}</td></tr>'
    )
    if totals["overdue"] > 0:
        summary += f'<tr class="overdue"><td>Of which overdue</td><td class="value">{cash(totals["overdue"])}</td></tr>'
    # F6: money held for the next fees, each currency on its own line.
    for credit_currency, held in found.get("credit", {}).items():
        if held > 0:
            summary += (
                f'<tr class="settled"><td>Credit held for the next fees</td>'
                f'<td class="value">{e(money.formatted(held, credit_currency))}</td></tr>'
            )

    # -- every due ----------------------------------------------------------------
    rows = []
    for index, due in enumerate(found["dues"], start=1):
        words, pill = status_of(due, today)
        under = note_under(due)
        classes = []
        if index % 2 == 0:
            classes.append("zebra")
        if due.status == FeeDueStatus.CANCELLED:
            classes.append("void")
        elif due.kind == FeeDueKind.LATE_FINE:
            classes.append("fine")
        strike = ' class="strike"' if due.status == FeeDueStatus.CANCELLED else ""
        under_html = f'<div class="sub">{e(under)}</div>' if under else ""

        rows.append(
            f'<tr class="{" ".join(classes)}"><td class="idx">{index}</td>'
            f"<td>{e(due.fee_head.name)}</td>"
            f"<td><span{strike}>{e(item_name(due))}</span>{under_html}</td>"
            f"<td>{dates.us(due.due_date)}</td>"
            f'<td class="num"><span{strike}>{cash_in(due.amount, due.currency_code)}</span></td>'
            f'<td class="num">{cash_in(due.discount_amount, due.currency_code) if due.discount_amount else "-"}</td>'
            f'<td class="num">{cash_in(due.paid_amount, due.currency_code) if due.paid_amount else "-"}</td>'
            f'<td class="num">{cash_in(balance_of(due), due.currency_code)}</td>'
            f'<td></td><td class="{pill}">{e(words)}</td></tr>'
        )

    if rows:
        rows.append(
            f'<tr class="total"><td></td><td colspan="3">Total (cancelled lines not counted)</td>'
            f'<td class="num">{cash_in(totals["charged"], currency)}</td>'
            f'<td class="num">{cash_in(totals["discount"], currency)}</td>'
            f'<td class="num">{cash_in(totals["paid"], currency)}</td>'
            f'<td class="num">{cash_in(totals["balance"], currency)}</td><td></td><td></td></tr>'
        )
        dues_table = f"""
    <table class="items" repeat="1">
        <tr><th class="idx" width="4%">#</th><th width="11%">Fee type</th><th width="18%">Item</th>
            <th width="11%">Due date</th><th class="num" width="11%">Amount</th>
            <th class="num" width="10%">Discount</th><th class="num" width="10%">Paid</th>
            <th class="num" width="10%">Balance</th><th width="2%"></th><th width="13%">Status</th></tr>
        {"".join(rows)}
    </table>
    <div class="legend">Late fines are shaded. A waived line owes nothing; a cancelled one was never charged.</div>"""
    else:
        dues_table = '<div class="empty">Nothing has been charged to this student for this year.</div>'

    # -- discounts in force --------------------------------------------------------
    concessions = found.get("concessions") or []
    if concessions:
        from ..reports.fees import discount_detail

        lines = "".join(
            f'<tr class="{"zebra" if index % 2 == 0 else ""}"><td class="idx">{index}</td>'
            f'<td>{e(c.fee_head.name if c.fee_head_id else "All fee types")}</td>'
            f"<td>{e(discount_detail(c, currency))}</td><td>{e(c.reason)}</td>"
            f"<td>{e(clock.format(c.created_at, DATE) or '')}</td></tr>"
            for index, c in enumerate(concessions, start=1)
        )
        discounts = f"""
    <table class="items" repeat="1">
        <tr><th class="idx" width="4%">#</th><th width="20%">Fee type</th><th width="34%">Discount</th>
            <th width="28%">Reason</th><th width="14%">Since</th></tr>
        {lines}
    </table>"""
    else:
        discounts = '<div class="empty">No discounts this year.</div>'

    # -- payments --------------------------------------------------------------------
    receipts = list(
        FeeReceipt.objects.filter(pk__in=[receipt.id for receipt in found.get("receipts") or []])
        .select_related("received_by")
        .order_by("receipt_date", "id")
    )
    if receipts:
        lines = []
        received = {}
        for index, receipt in enumerate(receipts, start=1):
            void = receipt.status == FeeReceiptStatus.CANCELLED
            mode = mode_label(receipt.payment_mode)
            paid_by = f"{mode} {receipt.reference}" if receipt.reference else mode
            strike = ' class="strike"' if void else ""
            if not void:
                received[receipt.currency_code] = received.get(receipt.currency_code, 0) + receipt.amount
            lines.append(
                f'<tr class="{" ".join(c for c in ("zebra" if index % 2 == 0 else "", "void" if void else "") if c)}">'
                f'<td class="idx">{index}</td><td><span{strike}>{e(receipt.receipt_number)}</span></td>'
                f"<td>{dates.us(receipt.receipt_date)}</td><td>{e(paid_by)}</td>"
                f"<td>{e(receipt.received_by.name if receipt.received_by_id else '')}</td>"
                f'<td class="num"><span{strike}>{cash_in(receipt.amount, receipt.currency_code)}</span></td>'
                f'<td></td><td class="{"pill-void" if void else "pill-paid"}">{"Cancelled" if void else "Valid"}</td></tr>'
            )
        total = " + ".join(cash_in(amount, code) for code, amount in sorted(received.items())) or cash_in(0, currency)
        lines.append(
            f'<tr class="total"><td></td><td colspan="4">Received (cancelled receipts not counted)</td>'
            f'<td class="num">{total}</td><td></td><td></td></tr>'
        )
        payments = f"""
    <table class="items" repeat="1">
        <tr><th class="idx" width="4%">#</th><th width="24%">Receipt no.</th><th width="12%">Date</th>
            <th width="19%">Paid by</th><th width="16%">Received by</th>
            <th class="num" width="12%">Amount</th><th width="2%"></th><th width="11%">Status</th></tr>
        {"".join(lines)}
    </table>
    <div class="legend">Receipts dated in this academic year. A payment can settle a due of another year.</div>"""
    else:
        payments = '<div class="empty">No payments received this year.</div>'

    issued = clock.format(clock.now(), DATE_TIME)
    title = f"Fee statement {year.name}"

    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>{e(title)} - {e(student.name)}</title>
<style>{STYLESHEET}{STATEMENT_STYLES}</style>
</head>
<body>
    {header(school, f"Academic year {year.name}", title="FEE STATEMENT")}

    <table><tr><td style="height: 18px; font-size: 1pt;">&nbsp;</td></tr></table>
    <table><tr>
        <td style="width: 48%">
            <div class="section-title">STUDENT</div>
            <table class="facts">{student_facts}</table>
        </td>
        <td style="width: 4%"></td>
        <td style="width: 48%">
            <div class="section-title">STATEMENT</div>
            <table class="facts">{statement_facts}</table>
            <table><tr><td style="height: 8px; font-size: 1pt;">&nbsp;</td></tr></table>
            <table class="summary">{summary}</table>
        </td>
    </tr></table>

    {section(f"FEES THIS YEAR ({currency})")}
    {dues_table}

    {section("DISCOUNTS IN FORCE")}
    {discounts}

    {section(f"PAYMENTS RECEIVED ({currency})")}
    {payments}

    <table><tr><td style="height: 26px; font-size: 1pt;">&nbsp;</td></tr></table>
    <table class="footer">
        <tr><td class="rule">This is a computer-generated statement and needs no signature.
            Please pay at the school office and keep your receipts.</td></tr>
        <tr><td>Issued {e(issued)} ({e(school.timezone)})</td></tr>
        <tr><td>Powered by School365ai</td></tr>
    </table>
</body>
</html>"""
