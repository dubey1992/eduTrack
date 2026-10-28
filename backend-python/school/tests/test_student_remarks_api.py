"""The class teacher's term remark (docs/pdf-design.md, the progress report):
who may write it, what is checked, how it is kept, and where it shows - the
Performance payload and the printed report."""

from school import factories, progress_reports
from school.enums import UserRole
from school.models import AuditLog, StudentTermRemark
from school.performance import for_student

from .test_student_performance_api import PerformanceTestCase


class RemarkTestCase(PerformanceTestCase):
    def setUp(self):
        super().setUp()
        self.class_teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER, first_name="Meena",
                                                   last_name="Iyer")
        self.section.class_teacher = self.class_teacher
        self.section.save(update_fields=["class_teacher"])

    def put(self, remark="Works hard; must read more at home.", user=None, term=None, student=None):
        return self.as_user(user or self.class_teacher).put(
            f"/api/v1/students/{(student or self.student).id}/remark",
            {"academic_term_id": (term or self.term_2).id, "remark": remark}, format="json",
        )

    def performance(self, user=None):
        return self.as_user(user or self.class_teacher).get(f"/api/v1/students/{self.student.id}/performance").data


class WhoMayWriteIt(RemarkTestCase):
    def test_the_class_teacher_writes_it_and_the_screen_shows_it(self):
        response = self.put()

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("Works hard; must read more at home.", response.data["remark"]["text"])
        self.assertEqual("Meena Iyer", response.data["remark"]["written_by"])
        data = self.performance()
        self.assertTrue(data["can_edit_remark"])
        self.assertEqual("Works hard; must read more at home.", data["remark"]["text"])

    def test_a_school_admin_may_write_it(self):
        self.assertEqual(200, self.put(user=self.admin).status_code)
        self.assertTrue(self.performance(self.admin)["can_edit_remark"])

    def test_a_teacher_of_another_class_may_not(self):
        other = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(403, self.put(user=other).status_code)
        self.assertFalse(StudentTermRemark.objects.exists())

    def test_a_super_admin_reads_it_but_may_not_write_it(self):
        self.put()
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.assertEqual(403, self.put(user=root, remark="Changed").status_code)
        data = self.performance(root)
        self.assertFalse(data["can_edit_remark"])
        self.assertEqual("Works hard; must read more at home.", data["remark"]["text"])

    def test_another_schools_admin_may_not(self):
        elsewhere = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)

        self.assertEqual(403, self.put(user=elsewhere).status_code)

    def test_signed_out_is_refused(self):
        from rest_framework.test import APIClient

        response = APIClient().put(f"/api/v1/students/{self.student.id}/remark",
                                   {"academic_term_id": self.term_2.id, "remark": "x"}, format="json")

        self.assertEqual(401, response.status_code)


class WhatIsChecked(RemarkTestCase):
    def test_a_remark_longer_than_a_thousand_characters_is_refused(self):
        response = self.put(remark="x" * 1001)

        self.assertEqual(422, response.status_code)
        self.assertIn("remark", response.data["details"]["errors"])

    def test_the_term_must_be_the_students_schools(self):
        other_year = factories.AcademicYearFactory(school=factories.SchoolFactory())
        foreign = factories.AcademicTermFactory(academic_year=other_year, school=other_year.school)

        response = self.put(term=foreign)

        self.assertEqual(422, response.status_code)
        self.assertIn("academic_term_id", response.data["details"]["errors"])

    def test_the_term_is_required(self):
        response = self.as_user(self.class_teacher).put(
            f"/api/v1/students/{self.student.id}/remark", {"remark": "x"}, format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertIn("academic_term_id", response.data["details"]["errors"])


class HowItIsKept(RemarkTestCase):
    def test_one_per_term_saved_over_and_removed_when_cleared(self):
        self.put("First")
        self.put("Second", user=self.admin)

        row = StudentTermRemark.objects.get()
        self.assertEqual(("Second", self.admin.id), (row.remark, row.written_by_id))

        self.assertEqual(200, self.put("   ").status_code)
        self.assertFalse(StudentTermRemark.objects.exists())
        self.assertIsNone(self.performance()["remark"])

    def test_each_term_has_its_own(self):
        self.put("Term two", term=self.term_2)
        self.put("Term one", term=self.term_1)

        self.assertEqual(2, StudentTermRemark.objects.count())
        self.assertEqual("Term two", for_student(self.student, self.term_2.id)["remark"]["text"])
        self.assertEqual("Term one", for_student(self.student, self.term_1.id)["remark"]["text"])

    def test_writing_and_removing_are_audited(self):
        self.put("First")
        self.put("")

        actions = list(AuditLog.objects.filter(module="assessments", entity_type="student")
                       .order_by("id").values_list("action", flat=True))
        self.assertEqual(["student_remark.saved", "student_remark.removed"], actions)


class OnTheReport(RemarkTestCase):
    def page(self):
        return progress_reports.document(for_student(self.student, None), school=self.school, generated_at="now")

    def test_the_report_prints_it_with_who_wrote_it(self):
        self.mark_published()
        self.put("Works hard <b>always</b>.\nMust read more.")

        page = self.page()

        self.assertIn("CLASS TEACHER&#x27;S REMARK", page)
        self.assertIn("Works hard &lt;b&gt;always&lt;/b&gt;.<br/>Must read more.", page)
        self.assertIn("Meena Iyer", page)

    def test_no_remark_prints_no_section(self):
        self.mark_published()

        self.assertNotIn("REMARK", self.page())

    def mark_published(self):
        self.mark(self.published(), marks="15")
