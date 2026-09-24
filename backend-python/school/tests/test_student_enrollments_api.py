"""Enrollment history: which class a student was in, year by year.

See docs/promotion.md. This slice is read-only in the sense that matters -
nothing here decides anything - but it is not passive: the row has to follow
the student without ever being asked to, or the history is wrong in exactly
the cases nobody checks.

What the tests hold on to:

- **Admitting a student records the year.** So does moving one between
  sections, and renumbering them.
- **A row is never blanked.** A student who loses their section keeps the
  row saying where they were.
- **One row per student per year**, kept by the database rather than by a
  check that could race.
- **The backfill is idempotent**, and says what it skipped and why.
"""

import datetime as dt

from django.core.cache import cache
from django.core.management import call_command
from django.test import TestCase
from io import StringIO
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import EnrollmentStatus, StudentStatus, UserRole
from school.models import Student, StudentEnrollment
from school.services import SchoolClassService, StudentEnrollmentService

STUDENTS = "/api/v1/students"


class EnrollmentTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.year = factories.AcademicYearFactory(
            school=self.school, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        self.school_class = factories.SchoolClassFactory(academic_year=self.year, school=self.school, name="Grade 7")
        self.section = factories.ClassSectionFactory(school_class=self.school_class, name="A")
        self.other_section = factories.ClassSectionFactory(school_class=self.school_class, name="B")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def payload(self, **overrides) -> dict:
        body = {
            "school_id": self.school.id,
            "class_section_id": self.section.id,
            "admission_number": "ADM-1",
            "first_name": "Aarav",
            "last_name": "Sharma",
            "guardian_name": "Meera Sharma",
        }
        body.update(overrides)

        return body

    def admit(self, **overrides) -> dict:
        response = self.client.post(STUDENTS, self.payload(**overrides), format="json")
        self.assertEqual(201, response.status_code, response.data)

        return response.data

    def rows_for(self, student_id: int):
        return StudentEnrollment.objects.filter(student_id=student_id).order_by("id")


class TheHistoryFollowsTheStudent(EnrollmentTestCase):
    def test_admitting_a_student_records_the_year_they_arrived_in(self):
        student = self.admit()

        row = self.rows_for(student["id"]).get()
        self.assertEqual(
            (self.school.id, self.year.id, self.school_class.id, self.section.id, EnrollmentStatus.STUDYING),
            (row.school_id, row.academic_year_id, row.school_class_id, row.class_section_id, row.status),
        )

    def test_the_roll_number_is_kept_as_it_was(self):
        student = self.admit(roll_number="17")

        self.assertEqual("17", self.rows_for(student["id"]).get().roll_number)

    def test_moving_a_student_between_sections_moves_the_row(self):
        student = self.admit()

        self.client.patch(
            f"{STUDENTS}/{student['id']}", {"class_section_id": self.other_section.id}, format="json"
        )

        rows = self.rows_for(student["id"])
        self.assertEqual(1, rows.count(), "one row per year, not one per move")
        self.assertEqual(self.other_section.id, rows.get().class_section_id)

    def test_renumbering_a_student_updates_the_row(self):
        student = self.admit(roll_number="17")

        self.client.patch(f"{STUDENTS}/{student['id']}", {"roll_number": "3"}, format="json")

        self.assertEqual("3", self.rows_for(student["id"]).get().roll_number)

    def test_a_student_with_no_section_gets_no_row_yet(self):
        # The admissions form insists on a section, so this is the shape a
        # student takes after a section is removed, or after an import that
        # could not place them.
        student = factories.StudentFactory(
            school=self.school, class_section=None, admission_number="ADM-NO-SECTION"
        )

        self.assertIsNone(StudentEnrollmentService.sync_current_year(student))
        self.assertEqual(0, self.rows_for(student.id).count())

    def test_the_row_appears_the_moment_the_section_does(self):
        student = factories.StudentFactory(
            school=self.school, class_section=None, admission_number="ADM-NO-SECTION"
        )

        self.client.patch(f"{STUDENTS}/{student.id}", {"class_section_id": self.section.id}, format="json")

        self.assertEqual(self.section.id, self.rows_for(student.id).get().class_section_id)

    def test_a_school_with_no_current_year_records_nothing_and_does_not_fail(self):
        self.year.is_current = False
        self.year.save(update_fields=["is_current"])

        student = self.admit()

        self.assertEqual(0, self.rows_for(student["id"]).count())

    def test_a_section_from_another_year_is_not_this_years_row(self):
        # The shape a promotion will produce: next year's section, while the
        # current year is still the old one.
        next_year = factories.AcademicYearFactory(school=self.school, name="2027-28", is_current=False)
        next_class = factories.SchoolClassFactory(academic_year=next_year, school=self.school, name="Grade 8")
        next_section = factories.ClassSectionFactory(school_class=next_class, name="A")

        student = self.admit(class_section_id=next_section.id)

        self.assertEqual(0, self.rows_for(student["id"]).count())

    def test_deactivating_a_student_leaves_the_history_alone(self):
        student = self.admit()

        self.client.patch(f"{STUDENTS}/{student['id']}/deactivate", format="json")

        self.assertEqual(1, self.rows_for(student["id"]).count())


class OneRowPerStudentPerYear(EnrollmentTestCase):
    def test_syncing_twice_writes_one_row(self):
        student = self.admit()

        stored = StudentEnrollment.objects.get(student_id=student["id"])
        StudentEnrollmentService.sync_current_year(Student.objects.get(pk=student["id"]))

        self.assertEqual(1, self.rows_for(student["id"]).count())
        self.assertEqual(stored.id, self.rows_for(student["id"]).get().id, "the same row, updated in place")

    def test_two_students_may_share_a_year(self):
        first = self.admit(admission_number="ADM-1")
        second = self.admit(admission_number="ADM-2", class_section_id=self.other_section.id)

        self.assertEqual(1, self.rows_for(first["id"]).count())
        self.assertEqual(1, self.rows_for(second["id"]).count())


class TheBackfill(EnrollmentTestCase):
    def setUp(self):
        super().setUp()
        # Students that exist without history, as they do in a database that
        # predates the table.
        self.existing = factories.StudentFactory(
            school=self.school, class_section=self.section, admission_number="OLD-1", roll_number="9"
        )
        self.sectionless = factories.StudentFactory(
            school=self.school, class_section=None, admission_number="OLD-2"
        )
        self.inactive = factories.StudentFactory(
            school=self.school, class_section=self.section, admission_number="OLD-3", status=StudentStatus.INACTIVE
        )

    def run_backfill(self, *args) -> str:
        out = StringIO()
        call_command("backfill_enrollments", *args, stdout=out)

        return out.getvalue()

    def test_it_writes_the_missing_rows_and_says_what_it_did(self):
        output = self.run_backfill()

        row = StudentEnrollment.objects.get(student_id=self.existing.id)
        self.assertEqual((self.section.id, "9", EnrollmentStatus.STUDYING), (row.class_section_id, row.roll_number, row.status))
        self.assertIn("1 enrolment rows written or confirmed", output)
        self.assertIn("1 students skipped", output)

    def test_a_student_with_no_section_is_skipped_not_failed(self):
        self.run_backfill()

        self.assertEqual(0, StudentEnrollment.objects.filter(student_id=self.sectionless.id).count())

    def test_an_inactive_student_is_left_out(self):
        self.run_backfill()

        self.assertEqual(0, StudentEnrollment.objects.filter(student_id=self.inactive.id).count())

    def test_running_it_twice_changes_nothing(self):
        self.run_backfill()
        first = StudentEnrollment.objects.get(student_id=self.existing.id)

        self.run_backfill()

        self.assertEqual(1, StudentEnrollment.objects.filter(student_id=self.existing.id).count())
        self.assertEqual(first.id, StudentEnrollment.objects.get(student_id=self.existing.id).id)

    def test_it_can_be_pointed_at_one_school(self):
        elsewhere = factories.SchoolFactory()
        their_year = factories.AcademicYearFactory(school=elsewhere, is_current=True)
        their_section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=their_year, school=elsewhere)
        )
        theirs = factories.StudentFactory(
            school=elsewhere, class_section=their_section, admission_number="THEIRS-1"
        )

        self.run_backfill("--school", str(self.school.id))

        self.assertEqual(1, StudentEnrollment.objects.filter(student_id=self.existing.id).count())
        self.assertEqual(0, StudentEnrollment.objects.filter(student_id=theirs.id).count())

    def test_a_school_that_does_not_exist_is_reported_not_crashed(self):
        errors = StringIO()
        call_command("backfill_enrollments", "--school", "9999999", stderr=errors)

        self.assertIn("No school with id", errors.getvalue())

    def test_a_school_with_no_current_year_skips_its_students(self):
        self.year.is_current = False
        self.year.save(update_fields=["is_current"])

        output = self.run_backfill()

        self.assertEqual(0, StudentEnrollment.objects.count())
        self.assertIn("2 students skipped", output)


class ReadingTheHistory(EnrollmentTestCase):
    def setUp(self):
        super().setUp()
        self.student = factories.StudentFactory(
            school=self.school, class_section=self.section, admission_number="ADM-9", roll_number="4"
        )
        self.last_year = factories.AcademicYearFactory(
            school=self.school,
            name="2025-26",
            start_date=dt.date(2025, 4, 1),
            end_date=dt.date(2026, 3, 31),
            is_current=False,
        )
        self.last_class = factories.SchoolClassFactory(
            academic_year=self.last_year, school=self.school, name="Grade 6"
        )
        self.last_section = factories.ClassSectionFactory(school_class=self.last_class, name="B")
        factories.StudentEnrollmentFactory(
            student=self.student,
            school=self.school,
            academic_year=self.last_year,
            school_class=self.last_class,
            class_section=self.last_section,
            roll_number="11",
            status=EnrollmentStatus.PROMOTED,
        )
        factories.StudentEnrollmentFactory(student=self.student, roll_number="4")

    def url(self, student_id: int) -> str:
        return f"{STUDENTS}/{student_id}/enrollments"

    def test_the_history_reads_newest_year_first(self):
        response = self.client.get(self.url(self.student.id))

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(["2026-27", "2025-26"], [row["academic_year_name"] for row in response.data])
        self.assertEqual(["Grade 7", "Grade 6"], [row["class_name"] for row in response.data])
        self.assertEqual(["A", "B"], [row["section_name"] for row in response.data])
        self.assertEqual(["4", "11"], [row["roll_number"] for row in response.data])
        self.assertEqual(["studying", "promoted"], [row["status"] for row in response.data])

    def test_a_student_with_no_history_reads_as_an_empty_list(self):
        fresh = factories.StudentFactory(school=self.school, class_section=None, admission_number="ADM-10")

        response = self.client.get(self.url(fresh.id))

        self.assertEqual(200, response.status_code)
        self.assertEqual([], response.data)

    def test_a_year_whose_section_was_removed_still_names_the_class(self):
        SchoolClassService.delete_section(self.last_section)

        response = self.client.get(self.url(self.student.id))

        last = next(row for row in response.data if row["academic_year_name"] == "2025-26")
        self.assertEqual("Grade 6", last["class_name"])
        self.assertIsNone(last["section_name"])

    def test_a_teacher_reads_their_own_students_history(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.section.class_teacher = teacher
        self.section.save(update_fields=["class_teacher"])

        response = self.as_user(teacher).get(self.url(self.student.id))

        self.assertEqual(200, response.status_code, response.data)

    def test_a_teacher_of_another_section_is_refused(self):
        stranger = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.other_section.class_teacher = stranger
        self.other_section.save(update_fields=["class_teacher"])

        self.assertEqual(403, self.as_user(stranger).get(self.url(self.student.id)).status_code)

    def test_another_school_is_refused(self):
        outsider = factories.UserFactory(
            school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN
        )

        self.assertEqual(403, self.as_user(outsider).get(self.url(self.student.id)).status_code)

    def test_a_group_admin_reads_a_branchs_student(self):
        branch = factories.SchoolFactory(parent_school=self.school)
        branch_year = factories.AcademicYearFactory(school=branch, is_current=True)
        branch_section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=branch_year, school=branch)
        )
        branch_student = factories.StudentFactory(
            school=branch, class_section=branch_section, admission_number="BR-1"
        )
        factories.StudentEnrollmentFactory(student=branch_student)
        group_admin = factories.UserFactory(school=self.school, role=UserRole.GROUP_ADMIN)

        response = self.as_user(group_admin).get(self.url(branch_student.id))

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(1, len(response.data))

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get(self.url(self.student.id)).status_code)

    def test_a_student_that_does_not_exist_is_a_404(self):
        self.assertEqual(404, self.client.get(self.url(9_999_999)).status_code)
