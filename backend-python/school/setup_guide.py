"""A new school's setup guide (docs/onboarding.md, slice O4).

Six steps in the order they depend on each other - a year before classes,
departments before subjects, classes before students. A step is done when
the school has the thing, never because somebody ticked it: a school that set
up its classes by hand has done the classes step.

Whether the guide still shows is remembered for the whole school
(`schools.setup_guide_closed_at`).
"""

from __future__ import annotations

from .enums import StudentStatus, UserRole
from .models import AcademicYear, ClassSection, Department, SchoolClass, Student, Subject, User

# Everybody on the staff list - not the admins setting the school up.
NOT_STAFF = (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN)

# Common departments offered in one step. Ticked to start with: the ones
# almost every school has.
DEPARTMENT_PRESETS = (
    ("Pre-Primary", True),
    ("Primary", True),
    ("Languages", True),
    ("Mathematics", True),
    ("Science", True),
    ("Social Studies", True),
    ("Computer Science", False),
    ("Arts", False),
    ("Physical Education", False),
    ("Commerce", False),
)


def steps_for(school_id: int) -> list[dict]:
    year = AcademicYear.objects.filter(school_id=school_id, is_current=True).first()
    classes = SchoolClass.objects.filter(school_id=school_id, academic_year=year) if year else SchoolClass.objects.none()
    sections = ClassSection.objects.filter(school_class__in=classes).count()
    departments = Department.objects.filter(school_id=school_id).count()
    subjects = Subject.objects.filter(school_id=school_id).count()
    staff = User.objects.filter(school_id=school_id).exclude(role__in=NOT_STAFF).count()
    students = Student.objects.filter(school_id=school_id, status=StudentStatus.ACTIVE).count()
    class_count = classes.count()

    return [
        step(
            "academic_year", "Academic year", "/academic-years",
            "The year's start and end dates. Mark it as the current year.",
            done=year is not None, summary=f"{year.name} is the current year" if year else None,
        ),
        step(
            "departments", "Departments", "/departments",
            "Groups of subjects and teachers, such as Science or Primary.",
            done=departments > 0, summary=counted(departments, "department"),
        ),
        step(
            "classes", "Classes & sections", "/classes",
            "Quick setup adds Nursery to Class 10, with their sections, in one step.",
            done=class_count > 0 and sections > 0,
            summary=f"{counted(class_count, 'class', 'classes')}, {counted(sections, 'section')}" if class_count else None,
            blocked_by=None if year else "Add the academic year first - classes belong to a year.",
        ),
        step(
            "subjects", "Subjects", "/subjects",
            "What is taught, and in which classes.",
            done=subjects > 0, summary=counted(subjects, "subject"),
            blocked_by=None if departments else "Add a department first - every subject belongs to one.",
        ),
        step(
            "staff", "Teachers & staff", "/staff",
            "Add them one by one or upload a spreadsheet. Each is emailed how to sign in.",
            done=staff > 0, summary=counted(staff, "person", "people"),
        ),
        step(
            "students", "Students", "/students",
            "Add them one by one or with Bulk Upload. Roll numbers are given automatically.",
            done=students > 0, summary=counted(students, "student"),
            blocked_by=None if sections else "Set up classes and sections first - every student is in one.",
        ),
    ]


# What a school may set up next, once the six are done. Not counted.
EXTRAS = (
    ("Holidays", "/holidays", "Days the school is closed, so attendance is not expected."),
    ("Timetable", "/timetable", "Periods and who teaches what, when."),
    ("Fees", "/fee-setup", "Fee heads, amounts and due dates."),
    ("Transport", "/transport/routes", "Buses, routes and stops."),
)


def step(key, title, path, detail, *, done, summary=None, blocked_by=None) -> dict:
    return {
        "key": key,
        "title": title,
        "detail": detail,
        "path": path,
        "done": done,
        "summary": summary if done else None,
        "blocked_by": None if done else blocked_by,
    }


def counted(n: int, singular: str, plural: str | None = None) -> str | None:
    if not n:
        return None

    return f"{n} {singular if n == 1 else (plural or singular + 's')}"
