"""The payslip as a PDF: what an employee files, and what their email carries.

Rendered the way payment receipts are (school/receipts.py): xhtml2pdf, which
is pure Python because shared hosting has no cairo or pango, so the layout is
simple tables and the stylesheet is the receipt's.
"""

from __future__ import annotations

import io

from xhtml2pdf import pisa

from .. import money
from ..enums import PayComponentType, PaymentMode, PayrollRunStatus
from ..receipts import STYLESHEET, e, label, row
from .service import period_label


def payslip_number(slip) -> str:
    return f"PSL-{slip.id:06d}"


def file_name(slip) -> str:
    run = slip.payroll_run
    return f"{payslip_number(slip)}-{run.year}-{run.month:02d}.pdf"


def render(slip) -> bytes:
    out = io.BytesIO()
    result = pisa.CreatePDF(document(slip), dest=out, encoding="utf-8")

    if result.err:
        raise RuntimeError(f"Could not render {file_name(slip)}")

    return out.getvalue()


def document(slip) -> str:
    """The payslip as HTML. Separate from render() so a test can read it."""
    run = slip.payroll_run
    school = slip.school

    def cash(value) -> str:
        return e(money.formatted(value, slip.currency_code))

    def lines_of(type_) -> str:
        cells = []
        for line in slip.lines.order_by("sort_order", "id"):
            if line.type != type_:
                continue
            detail = ""
            if line.full_amount is not None and line.full_amount != line.amount:
                detail = f' <span class="muted">(of {cash(line.full_amount)})</span>'
            if line.note:
                detail += f'<br><span class="muted">{e(line.note)}</span>'
            cells.append(f'<tr><td class="label">{e(line.name)}{detail}</td><td class="value">{cash(line.amount)}</td></tr>')
        return "".join(cells) or '<tr><td class="label muted">None</td><td class="value">-</td></tr>'

    draft = run.status == PayrollRunStatus.DRAFT
    paid = ""
    if slip.paid_on:
        paid = row("Paid on", e(f"{slip.paid_on:%m/%d/%Y} by {label(PaymentMode, slip.payment_mode)}"))
        if slip.payment_reference:
            paid += row("Reference", e(slip.payment_reference))

    shortfall = ""
    if slip.shortfall and slip.shortfall > 0:
        shortfall = (
            f'<tr class="due"><td class="label">Deductions beyond earnings, not taken</td>'
            f'<td class="value">{cash(slip.shortfall)}</td></tr>'
        )

    return f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><style>{STYLESHEET}</style></head>
<body>
<div class="sheet">
    <table class="head"><tr>
        <td><div class="brand">{e(school.name)}</div><div class="muted">Payslip for {e(period_label(run.year, run.month))}</div></td>
        <td class="right"><div class="brand">{"DRAFT" if draft else e(payslip_number(slip))}</div></td>
    </tr></table>

    <h1>Employee</h1>
    <table class="meta">
        {row("Name", e(slip.employee_name))}
        {row("Employee ID", e(slip.employee_code))}
        {row("Designation", e(slip.designation or "-"))}
        {row("Department", e(slip.department_name or "-"))}
        {paid}
    </table>

    <h1>Attendance</h1>
    <table class="meta">
        {row("Working days", e(slip.working_days))}
        {row("Paid days", e(slip.paid_days))}
        {row("Absent", e(slip.absent_days))}
        {row("Half days", e(slip.half_days))}
        {row("Not marked (paid)", e(slip.unmarked_days))}
    </table>

    <h1>Earnings</h1>
    <table class="amounts">{lines_of(PayComponentType.EARNING)}
        <tr><td class="label">Gross earnings</td><td class="value">{cash(slip.gross_earnings)}</td></tr>
    </table>

    <h1>Deductions</h1>
    <table class="amounts">{lines_of(PayComponentType.DEDUCTION)}
        <tr><td class="label">Total deductions</td><td class="value">{cash(slip.total_deductions)}</td></tr>
    </table>

    <table class="amounts" style="margin-top: 16px;">
        <tr class="settled"><td class="label">Net pay</td><td class="value">{cash(slip.net_pay)}</td></tr>
        {shortfall}
    </table>

    <div class="note muted">
        Pay is pro-rated by paid days over the month's working days. A working day nobody marked counts as paid.
        {"This is a draft and may still change." if draft else "This payslip is issued electronically and is valid without a signature."}
    </div>
</div>
</body>
</html>"""
