"""Bulk upload for class tests and for marks (docs/assessments.md).

Two uploads with deliberately different homes, and the reason is the whole
design:

- **Tests** go through the shared bulk importer, which is an administrator's
  tool. A file that crosses classes cannot be asked "is this your class" per
  row, so bulk creation belongs to the people for whom the answer is always
  yes within their school.
- **Marks** hang off one test, where the timetable already answers that
  question exactly. So a teacher uploads marks for their own class, with the
  same permission they have for marking by hand.

Both keep the rule the other uploads keep: nothing is written unless every
row passes.
"""

import datetime as dt
from decimal import Decimal
from io import BytesIO

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import Assessment, AssessmentMark

TESTS_IMPORT = "/api/v1/imports/assessments"
TESTS_TEMPLATE = "/api/v1/imports/assessments/template"

HEADINGS = "class,subject,term,type,title,max_marks,pass_marks,weightage,date,grade_scale,topic"


def csv_file(*rows: str, name: str = "tests.csv", headings: str = HEADINGS) -> SimpleUploadedFile:
    body = "\n".join([headings, *rows]) + "\n"

    return SimpleUploadedFile(name, body.encode("utf-8"), content_type="text/csv")


class ImportTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.year = factories.AcademicYearFactory(
            school=self.school, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        self.term = factories.AcademicTermFactory(
            academic_year=self.year,
            school=self.school,
            name="Term 1",
            sequence_number=1,
            start_date=dt.date(2026, 4, 1),
            end_date=dt.date(2026, 8, 31),
        )
        self.school_class = factories.SchoolClassFactory(
            academic_year=self.year, school=self.school, name="Grade 8", level=8
        )
        self.section = factories.ClassSectionFactory(school_class=self.school_class, name="A")
        self.department = factories.DepartmentFactory(school=self.school, name="Mathematics")
        self.subject = factories.SubjectFactory(
            department=self.department, school=self.school, name="Mathematics", min_class_level=1, max_class_level=12
        )
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        factories.TimetableEntryFactory(
            school=self.school,
            class_section=self.section,
            subject=self.subject,
            teacher=self.teacher,
            period=factories.PeriodFactory(school=self.school),
        )
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def rows(self, response) -> list[dict]:
        return response.data["details"]["rows"]

    def good_row(self, **overrides) -> str:
        values = {
            "class": "Grade 8 A",
            "subject": "Mathematics",
            "term": "Term 1",
            "type": "class_test",
            "title": "Fractions - unit test",
            "max_marks": "20",
            "pass_marks": "7",
            "weightage": "25",
            "date": "07/15/2026",
            "grade_scale": "",
            "topic": "",
        }
        values.update(overrides)

        return ",".join(values[key] for key in HEADINGS.split(","))


class UploadingTests(ImportTestCase):
    def test_the_template_names_the_columns_and_shows_one_row(self):
        response = self.client.get(TESTS_TEMPLATE)

        self.assertEqual(200, response.status_code)
        text = response.content.decode("utf-8-sig")
        self.assertIn("class,subject,term,type,title", text)
        self.assertIn("Grade 8 A", text)

    def test_a_file_of_tests_is_imported(self):
        response = self.client.post(
            TESTS_IMPORT,
            {"file": csv_file(self.good_row(), self.good_row(title="Decimals", date="07/22/2026", weightage="20"))},
            format="multipart",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(2, response.data["imported"])
        self.assertEqual(2, Assessment.objects.filter(school=self.school).count())

        created = Assessment.objects.order_by("id").first()
        self.assertEqual("draft", created.status, "an imported test is a draft, like any other")
        self.assertEqual(Decimal("20.00"), created.max_marks)
        self.assertEqual(self.section.id, created.class_section_id)
        self.assertEqual(self.admin.id, created.created_by_id)

    def test_the_optional_columns_may_be_left_empty(self):
        response = self.client.post(
            TESTS_IMPORT,
            {"file": csv_file(self.good_row(pass_marks="", weightage=""))},
            format="multipart",
        )

        self.assertEqual(201, response.status_code, response.data)
        created = Assessment.objects.get(school=self.school)
        self.assertIsNone(created.pass_marks)
        self.assertIsNone(created.weightage)

    def test_a_grade_scale_and_a_topic_can_be_named(self):
        factories.GradeScaleFactory(school=self.school, name="Secondary")
        factories.SyllabusTopicFactory(school=self.school, subject=self.subject, title="Fractions")

        response = self.client.post(
            TESTS_IMPORT,
            {"file": csv_file(self.good_row(grade_scale="secondary", topic="fractions"))},
            format="multipart",
        )

        self.assertEqual(201, response.status_code, response.data)
        created = Assessment.objects.get(school=self.school)
        self.assertIsNotNone(created.grade_scale_id)
        self.assertIsNotNone(created.syllabus_topic_id)

    def test_a_class_that_does_not_exist_is_named_by_row(self):
        response = self.client.post(
            TESTS_IMPORT, {"file": csv_file(self.good_row(**{"class": "Grade 9 Z"}))}, format="multipart"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(2, self.rows(response)[0]["row"], "the heading is row 1")
        self.assertIn('There is no class "Grade 9 Z"', self.rows(response)[0]["messages"][0])

    def test_the_pieces_must_belong_together(self):
        infants = factories.SubjectFactory(
            department=self.department, school=self.school, name="Phonics", min_class_level=1, max_class_level=4
        )
        del infants

        cases = {
            "Phonics is not taught": self.good_row(subject="Phonics"),
            "must fall inside Term 1": self.good_row(date="09/30/2026"),
            'There is no term "Term 9"': self.good_row(term="Term 9"),
        }

        for expected, row in cases.items():
            with self.subTest(expected=expected):
                response = self.client.post(TESTS_IMPORT, {"file": csv_file(row)}, format="multipart")

                self.assertEqual(422, response.status_code, response.data)
                self.assertTrue(
                    any(expected in message for message in self.rows(response)[0]["messages"]),
                    self.rows(response),
                )

    def test_the_marks_columns_are_checked(self):
        cases = {
            "greater than 0": self.good_row(max_marks="0"),
            "not a number": self.good_row(max_marks="twenty"),
            "greater than max_marks": self.good_row(max_marks="20", pass_marks="30"),
            "between 0 and 100": self.good_row(weightage="150"),
        }

        for expected, row in cases.items():
            with self.subTest(expected=expected):
                response = self.client.post(TESTS_IMPORT, {"file": csv_file(row)}, format="multipart")

                self.assertEqual(422, response.status_code, response.data)
                self.assertTrue(
                    any(expected in message for message in self.rows(response)[0]["messages"]),
                    self.rows(response),
                )

    def test_a_type_outside_the_list_is_refused(self):
        response = self.client.post(TESTS_IMPORT, {"file": csv_file(self.good_row(type="viva"))}, format="multipart")

        self.assertEqual(422, response.status_code, response.data)

    def test_one_bad_row_stops_the_whole_file(self):
        response = self.client.post(
            TESTS_IMPORT,
            {"file": csv_file(self.good_row(), self.good_row(title="Broken", max_marks="0"))},
            format="multipart",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(0, Assessment.objects.count(), "nothing is written until every row passes")

    def test_a_file_with_the_wrong_headings_is_refused(self):
        response = self.client.post(
            TESTS_IMPORT, {"file": csv_file("x", headings="wrong,headings")}, format="multipart"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("column headings do not match", self.rows(response)[0]["messages"][0])

    def test_a_teacher_may_not_upload_a_file_of_tests(self):
        response = self.as_user(self.teacher).post(
            TESTS_IMPORT, {"file": csv_file(self.good_row())}, format="multipart"
        )

        self.assertEqual(403, response.status_code, response.data)
        self.assertEqual(403, self.as_user(self.teacher).get(TESTS_TEMPLATE).status_code)

    def test_a_super_admin_may_not_either(self):
        root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        self.assertEqual(403, root.get(TESTS_TEMPLATE).status_code)

    def test_another_schools_class_cannot_be_named(self):
        elsewhere = factories.SchoolFactory()
        their_year = factories.AcademicYearFactory(school=elsewhere, is_current=True)
        their_class = factories.SchoolClassFactory(
            academic_year=their_year, school=elsewhere, name="Grade 8", level=8
        )
        factories.ClassSectionFactory(school_class=their_class, name="Z")

        response = self.client.post(
            TESTS_IMPORT, {"file": csv_file(self.good_row(**{"class": "Grade 8 Z"}))}, format="multipart"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn('There is no class "Grade 8 Z"', self.rows(response)[0]["messages"][0])
        self.assertEqual(0, Assessment.objects.count())


class UploadingMarks(ImportTestCase):
    def setUp(self):
        super().setUp()
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

    def template_url(self) -> str:
        return f"/api/v1/assessments/{self.assessment.id}/marks/template"

    def upload_url(self) -> str:
        return f"/api/v1/assessments/{self.assessment.id}/marks/import"

    def marks_file(self, *rows: str, headings: str = "admission_number,student_name,marks,absent,remarks"):
        body = "\n".join([headings, *rows]) + "\n"

        return SimpleUploadedFile("marks.csv", body.encode("utf-8"), content_type="text/csv")

    def stored(self, student):
        return AssessmentMark.objects.filter(assessment_id=self.assessment.id, student_id=student.id).first()

    def test_the_template_comes_with_the_class_already_on_it(self):
        response = self.as_user(self.teacher).get(self.template_url())

        self.assertEqual(200, response.status_code)
        text = response.content.decode("utf-8-sig")
        self.assertIn("admission_number,student_name,marks,absent,remarks", text)
        self.assertIn("ADM-1", text)
        self.assertIn("ADM-2", text)

    def test_the_template_carries_the_marks_already_entered(self):
        factories.AssessmentMarkFactory(
            assessment=self.assessment, school=self.school, student=self.students[0], marks_obtained=Decimal("17.50")
        )

        text = self.as_user(self.teacher).get(self.template_url()).content.decode("utf-8-sig")

        self.assertIn("17.50", text)

    def test_a_filled_in_file_is_saved(self):
        response = self.as_user(self.teacher).post(
            self.upload_url(),
            {"file": self.marks_file("ADM-1,Aarav,17.5,,Careless slips", "ADM-2,Bina,,yes,")},
            format="multipart",
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(Decimal("17.50"), self.stored(self.students[0]).marks_obtained)
        self.assertEqual("Careless slips", self.stored(self.students[0]).remarks)
        self.assertIs(True, self.stored(self.students[1]).is_absent)
        self.assertIsNone(self.stored(self.students[1]).marks_obtained)

    def test_the_answer_is_the_sheet_as_it_now_stands(self):
        response = self.as_user(self.teacher).post(
            self.upload_url(), {"file": self.marks_file("ADM-1,Aarav,17.5,,")}, format="multipart"
        )

        self.assertEqual(2, len(response.data["entries"]))
        self.assertEqual("17.50", response.data["entries"][0]["marks_obtained"])

    def test_a_mark_the_test_cannot_hold_is_refused_by_row(self):
        response = self.as_user(self.teacher).post(
            self.upload_url(), {"file": self.marks_file("ADM-1,Aarav,99,,")}, format="multipart"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("between 0 and 20.00", self.rows(response)[0]["messages"][0])
        self.assertIsNone(self.stored(self.students[0]))

    def test_absent_with_a_mark_is_refused(self):
        response = self.as_user(self.teacher).post(
            self.upload_url(), {"file": self.marks_file("ADM-1,Aarav,10,yes,")}, format="multipart"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("absent student has no marks", self.rows(response)[0]["messages"][0])

    def test_a_student_who_is_not_in_this_class_is_refused(self):
        response = self.as_user(self.teacher).post(
            self.upload_url(), {"file": self.marks_file("ADM-999,Somebody,10,,")}, format="multipart"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("is in this class", self.rows(response)[0]["messages"][0])

    def test_the_same_student_twice_is_refused(self):
        response = self.as_user(self.teacher).post(
            self.upload_url(),
            {"file": self.marks_file("ADM-1,Aarav,10,,", "ADM-1,Aarav,12,,")},
            format="multipart",
        )

        self.assertEqual(422, response.status_code, response.data)
        # The first sighting is fine; it is the repeat that is reported, and
        # it points back at the line the student was already on.
        self.assertEqual(3, self.rows(response)[0]["row"])
        self.assertIn("also on row 2", self.rows(response)[0]["messages"][0])

    def test_a_nonsense_absent_column_is_refused(self):
        response = self.as_user(self.teacher).post(
            self.upload_url(), {"file": self.marks_file("ADM-1,Aarav,,maybe,")}, format="multipart"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn('takes "yes" or "no"', self.rows(response)[0]["messages"][0])

    def test_one_bad_row_writes_nothing_at_all(self):
        response = self.as_user(self.teacher).post(
            self.upload_url(),
            {"file": self.marks_file("ADM-1,Aarav,17,,", "ADM-2,Bina,99,,")},
            format="multipart",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(0, AssessmentMark.objects.count())

    def test_the_wrong_headings_are_refused(self):
        response = self.as_user(self.teacher).post(
            self.upload_url(), {"file": self.marks_file("x", headings="wrong,headings")}, format="multipart"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("column headings do not match", self.rows(response)[0]["messages"][0])

    def test_an_empty_file_is_refused(self):
        response = self.as_user(self.teacher).post(
            self.upload_url(), {"file": self.marks_file()}, format="multipart"
        )

        self.assertEqual(422, response.status_code, response.data)

    def test_a_missing_file_is_named(self):
        response = self.as_user(self.teacher).post(self.upload_url(), {}, format="multipart")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("file", response.data["details"]["errors"])

    def test_something_that_is_not_a_csv_is_refused(self):
        upload = SimpleUploadedFile("marks.xlsx", BytesIO(b"not a csv").read(), content_type="application/vnd.ms-excel")

        response = self.as_user(self.teacher).post(self.upload_url(), {"file": upload}, format="multipart")

        self.assertEqual(422, response.status_code, response.data)

    def test_a_published_test_takes_no_upload(self):
        self.assessment.status = "published"
        self.assessment.save(update_fields=["status"])

        response = self.as_user(self.teacher).post(
            self.upload_url(), {"file": self.marks_file("ADM-1,Aarav,17,,")}, format="multipart"
        )

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("ASSESSMENT_PUBLISHED", response.data["code"])

    def test_a_teacher_of_another_class_may_neither_download_nor_upload(self):
        stranger = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        self.assertEqual(403, stranger.get(self.template_url()).status_code)
        self.assertEqual(
            403,
            stranger.post(self.upload_url(), {"file": self.marks_file("ADM-1,Aarav,17,,")}, format="multipart").status_code,
        )

    def test_another_school_reaches_neither(self):
        outsider = self.as_user(
            factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        )

        self.assertEqual(403, outsider.get(self.template_url()).status_code)
        self.assertEqual(
            403,
            outsider.post(self.upload_url(), {"file": self.marks_file("ADM-1,Aarav,17,,")}, format="multipart").status_code,
        )

    def test_a_super_admin_reads_the_sheet_and_uploads_nothing(self):
        root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        # They may read the test itself - and neither download the roster nor
        # send marks back. The only role that can tell those two apart.
        self.assertEqual(200, root.get(f"/api/v1/assessments/{self.assessment.id}").status_code)
        self.assertEqual(403, root.get(self.template_url()).status_code)
        self.assertEqual(
            403,
            root.post(self.upload_url(), {"file": self.marks_file("ADM-1,Aarav,17,,")}, format="multipart").status_code,
        )
        self.assertEqual(0, AssessmentMark.objects.count())
