"""Students by class, by roll number (docs/onboarding.md, slice O2).

A teacher reads a section by roll number, so: a section's list is in roll
order (9 before 10), a student left without a number gets the next free one,
two active students in a section never share one, and a section can be
renumbered 1, 2, 3 ... in name order when a school asks.
"""

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase, TestCase
from rest_framework.test import APIClient

from school import factories, roll_numbers, tokens
from school.enums import StudentStatus, UserRole
from school.models import AuditLog, Student

HEADINGS = "admission_number,first_name,last_name,class,section,roll_number,guardian_name,guardian_mobile,address"


class Normalising(SimpleTestCase):
    def test_leading_zeros_and_spaces_do_not_make_a_new_number(self):
        self.assertEqual("7", roll_numbers.normalise(" 07 "))
        self.assertEqual("12A", roll_numbers.normalise("12A"))
        self.assertIsNone(roll_numbers.normalise("  "))
        self.assertIsNone(roll_numbers.normalise(None))


class RollTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.year = factories.AcademicYearFactory(school=self.school, is_current=True)
        self.school_class = factories.SchoolClassFactory(
            school=self.school, academic_year=self.year, name="Class 5", level=5
        )
        self.section = factories.ClassSectionFactory(school_class=self.school_class, name="A")
        self.other_section = factories.ClassSectionFactory(school_class=self.school_class, name="B")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def student(self, roll_number=None, section=None, **fields):
        return factories.StudentFactory(
            school=self.school, class_section=section or self.section, roll_number=roll_number, **fields
        )

    def admit(self, **overrides):
        body = {
            "class_section_id": self.section.id,
            "admission_number": f"ADM-{Student.objects.count() + 1:03d}",
            "first_name": "Isha",
            "last_name": "Rao",
            "guardian_name": "Kavya Rao",
        }
        body.update(overrides)

        return self.client.post("/api/v1/students", body, format="json")


class NextFreeNumber(RollTest):
    def test_the_first_student_in_a_section_is_number_one(self):
        response = self.admit()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("1", response.data["roll_number"])

    def test_a_blank_number_is_one_past_the_highest(self):
        self.student("3")
        self.student("12")
        self.student("12B")  # not a plain number: does not count

        self.assertEqual("13", self.admit(roll_number="").data["roll_number"])

    def test_a_gap_is_not_filled(self):
        # A gap in the middle would reorder a register already written down.
        self.student("1")
        self.student("4")

        self.assertEqual("5", self.admit().data["roll_number"])

    def test_numbers_are_counted_per_section(self):
        self.student("9", section=self.other_section)

        self.assertEqual("1", self.admit().data["roll_number"])

    def test_a_student_who_left_frees_their_number(self):
        self.student("8", status=StudentStatus.INACTIVE)
        self.student("2")

        self.assertEqual("3", self.admit().data["roll_number"])
        self.assertEqual(201, self.admit(roll_number="8").status_code)

    def test_a_typed_number_is_kept(self):
        self.assertEqual("42", self.admit(roll_number="42").data["roll_number"])


class Duplicates(RollTest):
    def test_a_number_already_held_in_the_section_is_refused_naming_the_holder(self):
        self.student("5", first_name="Asha", last_name="Verma")

        response = self.admit(roll_number="05")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("already Asha Verma's", response.data["details"]["errors"]["roll_number"][0])

    def test_the_same_number_in_another_section_is_fine(self):
        self.student("5", section=self.other_section)

        self.assertEqual(201, self.admit(roll_number="5").status_code)

    def test_editing_a_student_does_not_clash_with_themselves(self):
        me = self.student("5")

        response = self.client.patch(f"/api/v1/students/{me.id}", {"roll_number": "5"}, format="json")

        self.assertEqual(200, response.status_code, response.data)

    def test_editing_to_a_taken_number_is_refused(self):
        self.student("5", first_name="Asha", last_name="Verma")
        me = self.student("6")

        response = self.client.patch(f"/api/v1/students/{me.id}", {"roll_number": "5"}, format="json")

        self.assertEqual(422, response.status_code, response.data)

    def test_moving_into_a_section_checks_the_number_there(self):
        self.student("5", section=self.other_section)
        me = self.student("5")

        response = self.client.patch(
            f"/api/v1/students/{me.id}",
            {"class_section_id": self.other_section.id, "roll_number": "5"},
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)

    def test_moving_without_a_number_takes_the_next_free_one_there(self):
        self.student("7", section=self.other_section)
        me = self.student("5")

        response = self.client.patch(
            f"/api/v1/students/{me.id}", {"class_section_id": self.other_section.id}, format="json"
        )

        self.assertEqual("8", response.data["roll_number"])

    def test_clearing_a_number_takes_the_next_free_one(self):
        self.student("3")
        me = self.student("1")

        response = self.client.patch(f"/api/v1/students/{me.id}", {"roll_number": ""}, format="json")

        self.assertEqual("4", response.data["roll_number"])


class RollOrder(RollTest):
    def test_a_section_lists_by_roll_number_nine_before_ten_blanks_last(self):
        for roll, name in (("10", "Zara"), ("2", "Yash"), (None, "Aarav"), ("9", "Bela"), ("1", "Kiran")):
            self.student(roll, first_name=name)

        response = self.client.get(f"/api/v1/students?class_section_id={self.section.id}")

        self.assertEqual(
            ["Kiran", "Yash", "Bela", "Zara", "Aarav"], [row["first_name"] for row in response.data["data"]]
        )

    def test_the_whole_school_list_stays_in_name_order(self):
        self.student("1", first_name="Zara")
        self.student("2", first_name="Aarav")

        response = self.client.get("/api/v1/students")

        self.assertEqual(["Aarav", "Zara"], [row["first_name"] for row in response.data["data"]])


class ClassList(RollTest):
    url = "/api/v1/students/classes"

    def test_classes_come_in_class_order_with_section_counts(self):
        nursery = factories.SchoolClassFactory(school=self.school, academic_year=self.year, name="Nursery", level=-2)
        nursery_a = factories.ClassSectionFactory(school_class=nursery, name="A")
        self.student(section=nursery_a)
        self.student()
        self.student()
        self.student(status=StudentStatus.INACTIVE)

        response = self.client.get(self.url)

        self.assertEqual(200, response.status_code, response.data)
        rows = response.data["data"]
        self.assertEqual(["Nursery", "Class 5"], [row["name"] for row in rows])
        self.assertEqual([{"id": self.section.id, "name": "A", "students": 2},
                          {"id": self.other_section.id, "name": "B", "students": 0}], rows[1]["sections"])

    def test_only_the_current_year(self):
        old_year = factories.AcademicYearFactory(school=self.school, name="Last year", is_current=False)
        old = factories.SchoolClassFactory(school=self.school, academic_year=old_year, name="Class 4", level=4)
        factories.ClassSectionFactory(school_class=old)

        names = [row["name"] for row in self.client.get(self.url).data["data"]]

        self.assertEqual(["Class 5"], names)

    def test_another_schools_classes_never_appear(self):
        other = factories.SchoolFactory()
        other_year = factories.AcademicYearFactory(school=other, is_current=True)
        other_class = factories.SchoolClassFactory(school=other, academic_year=other_year, name="Class 1", level=1)
        factories.ClassSectionFactory(school_class=other_class)

        names = [row["name"] for row in self.client.get(f"{self.url}?school_id={other.id}").data["data"]]

        self.assertNotIn("Class 1", names)

    def test_a_teacher_sees_only_their_own_sections(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.other_section.class_teacher = teacher
        self.other_section.save()

        rows = self.as_user(teacher).get(self.url).data["data"]

        self.assertEqual([["B"]], [[s["name"] for s in row["sections"]] for row in rows])

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get(self.url).status_code)


class Renumber(RollTest):
    def url(self, section=None):
        return f"/api/v1/sections/{(section or self.section).id}/renumber"

    def test_active_students_are_numbered_in_name_order(self):
        zara = self.student("1", first_name="Zara")
        aarav = self.student("7", first_name="Aarav")
        bela = self.student(None, first_name="Bela")
        left = self.student("2", first_name="Abel", status=StudentStatus.INACTIVE)

        response = self.client.post(self.url())

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(3, response.data["numbered"])
        for student, number in ((aarav, "1"), (bela, "2"), (zara, "3"), (left, "2")):
            student.refresh_from_db()
            self.assertEqual(number, student.roll_number, student.first_name)

    def test_each_changed_number_is_audited(self):
        self.student("1", first_name="Aarav")
        self.student("5", first_name="Bela")
        before = AuditLog.objects.count()

        self.client.post(self.url())

        self.assertEqual(before + 1, AuditLog.objects.count())

    def test_a_teacher_may_renumber_their_own_section_only(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.section.class_teacher = teacher
        self.section.save()
        client = self.as_user(teacher)

        self.assertEqual(403, client.post(self.url(self.other_section)).status_code)
        # Whether a teacher may write students at all is the school's
        # permissions matrix; either answer is a decision, never a 500.
        self.assertIn(client.post(self.url()).status_code, (200, 403))

    def test_another_schools_section_is_forbidden(self):
        other = factories.ClassSectionFactory()
        student = factories.StudentFactory(class_section=other, roll_number="9")

        self.assertEqual(403, self.client.post(self.url(other)).status_code)
        student.refresh_from_db()
        self.assertEqual("9", student.roll_number)

    def test_an_unknown_section_is_404(self):
        self.assertEqual(404, self.client.post("/api/v1/sections/999999/renumber").status_code)


class BulkUpload(RollTest):
    def upload(self, *rows):
        body = "\r\n".join([HEADINGS, *rows]) + "\r\n"
        upload = SimpleUploadedFile("students.csv", body.encode("utf-8"), content_type="text/csv")

        return self.client.post("/api/v1/imports/students", {"file": upload}, format="multipart")

    def rolls(self):
        return dict(Student.objects.filter(class_section=self.section).values_list("first_name", "roll_number"))

    def test_blank_rows_are_numbered_in_file_order_past_the_typed_ones(self):
        self.student("2", first_name="Old")

        response = self.upload(
            "A1,Zoya,K,Class 5,A,,G,,",
            "A2,Arjun,K,Class 5,A,6,G,,",
            "A3,Mira,K,Class 5,A,,G,,",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual({"Old": "2", "Zoya": "7", "Arjun": "6", "Mira": "8"}, self.rolls())

    def test_a_number_already_held_is_refused_and_nothing_is_written(self):
        self.student("4", first_name="Asha", last_name="Verma")

        response = self.upload("A1,Zoya,K,Class 5,A,,G,,", "A2,Arjun,K,Class 5,A,4,G,,")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("Asha Verma", str(response.data))
        self.assertEqual(1, Student.objects.count())

    def test_the_same_number_twice_in_one_section_of_the_file_is_refused(self):
        response = self.upload("A1,Zoya,K,Class 5,A,3,G,,", "A2,Arjun,K,Class 5,A,3,G,,")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("Zoya K", str(response.data))

    def test_the_same_number_in_two_sections_of_the_file_is_fine(self):
        response = self.upload("A1,Zoya,K,Class 5,A,3,G,,", "A2,Arjun,K,Class 5,B,3,G,,")

        self.assertEqual(201, response.status_code, response.data)
