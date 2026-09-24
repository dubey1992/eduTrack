"""Class tests, over HTTP (docs/assessments.md).

This is the slice where who-may-do-what is decided, so the DENY half is most
of the file. The rule that matters, and the one a reader should hold on to:

    **A teacher reaches a section and subject only when the timetable says
    they teach it.** Being the class teacher of 8A is not enough - the class
    teacher of 8A does not thereby teach 8A mathematics.

The rest is the other kind of loophole: a request where every field is fine
on its own and the whole means nothing. A subject not taught at that level, a
term from another year, a topic belonging to a different subject, a weightage
that takes the term past 100%.

The year is 2026-27, Term 1 running 1 April to 31 August 2026.
"""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import AssessmentStatus, UserRole
from school.models import Assessment

URL = "/api/v1/assessments"


class AssessmentTestCase(TestCase):
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
        self.other_section = factories.ClassSectionFactory(school_class=self.school_class, name="B")

        self.department = factories.DepartmentFactory(school=self.school, name="Mathematics")
        self.subject = factories.SubjectFactory(
            department=self.department, school=self.school, name="Mathematics", min_class_level=6, max_class_level=10
        )
        self.other_subject = factories.SubjectFactory(
            department=self.department, school=self.school, name="Science", min_class_level=6, max_class_level=10
        )

        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.period = factories.PeriodFactory(school=self.school)
        # The timetable is what says who teaches what to whom.
        factories.TimetableEntryFactory(
            school=self.school,
            class_section=self.section,
            subject=self.subject,
            teacher=self.teacher,
            period=self.period,
        )

        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def payload(self, **overrides) -> dict:
        body = {
            "class_section_id": self.section.id,
            "subject_id": self.subject.id,
            "academic_term_id": self.term.id,
            "type": "class_test",
            "title": "Fractions - unit test",
            "max_marks": "20",
            "assessment_date": "2026-04-15",
        }
        body.update(overrides)

        return body

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]

    def existing(self, **overrides) -> Assessment:
        fields = {
            "school": self.school,
            "academic_year": self.year,
            "academic_term": self.term,
            "class_section": self.section,
            "subject": self.subject,
            "created_by": self.admin,
        }
        fields.update(overrides)

        return factories.AssessmentFactory(**fields)


class CreatingATest(AssessmentTestCase):
    def test_a_test_is_created_and_comes_back_whole(self):
        response = self.client.post(URL, self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("Fractions - unit test", response.data["title"])
        self.assertEqual("20.00", response.data["max_marks"])
        self.assertEqual("Grade 8 A", response.data["class_section_name"])
        self.assertEqual("Mathematics", response.data["subject_name"])
        self.assertEqual("Term 1", response.data["term_name"])
        self.assertEqual(AssessmentStatus.DRAFT, response.data["status"], "everything starts as a draft")
        self.assertIsNone(response.data["published_at"])

    def test_the_school_and_year_come_from_the_section_not_the_request(self):
        elsewhere = factories.SchoolFactory()

        response = self.client.post(
            URL, self.payload(school_id=elsewhere.id, academic_year_id=999), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, response.data["school_id"])
        self.assertEqual(self.year.id, response.data["academic_year_id"])

    def test_a_teacher_creates_one_for_the_class_they_teach(self):
        response = self.as_user(self.teacher).post(URL, self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.teacher.name, response.data["created_by_name"])

    def test_the_optional_pieces_are_optional(self):
        response = self.client.post(URL, self.payload(), format="json")

        self.assertIsNone(response.data["pass_marks"])
        self.assertIsNone(response.data["weightage"])
        self.assertIsNone(response.data["syllabus_topic_id"])
        self.assertIsNone(response.data["grade_scale_id"])

    def test_a_topic_and_a_scale_can_be_named(self):
        topic = factories.SyllabusTopicFactory(school=self.school, subject=self.subject, title="Fractions")
        scale = factories.GradeScaleFactory(school=self.school, name="Secondary")

        response = self.client.post(
            URL, self.payload(syllabus_topic_id=topic.id, grade_scale_id=scale.id), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("Fractions", response.data["syllabus_topic_title"])
        self.assertEqual("Secondary", response.data["grade_scale_name"])

    def test_missing_fields_are_named(self):
        response = self.client.post(URL, {}, format="json")

        self.assertEqual(422, response.status_code, response.data)
        for field in ("class_section_id", "subject_id", "academic_term_id", "type", "title", "assessment_date"):
            self.assertIn(field, self.errors(response))

    def test_a_type_outside_the_list_is_refused(self):
        response = self.client.post(URL, self.payload(type="viva"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("type", self.errors(response))


class TheMarksMustMakeSense(AssessmentTestCase):
    def test_max_marks_is_required(self):
        body = self.payload()
        del body["max_marks"]

        response = self.client.post(URL, body, format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("max_marks", self.errors(response))

    def test_a_test_out_of_nothing_is_refused(self):
        for value in ("0", "-5"):
            with self.subTest(max_marks=value):
                response = self.client.post(URL, self.payload(max_marks=value), format="json")

                self.assertEqual(422, response.status_code, response.data)
                self.assertIn("max_marks", self.errors(response))

    def test_a_test_out_of_an_absurd_number_is_refused(self):
        response = self.client.post(URL, self.payload(max_marks="5000"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The max marks field must not be greater than 1000.", self.errors(response)["max_marks"][0]
        )

    def test_marks_that_are_not_a_number_are_refused(self):
        response = self.client.post(URL, self.payload(max_marks="twenty"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("The max marks field must be a number.", self.errors(response)["max_marks"][0])

    def test_a_pass_mark_nobody_could_reach_is_refused(self):
        response = self.client.post(URL, self.payload(max_marks="20", pass_marks="21"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The pass marks field must not be greater than max marks.", self.errors(response)["pass_marks"][0]
        )

    def test_a_pass_mark_equal_to_the_maximum_is_allowed(self):
        response = self.client.post(URL, self.payload(max_marks="20", pass_marks="20"), format="json")

        self.assertEqual(201, response.status_code, response.data)

    def test_marks_keep_their_decimals(self):
        response = self.client.post(URL, self.payload(max_marks="17.5"), format="json")

        self.assertEqual("17.50", response.data["max_marks"])


class TheWeightageOfATerm(AssessmentTestCase):
    def test_a_weightage_over_a_hundred_is_refused_on_its_own(self):
        response = self.client.post(URL, self.payload(weightage="120"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("weightage", self.errors(response))

    def test_the_weightages_of_one_subject_and_term_may_not_pass_a_hundred(self):
        self.existing(weightage=70)

        response = self.client.post(URL, self.payload(weightage="40"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("past 100%", self.errors(response)["weightage"][0])

    def test_reaching_exactly_a_hundred_is_allowed(self):
        self.existing(weightage=70)

        response = self.client.post(URL, self.payload(weightage="30"), format="json")

        self.assertEqual(201, response.status_code, response.data)

    def test_another_subject_has_its_own_hundred(self):
        self.existing(weightage=100)

        response = self.client.post(URL, self.payload(subject_id=self.other_subject.id, weightage="60"), format="json")

        self.assertEqual(201, response.status_code, response.data)

    def test_another_section_has_its_own_hundred(self):
        self.existing(weightage=100)

        response = self.client.post(
            URL, self.payload(class_section_id=self.other_section.id, weightage="60"), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)

    def test_editing_a_test_does_not_count_its_own_weightage_twice(self):
        existing = self.existing(weightage=60)

        response = self.client.patch(f"{URL}/{existing.id}", {"weightage": "60"}, format="json")

        self.assertEqual(200, response.status_code, response.data)


class ThePiecesMustBelongTogether(AssessmentTestCase):
    def test_a_subject_not_taught_at_that_level_is_refused(self):
        infants = factories.SubjectFactory(
            department=self.department, school=self.school, name="Phonics", min_class_level=1, max_class_level=4
        )

        response = self.client.post(URL, self.payload(subject_id=infants.id), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("Phonics is not taught at Grade 8.", self.errors(response)["subject_id"][0])

    def test_a_term_from_another_year_is_refused(self):
        next_year = factories.AcademicYearFactory(school=self.school, name="2027-28", is_current=False)
        their_term = factories.AcademicTermFactory(
            academic_year=next_year,
            school=self.school,
            name="Term 1",
            sequence_number=1,
            start_date=dt.date(2027, 4, 1),
            end_date=dt.date(2027, 8, 31),
        )

        response = self.client.post(
            URL, self.payload(academic_term_id=their_term.id, assessment_date="2027-04-15"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("different academic year", self.errors(response)["academic_term_id"][0])

    def test_a_date_outside_the_term_is_refused(self):
        response = self.client.post(URL, self.payload(assessment_date="2026-09-01"), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("must fall inside Term 1", self.errors(response)["assessment_date"][0])

    def test_the_first_and_last_day_of_the_term_are_inside_it(self):
        for date in ("2026-04-01", "2026-08-31"):
            with self.subTest(date=date):
                response = self.client.post(
                    URL, self.payload(title=f"On {date}", assessment_date=date), format="json"
                )

                self.assertEqual(201, response.status_code, response.data)

    def test_a_topic_from_another_subject_is_refused(self):
        topic = factories.SyllabusTopicFactory(school=self.school, subject=self.other_subject, title="Gravity")

        response = self.client.post(URL, self.payload(syllabus_topic_id=topic.id), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            '"Gravity" is not a topic of Mathematics.', self.errors(response)["syllabus_topic_id"][0]
        )

    def test_something_that_is_not_a_date_is_refused(self):
        response = self.client.post(URL, self.payload(assessment_date="next Tuesday"), format="json")

        self.assertEqual(422, response.status_code, response.data)

    def test_every_broken_rule_is_reported_at_once(self):
        response = self.client.post(
            URL, self.payload(title="", max_marks="0", type="viva", assessment_date="2026-09-30"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        for field in ("title", "max_marks", "type", "assessment_date"):
            self.assertIn(field, self.errors(response))


class NothingFromAnotherSchoolMayBeNamed(AssessmentTestCase):
    def setUp(self):
        super().setUp()
        self.elsewhere = factories.SchoolFactory()
        self.their_year = factories.AcademicYearFactory(school=self.elsewhere, is_current=True)
        self.their_class = factories.SchoolClassFactory(
            academic_year=self.their_year, school=self.elsewhere, name="Grade 8", level=8
        )
        self.their_section = factories.ClassSectionFactory(school_class=self.their_class, name="A")
        self.their_department = factories.DepartmentFactory(school=self.elsewhere, name="Mathematics")
        self.their_subject = factories.SubjectFactory(
            department=self.their_department, school=self.elsewhere, min_class_level=1, max_class_level=12
        )
        self.their_term = factories.AcademicTermFactory(
            academic_year=self.their_year, school=self.elsewhere, name="Term 1", sequence_number=1
        )

    def test_another_schools_section_is_not_a_section_this_actor_can_name(self):
        response = self.client.post(URL, self.payload(class_section_id=self.their_section.id), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The selected class section id is invalid.", self.errors(response)["class_section_id"][0]
        )

    def test_another_schools_subject_term_topic_and_scale_are_refused(self):
        their_topic = factories.SyllabusTopicFactory(school=self.elsewhere, subject=self.their_subject)
        their_scale = factories.GradeScaleFactory(school=self.elsewhere)

        cases = {
            "subject_id": self.their_subject.id,
            "academic_term_id": self.their_term.id,
            "syllabus_topic_id": their_topic.id,
            "grade_scale_id": their_scale.id,
        }

        for field, value in cases.items():
            with self.subTest(field=field):
                response = self.client.post(URL, self.payload(**{field: value}), format="json")

                self.assertEqual(422, response.status_code, response.data)
                self.assertIn(field, self.errors(response))

    def test_an_id_that_does_not_exist_reads_the_same_as_one_from_elsewhere(self):
        response = self.client.post(URL, self.payload(subject_id=9_999_999), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("The selected subject id is invalid.", self.errors(response)["subject_id"][0])


class WhoMaySetATest(AssessmentTestCase):
    def test_a_teacher_may_not_set_one_for_a_class_they_do_not_teach(self):
        response = self.as_user(self.teacher).post(
            URL, self.payload(class_section_id=self.other_section.id), format="json"
        )

        self.assertEqual(403, response.status_code, response.data)

    def test_a_teacher_may_not_set_one_for_a_subject_they_do_not_teach(self):
        response = self.as_user(self.teacher).post(
            URL, self.payload(subject_id=self.other_subject.id), format="json"
        )

        self.assertEqual(403, response.status_code, response.data)

    def test_being_the_class_teacher_is_not_teaching_the_subject(self):
        # The heart of the rule: the class teacher of 8A does not thereby
        # teach 8A science.
        class_teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.other_section.class_teacher = class_teacher
        self.other_section.save(update_fields=["class_teacher"])

        response = self.as_user(class_teacher).post(
            URL, self.payload(class_section_id=self.other_section.id, subject_id=self.subject.id), format="json"
        )

        self.assertEqual(403, response.status_code, response.data)

    def test_an_hod_sets_one_for_their_own_departments_subject(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        self.department.hod_user = hod
        self.department.save(update_fields=["hod_user"])

        response = self.as_user(hod).post(URL, self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)

    def test_an_hod_of_another_department_is_refused(self):
        science = factories.DepartmentFactory(school=self.school, name="Science")
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        science.hod_user = hod
        science.save(update_fields=["hod_user"])

        response = self.as_user(hod).post(URL, self.payload(), format="json")

        self.assertEqual(403, response.status_code, response.data)

    def test_an_hod_who_heads_nothing_is_refused(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)

        self.assertEqual(403, self.as_user(hod).post(URL, self.payload(), format="json").status_code)

    def test_the_roles_with_no_business_here_are_refused_outright(self):
        for role in (UserRole.STAFF, UserRole.ACCOUNTANT, UserRole.TRANSPORT_MANAGER, UserRole.BUS_ATTENDANT):
            with self.subTest(role=role):
                stranger = self.as_user(factories.UserFactory(school=self.school, role=role))

                self.assertEqual(403, stranger.get(URL).status_code)
                self.assertEqual(403, stranger.post(URL, self.payload(), format="json").status_code)

    def test_a_super_admin_reads_any_schools_tests_and_sets_none(self):
        existing = self.existing()
        root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        self.assertEqual(200, root.get(f"{URL}/{existing.id}").status_code)
        self.assertEqual(403, root.post(URL, self.payload(), format="json").status_code)
        self.assertEqual(403, root.patch(f"{URL}/{existing.id}", {"title": "Mine"}, format="json").status_code)
        self.assertEqual(403, root.delete(f"{URL}/{existing.id}").status_code)

    def test_a_group_admin_sets_one_in_a_branch(self):
        branch = factories.SchoolFactory(parent_school=self.school)
        branch_year = factories.AcademicYearFactory(school=branch, is_current=True)
        branch_class = factories.SchoolClassFactory(
            academic_year=branch_year, school=branch, name="Grade 8", level=8
        )
        branch_section = factories.ClassSectionFactory(school_class=branch_class, name="A")
        branch_term = factories.AcademicTermFactory(
            academic_year=branch_year,
            school=branch,
            name="Term 1",
            sequence_number=1,
            start_date=dt.date(2026, 4, 1),
            end_date=dt.date(2026, 8, 31),
        )
        branch_subject = factories.SubjectFactory(
            department=factories.DepartmentFactory(school=branch), school=branch, min_class_level=1, max_class_level=12
        )
        group_admin = self.as_user(factories.UserFactory(school=self.school, role=UserRole.GROUP_ADMIN))

        response = group_admin.post(
            URL,
            self.payload(
                class_section_id=branch_section.id, subject_id=branch_subject.id, academic_term_id=branch_term.id
            ),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(branch.id, response.data["school_id"])

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get(URL).status_code)

    def test_the_module_can_be_switched_off_for_a_school(self):
        from school.models import ModuleSetting

        ModuleSetting.objects.create(
            school_id=self.school.id, module="assessments", platform_enabled=True, school_enabled=False
        )
        cache.clear()

        response = self.client.get(URL)

        self.assertEqual(403, response.status_code, response.data)
        self.assertEqual("MODULE_DISABLED", response.data["code"])


class EditingAndDeleting(AssessmentTestCase):
    def setUp(self):
        super().setUp()
        self.assessment = self.existing()

    def test_a_field_can_be_changed_on_its_own(self):
        response = self.client.patch(f"{URL}/{self.assessment.id}", {"title": "Renamed"}, format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("Renamed", response.data["title"])

    def test_the_section_and_subject_are_fixed_at_creation(self):
        response = self.client.patch(
            f"{URL}/{self.assessment.id}",
            {"class_section_id": self.other_section.id, "subject_id": self.other_subject.id},
            format="json",
        )

        self.assessment.refresh_from_db()
        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(self.section.id, self.assessment.class_section_id)
        self.assertEqual(self.subject.id, self.assessment.subject_id)

    def test_moving_the_date_is_checked_against_the_stored_term(self):
        response = self.client.patch(
            f"{URL}/{self.assessment.id}", {"assessment_date": "2026-12-01"}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("assessment_date", self.errors(response))

    def test_a_teacher_edits_their_own_test(self):
        mine = self.existing(created_by=self.teacher)

        response = self.as_user(self.teacher).patch(f"{URL}/{mine.id}", {"title": "Mine"}, format="json")

        self.assertEqual(200, response.status_code, response.data)

    def test_a_teacher_may_not_edit_a_test_of_a_class_they_do_not_teach(self):
        theirs = self.existing(class_section=self.other_section)

        response = self.as_user(self.teacher).patch(f"{URL}/{theirs.id}", {"title": "Mine"}, format="json")

        self.assertEqual(403, response.status_code, response.data)

    def test_a_draft_can_be_deleted(self):
        response = self.client.delete(f"{URL}/{self.assessment.id}")

        self.assertEqual(204, response.status_code)
        self.assertFalse(Assessment.objects.filter(pk=self.assessment.id).exists())

    def test_a_published_test_cannot_be_edited_or_deleted(self):
        published = self.existing(status=AssessmentStatus.PUBLISHED)

        edited = self.client.patch(f"{URL}/{published.id}", {"title": "Quietly"}, format="json")
        removed = self.client.delete(f"{URL}/{published.id}")

        for response in (edited, removed):
            self.assertEqual(409, response.status_code, response.data)
            self.assertEqual("ASSESSMENT_PUBLISHED", response.data["code"])

        self.assertTrue(Assessment.objects.filter(pk=published.id).exists())

    def test_another_schools_test_cannot_be_read_edited_or_deleted(self):
        elsewhere = factories.SchoolFactory()
        their_year = factories.AcademicYearFactory(school=elsewhere, is_current=True)
        their_section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=their_year, school=elsewhere)
        )
        theirs = factories.AssessmentFactory(
            school=elsewhere,
            academic_year=their_year,
            academic_term=factories.AcademicTermFactory(academic_year=their_year, school=elsewhere),
            class_section=their_section,
            subject=factories.SubjectFactory(
                department=factories.DepartmentFactory(school=elsewhere), school=elsewhere
            ),
            created_by=factories.UserFactory(school=elsewhere, role=UserRole.SCHOOL_ADMIN),
        )

        self.assertEqual(403, self.client.get(f"{URL}/{theirs.id}").status_code)
        self.assertEqual(403, self.client.patch(f"{URL}/{theirs.id}", {"title": "Mine"}, format="json").status_code)
        self.assertEqual(403, self.client.delete(f"{URL}/{theirs.id}").status_code)


class TheListShowsOnlyWhatIsYours(AssessmentTestCase):
    def setUp(self):
        super().setUp()
        self.mine = self.existing(title="Mine")
        self.other_class = self.existing(class_section=self.other_section, title="Another section")
        self.other_subject_test = self.existing(subject=self.other_subject, title="Another subject")

    def test_an_admin_sees_the_whole_school(self):
        response = self.client.get(URL)

        self.assertEqual(
            {"Mine", "Another section", "Another subject"},
            {row["title"] for row in response.data["data"]},
        )

    def test_a_teacher_sees_only_what_they_teach(self):
        response = self.as_user(self.teacher).get(URL)

        self.assertEqual(["Mine"], [row["title"] for row in response.data["data"]])

    def test_a_filter_cannot_widen_what_a_teacher_sees(self):
        response = self.as_user(self.teacher).get(URL, {"class_section_id": self.other_section.id})

        self.assertEqual([], response.data["data"])

    def test_a_teacher_who_teaches_nothing_sees_nothing(self):
        idle = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        response = self.as_user(idle).get(URL)

        self.assertEqual([], response.data["data"])

    def test_an_hod_sees_their_departments_subjects(self):
        science = factories.DepartmentFactory(school=self.school, name="Science")
        science_subject = factories.SubjectFactory(
            department=science, school=self.school, name="Physics", min_class_level=1, max_class_level=12
        )
        self.existing(subject=science_subject, title="Physics test")
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        science.hod_user = hod
        science.save(update_fields=["hod_user"])

        response = self.as_user(hod).get(URL)

        self.assertEqual(["Physics test"], [row["title"] for row in response.data["data"]])

    def test_the_list_never_includes_another_school(self):
        elsewhere = factories.SchoolFactory()
        their_year = factories.AcademicYearFactory(school=elsewhere, is_current=True)
        factories.AssessmentFactory(
            school=elsewhere,
            academic_year=their_year,
            academic_term=factories.AcademicTermFactory(academic_year=their_year, school=elsewhere),
            class_section=factories.ClassSectionFactory(
                school_class=factories.SchoolClassFactory(academic_year=their_year, school=elsewhere)
            ),
            subject=factories.SubjectFactory(
                department=factories.DepartmentFactory(school=elsewhere), school=elsewhere
            ),
            title="Theirs",
            created_by=factories.UserFactory(school=elsewhere, role=UserRole.SCHOOL_ADMIN),
        )

        response = self.client.get(URL)

        self.assertNotIn("Theirs", [row["title"] for row in response.data["data"]])

    def test_a_school_id_in_the_query_string_does_not_widen_the_list(self):
        elsewhere = factories.SchoolFactory()

        response = self.client.get(URL, {"school_id": elsewhere.id})

        self.assertEqual(3, len(response.data["data"]), "their own school, not somebody else's")

    def test_the_list_filters_by_term_section_subject_type_and_status(self):
        self.existing(title="A quiz", type="quiz")

        self.assertEqual(
            ["A quiz"], [row["title"] for row in self.client.get(URL, {"type": "quiz"}).data["data"]]
        )
        self.assertEqual(4, len(self.client.get(URL, {"academic_term_id": self.term.id}).data["data"]))
        self.assertEqual(
            2, len(self.client.get(URL, {"class_section_id": self.section.id, "subject_id": self.subject.id}).data["data"])
        )
        self.assertEqual(4, len(self.client.get(URL, {"status": "draft"}).data["data"]))
        self.assertEqual(0, len(self.client.get(URL, {"status": "published"}).data["data"]))

    def test_the_newest_test_reads_first(self):
        self.existing(title="Later", assessment_date=dt.date(2026, 5, 20))

        response = self.client.get(URL)

        self.assertEqual("Later", response.data["data"][0]["title"])
