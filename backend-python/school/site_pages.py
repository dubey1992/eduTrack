"""The public website's own pages (docs/site-pages.md).

Any number of pages - About Us, a privacy policy, a help centre - each
written by the Super Admin as plain text in a small, line-based format,
drafted, previewed and then published.

**Three of them are built in and always exist.** About Us, the Privacy
Policy and the Terms of Use are linked from the footer and, in the
privacy policy's case, required by Google Play - so they cannot be
deleted or moved to another address. Their text ships here, in code, so
an empty table still serves a privacy policy. A row appears only once
somebody saves or publishes one of them, and from then on the row is the
truth.

**The page-text format** is a deliberately small subset of Markdown, read
line by line by the client:

- `# `, `## `, `### ` at the start of a line - a heading
- `- ` or `* ` - a bullet; `1. ` (any number) - a numbered item
- `---` alone on a line - a divider
- a blank line between paragraphs; a single newline is kept as a line break
- `**bold**` and `[text](address)` inside a line

The client never renders it as HTML, so the only thing worth checking on
the way in is where its links point - with the homepage's own rule
(`marketing.url_problem`), so a `javascript:` address is refused here
exactly as it is in the footer.
"""

from __future__ import annotations

import datetime as dt
import re
from dataclasses import dataclass

from . import marketing, module_pages

# The whole website, built-ins included. Bounded so the Super Admin's list
# never needs paging and the footer never needs a scroll bar.
MAX_PAGES = 50

MAX_TITLE = 120

# Far longer than any page anybody reads to the end - the privacy policy is
# under a tenth of it - and short enough that a paste of something that is
# not a page is refused rather than stored.
MAX_BODY = 100_000

SLUG_MIN = 2
SLUG_MAX = 60

# Lowercase letters and digits, with single hyphens between them: an
# address somebody can read aloud and type back.
SLUG_PATTERN = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

# Any `[text](address)` in the text. An address with a space in it is not a
# link at all, which is also how the client reads it.
LINK_PATTERN = re.compile(r"\[([^\]]+)\]\(([^)\s]*)\)")

# Addresses a page may not take. A page is served at school365ai.com/<slug>,
# and every one of these is already something at that address: a screen of
# the app (its go_router paths), a part of the public site, or a path the
# web server itself answers (the API, the Flutter build's own files). A page
# given one of them would either never be reached or hide what is there.
RESERVED_SLUGS = frozenset(
    {
        # The app's screens.
        "login", "attendant-login", "forgot-password", "reset-password", "change-password", "splash",
        "maintenance", "dashboard", "users", "schools", "early-access", "payments", "academic-years",
        "assessments", "grade-scales", "holidays", "departments", "subjects", "promotion", "classes",
        "timetable", "staff", "students", "attendance", "staff-attendance", "biometric-devices", "leaves",
        "teaching-reports", "syllabus", "hod-reports", "transport", "my-trip", "communication",
        "announcements", "inbox", "reports", "payroll", "my-payslips", "audit-log", "mail-settings",
        "homepage-content", "site-pages", "profile", "module-settings", "permissions",
        # The public site's own sections and routes.
        "pages", "features", "for-schools", "mobile-app", "contact",
        # What the web server answers before Flutter ever sees the address.
        "api", "assets", "canvaskit", "icons", "index", "admin", "www", "404",
    }
)


@dataclass(frozen=True)
class BuiltIn:
    """A page that exists whether or not anybody has saved it."""

    slug: str
    title: str
    body: str
    # Whether visitors can read the shipped text before anybody publishes
    # it. The terms are not: their text has blanks only the operator can
    # fill in, and a page saying "[COMPANY LEGAL NAME]" is worse than none.
    live_by_default: bool
    # The date the shipped text was last changed in substance, shown as the
    # page's "last updated" until somebody publishes their own version.
    published_at: dt.datetime | None = None
    # Set on a page about one part of the product (school/module_pages.py):
    # the line its card shows. The public site lays such a page out with a
    # demo invitation and links to the other parts.
    blurb: str | None = None


ABOUT_BODY = """School365ai is school management software. A school uses it to run its day-to-day records in one place, instead of across registers, spreadsheets and phone calls.

## What it covers

- **People.** Students, staff, departments, classes and sections.
- **The school day.** Student and staff attendance, leave, timetables, teaching reports, syllabus progress and marks.
- **Transport.** Vehicles, routes and stops, and trips followed from the bus.
- **Communication.** Announcements, and alerts by SMS, WhatsApp, email and app notification.
- **Payroll.** Salaries and payslips for the school's own staff.

## Where it is used

School administrators work in the web portal. Teachers and other school staff carry the School365ai app on their phones, and bus crews use the School365ai Driver app.

## Schools in different countries

Each school keeps its own currency and its own time zone, so amounts and dates read the way that school expects them to.

## The school's information is the school's

Each school owns the information in its account. Every screen and every request is checked against the school the signed-in person belongs to, and against what their role allows.

To get in touch, use the details at the foot of our [homepage](/)."""


PRIVACY_BODY = """School365ai is school management software. Schools use it to run their own records: students, staff, attendance, timetables and school transport. The School365ai app is what a school's own staff carry - teachers, heads of department and office staff - and the School365ai Driver app is the part of it carried on a school bus.

The school is the owner of the information in its account. We hold and process that information on the school's behalf and under its instructions. If you are a parent or a member of staff asking what is held about you, your school is the place to ask, and they can answer from their own screens.

## What the Driver app collects

- **Where the bus is.** While a trip is running and the driver or attendant has location sharing switched on, the app sends the phone's position to the school. This is how the office and the school's live map show where a bus is on its route.
- **Only during a trip.** Sharing starts when a trip starts and stops when it ends, when the crew switches it off, or when they leave the trip screen. The app does not ask for background location permission and cannot follow a phone when no trip is running. A notification is shown the whole time a trip is sharing its position, so it is never happening quietly.
- **What the crew marks.** Which child boarded, was dropped off or was absent, at which stop, at what time, and which crew member marked it.
- **That a parent was called.** When the crew uses Call parent, the app records that a call was made, about which child, and when. The phone number itself is never recorded, and the crew is never shown it.
- **The account.** Name, mobile number, and the phone the account was set up on, so a passcode cannot be used from anywhere else.

## What the School365ai app collects

- **Where you are, once, when you check in or out.** Checking in and out asks the phone for its position once, to confirm you are at school. The position is compared with the school's pin and then thrown away: what is kept is the time, and how far from school you were. The app never follows a phone, never asks for background location, and asks nothing at all where a school marks staff in the office.
- **What you record as part of your work.** The class register, teaching reports, marks and syllabus progress you enter, and your own leave requests - the same records as on the school's website.
- **A register taken without signal.** Kept on the phone until there is signal, then sent and removed. The phone also keeps the names and roll numbers of your classes, so a register can be opened without signal - never anybody's marks.
- **Notifications.** Where your school uses notifications, the phone's notification address is registered to your account when you sign in and removed when you sign out. Nothing else about the phone is recorded.
- **No microphone, no camera, no contacts.** The School365ai app does not ask for them.

## How long it is kept

Bus positions are deleted after 30 days. They exist so a school can see where a bus is now and answer a question about this morning, not to build a history of anybody's movements.

Trip records - who boarded where, and when - are part of the school's own records and are kept for as long as the school keeps them. Account records are kept while the account exists.

## Who can see it

Staff at your own school, and only at your own school. Every screen and every request is checked against the school the signed-in account belongs to, and against what that person's role allows: a bus crew member reaches the routes they run and nothing else.

We do not sell information, and we do not use it for advertising. The app carries no advertising, no analytics and no tracking software.

## Services we rely on

- **Google Maps.** The school's web portal draws maps using Google Maps. Google receives the map requests it needs to draw them.
- **Google Fonts.** The apps load their typeface from Google's font service, which sees the request and the device's IP address, as any web request does.
- **Messaging and email providers.** Where a school switches on SMS, WhatsApp or email alerts, the message and the recipient's number or address are handed to the provider the school has configured, so that it can be delivered.
- **Google Firebase Cloud Messaging.** Where a school uses notifications, Firebase delivers them to staff phones. It receives the phone's notification address and the text of the notification.
- **Hosting.** The service and its database run on the hosting the school's operator has arranged.

## Children

The apps hold information about children because that is what a school register, a class test and a bus run are about. Children do not have accounts and do not use these apps. Information about a child is entered by their school and is visible to that school's staff, each only as far as their role allows.

## Keeping it safe

Access needs an account, and on the bus it needs the registered phone as well as a passcode. Repeated wrong passcodes lock the account until the school unlocks it. Passwords and passcodes are stored only as one-way hashes - nobody, including us, can read them back. Every change to a record is logged with who made it and when.

## Your choices

A crew member can switch location sharing off at any time from the trip screen. The trip, and marking children on and off, keeps working; the school simply will not see where the bus is.

In the School365ai app, location is asked only when you tap Check in or Check out, and notifications can be switched off in the phone's settings at any time. The app keeps working, and messages still arrive in its inbox.

To see, correct or delete what is held about you, ask your school. If your school needs our help to do it, they can ask us.

## Who to contact

School365ai is operated by the company named in your school's agreement, which is also where the address for written notices is given. Questions about this policy, or about information held about you, should go to your school in the first instance; they can reach us on your behalf.

## Changes

If this policy changes in substance, the date at the top changes with it."""


TERMS_BODY = """These terms apply to everyone who uses School365ai: the website at school365ai.com, the school web portal, the **School365ai** app and the **School365ai Driver** app (together, "the Service"). By signing in to or using the Service, you agree to them. If you do not agree, do not use the Service.

---

## 1. Who we are, and who the Service is for

School365ai is school management software, operated by **[COMPANY LEGAL NAME]**, [REGISTERED ADDRESS] ("we", "us").

Schools use the Service to run their own records: students, staff, attendance, timetables, teaching reports, marks, leave, payroll, transport and messages. **The school is our customer.** Each school has its own agreement with us, and that agreement governs fees, service levels and data handling between us and the school. If anything in these terms conflicts with your school's agreement, the school's agreement prevails.

These terms are for the people who use the Service on a school's behalf: school administrators, heads of department, teachers, office and accounts staff, transport managers, drivers and bus attendants.

## 2. Your account

- **Your school gives you your account.** Accounts are created, changed and closed by your school, not by us. Your school decides which role you have and what you can see.
- **Keep your sign-in to yourself.** Do not share your password or passcode, or let anyone else use your account. You are responsible for what is done with your account.
- **Driver and attendant accounts are tied to one phone.** A passcode works only on the phone the account was set up on. Repeated wrong passcodes lock the account until your school unlocks it.
- **Tell your school straight away** if you think someone else has used your account, or if a phone with the app on it is lost or stolen. Your school can sign you out of every device.
- **Temporary passwords must be changed** the first time you sign in.

## 3. Using the Service properly

You may use the Service only for your work at your school, and only as your role allows. You must not:

- try to see, change or delete information you have not been given access to, including another school's information;
- copy, export or share information about students, parents or staff except as your work at the school requires;
- enter information you know to be false, such as attendance, marks or check-ins you did not make;
- check in or out for somebody else, or try to make the app believe you are somewhere you are not;
- probe, scan or test the Service for weaknesses, or try to get around its security, unless we have agreed to this in writing;
- overload or disrupt the Service, or use automated tools to collect information from it;
- upload anything unlawful, harmful or offensive, or anything that infringes someone else's rights;
- use the Service to send messages that are spam, misleading or unrelated to school matters.

Your school may have its own rules on top of these, such as a staff code of conduct or a data protection policy. You must follow those too.

## 4. Information about children and other people

The Service holds personal information about students, parents and staff, and much of it is about children. **Treat it as confidential.**

- Use it only for school purposes.
- Do not take screenshots of it, photograph it or download it, except as your school allows.
- Sign out of the web portal on shared computers.
- Report any accidental disclosure to your school at once.

The school owns the information in its account. We hold and process it on the school's behalf. How we handle it is explained in our [Privacy Policy](/privacy).

## 5. Your records are the school's records

What you enter, including registers, teaching reports, marks, syllabus progress, leave requests and trip marks, becomes part of your school's records. It is kept and used according to your school's decisions, and it may still be held after you leave the school. Every change is logged with who made it and when.

Check your entries before submitting them. Some records, such as a finalised payroll run or a submitted register, can be corrected only by someone with the right role.

## 6. Bus crews: safety comes first

**Drivers: do not use the app while the vehicle is moving.** Start and end trips, mark students and read messages only when the vehicle is safely stopped. If you use in-app navigation, set it up before you set off, keep the phone in a fixed holder, and follow traffic laws and your school's instructions at all times. Directions can be wrong: road signs, road conditions and your own judgement always come first.

While a trip is running and location sharing is on, the app sends the phone's position to your school. You can switch sharing off on the trip screen. The trip, and marking students on and off, keeps working.

## 7. Location, check-in and phone storage

- **Staff check-in** asks the phone for its position once, when you tap Check in or Check out, to confirm you are at school. It does not follow you.
- **Without signal**, some things are kept on the phone and sent when signal returns: registers, trip marks, and your class lists so a register can be opened offline. Things that were never sent may be lost if the app is removed or the phone is reset before it reconnects.
- **Notifications** can be switched off in your phone's settings at any time.

## 8. What the Service is not

- **It is not an emergency service.** Bus positions, alerts and messages can be late, incomplete or missing because of signal, the phone, or the delivery provider. Never rely on the Service in an emergency: contact the emergency services and the people involved directly.
- **Message delivery is not guaranteed.** SMS, WhatsApp, email and push notifications are delivered by third-party providers your school chooses. We pass messages to them but cannot guarantee they arrive.
- **Reports and figures are only as good as the records behind them.** Your school is responsible for the accuracy of what it enters, and for decisions it makes using the Service. That includes attendance, marks, promotion and pay.

## 9. Availability and changes

We work to keep the Service available and your school's information safe, but we do not promise it will always be available or free of errors. It may be unavailable during planned maintenance, and the app shows when that is the case. We may change, improve or remove features over time. Where a change materially affects how your school uses the Service, we will tell the school.

Keep the apps updated. An old version may stop working when the Service changes.

## 10. Ending your access

Your access ends when your school closes or deactivates your account, when you leave the school, or when your school's agreement with us ends. We may suspend an account straight away if it is used in breach of these terms, or to protect students, the school or the Service. Where we can, we will tell your school first.

## 11. Ownership

The Service, its software, design and content, and the School365ai name and logo belong to us or our licensors. Using the Service gives you no rights in them beyond using it as these terms allow. You must not copy, modify, reverse-engineer or resell any part of it, except as the law allows.

The information your school puts into the Service belongs to your school.

## 12. Our responsibility to you

The Service is provided to you for your school's use. Our commitments, and the limits on our liability, are set out in our agreement with your school. As far as the law allows, we are not liable to you personally for indirect or consequential loss, or for loss caused by inaccurate information entered by others, misuse of your account, or the failure of third-party networks, phones or message providers.

Nothing in these terms limits liability that cannot be limited by law, such as liability for death or personal injury caused by negligence, or for fraud.

## 13. The website

On the public website you can join our early-access list or sign up for news. We use what you give us only to contact you about School365ai, and you can ask us to stop at any time. Links to other websites are provided for convenience. We are not responsible for their content.

## 14. Changes to these terms

We may update these terms. When we do, we change the date at the top, and for significant changes we tell schools in advance. If you keep using the Service after a change takes effect, you accept the updated terms.

## 15. Law and disputes

These terms are governed by the laws of **[COUNTRY / STATE]**, and disputes are subject to the courts of **[CITY / JURISDICTION]**, unless the law where you live gives you the right to bring a claim elsewhere.

## 16. Contact

For questions about your account, your access or information held about you, contact your school first. They can reach us on your behalf.

To reach us directly: **[SUPPORT EMAIL]** · **[PHONE]** · **[POSTAL ADDRESS]**"""


# In the order the Super Admin's list shows them.
BUILT_INS: tuple[BuiltIn, ...] = (
    BuiltIn("about", "About Us", ABOUT_BODY, live_by_default=True),
    BuiltIn(
        "privacy", "Privacy Policy", PRIVACY_BODY, live_by_default=True,
        published_at=dt.datetime(2026, 10, 26, tzinfo=dt.timezone.utc),
    ),
    BuiltIn("terms", "Terms of Use", TERMS_BODY, live_by_default=False),
    # Then one page per part of the product (docs/seo.md, S3).
    *(
        BuiltIn(module.slug, module.title, module.body, live_by_default=True, blurb=module.blurb)
        for module in module_pages.MODULES
    ),
)

BUILT_IN_SLUGS: tuple[str, ...] = tuple(page.slug for page in BUILT_INS)


def built_in(slug: str) -> BuiltIn | None:
    return next((page for page in BUILT_INS if page.slug == slug), None)


def slug_problem(slug: str) -> str | None:
    """Why this address may not be given to a page, or None if it may.

    Only what can be told from the address itself. Whether another page
    already has it is a question for the table, asked by the request.
    """
    if not SLUG_MIN <= len(slug) <= SLUG_MAX:
        return f"An address must be {SLUG_MIN} to {SLUG_MAX} characters long."

    if not SLUG_PATTERN.match(slug):
        return "Use lowercase letters, numbers and single hyphens, e.g. help-center."

    if slug in RESERVED_SLUGS:
        return "That address is reserved by the app. Choose another."

    return None


def link_problems(body: str) -> list[str]:
    """Every link in the text that may not be used, each with its reason.

    All of them at once rather than the first, so a page with three bad
    links is fixed in one pass rather than three saves.
    """
    problems = []

    for match in LINK_PATTERN.finditer(body):
        text, address = match.group(1), match.group(2)
        reason = marketing.url_problem(address)

        if reason is not None:
            problems.append(f'The link "{text}" can\'t be used: {reason}')

    return problems
