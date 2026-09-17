"""Syllabus tracking, over HTTP.

**The outline belongs to whoever runs the subject** - an admin of its school,
or the HOD of its department. A teacher reads it and does not edit it.

**Ticking a topic off is broader**: the teacher timetabled for that subject in
that section may, checked against the live timetable.

**Nobody reads another school's syllabus by changing an id.** Laravel's list
and checklist both let that happen; the fix landed on both backends together,
and the DENY cases here are the ones that held it down.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import SyllabusTopic, SyllabusTopicProgress
from school.services import percent_of


class SyllabusTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        self.department = factories.DepartmentFactory(
            school=self.school, name="Mathematics", hod_user=self.hod
        )
        self.subject = factories.SubjectFactory(
            school=self.school, department=self.department, name="Algebra"
        )

        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

        self.section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(
                school=self.school,
                academic_year=factories.AcademicYearFactory(school=self.school),
            )
        )
        factories.TimetableEntryFactory(
            school=self.school,
            class_section=self.section,
            period=factories.PeriodFactory(school=self.school, period_number=1),
            subject=self.subject,
            teacher=self.teacher,
        )

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]

    def elsewhere(self):
        """Another school, with a subject, a section and an admin of its own."""
        school = factories.SchoolFactory()
        subject = factories.SubjectFactory(
            school=school, department=factories.DepartmentFactory(school=school)
        )
        section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(
                school=school, academic_year=factories.AcademicYearFactory(school=school)
            )
        )
        admin = factories.UserFactory(school=school, role=UserRole.SCHOOL_ADMIN)

        return school, subject, section, admin


class OutlineTest(SyllabusTestCase):
    def add(self, user, **overrides):
        body = {"subject_id": self.subject.id, "title": "Chapter 1: Whole numbers", "sequence_number": 1}
        body.update(overrides)

        return self.as_user(user).post("/api/v1/syllabus-topics", body, format="json")

    # -- adding -------------------------------------------------------------

    def test_a_school_admin_adds_a_topic(self):
        response = self.add(self.admin)

        self.assertEqual(201, response.status_code)
        self.assertEqual(
            {
                "id": response.data["id"],
                "school_id": self.school.id,
                "subject_id": self.subject.id,
                "subject_name": "Algebra",
                "title": "Chapter 1: Whole numbers",
                "sequence_number": 1,
            },
            response.data,
        )

    def test_a_null_school_id_from_the_client_is_ignored(self):
        self.assertEqual(201, self.add(self.admin, school_id=None).status_code)

    def test_the_hod_of_the_subjects_department_adds_a_topic(self):
        self.assertEqual(201, self.add(self.hod).status_code)

    def test_an_hod_of_another_department_does_not(self):
        other_hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        factories.DepartmentFactory(school=self.school, name="Science", hod_user=other_hod)

        self.assertEqual(403, self.add(other_hod).status_code)

    def test_a_teacher_does_not_add_topics(self):
        self.assertEqual(403, self.add(self.teacher).status_code)

    def test_another_schools_subject_is_invalid(self):
        _, foreign_subject, _, _ = self.elsewhere()

        response = self.add(self.admin, subject_id=foreign_subject.id)

        self.assertEqual(422, response.status_code)
        self.assertIn("subject_id", self.errors(response))

    def test_a_super_admin_adds_to_any_school(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.assertEqual(201, self.add(root, school_id=self.school.id).status_code)

    def test_a_sequence_number_is_unique_within_a_subject(self):
        self.add(self.admin)

        response = self.add(self.admin, title="Again")

        self.assertEqual(
            ["The sequence number has already been taken."], self.errors(response)["sequence_number"]
        )

    def test_every_subject_may_start_at_one(self):
        self.add(self.admin)
        geometry = factories.SubjectFactory(school=self.school, department=self.department)

        self.assertEqual(201, self.add(self.admin, subject_id=geometry.id).status_code)

    def test_a_long_title_and_a_taken_number_are_reported_together(self):
        # DRF would skip a cross-field validate() once the title failed; the
        # taken number has to be reported anyway, as Laravel does.
        self.add(self.admin)

        response = self.add(self.admin, title="x" * 256)

        self.assertEqual({"title", "sequence_number"}, set(self.errors(response)))

    def test_a_sequence_number_starts_at_one(self):
        response = self.add(self.admin, sequence_number=0)

        self.assertEqual(
            ["The sequence number field must be at least 1."], self.errors(response)["sequence_number"]
        )

    def test_an_empty_topic_names_every_missing_field(self):
        response = self.as_user(self.admin).post("/api/v1/syllabus-topics", {}, format="json")

        self.assertEqual(["subject_id", "title", "sequence_number"], list(self.errors(response)))

    # -- editing and removing -----------------------------------------------

    def test_a_school_admin_renames_a_topic(self):
        topic = factories.SyllabusTopicFactory(subject=self.subject)

        response = self.as_user(self.admin).patch(
            f"/api/v1/syllabus-topics/{topic.id}", {"title": "Renamed"}, format="json"
        )

        self.assertEqual("Renamed", response.data["title"])

    def test_the_hod_edits_their_departments_topic(self):
        topic = factories.SyllabusTopicFactory(subject=self.subject)

        response = self.as_user(self.hod).patch(
            f"/api/v1/syllabus-topics/{topic.id}", {"sequence_number": 7}, format="json"
        )

        self.assertEqual(7, response.data["sequence_number"])

    def test_a_teacher_does_not_edit_even_a_malformed_request(self):
        # Authorized before validated, so a stranger learns nothing from 422s.
        topic = factories.SyllabusTopicFactory(subject=self.subject)

        response = self.as_user(self.teacher).patch(
            f"/api/v1/syllabus-topics/{topic.id}", {"title": ""}, format="json"
        )

        self.assertEqual(403, response.status_code)

    def test_another_schools_admin_does_not_edit(self):
        topic = factories.SyllabusTopicFactory(subject=self.subject)
        _, _, _, stranger = self.elsewhere()

        response = self.as_user(stranger).patch(
            f"/api/v1/syllabus-topics/{topic.id}", {"title": "Mine now"}, format="json"
        )

        self.assertEqual(403, response.status_code)

    def test_a_number_taken_by_another_topic_is_refused_but_its_own_is_not(self):
        first = factories.SyllabusTopicFactory(subject=self.subject, sequence_number=1)
        factories.SyllabusTopicFactory(subject=self.subject, sequence_number=2)

        taken = self.as_user(self.admin).patch(
            f"/api/v1/syllabus-topics/{first.id}", {"sequence_number": 2}, format="json"
        )
        own = self.as_user(self.admin).patch(
            f"/api/v1/syllabus-topics/{first.id}", {"sequence_number": 1}, format="json"
        )

        self.assertEqual(422, taken.status_code)
        self.assertEqual(200, own.status_code)

    def test_a_blank_title_is_required_when_sent(self):
        topic = factories.SyllabusTopicFactory(subject=self.subject)

        response = self.as_user(self.admin).patch(
            f"/api/v1/syllabus-topics/{topic.id}", {"title": ""}, format="json"
        )

        self.assertEqual(["The title field is required."], self.errors(response)["title"])

    def test_an_edit_that_changes_nothing_writes_nothing(self):
        topic = factories.SyllabusTopicFactory(subject=self.subject)
        before = SyllabusTopic.objects.get(pk=topic.pk).updated_at

        response = self.as_user(self.admin).patch(
            f"/api/v1/syllabus-topics/{topic.id}", {"title": topic.title}, format="json"
        )

        self.assertEqual(200, response.status_code)
        self.assertEqual(before, SyllabusTopic.objects.get(pk=topic.pk).updated_at)

    def test_a_school_admin_removes_a_topic(self):
        topic = factories.SyllabusTopicFactory(subject=self.subject)

        response = self.as_user(self.admin).delete(f"/api/v1/syllabus-topics/{topic.id}")

        self.assertEqual(204, response.status_code)
        self.assertFalse(SyllabusTopic.objects.exists())

    def test_a_teacher_and_another_school_do_not_remove_topics(self):
        topic = factories.SyllabusTopicFactory(subject=self.subject)
        _, _, _, stranger = self.elsewhere()

        for user in (self.teacher, stranger):
            response = self.as_user(user).delete(f"/api/v1/syllabus-topics/{topic.id}")
            self.assertEqual(403, response.status_code)

        self.assertTrue(SyllabusTopic.objects.exists())

    def test_a_topic_that_is_not_there_is_a_404(self):
        response = self.as_user(self.admin).delete("/api/v1/syllabus-topics/999999")

        self.assertEqual(404, response.status_code)

    # -- reading ------------------------------------------------------------

    def test_a_teacher_reads_the_outline_in_teaching_order(self):
        factories.SyllabusTopicFactory(subject=self.subject, sequence_number=2, title="Second")
        factories.SyllabusTopicFactory(subject=self.subject, sequence_number=1, title="First")

        response = self.as_user(self.teacher).get(f"/api/v1/syllabus-topics?subject_id={self.subject.id}")

        self.assertEqual(["First", "Second"], [topic["title"] for topic in response.data])

    def test_another_schools_outline_is_not_found(self):
        # DENY. Laravel answered 200 with the other school's topics.
        _, foreign_subject, _, stranger = self.elsewhere()
        factories.SyllabusTopicFactory(subject=self.subject, title="Private")

        response = self.as_user(stranger).get(f"/api/v1/syllabus-topics?subject_id={self.subject.id}")

        self.assertEqual(404, response.status_code)
        self.assertEqual("NOT_FOUND", response.data["code"])
        self.assertNotIn("Private", str(response.data))

    def test_a_super_admin_reads_any_outline(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        factories.SyllabusTopicFactory(subject=self.subject)

        response = self.as_user(root).get(f"/api/v1/syllabus-topics?subject_id={self.subject.id}")

        self.assertEqual(1, len(response.data))

    def test_staff_and_transport_managers_do_not_read_the_outline(self):
        for role in (UserRole.STAFF, UserRole.TRANSPORT_MANAGER):
            user = factories.UserFactory(school=self.school, role=role)
            response = self.as_user(user).get(f"/api/v1/syllabus-topics?subject_id={self.subject.id}")
            self.assertEqual(403, response.status_code, role)

    def test_the_outline_needs_a_real_subject(self):
        missing = self.as_user(self.admin).get("/api/v1/syllabus-topics")
        junk = self.as_user(self.admin).get("/api/v1/syllabus-topics?subject_id=abc")

        self.assertEqual(["The subject id field is required."], self.errors(missing)["subject_id"])
        self.assertEqual(["The subject id field must be an integer."], self.errors(junk)["subject_id"])


class ChecklistTest(SyllabusTestCase):
    def setUp(self):
        super().setUp()
        self.topic = factories.SyllabusTopicFactory(subject=self.subject, sequence_number=1)

    def tick(self, user, completed=True, **overrides):
        body = {"syllabus_topic_id": self.topic.id, "class_section_id": self.section.id, "completed": completed}
        body.update(overrides)

        return self.as_user(user).patch("/api/v1/syllabus-progress", body, format="json")

    def checklist(self, user, subject=None, section=None):
        return self.as_user(user).get(
            "/api/v1/syllabus-progress"
            f"?subject_id={(subject or self.subject).id}&class_section_id={(section or self.section).id}"
        )

    # -- ticking ------------------------------------------------------------

    def test_the_timetabled_teacher_ticks_a_topic_off(self):
        response = self.tick(self.teacher)

        self.assertEqual(200, response.status_code)
        self.assertEqual(1, response.data["completed_topics"])
        self.assertEqual(100, response.data["progress_percent"])
        self.assertEqual(self.teacher.name, response.data["topics"][0]["completed_by_name"])
        self.assertRegex(response.data["topics"][0]["completed_at"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$")

    def test_unticking_removes_the_mark(self):
        self.tick(self.teacher)

        response = self.tick(self.teacher, completed=False)

        self.assertFalse(response.data["topics"][0]["completed"])
        self.assertFalse(SyllabusTopicProgress.objects.exists())

    def test_a_teacher_not_timetabled_for_it_does_not_tick(self):
        other = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(403, self.tick(other).status_code)

    def test_the_departments_hod_ticks_without_a_timetable_slot(self):
        self.assertEqual(200, self.tick(self.hod).status_code)

    def test_an_hod_of_another_department_does_not_tick(self):
        other_hod = factories.UserFactory(school=self.school, role=UserRole.HOD)

        self.assertEqual(403, self.tick(other_hod).status_code)

    def test_a_school_admin_ticks_and_another_schools_admin_does_not(self):
        _, _, _, stranger = self.elsewhere()

        self.assertEqual(200, self.tick(self.admin).status_code)
        self.assertEqual(403, self.tick(stranger).status_code)

    def test_a_section_from_another_school_than_the_topic_is_invalid(self):
        _, _, foreign_section, _ = self.elsewhere()

        response = self.tick(self.admin, class_section_id=foreign_section.id)

        self.assertEqual(
            ["The selected class section id is invalid."], self.errors(response)["class_section_id"]
        )

    def test_a_super_admin_ticks_anywhere(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.assertEqual(200, self.tick(root).status_code)

    def test_nonsense_is_named_field_by_field(self):
        response = self.tick(self.admin, syllabus_topic_id=999999, class_section_id=999999, completed="maybe")

        self.assertEqual(
            {
                "syllabus_topic_id": ["The selected syllabus topic id is invalid."],
                "class_section_id": ["The selected class section id is invalid."],
                "completed": ["The completed field must be true or false."],
            },
            self.errors(response),
        )

    # -- reading ------------------------------------------------------------

    def test_the_checklist_lists_every_topic_with_its_mark(self):
        factories.SyllabusTopicFactory(subject=self.subject, sequence_number=2)
        self.tick(self.teacher)

        response = self.checklist(self.teacher)

        self.assertEqual(2, response.data["total_topics"])
        self.assertEqual(50, response.data["progress_percent"])
        self.assertEqual([True, False], [topic["completed"] for topic in response.data["topics"]])

    def test_another_schools_subject_is_not_readable_through_ones_own_section(self):
        # DENY. The section is the stranger's own, so the policy passes; it is
        # the subject that is somebody else's. Laravel answered 200.
        _, _, own_section, stranger = self.elsewhere()

        response = self.checklist(stranger, section=own_section)

        self.assertEqual(404, response.status_code)
        self.assertEqual("NOT_FOUND", response.data["code"])

    def test_another_schools_teacher_does_not_read_the_checklist(self):
        outsider = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.TEACHER)

        self.assertEqual(403, self.checklist(outsider).status_code)

    def test_staff_do_not_read_the_checklist(self):
        staff = factories.UserFactory(school=self.school, role=UserRole.STAFF)

        self.assertEqual(403, self.checklist(staff).status_code)

    def test_a_super_admin_reads_any_checklist(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.assertEqual(200, self.checklist(root).status_code)


class PercentTest(TestCase):
    def test_halves_round_up_the_way_php_rounds_them(self):
        # Python's round(12.5) is 12. PHP's is 13, and that is the contract.
        self.assertEqual(13, percent_of(1, 8))
        self.assertEqual(38, percent_of(3, 8))
        self.assertEqual(63, percent_of(5, 8))
        self.assertEqual(33, percent_of(1, 3))
        self.assertEqual(67, percent_of(2, 3))

    def test_nothing_to_do_is_nought_percent(self):
        self.assertEqual(0, percent_of(0, 0))
