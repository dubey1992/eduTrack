"""Every endpoint the API serves, and therefore every one the contract owes.

Generated from the route table on 2026-09-16 and then maintained by hand. It is
not a convenience: without it, "the contract covers the API" is a feeling rather
than a fact, and the endpoint nobody remembers is exactly the one a rewrite gets
wrong.

A backend test (RouteManifestTest) fails if a route exists that is not listed
here, so adding an endpoint forces a decision about covering it rather than
letting it slip in unnoticed. The manifest lives on this side of the line
because it describes the contract, not the implementation - the Python backend
will owe exactly the same list.
"""

from __future__ import annotations

ENDPOINTS: list[tuple[str, str]] = [
    # -- academic-years --------------------------------------------
    ("GET", "academic-years"),
    ("POST", "academic-years"),
    ("DELETE", "academic-years/{academicYear}"),
    ("GET", "academic-years/{academicYear}"),
    ("PATCH", "academic-years/{academicYear}"),
    ("PATCH", "academic-years/{academicYear}/set-current"),

    # -- announcements ---------------------------------------------
    ("GET", "announcements"),
    ("POST", "announcements"),
    ("GET", "announcements/preview"),
    ("DELETE", "announcements/{announcement}"),
    ("GET", "announcements/{announcement}"),

    # -- attendance ------------------------------------------------
    ("GET", "attendance"),
    ("PATCH", "attendance"),
    ("POST", "attendance"),
    ("GET", "attendance/register"),

    # -- auth ------------------------------------------------------
    ("POST", "auth/change-password"),
    ("POST", "auth/forgot-password"),
    ("POST", "auth/login"),
    ("POST", "auth/logout"),
    ("POST", "auth/reset-password"),

    # -- classes ---------------------------------------------------
    ("GET", "classes"),
    ("POST", "classes"),
    ("DELETE", "classes/{schoolClass}"),
    ("GET", "classes/{schoolClass}"),
    ("PATCH", "classes/{schoolClass}"),
    ("POST", "classes/{schoolClass}/sections"),

    # -- communication ---------------------------------------------
    ("GET", "communication/messages"),
    ("GET", "communication/messages/{message}"),
    ("POST", "communication/messages/{message}/retry"),
    ("GET", "communication/settings"),
    ("PUT", "communication/settings"),
    ("GET", "communication/summary"),
    ("GET", "communication/templates"),
    ("DELETE", "communication/templates/{event}"),
    ("PUT", "communication/templates/{event}"),

    # -- dashboard -------------------------------------------------
    ("GET", "dashboard"),

    # -- departments -----------------------------------------------
    ("GET", "departments"),
    ("POST", "departments"),
    ("DELETE", "departments/{department}"),
    ("GET", "departments/{department}"),
    ("PATCH", "departments/{department}"),

    # -- early-access ----------------------------------------------
    ("GET", "early-access"),
    ("POST", "early-access"),
    ("GET", "early-access/{earlyAccessRequest}"),
    ("PATCH", "early-access/{earlyAccessRequest}"),

    # -- hod -------------------------------------------------------
    ("GET", "hod/department-report"),

    # -- holidays --------------------------------------------------
    ("GET", "holidays"),
    ("POST", "holidays"),
    ("DELETE", "holidays/{holiday}"),
    ("GET", "holidays/{holiday}"),
    ("PATCH", "holidays/{holiday}"),

    # -- imports ---------------------------------------------------
    ("POST", "imports/{type}"),
    ("GET", "imports/{type}/template"),

    # -- inbox -----------------------------------------------------
    ("GET", "inbox"),
    ("POST", "inbox/read-all"),
    ("GET", "inbox/unread-count"),
    ("POST", "inbox/{message}/read"),

    # -- leaves ----------------------------------------------------
    ("GET", "leaves"),
    ("POST", "leaves"),
    ("GET", "leaves/summary"),
    ("PATCH", "leaves/{leave}/approve"),
    ("PATCH", "leaves/{leave}/reject"),

    # -- me --------------------------------------------------------
    ("GET", "me"),

    # -- payments --------------------------------------------------
    ("GET", "payments"),
    ("POST", "payments"),
    ("GET", "payments/summary"),
    ("GET", "payments/{payment}"),
    ("PATCH", "payments/{payment}"),
    ("GET", "payments/{payment}/receipt"),
    ("POST", "payments/{payment}/receipt"),

    # -- periods ---------------------------------------------------
    ("GET", "periods"),
    ("POST", "periods"),
    ("DELETE", "periods/{period}"),
    ("PATCH", "periods/{period}"),

    # -- reports ---------------------------------------------------
    ("GET", "reports/staff-attendance"),
    ("GET", "reports/student-attendance"),
    ("GET", "reports/teaching-coverage"),
    ("GET", "reports/transport-usage"),

    # -- schools ---------------------------------------------------
    ("GET", "schools"),
    ("POST", "schools"),
    ("GET", "schools/{school}"),
    ("PATCH", "schools/{school}"),
    ("PATCH", "schools/{school}/activate"),
    ("PATCH", "schools/{school}/deactivate"),

    # -- sections --------------------------------------------------
    ("DELETE", "sections/{section}"),
    ("PATCH", "sections/{section}"),

    # -- staff -----------------------------------------------------
    ("GET", "staff"),
    ("POST", "staff"),
    ("GET", "staff/{staffProfile}"),
    ("PATCH", "staff/{staffProfile}"),

    # -- staff-attendance ------------------------------------------
    ("GET", "staff-attendance"),
    ("PATCH", "staff-attendance"),
    ("POST", "staff-attendance"),
    ("GET", "staff-attendance/register"),

    # -- students --------------------------------------------------
    ("GET", "students"),
    ("POST", "students"),
    ("GET", "students/{student}"),
    ("PATCH", "students/{student}"),
    ("PATCH", "students/{student}/activate"),
    ("PATCH", "students/{student}/deactivate"),
    ("DELETE", "students/{student}/transport"),
    ("PUT", "students/{student}/transport"),

    # -- subjects --------------------------------------------------
    ("GET", "subjects"),
    ("POST", "subjects"),
    ("DELETE", "subjects/{subject}"),
    ("GET", "subjects/{subject}"),
    ("PATCH", "subjects/{subject}"),

    # -- syllabus-progress -----------------------------------------
    ("GET", "syllabus-progress"),
    ("PATCH", "syllabus-progress"),

    # -- syllabus-topics -------------------------------------------
    ("GET", "syllabus-topics"),
    ("POST", "syllabus-topics"),
    ("DELETE", "syllabus-topics/{syllabusTopic}"),
    ("PATCH", "syllabus-topics/{syllabusTopic}"),

    # -- teaching-reports ------------------------------------------
    ("GET", "teaching-reports"),
    ("POST", "teaching-reports"),
    ("GET", "teaching-reports/summary"),
    ("PATCH", "teaching-reports/{report}/review"),

    # -- timetable -------------------------------------------------
    ("GET", "timetable"),
    ("POST", "timetable"),
    ("DELETE", "timetable/{entry}"),

    # -- timezones -------------------------------------------------
    ("GET", "timezones"),

    # -- transport -------------------------------------------------
    ("GET", "transport/drivers"),
    ("POST", "transport/drivers"),
    ("DELETE", "transport/drivers/{driver}"),
    ("GET", "transport/drivers/{driver}"),
    ("PATCH", "transport/drivers/{driver}"),
    ("GET", "transport/routes"),
    ("POST", "transport/routes"),
    ("DELETE", "transport/routes/{route}"),
    ("GET", "transport/routes/{route}"),
    ("PATCH", "transport/routes/{route}"),
    ("POST", "transport/routes/{route}/stops"),
    ("GET", "transport/routes/{route}/students"),
    ("DELETE", "transport/stops/{stop}"),
    ("PATCH", "transport/stops/{stop}"),
    ("GET", "transport/trips"),
    ("POST", "transport/trips"),
    ("GET", "transport/trips/{trip}"),
    ("POST", "transport/trips/{trip}/cancel"),
    ("POST", "transport/trips/{trip}/end"),
    ("PATCH", "transport/trips/{trip}/riders/{student}"),
    ("POST", "transport/trips/{trip}/stops/{stop}/reached"),
    ("GET", "transport/vehicles"),
    ("POST", "transport/vehicles"),
    ("DELETE", "transport/vehicles/{vehicle}"),
    ("GET", "transport/vehicles/{vehicle}"),
    ("PATCH", "transport/vehicles/{vehicle}"),

    # -- users -----------------------------------------------------
    ("GET", "users"),
    ("POST", "users"),
    ("GET", "users/{user}"),
    ("PATCH", "users/{user}"),
    ("PATCH", "users/{user}/activate"),
    ("PATCH", "users/{user}/deactivate"),
]


# Served by the Python backend only - features built after the port froze the
# Laravel one (docs/python-migration.md). Kept out of ENDPOINTS, which is the
# list RouteManifestTest holds Laravel to; that test reads only what comes
# before this marker. Counted towards coverage when the backend under test
# serves them.
PYTHON_ONLY_ENDPOINTS: list[tuple[str, str]] = [
    # -- payroll (Phase 19, docs/payroll.md) -----------------------
    ("GET", "payroll/salaries"),
    ("GET", "payroll/salaries/{staffProfile}"),
    ("PUT", "payroll/salaries/{staffProfile}"),
    ("GET", "payroll/runs"),
    ("POST", "payroll/runs"),
    ("GET", "payroll/runs/{run}"),
    ("DELETE", "payroll/runs/{run}"),
    ("GET", "payroll/runs/{run}/payslips"),
    ("POST", "payroll/runs/{run}/regenerate"),
    ("POST", "payroll/runs/{run}/finalize"),
    ("POST", "payroll/runs/{run}/pay"),
    ("GET", "payroll/payslips/{payslip}"),
    ("POST", "payroll/payslips/{payslip}/adjustments"),
    ("DELETE", "payroll/payslips/{payslip}/adjustments/{line}"),
    ("POST", "payroll/payslips/{payslip}/pay"),
    ("GET", "payroll/payslips/{payslip}/pdf"),
    ("POST", "payroll/payslips/{payslip}/email"),
    ("GET", "payroll/my-payslips"),
    # -- advanced reporting (Phase 20, docs/reports.md) -------------
    ("GET", "reports/leave-usage"),
    ("GET", "reports/payroll-summary"),
    ("GET", "reports/syllabus-progress"),
    # -- audit and security (Phase 21, docs/security.md) -------------
    ("GET", "audit-logs"),
    ("GET", "audit-logs/{entry}"),
    ("GET", "auth/sessions"),
    ("POST", "auth/sessions/others"),
    ("DELETE", "auth/sessions/{session}"),
    ("POST", "users/{user}/unlock"),
    # -- messaging channels and SMTP (docs/communication.md) -----------
    ("POST", "communication/settings/test"),
    ("PUT", "communication/templates/{event}/whatsapp"),
    ("DELETE", "communication/templates/{event}/whatsapp"),
    ("POST", "communication/notices"),
    ("GET", "communication/notices/preview"),
    ("GET", "settings/mail"),
    ("PUT", "settings/mail"),
    ("POST", "settings/mail/test"),
    # -- academic terms (docs/assessments.md) ---------------------------
    ("GET", "academic-terms"),
    ("POST", "academic-terms"),
    ("GET", "academic-terms/{academicTerm}"),
    ("PATCH", "academic-terms/{academicTerm}"),
    ("DELETE", "academic-terms/{academicTerm}"),

    # -- grade scales (docs/assessments.md) -----------------------------
    ("GET", "grade-scales"),
    ("POST", "grade-scales"),
    ("GET", "grade-scales/{gradeScale}"),
    ("PUT", "grade-scales/{gradeScale}"),
    ("DELETE", "grade-scales/{gradeScale}"),

    # -- module settings and the permissions matrix (docs/settings.md) --
    ("GET", "settings/modules"),
    ("PUT", "settings/modules/{module}"),
    ("GET", "settings/permissions"),
    ("PUT", "settings/permissions"),
    ("POST", "settings/permissions/reset"),
    # -- my profile (docs/profile.md) --------------------------------
    ("GET", "profile"),
    ("PATCH", "profile"),
    ("POST", "profile/email"),
    ("POST", "profile/photo"),
    ("DELETE", "profile/photo"),
    ("GET", "users/{user}/photo"),
    # -- the Bus Attendant (docs/maps.md) -------------------------------
    ("POST", "auth/attendant/setup"),
    ("POST", "auth/attendant/login"),
    ("GET", "staff/{profile}/attendant"),
    ("POST", "staff/{profile}/attendant/setup-code"),
    ("DELETE", "staff/{profile}/attendant/devices/{device}"),
    ("GET", "transport/my-routes"),
    ("POST", "transport/trips/{trip}/sync"),
    ("POST", "transport/trips/{trip}/locations"),
    ("GET", "transport/trips/{trip}/live"),
]


def count() -> int:
    return len(ENDPOINTS)
