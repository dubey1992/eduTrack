"""A student's gender (docs/dashboard.md, D1): the form, the import, and the
dashboard's boys / girls / "other or not given" cards."""

from django.core.cache import cache
from django.test import TestCase

from school import factories
from school.enums import StudentGender, StudentStatus, UserRole
from school.models import Student

from .test_imports_api import HEADINGS, ImportTest
from .test_students_api import StudentApiTest


class TheForm(StudentApiTest):
    def test_a_new_student_keeps_their_gender(self):
        response = self.client.post("/api/v1/students", self.payload(gender="female"), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("female", response.data["gender"])
        self.assertEqual("female", Student.objects.get(pk=response.data["id"]).gender)

    def test_it_is_optional_and_blank_is_not_given(self):
        for body in (self.payload(admission_number="A-1"), self.payload(admission_number="A-2", gender="")):
            response = self.client.post("/api/v1/students", body, format="json")
            self.assertEqual(201, response.status_code, response.data)
            self.assertIsNone(response.data["gender"])

    def test_anything_else_is_refused(self):
        for value in ("boy", "MALE", "x"):
            response = self.client.post("/api/v1/students", self.payload(gender=value), format="json")
            self.assertEqual(422, response.status_code, value)
            self.assertIn("gender", response.data["details"]["errors"])

    def test_it_can_be_changed_and_cleared(self):
        student = self.a_student()

        changed = self.client.patch(f"/api/v1/students/{student.id}", {"gender": "other"}, format="json")
        self.assertEqual(("other", 200), (changed.data["gender"], changed.status_code))

        cleared = self.client.patch(f"/api/v1/students/{student.id}", {"gender": ""}, format="json")
        self.assertIsNone(cleared.data["gender"])

    def test_the_spreadsheet_spellings_are_understood(self):
        self.assertEqual(
            ["male", "male", "female", "female", "other", None, None],
            [StudentGender.from_text(text) for text in ("Male", " m ", "F", "girl", "Other", "", None)],
        )
        with self.assertRaises(ValueError):
            StudentGender.from_text("unknown")


class TheImport(ImportTest):
    WITH_GENDER = HEADINGS + ",gender"

    def test_the_template_has_the_column(self):
        body = self.client.get("/api/v1/imports/students/template").content.decode("utf-8-sig")

        self.assertTrue(body.startswith(self.WITH_GENDER))

    def test_a_file_with_gender_stores_it(self):
        response = self.upload(
            "ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,,M",
            "ADM-2,Zara,Khan,Grade 5,A,,Ali Khan,,,Female",
            "ADM-3,Sam,Lee,Grade 5,A,,Kim Lee,,,",
            headings=self.WITH_GENDER,
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(
            {"ADM-1": "male", "ADM-2": "female", "ADM-3": None},
            dict(Student.objects.filter(school=self.school).values_list("admission_number", "gender")),
        )

    def test_an_old_file_without_the_column_still_imports(self):
        response = self.upload("ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,")

        self.assertEqual(201, response.status_code, response.data)
        self.assertIsNone(Student.objects.get(school=self.school).gender)

    def test_a_gender_it_cannot_read_stops_the_file(self):
        response = self.upload("ADM-1,Aarav,Sharma,Grade 5,A,,Meera Sharma,,,maybe", headings=self.WITH_GENDER)

        self.assertEqual(422, response.status_code)
        self.assertIn("gender", str(response.data))
        self.assertEqual(0, Student.objects.filter(school=self.school).count())


class TheDashboard(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

    def students(self, gender, count, school=None, status=StudentStatus.ACTIVE):
        for _ in range(count):
            factories.StudentFactory(school=school or self.school, gender=gender, status=status)

    def cards(self, user=None) -> dict:
        from .test_students_api import StudentApiTest

        response = StudentApiTest.as_user(None, user or self.admin).get("/api/v1/dashboard")
        self.assertEqual(200, response.status_code, response.data)

        return {card["key"]: card for card in response.data["cards"]}

    def test_boys_girls_and_the_rest_add_up_to_the_roll(self):
        self.students("male", 3)
        self.students("female", 4)
        self.students("other", 1)
        self.students(None, 2)

        cards = self.cards()

        self.assertEqual(
            [("students", "10"), ("boys", "3"), ("girls", "4"), ("gender_other", "3")],
            [(key, cards[key]["value"]) for key in ("students", "boys", "girls", "gender_other")],
        )
        self.assertEqual("30% of the roll", cards["boys"]["hint"])
        # The ones nobody has filled in are named, so somebody can.
        self.assertEqual(("2 not given yet", "caution"), (cards["gender_other"]["hint"], cards["gender_other"]["tone"]))

    def test_no_third_card_once_everybody_is_recorded(self):
        self.students("male", 2)
        self.students("female", 2)

        cards = self.cards()

        self.assertNotIn("gender_other", cards)
        self.assertEqual("50% of the roll", cards["girls"]["hint"])

    def test_only_the_active_roll_counts(self):
        self.students("male", 2)
        self.students("male", 5, status=StudentStatus.INACTIVE)

        self.assertEqual("2", self.cards()["boys"]["value"])

    def test_an_empty_school_reads_zero_not_a_percentage_of_nothing(self):
        cards = self.cards()

        self.assertEqual(("0", "on the roll"), (cards["boys"]["value"], cards["boys"]["hint"]))
        self.assertNotIn("gender_other", cards)

    def test_another_schools_students_are_never_counted(self):
        other = factories.SchoolFactory()
        self.students("female", 6, school=other)
        self.students("female", 1)

        self.assertEqual("1", self.cards()["girls"]["value"])

    def test_a_teacher_gets_no_roll_figures(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertFalse({"boys", "girls", "gender_other"} & set(self.cards(teacher)))
