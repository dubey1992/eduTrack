"""What a trusted school computer keeps for working offline
(docs/offline-web.md, O2, decided 2026-11-28).

One request, not hundreds - the host serves each request as a fresh process,
so a computer filling its copy page by page would be slow and would compete
with everybody else's work. The answer is compact and only what the person
may already see online:

- **students** - the active ones the students list would show them (a
  teacher: their own classes), with class, roll number and guardian;
- **classes** - the sections those students are in;
- **staff** - only for someone the permissions matrix lets see staff;
- **dues** - only for someone who may see fees: each student's fee lines
  with something still owed, any year, so the fee counter can take a
  payment with the line down (O4);
- **school** - name, address, phone and currency, for a provisional receipt.

The school decides whether its computers may keep this at all (Students
module setting `offline_copies`, on by default); the computer decides
whether it is one the person trusts (the tick at sign-in, kept on the
computer). Nothing here is written to the server.
"""

from __future__ import annotations

from collections import defaultdict

from django.utils import timezone
from rest_framework import status

from . import modules, permissions
from .clock import SchoolClock
from .enums import StudentStatus, UserRole, UserStatus
from .errors import ApiError
from .fees.ledger import balance_of, is_overdue, owed
from .models import ClassSection, School, StaffProfile, StudentFeeDue
from .resources import section_label

MODULE = "students"
SETTING = "offline_copies"

# A school bigger than this keeps its first students only: the copy has to
# fit in a browser's storage, and no real school office needs more offline.
STUDENT_LIMIT = 5000

# Who works in the web office; the bus crew and families have their own apps.
OFFICE_ROLES = (
    UserRole.SCHOOL_ADMIN,
    UserRole.GROUP_ADMIN,
    UserRole.HOD,
    UserRole.TEACHER,
    UserRole.STAFF,
    UserRole.ACCOUNTANT,
    UserRole.TRANSPORT_MANAGER,
)


class OfflineCopiesOff(ApiError):
    status_code = status.HTTP_403_FORBIDDEN
    error_code = "OFFLINE_COPIES_OFF"


def allowed(school_id: int | None) -> bool:
    return school_id is not None and bool(modules.setting(school_id, MODULE, SETTING))


def build(actor) -> dict:
    from .services import StaffProfileService, StudentService

    school_id = actor.school_id
    if not allowed(school_id):
        raise OfflineCopiesOff("This school keeps no offline copies on its computers.")

    school = School.objects.get(pk=school_id)
    today = SchoolClock.for_school(school_id).now().date()

    students = list(
        StudentService.visible_to(actor, {"school_id": school_id, "status": StudentStatus.ACTIVE})
        .select_related("class_section__school_class")
        .order_by("class_section__school_class__level", "class_section__name", "roll_number", "first_name", "id")[
            :STUDENT_LIMIT
        ]
    )
    student_ids = [s.id for s in students]
    section_ids = sorted({s.class_section_id for s in students if s.class_section_id})

    answer = {
        "generated_at": timezone.now().isoformat(),
        "school": {
            "id": school.id,
            "name": school.name,
            "address": ", ".join(p for p in (school.address, school.city, school.state, school.postal_code) if p),
            "phone": school.phone,
            "email": school.email,
            "currency_code": school.currency_code,
        },
        "classes": [
            {"id": section.id, "name": section_label(section)}
            for section in ClassSection.objects.select_related("school_class")
            .filter(pk__in=section_ids)
            .order_by("school_class__level", "school_class__name", "name")
        ],
        "students": [
            {
                "id": s.id,
                "name": s.name,
                "admission_number": s.admission_number,
                "roll_number": s.roll_number,
                "class_section_id": s.class_section_id,
                "class_name": section_label(s.class_section),
                "guardian_name": s.guardian_name,
                "guardian_mobile": s.guardian_mobile,
            }
            for s in students
        ],
        "staff": None,
        "dues": None,
    }

    if permissions.may_view(actor, "staff") and modules.is_enabled(school_id, "staff"):
        staff = (
            StaffProfileService.visible_to(actor, {"school_id": school_id})
            .select_related("user", "department")
            .filter(user__status=UserStatus.ACTIVE)
        )
        answer["staff"] = [
            {
                "id": row.id,
                "name": row.user.name,
                "employee_id": row.employee_id,
                "department": row.department.name if row.department_id else None,
                "designation": row.designation,
                "mobile": row.user.mobile,
                "email": row.user.email,
            }
            for row in staff
        ]

    if permissions.may_view(actor, "fees") and modules.is_enabled(school_id, "fees"):
        by_student = defaultdict(list)
        for due in (
            owed(StudentFeeDue.objects.filter(school_id=school_id, student_id__in=student_ids))
            .select_related("fee_head", "academic_year")
            .order_by("student_id", "due_date", "id")
        ):
            by_student[due.student_id].append(
                {
                    "id": due.id,
                    "academic_year_id": due.academic_year_id,
                    "academic_year": due.academic_year.name,
                    "fee_head": due.fee_head.name,
                    "label": due.label,
                    "kind": due.kind,
                    "due_date": due.due_date.isoformat(),
                    "currency_code": due.currency_code,
                    "balance": f"{balance_of(due):.2f}",
                    "is_overdue": is_overdue(due, today),
                }
            )
        answer["dues"] = {str(student_id): dues for student_id, dues in by_student.items()}

    return answer
