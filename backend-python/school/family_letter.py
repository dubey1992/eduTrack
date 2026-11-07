"""The letter a parent takes home to sign in to the Family app
(docs/parent-student-app.md, F0).

Wears the platform's shared PDF look (school/pdf_design.py): the school's blue
band, then who the letter is for and their children, the mobile number they
sign in with, the setup code in large print with the date it stops working,
the four steps, and what to do with the letter afterwards.

The code is printed here and shown nowhere else: issuing the letter issues a
fresh code, so the office never copies one by hand.
"""

from __future__ import annotations

from . import pdf_design
from .clock import DATE, SchoolClock
from .pdf_design import e, fact, facts, school_band, section, spacer

LETTER_STYLES = """
.code { font-size: 26pt; font-weight: bold; letter-spacing: 4pt; color: #1D4ED8; padding: 6px 0 2px 0; }
.code-note { font-size: 9pt; color: #475569; }
.step { font-size: 10.5pt; padding: 3px 0; }
.step-n { font-weight: bold; color: #1D4ED8; width: 22px; }
.keep { font-size: 9.5pt; color: #475569; padding-top: 4px; }
"""


def file_name(guardian) -> str:
    return f"Family-app-letter-{guardian.name.replace(' ', '-')}.pdf"


def render(guardian, children, code: str, expires) -> bytes:
    return pdf_design.render(document(guardian, children, code, expires), file_name(guardian))


def document(guardian, children, code: str, expires) -> str:
    school = guardian.school
    clock = SchoolClock.for_school(school)
    valid_until = clock.format(expires, DATE)
    names = ", ".join(
        f"{child.first_name} {child.last_name}".strip()
        + (f" ({child.class_section.school_class.name} {child.class_section.name})" if child.class_section else "")
        for child in children
    )

    steps = [
        "Install the School365ai Family app from Google Play on your phone.",
        "Open it and choose “I have a letter from my school”.",
        f"Enter your mobile number, {guardian.login_mobile}, and the setup code above.",
        "Choose your own 6-digit passcode. You will use it to sign in from now on.",
    ]
    step_rows = "".join(
        f'<tr><td class="step step-n">{number}.</td><td class="step">{e(text)}</td></tr>'
        for number, text in enumerate(steps, start=1)
    )
    office = pdf_design.joined(school.phone and f"Phone {school.phone}", school.email)

    body = f"""
    {school_band(school, "FAMILY APP", subtitle="Your sign-in letter")}
    {spacer(14)}
    <p>Dear {e(guardian.name)},</p>
    <p>{e(school.name)} now shares your child's day with you in the School365ai Family app: attendance,
    the school bus, fees, results and notices from the school, on your phone.</p>
    {section("For")}
    {facts([("Guardian", guardian.name), ("Children", names or "-"), ("Mobile number", guardian.login_mobile)])}
    {section("Your setup code")}
    <div class="code">{e(code[:4])} {e(code[4:])}</div>
    <div class="code-note">Use it once, on your own phone, by {e(valid_until)}. After that, ask the school office for a new letter.</div>
    {section("How to start")}
    <table>{step_rows}</table>
    {section("Keep it safe")}
    <div class="keep">Do not share this code or your passcode with anyone. The school will never ask you for your passcode.
    If you lose your phone, tell the school office and they will remove it.</div>
    {pdf_design.closing([f"Questions? Contact the school office{': ' + office if office else '.'}"])}
    """

    return pdf_design.page("Family app sign-in letter", body, footer=f"{school.name} - Family app letter",
                           extra_styles=LETTER_STYLES)


__all__ = ["document", "file_name", "render", "fact"]
