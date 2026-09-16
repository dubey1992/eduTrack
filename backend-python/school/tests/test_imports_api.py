"""Bulk upload, over HTTP.

The rule most of these are about: **nothing is written until every row has
passed.** A half-finished import is worse than a refused one, because the
school then has to work out which rows landed before it can upload the
corrected file.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import Student

from .test_scope import section_in

HEADINGS = (
    "admission_number,first_name,last_name,class,section,"
    "roll_number,guardian_name,guardian_mobile,address"
)


def csv_file(*rows: str, name: str = "students.csv", headings: str = HEADINGS):
    from django.core.files.uploadedfile import SimpleUploadedFile

    body = "\r\n".join([headings, *rows]) + "\r\n"

    return SimpleUploadedFile(name, body.encode("utf-8"), content_type="text/csv")


class ImportTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.year = factories.AcademicYearFactory(school=self.school, is_current=True)
        self.school_class = factories.SchoolClassFactory(
            academic_year=self.year, school=self.school, name="Grade 5"
        )
        self.section = factories.ClassSectionFactory(school_class=self.school_class, name="A")

        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def upload(self, *rows, **kwargs):
        return self.client.post(
            "/api/v1/imports/students",
            {"file": csv_file(*rows, **kwargs)},
            format="multipart",
        )


class TheTemplate(ImportTest):
    def test_it_downloads_as_a_csv_with_an_example_row(self):
        response = self.client.get("/api/v1/imports/students/template")

        self.assertEqual(200, response.status_code)
        self.assertIn("text/csv", response["Content-Type"])
        self.assertIn('filename="students-template.csv"', response["Content-Disposition"])

        body = response.content.decode("utf-8-sig")
        self.assertTrue(body.startswith(HEADINGS))
        self.assertIn("ADM-2026-001", body)

    def test_it_opens_correctly_in_a_spreadsheet(self):
        # Excel reads a CSV as the system codepage unless the file opens with
        # a byte order mark, which mangles any non-ASCII name.
        response = self.client.get("/api/v1/imports/students/template")

        self.assertTrue(response.content.startswith(b"\xef\xbb\xbf"))

    def test_a_kind_nobody_can_import_is_404(self):
        self.assertEqual(404, self.client.get("/api/v1/imports/unicorns/template").status_code)

    def test_a_teacher_cannot_download_it(self):
        # The same permission as adding one by hand, which a teacher does not
        # have.
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        self.assertEqual(403, teacher.get("/api/v1/imports/students/template").status_code)


class AGoodFile(ImportTest):
    def test_every_row_becomes_a_student(self):
        response = self.upload(
            "ADM-1,Aarav,Sharma,Grade 5,A,12,Meera Sharma,+91 98765 43210,14 Rose Lane",
            "ADM-2,Zainab,Okafor,Grade 5,A,13,Nneka Okafor,,",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(2, response.data["imported"])
        self.assertEqual("Students", response.data["label"])
        self.assertEqual(2, Student.objects.filter(school=self.school).count())

    def test_the_students_land_in_the_named_section(self):
        self.upload("ADM-1,Aarav,Sharma,Grade 5,A,12,Meera Sharma,,")

        student = Student.objects.get(admission_number="ADM-1")

        self.assertEqual(self.section.id, student.class_section_id)
        self.assertEqual(self.school.id, student.school_id)
        self.assertEqual("active", student.status)

    def test_the_class_and_section_are_matched_regardless_of_case_or_spacing(self):
        response = self.upload("ADM-1,Aarav,Sharma,  grade 5  ,  a  ,,Meera Sharma,,")

        self.assertEqual(201, response.status_code, response.data)

    def test_a_blank_cell_is_stored_as_nothing(self):
        self.upload("ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,")

        student = Student.objects.get(admission_number="ADM-1")

        self.assertIsNone(student.roll_number)
        self.assertIsNone(student.guardian_mobile)

    def test_a_trailing_blank_line_is_not_a_row(self):
        # What every spreadsheet leaves behind.
        response = self.upload("ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,", ",,,,,,,,")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(1, response.data["imported"])

    def test_a_file_with_a_byte_order_mark_still_matches_its_headings(self):
        from django.core.files.uploadedfile import SimpleUploadedFile

        body = (HEADINGS + "\r\nADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,\r\n").encode("utf-8-sig")

        response = self.client.post(
            "/api/v1/imports/students",
            {"file": SimpleUploadedFile("students.csv", body, content_type="text/csv")},
            format="multipart",
        )

        self.assertEqual(201, response.status_code, response.data)


class ABadFile(ImportTest):
    def assertRefused(self, response):
        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("BULK_IMPORT_FAILED", response.data["code"])

        return response.data["details"]["rows"]

    def test_nothing_is_written_when_one_row_is_wrong(self):
        # The whole point. Nineteen good rows and one bad one import nothing.
        response = self.upload(
            "ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,",
            "ADM-2,Zainab,Okafor,Grade 9,Z,,Nneka Okafor,,",
        )

        self.assertRefused(response)
        self.assertEqual(0, Student.objects.count())

    def test_the_error_points_at_the_line_in_the_spreadsheet(self):
        rows = self.assertRefused(
            self.upload(
                "ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,",
                "ADM-2,Zainab,Okafor,Grade 9,Z,,Nneka Okafor,,",
            )
        )

        # Line 3, not index 1: the headings are line 1, so this is the line
        # number the person sees in their spreadsheet.
        self.assertEqual(3, rows[0]["row"])
        self.assertIn('There is no section "Z" in class "Grade 9".', rows[0]["messages"])

    def test_every_problem_is_reported_not_just_the_first(self):
        # One upload should tell the school everything it needs to fix, not
        # ten uploads finding one mistake each.
        rows = self.assertRefused(
            self.upload(
                ",Aarav,Sharma,Grade 5,A,,Meera Sharma,,",
                "ADM-2,Zainab,,Grade 5,A,,Nneka Okafor,,",
                "ADM-3,Rahul,Verma,Grade 9,Z,,A Guardian,,",
            )
        )

        self.assertEqual([2, 3, 4], [row["row"] for row in rows])

    def test_a_duplicate_inside_the_file_is_caught(self):
        # The database catches a clash with an existing record; nothing else
        # catches the same admission number typed twice in one spreadsheet.
        rows = self.assertRefused(
            self.upload(
                "ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,",
                "ADM-1,Zainab,Okafor,Grade 5,A,,Nneka Okafor,,",
            )
        )

        self.assertIn('The admission_number "ADM-1" is also on row 2.', rows[0]["messages"])

    def test_a_clash_with_an_existing_student_is_caught(self):
        factories.StudentFactory(
            school=self.school, class_section=self.section, admission_number="ADM-1"
        )

        rows = self.assertRefused(self.upload("ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,"))

        self.assertIn("The admission number has already been taken.", rows[0]["messages"])

    def test_a_malformed_phone_number_is_caught(self):
        rows = self.assertRefused(self.upload("ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,nope,"))

        self.assertIn("The guardian mobile field format is invalid.", rows[0]["messages"])

    def test_the_wrong_headings_are_refused_before_any_row_is_read(self):
        rows = self.assertRefused(
            self.upload("whatever", headings="name,class,phone")
        )

        self.assertIn("do not match the template", rows[0]["messages"][0])

    def test_a_file_with_no_rows_is_refused(self):
        rows = self.assertRefused(self.upload())

        self.assertIn("The file has headings but no rows.", rows[0]["messages"])

    def test_a_missing_file_is_422_naming_the_field(self):
        response = self.client.post("/api/v1/imports/students", {}, format="multipart")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("file", response.data["details"]["errors"])

    def test_something_that_is_not_a_csv_is_refused(self):
        response = self.client.post(
            "/api/v1/imports/students",
            {"file": csv_file("ADM-1,a,b,Grade 5,A,,g,,", name="roll.xlsx")},
            format="multipart",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn(
            "Upload a CSV file. In Excel, choose File - Save As - CSV.",
            response.data["details"]["errors"]["file"],
        )


class WhenTheSchoolIsNotReady(ImportTest):
    def test_a_school_with_no_current_year_is_told_so(self):
        self.year.is_current = False
        self.year.save()

        response = self.upload("ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn(
            "This school has no classes in its current academic year yet. "
            "Set one up before importing students.",
            response.data["details"]["rows"][0]["messages"],
        )


class ImportIsolation(ImportTest):
    def test_the_file_lands_in_the_actors_school_whatever_it_says(self):
        outsider = factories.SchoolFactory()

        response = self.client.post(
            "/api/v1/imports/students",
            {
                "file": csv_file("ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,"),
                "school_id": outsider.id,
            },
            format="multipart",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, Student.objects.get(admission_number="ADM-1").school_id)
        self.assertEqual(0, Student.objects.filter(school=outsider).count())

    def test_an_admin_in_a_group_must_name_the_branch(self):
        # A spreadsheet is filed into a branch, never into a group.
        group = factories.SchoolFactory()
        north = factories.SchoolFactory(parent_school=group)
        admin = self.as_user(factories.UserFactory(school=north, role=UserRole.SCHOOL_ADMIN))

        response = admin.post(
            "/api/v1/imports/students",
            {"file": csv_file("ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,")},
            format="multipart",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("school_id", response.data["details"]["errors"])

    def test_an_admin_in_a_group_cannot_file_into_a_school_outside_it(self):
        group = factories.SchoolFactory()
        north = factories.SchoolFactory(parent_school=group)
        admin = self.as_user(factories.UserFactory(school=north, role=UserRole.SCHOOL_ADMIN))

        response = admin.post(
            "/api/v1/imports/students",
            {
                "file": csv_file("ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,"),
                "school_id": self.school.id,
            },
            format="multipart",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("school_id", response.data["details"]["errors"])
        self.assertEqual(0, Student.objects.count())

    def test_a_teacher_cannot_import_anybody(self):
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        response = teacher.post(
            "/api/v1/imports/students",
            {"file": csv_file("ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,")},
            format="multipart",
        )

        self.assertEqual(403, response.status_code, response.data)
        self.assertEqual(0, Student.objects.count())
