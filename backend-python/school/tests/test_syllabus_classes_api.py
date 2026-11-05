"""A syllabus topic belongs to a class (decided 2026-11-05).

Computer Science for Playgroup is not Computer Science for Class 9: a topic is
written for a class, every section of that class shares it, and no other class
sees it. Filed by class *level*, so it carries from one academic year to the
next. A topic written before this has no class and still reaches every class.
"""

from django.utils import timezone

from school import factories
from school.models import SyllabusTopic, SyllabusTopicProgress

from .test_syllabus_api import SyllabusTestCase


class ClassSyllabusTestCase(SyllabusTestCase):
    def setUp(self):
        super().setUp()
        self.year = self.section.school_class.academic_year
        self.five = self.section.school_class
        self.five.level = 5
        self.five.save()
        # Another section of Class 5, and a Class 9.
        self.five_b = factories.ClassSectionFactory(school_class=self.five, name="B")
        self.nine = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(school=self.school, academic_year=self.year, level=9)
        )

    def topic(self, title, level, number):
        now = timezone.now()
        return SyllabusTopic.objects.create(
            school=self.school, subject=self.subject, class_level=level, title=title, sequence_number=number,
            created_at=now, updated_at=now,
        )

    def titles(self, response):
        self.assertEqual(200, response.status_code, response.data)
        rows = response.data["topics"] if isinstance(response.data, dict) and "topics" in response.data else response.data
        return [row["title"] for row in rows]

    def checklist(self, section, user=None):
        return self.as_user(user or self.admin).get(
            f"/api/v1/syllabus-progress?subject_id={self.subject.id}&class_section_id={section.id}"
        )

    def add(self, **body):
        payload = {"subject_id": self.subject.id, "title": "Fractions", "sequence_number": 1, **body}
        return self.as_user(self.admin).post("/api/v1/syllabus-topics", payload, format="json")


class Adding(ClassSyllabusTestCase):
    def test_a_topic_is_filed_for_its_class(self):
        response = self.add(class_level=5)

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual((5, "Class 5"), (response.data["class_level"], response.data["class_level_name"]))

    def test_each_class_numbers_its_own_topics_from_one(self):
        self.assertEqual(201, self.add(class_level=5).status_code)

        self.assertEqual(201, self.add(class_level=9, title="Polynomials").status_code)

    def test_a_number_taken_in_the_same_class_is_refused(self):
        self.add(class_level=5)

        response = self.add(class_level=5, title="Decimals")

        self.assertEqual(422, response.status_code)
        self.assertIn("sequence_number", self.errors(response))

    def test_a_class_the_subject_is_not_taught_in_is_refused(self):
        self.subject.min_class_level, self.subject.max_class_level = 3, 12
        self.subject.save()

        response = self.add(class_level=-3)

        self.assertEqual(422, response.status_code)
        self.assertIn("Playgroup", self.errors(response)["class_level"][0])

    def test_a_level_outside_the_school_years_is_refused(self):
        self.assertEqual(422, self.add(class_level=13).status_code)


class WhoSeesWhat(ClassSyllabusTestCase):
    def setUp(self):
        super().setUp()
        self.topic("Fractions", 5, 1)
        self.topic("Polynomials", 9, 1)
        self.topic("Revision", None, 1)

    def test_a_class_sees_its_own_topics_and_those_for_every_class(self):
        self.assertEqual(["Revision", "Fractions"], self.titles(self.checklist(self.section)))

    def test_every_section_of_the_class_shares_them(self):
        self.assertEqual(self.titles(self.checklist(self.section)), self.titles(self.checklist(self.five_b)))

    def test_another_class_does_not_see_them(self):
        self.assertEqual(["Revision", "Polynomials"], self.titles(self.checklist(self.nine)))

    def test_the_checklist_says_whose_syllabus_it_is(self):
        data = self.checklist(self.section).data

        self.assertEqual((5, "Class 5", 2), (data["class_level"], data["class_level_name"], data["total_topics"]))

    def test_the_list_narrows_to_a_named_section(self):
        response = self.as_user(self.teacher).get(
            f"/api/v1/syllabus-topics?subject_id={self.subject.id}&class_section_id={self.nine.id}"
        )

        self.assertEqual(["Revision", "Polynomials"], self.titles(response))

    def test_without_a_class_the_list_is_the_whole_outline(self):
        response = self.as_user(self.admin).get(f"/api/v1/syllabus-topics?subject_id={self.subject.id}")

        self.assertEqual({"Revision", "Fractions", "Polynomials"}, set(self.titles(response)))

    def test_a_topic_without_a_class_says_it_is_for_every_class(self):
        response = self.as_user(self.admin).get(f"/api/v1/syllabus-topics?subject_id={self.subject.id}")
        revision = next(row for row in response.data if row["title"] == "Revision")

        self.assertEqual((None, "All classes"), (revision["class_level"], revision["class_level_name"]))


class Ticking(ClassSyllabusTestCase):
    def tick(self, topic, section):
        return self.as_user(self.teacher).patch(
            "/api/v1/syllabus-progress",
            {"syllabus_topic_id": topic.id, "class_section_id": section.id, "completed": True},
            format="json",
        )

    def test_another_class_topic_cannot_be_ticked_off(self):
        response = self.tick(self.topic("Polynomials", 9, 1), self.section)

        self.assertEqual(422, response.status_code)
        self.assertIn("Class 9", self.errors(response)["class_section_id"][0])
        self.assertFalse(SyllabusTopicProgress.objects.exists())

    def test_its_own_topic_is_ticked_off(self):
        self.assertEqual(200, self.tick(self.topic("Fractions", 5, 1), self.section).status_code)


class Moving(ClassSyllabusTestCase):
    def test_a_topic_without_a_class_is_given_one(self):
        topic = self.topic("Fractions", None, 1)

        response = self.as_user(self.admin).patch(f"/api/v1/syllabus-topics/{topic.id}", {"class_level": 5},
                                                  format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual([], self.titles(self.checklist(self.nine)))
        self.assertEqual(["Fractions"], self.titles(self.checklist(self.section)))

    def test_moving_onto_a_taken_number_is_refused(self):
        self.topic("Fractions", 5, 1)
        loose = self.topic("Decimals", None, 1)

        response = self.as_user(self.admin).patch(f"/api/v1/syllabus-topics/{loose.id}", {"class_level": 5},
                                                  format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("sequence_number", self.errors(response))


class Counting(ClassSyllabusTestCase):
    def test_the_teachers_list_counts_only_their_class_topics(self):
        self.topic("Fractions", 5, 1)
        self.topic("Polynomials", 9, 1)
        self.topic("Revision", None, 1)

        rows = self.as_user(self.teacher).get("/api/v1/syllabus-progress/mine").data["data"]
        row = next(r for r in rows if r["class_section_id"] == self.section.id)

        self.assertEqual(2, row["total_topics"])


class Reporting(ClassSyllabusTestCase):
    """A teaching report ticks its topic off for the class, so it may only
    name one that class follows."""

    def report(self, topic):
        import datetime as dt

        from school.models import TimetableEntry

        factories.reports_without_attendance(self.school)
        entry = TimetableEntry.objects.get(class_section=self.section)
        today = dt.date.today()
        day = today - dt.timedelta(days=(today.weekday() - ["monday", "tuesday", "wednesday", "thursday", "friday",
                                                               "saturday", "sunday"].index(entry.day_of_week)) % 7 or 7)
        return self.as_user(self.teacher).post("/api/v1/teaching-reports", {
            "timetable_entry_id": entry.id, "report_date": day.isoformat(), "topic_taught": "Fractions",
            "syllabus_topic_id": topic.id,
        }, format="json")

    def test_another_class_topic_is_refused(self):
        response = self.report(self.topic("Polynomials", 9, 1))

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("Class 9", self.errors(response)["syllabus_topic_id"][0])

    def test_its_own_class_topic_is_taken(self):
        self.assertEqual(201, self.report(self.topic("Fractions", 5, 1)).status_code)


class ForAPeriod(ClassSyllabusTestCase):
    def test_the_list_narrows_to_a_periods_class(self):
        from school.models import TimetableEntry

        self.topic("Fractions", 5, 1)
        self.topic("Polynomials", 9, 1)
        entry = TimetableEntry.objects.get(class_section=self.section)

        response = self.as_user(self.teacher).get(
            f"/api/v1/syllabus-topics?subject_id={self.subject.id}&timetable_entry_id={entry.id}"
        )

        self.assertEqual(["Fractions"], self.titles(response))
