"""The fixed words and icons of the public website's design (the "Warm
Editorial" redesign, 2026-11-14).

The homepage's hero, features title, web and app sections and closing call
are the Super Admin's to edit (school/marketing_copy.py). What is here is
the rest: the role tabs, the homepage questions, how features are grouped
on the features page, and the icons. Every sentence describes what
School365ai does today - nothing planned is written as if it exists, and
there are no numbers, testimonials or certifications we cannot show.
"""

from __future__ import annotations

from django.utils.safestring import mark_safe


def _icon(*paths: str) -> str:
    """A 24px line icon in the site's style: currentColor, round joins."""
    body = "".join(f'<path d="{d}"/>' for d in paths)
    return mark_safe(
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" '
        f'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{body}</svg>'
    )


ICONS = {
    "attendance": _icon("M9 11l3 3 8-8", "M20 12v7a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h9"),
    "fees": _icon("M4 6h16v12H4z", "M4 10h16", "M8 15h3"),
    "bus": _icon("M5 17V6a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v11", "M5 12h14", "M7 20v-3", "M17 20v-3", "M8 15h.01", "M16 15h.01"),
    "staff": _icon("M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8z", "M4 21a8 8 0 0 1 16 0"),
    "timetable": _icon("M4 5h16v15H4z", "M4 10h16", "M9 5v15", "M8 3v4", "M16 3v4"),
    "progress": _icon("M4 20h16", "M7 16v-4", "M12 16V8", "M17 16v-6"),
    "payroll": _icon("M12 3v18", "M16 7H10a3 3 0 0 0 0 6h4a3 3 0 0 1 0 6H8"),
    "message": _icon("M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.4A8 8 0 1 1 21 12z"),
    "reports": _icon("M7 3h8l4 4v14H7z", "M15 3v4h4", "M10 13h6", "M10 17h6"),
    "records": _icon("M4 4h16v16H4z", "M8 9h8", "M8 13h8", "M8 17h5"),
    "phone": _icon("M8 2h8a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z", "M11 18h2"),
    "shield": _icon("M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z", "M9 12l2 2 4-4"),
    "spark": _icon("M12 3v4", "M12 17v4", "M3 12h4", "M17 12h4", "M6 6l2.5 2.5", "M15.5 15.5 18 18", "M18 6l-2.5 2.5", "M8.5 15.5 6 18"),
    "chat": _icon("M4 5h16v11H8l-4 4z"),
    "check": _icon("M5 12l5 5L20 7"),
    "exam": _icon("M6 3h12v18H6z", "M9 8h6", "M9 12h6", "M9 16h3", "M14 17l1.5 1.5L18 16"),
    "family": _icon(
        "M9 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6z", "M3 20a6 6 0 0 1 12 0", "M16.5 11a2.5 2.5 0 1 0 0-5",
        "M21 20a5 5 0 0 0-4.5-5",
    ),
}

# Each product page's icon and tint (school/module_pages.py slugs).
MODULE_ICONS = {
    "school-attendance-software": ("attendance", ""),
    "school-fee-management-software": ("fees", "tone-gold"),
    "school-bus-tracking-software": ("bus", "tone-lilac"),
    "staff-attendance-software": ("staff", ""),
    "school-timetable-software": ("timetable", "tone-gold"),
    "student-progress-reports": ("progress", "tone-lilac"),
    "school-payroll-software": ("payroll", ""),
    "school-communication-software": ("message", "tone-gold"),
    "school-reports-and-analytics": ("reports", "tone-lilac"),
    "student-information-system": ("records", ""),
    "school-staff-and-driver-apps": ("phone", "tone-gold"),
    "school-exam-management-software": ("exam", "tone-lilac"),
}


# The name a product page's card, and the footer, show: a word or two a school
# recognises. The page's own heading and <title> keep the long name, which is
# what people search for.
SHORT_NAMES = {
    "school-attendance-software": "Attendance",
    "school-fee-management-software": "Fees",
    "school-bus-tracking-software": "School Bus",
    "staff-attendance-software": "Staff Check-in",
    "school-timetable-software": "Timetable",
    "student-progress-reports": "Report Cards & Results",
    "school-exam-management-software": "Exams & Admit Cards",
    "school-payroll-software": "Payroll & Leave",
    "school-communication-software": "Messages",
    "school-reports-and-analytics": "Reports",
    "student-information-system": "Records",
    "school-staff-and-driver-apps": "Mobile Apps",
}


# The help centre topic each product page's how-to guides are filed under
# (school/site_pages.py HELP_TOPICS), so a product page can list them.
MODULE_TOPICS = {
    "school-attendance-software": "attendance",
    "school-fee-management-software": "fees",
    "school-bus-tracking-software": "transport",
    "staff-attendance-software": "staff",
    "school-timetable-software": "teaching",
    "student-progress-reports": "tests",
    "school-exam-management-software": "tests",
    "school-payroll-software": "staff",
    "school-communication-software": "communication",
    "student-information-system": "getting-started",
    "school-staff-and-driver-apps": "apps",
}

def short_name(slug: str, title: str) -> str:
    return SHORT_NAMES.get(slug, title)

def module_look(slug: str) -> dict:
    icon, tone = MODULE_ICONS.get(slug, ("check", ""))
    return {"icon": ICONS[icon], "tone": tone}


# The features page, grouped the way a school thinks about its day. A product
# page not named here still appears, under "More".
FEATURE_GROUPS = (
    ("Students and academics", "Records, the register, the timetable and how each child is doing.",
     ("student-information-system", "school-attendance-software", "school-timetable-software",
      "school-exam-management-software", "student-progress-reports")),
    ("Fees and finance", "What each family owes, what they paid, and the receipt.",
     ("school-fee-management-software",)),
    ("Staff and payroll", "Staff attendance, check-in from the phone, leave and the month's pay.",
     ("staff-attendance-software", "school-payroll-software")),
    ("School transport", "Routes, stops, trips and who is on the bus.",
     ("school-bus-tracking-software",)),
    ("Communication", "Alerts and announcements to families and staff.",
     ("school-communication-software",)),
    ("Reports and the apps", "The school's figures, and the Android apps.",
     ("school-reports-and-analytics", "school-staff-and-driver-apps")),
)


def grouped(modules: list) -> list[dict]:
    """The product pages under FEATURE_GROUPS, in the order written there."""
    by_slug = {module.slug: module for module in modules}
    groups, placed = [], set()

    for title, blurb, slugs in FEATURE_GROUPS:
        members = [by_slug[slug] for slug in slugs if slug in by_slug]
        placed.update(module.slug for module in members)
        if members:
            groups.append({"title": title, "blurb": blurb, "modules": members})

    rest = [module for module in modules if module.slug not in placed]
    if rest:
        groups.append({"title": "More", "blurb": "", "modules": rest})

    return groups


# The homepage's role tabs: one connected school, four ways in.
ROLES = (
    {
        "key": "leaders",
        "tab": "School leaders",
        "eyebrow": "For principals and administrators",
        "title": "See the whole school, without chasing updates.",
        "body": "The dashboard brings today's attendance, fees, bus trips and the setup still to do onto one page, "
                "with trends over time and reports you can download.",
        "points": (
            "Today's attendance, fees and trips on one dashboard",
            "Exam date sheets and admit cards, published when ready",
            "Reports as PDF or CSV, and early warnings for students who are slipping",
        ),
        "card": "School overview",
        "rows": (("Attendance", "Register by register"), ("Fees", "Collected and due"),
                 ("Transport", "Trips running now")),
        "foot": "One page to start the day",
    },
    {
        "key": "teachers",
        "tab": "Teachers",
        "eyebrow": "For teachers and heads of department",
        "title": "Less paperwork. More time for teaching.",
        "body": "On the School365ai staff app a teacher sees today's periods, takes the class register - even "
                "without signal - and files a short report on what each period covered.",
        "points": (
            "Today's timetable, period by period",
            "The class register on the phone, even offline",
            "Test marks that become grades, report cards and progress reports",
        ),
        "card": "Today's classes",
        "rows": (("Period 1", "Class 7 A, Science"), ("Register", "Present or absent"),
                 ("Teaching report", "What was covered")),
        "foot": "The classroom essentials, in a pocket",
    },
    {
        "key": "office",
        "tab": "Office staff",
        "eyebrow": "For the school office",
        "title": "Make everyday administration flow.",
        "body": "Student and staff records, fees and receipts, leave and messages to families - in one place "
                "instead of registers and spreadsheets.",
        "points": (
            "Student records, imported from a spreadsheet",
            "Fee receipts as PDFs, with balances and credit",
            "Admit cards for a whole section, printed at once",
        ),
        "card": "Office worklist",
        "rows": (("Fees", "Receipts and dues"), ("Admissions", "New students"), ("Staff", "Attendance and leave")),
        "foot": "Fewer scattered records",
    },
    {
        "key": "transport",
        "tab": "Transport teams",
        "eyebrow": "For transport managers and bus crews",
        "title": "Keep every trip connected.",
        "body": "Routes and stops are set once. On the day the crew runs each trip from the School365ai Driver "
                "app, marks every child on and off the bus, and families are told.",
        "points": (
            "Routes, stops and the students on each bus",
            "Boarded and dropped, marked from the Driver app",
            "The bus's live location while a trip runs",
        ),
        "card": "Transport desk",
        "rows": (("Morning trips", "Running now"), ("Students", "Boarded or dropped"),
                 ("Families", "Told by SMS or WhatsApp")),
        "foot": "From the school gate to the school bus",
    },
)

# The homepage's questions, shown as an accordion and given to search
# engines as an FAQ. The answers say only what is true today.
HOME_FAQ = (
    ("What does School365ai do?",
     "It runs a school's day in one place: student and staff records, attendance, timetables and teaching "
     "reports, exam date sheets and admit cards, tests, report cards and progress reports, fees and receipts, "
     "the school bus, messages to families, payroll and reports. The office works on the web; teachers and bus "
     "crews use Android apps."),
    ("Can we schedule exams and print admit cards?",
     "Yes. A school sets up each exam's date sheet - every class's papers with their dates and times - "
     "publishes it when it is ready, and prints admit cards for one student or a whole section as a PDF. A "
     "change after publishing is issued as a new version, and earlier cards still reprint as they were."),
    ("How is an admit card different from a report card?",
     "An admit card is for exam day: the student, the centre, the reporting time and the papers they sit. A "
     "report card comes after: the marks, the grades and the result, in the school's own grading system."),
    ("Can our school start now?",
     "School365ai is welcoming schools through its early-access programme. Request a demo or join early "
     "access, and we will tell you how to get started."),
    ("Do teachers need a computer?",
     "No. Teachers and office staff can use the School365ai app on an Android phone, and drivers and bus "
     "attendants use the School365ai Driver app. The office dashboard runs in any modern browser."),
    ("How are families kept informed?",
     "The school can send alerts by SMS and WhatsApp - for example when a child is marked absent, or boards "
     "and leaves the school bus - and publish announcements."),
    ("How much does it cost?",
     "That depends on your school and the parts you use. Request a demo and we will go through it with you."),
)
