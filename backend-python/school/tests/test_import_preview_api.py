"""Seeing a file before it lands (docs/imports.md).

"Nothing is written unless every row passes" still leaves a file that passes
landing unseen, and there is no undo for a hundred records created from the
wrong spreadsheet. So every upload can be previewed first: the same reading
and the same checks, and then the rows come back instead of being written.

The two things the tests hold on to: a preview writes nothing, and a preview
refuses exactly what the upload would refuse.
"""

import datetime as dt

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import Assessment, AssessmentMark, Student

STUDENT_HEADINGS = "admission_number,first_name,last_name,class,section,roll_number,guardian_name,guardian_mobile,address"


def csv_file(*rows: str, headings: str, name: str = "upload.csv") -> SimpleUploadedFile:
    body = "\n".join([headings, *rows]) + "\n"

    return SimpleUploadedFile(name, body.encode("utf-8"), content_type="text/csv")


class PreviewTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.year = factories.AcademicYearFactory(
            school=self.school, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        self.school_class = factories.SchoolClassFactory(
            academic_year=self.year, school=self.school, name="Grade 8", level=8
        )
        self.section = factories.ClassSectionFactory(school_class=self.school_class, name="A")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def student_row(self, admission_number: str = "ADM-1", name: str = "Aarav") -> str:
        return f"{admission_number},{name},Sharma,Grade 8,A,12,Meera Sharma,,"

    def rows(self, response) -> list[dict]:
        return response.data["details"]["rows"]


class PreviewingAFileOfStudents(PreviewTestCase):
    def url(self) -> str:
        return "/api/v1/imports/students/preview"

    def test_the_rows_come_back_and_nothing_is_written(self):
        response = self.client.post(
            self.url(),
            {"file": csv_file(self.student_row(), self.student_row("ADM-2", "Bina"), headings=STUDENT_HEADINGS)},
            format="multipart",
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(2, response.data["row_count"])
        self.assertEqual("Students", response.data["label"])
        self.assertEqual(["admission_number", "first_name"], response.data["headings"][:2])
        self.assertEqual(2, response.data["rows"][0]["row"], "the heading is row 1")
        self.assertEqual("ADM-1", response.data["rows"][0]["values"][0])
        self.assertEqual(0, Student.objects.count(), "a preview writes nothing")

    def test_a_preview_refuses_what_the_upload_would_refuse(self):
        response = self.client.post(
            self.url(),
            # A class the school does not have: valid column by column, and
            # nothing as a whole.
            {"file": csv_file("ADM-1,Aarav,Sharma,Grade 9,Z,12,Meera Sharma,,", headings=STUDENT_HEADINGS)},
            format="multipart",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("no section", self.rows(response)[0]["messages"][0])
        self.assertEqual(0, Student.objects.count())

    def test_a_file_with_the_wrong_headings_is_refused(self):
        response = self.client.post(
            self.url(), {"file": csv_file("x", headings="wrong,headings")}, format="multipart"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("column headings do not match", self.rows(response)[0]["messages"][0])

    def test_a_missing_file_is_named(self):
        response = self.client.post(self.url(), {}, format="multipart")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("file", response.data["details"]["errors"])

    def test_a_long_file_says_how_many_rows_it_holds(self):
        rows = [self.student_row(f"ADM-{index}", f"Student{index}") for index in range(1, 61)]

        response = self.client.post(
            self.url(), {"file": csv_file(*rows, headings=STUDENT_HEADINGS)}, format="multipart"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(60, response.data["row_count"])
        self.assertEqual(50, len(response.data["rows"]), "the first fifty are enough to recognise it by")
        self.assertIs(True, response.data["truncated"])

    def test_a_teacher_may_not_preview_a_file_of_students(self):
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        response = teacher.post(
            self.url(), {"file": csv_file(self.student_row(), headings=STUDENT_HEADINGS)}, format="multipart"
        )

        self.assertEqual(403, response.status_code, response.data)

    def test_a_kind_that_does_not_exist_is_a_404(self):
        response = self.client.post(
            "/api/v1/imports/nonsense/preview",
            {"file": csv_file(self.student_row(), headings=STUDENT_HEADINGS)},
            format="multipart",
        )

        self.assertEqual(404, response.status_code)


class PreviewingAFileOfMarks(PreviewTestCase):
    def setUp(self):
        super().setUp()
        self.term = factories.AcademicTermFactory(
            academic_year=self.year,
            school=self.school,
            name="Term 1",
            sequence_number=1,
            start_date=dt.date(2026, 4, 1),
            end_date=dt.date(2026, 8, 31),
        )
        self.department = factories.DepartmentFactory(school=self.school, name="Mathematics")
        self.subject = factories.SubjectFactory(
            department=self.department, school=self.school, min_class_level=1, max_class_level=12
        )
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        factories.TimetableEntryFactory(
            school=self.school,
            class_section=self.section,
            subject=self.subject,
            teacher=self.teacher,
            period=factories.PeriodFactory(school=self.school),
        )
        self.students = [
            factories.StudentFactory(
                school=self.school, class_section=self.section, first_name=name, admission_number=f"ADM-{index}"
            )
            for index, name in enumerate(("Aarav", "Bina"), start=1)
        ]
        self.assessment = factories.AssessmentFactory(
            school=self.school,
            academic_year=self.year,
            academic_term=self.term,
            class_section=self.section,
            subject=self.subject,
            max_marks=20,
            created_by=self.teacher,
        )

    def url(self) -> str:
        return f"/api/v1/assessments/{self.assessment.id}/marks/preview"

    def marks_file(self, *rows: str, headings: str = "admission_number,student_name,marks,absent,remarks"):
        return csv_file(*rows, headings=headings, name="marks.csv")

    def test_the_marks_come_back_named_and_nothing_is_saved(self):
        response = self.as_user(self.teacher).post(
            self.url(),
            {"file": self.marks_file("ADM-1,Aarav,17.5,,", "ADM-2,Bina,,yes,")},
            format="multipart",
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(2, response.data["row_count"])
        self.assertEqual("ADM-1", response.data["rows"][0]["admission_number"])
        self.assertEqual("17.50", response.data["rows"][0]["marks_obtained"])
        self.assertIs(True, response.data["rows"][1]["is_absent"])
        self.assertEqual(0, AssessmentMark.objects.count(), "a preview saves nothing")

    def test_a_preview_refuses_a_mark_the_test_cannot_hold(self):
        response = self.as_user(self.teacher).post(
            self.url(), {"file": self.marks_file("ADM-1,Aarav,99,,")}, format="multipart"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("between 0 and 20.00", self.rows(response)[0]["messages"][0])

    def test_a_teacher_of_another_class_may_not_preview(self):
        stranger = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        response = stranger.post(self.url(), {"file": self.marks_file("ADM-1,Aarav,17,,")}, format="multipart")

        self.assertEqual(403, response.status_code, response.data)

    def test_another_school_may_not_either(self):
        outsider = self.as_user(
            factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        )

        response = outsider.post(self.url(), {"file": self.marks_file("ADM-1,Aarav,17,,")}, format="multipart")

        self.assertEqual(403, response.status_code, response.data)

    def test_a_super_admin_reads_the_test_and_previews_nothing(self):
        # The one role that can tell "may read" from "may mark" apart: a
        # preview is a step in marking, so it answers to the same rule.
        root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        self.assertEqual(200, root.get(f"/api/v1/assessments/{self.assessment.id}").status_code)
        self.assertEqual(
            403,
            root.post(self.url(), {"file": self.marks_file("ADM-1,Aarav,17,,")}, format="multipart").status_code,
        )


class PreviewingAFileOfTests(PreviewTestCase):
    def setUp(self):
        super().setUp()
        self.term = factories.AcademicTermFactory(
            academic_year=self.year,
            school=self.school,
            name="Term 1",
            sequence_number=1,
            start_date=dt.date(2026, 4, 1),
            end_date=dt.date(2026, 8, 31),
        )
        self.department = factories.DepartmentFactory(school=self.school, name="Mathematics")
        factories.SubjectFactory(
            department=self.department, school=self.school, name="Mathematics", min_class_level=1, max_class_level=12
        )

    def url(self) -> str:
        return "/api/v1/imports/assessments/preview"

    def row(self, title: str = "Fractions", date: str = "07/15/2026") -> str:
        return f"Grade 8 A,Mathematics,Term 1,class_test,{title},20,7,25,{date},,"

    def headings(self) -> str:
        return "class,subject,term,type,title,max_marks,pass_marks,weightage,date,grade_scale,topic"

    def test_a_file_of_tests_previews_without_creating_any(self):
        response = self.client.post(
            self.url(),
            {"file": csv_file(self.row(), self.row("Decimals", "07/22/2026"), headings=self.headings())},
            format="multipart",
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(2, response.data["row_count"])
        self.assertEqual("Class Tests", response.data["label"])
        self.assertEqual("Grade 8 A", response.data["rows"][0]["values"][0])
        self.assertEqual(0, Assessment.objects.count(), "a preview creates nothing")

    def test_the_preview_refuses_a_date_outside_the_term(self):
        response = self.client.post(
            self.url(), {"file": csv_file(self.row(date="09/30/2026"), headings=self.headings())}, format="multipart"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("must fall inside Term 1", self.rows(response)[0]["messages"][0])
        self.assertEqual(0, Assessment.objects.count())
