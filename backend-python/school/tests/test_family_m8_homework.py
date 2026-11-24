"""Homework for parents (docs/mobile-apps-review.md, M8, 8.1): what the
teacher wrote in the Homework box, shown to the parents of that class, and
one evening push a day.
"""

import datetime as dt

from school import factories, family_homework
from school.clock import SchoolClock
from school.enums import MessageEvent
from school.models import Message, ModuleSetting

from . import test_family_f1_api as f1
from . import test_family_f2_api as f2

FAMILY = f1.FAMILY


class HomeworkTest(f2.LearningTest):
    def setUp(self):
        super().setUp()
        self.english = factories.SubjectFactory(department__school=self.school, name="English")
        self.maths_period = factories.TimetableEntryFactory(class_section=self.class_section, subject=self.maths)
        self.english_period = factories.TimetableEntryFactory(class_section=self.class_section, subject=self.english)

    def report(self, entry, homework, days_ago=0):
        return factories.DailyTeachingReportFactory(
            timetable_entry=entry, report_date=self.today() - dt.timedelta(days=days_ago), homework=homework,
        )

    def homework(self, child=None):
        response = self.parent.get(f"{FAMILY}/children/{(child or self.child).id}/homework")
        return response

    def evening(self, hour=18, minute=30):
        """An instant at [hour]:[minute] today on the school's clock."""
        clock = SchoolClock.for_school(self.school)
        return clock.now().replace(hour=hour, minute=minute, second=0, microsecond=0)


class ParentsSeeHomework(HomeworkTest):
    def test_what_the_teacher_wrote_is_shown_under_its_day_newest_first(self):
        self.report(self.maths_period, "Exercise 4.2, questions 1-10")
        self.report(self.english_period, "Read chapter 3", days_ago=2)

        response = self.homework()

        self.assertEqual(200, response.status_code, response.data)
        days = response.data["days"]
        self.assertEqual(2, len(days))
        self.assertTrue(days[0]["today"])
        self.assertEqual(
            [("Mathematics", "Exercise 4.2, questions 1-10")],
            [(item["subject"], item["homework"]) for item in days[0]["items"]],
        )
        self.assertEqual("Read chapter 3", days[1]["items"][0]["homework"])

    def test_a_report_with_no_homework_is_left_out(self):
        self.report(self.maths_period, None)
        self.report(self.english_period, "")

        self.assertEqual([], self.homework().data["days"])

    def test_only_the_childs_own_class(self):
        other_section = factories.ClassSectionFactory(school_class=self.class_section.school_class, name="B")
        elsewhere = factories.TimetableEntryFactory(class_section=other_section, subject=self.maths)
        self.report(elsewhere, "Not for this class")

        self.assertEqual([], self.homework().data["days"])

    def test_older_than_two_weeks_is_not_shown(self):
        self.report(self.maths_period, "Long ago", days_ago=family_homework.DAYS_SHOWN)

        self.assertEqual([], self.homework().data["days"])

    def test_another_familys_child_is_refused(self):
        stranger = self.other_family_child()

        self.assertIn(self.homework(stranger).status_code, (403, 404))

    def test_signing_in_is_required(self):
        from rest_framework.test import APIClient

        self.assertEqual(401, APIClient().get(f"{FAMILY}/children/{self.child.id}/homework").status_code)


class TheEveningPush(HomeworkTest):
    def sent(self):
        return Message.objects.filter(event=MessageEvent.HOMEWORK_FOR_FAMILY, student=self.child)

    def test_after_six_the_family_is_told_how_many_and_in_what(self):
        self.report(self.maths_period, "Exercise 4.2")
        self.report(self.english_period, "Read chapter 3")

        family_homework.send_digest(at=self.evening(), school_id=self.school.id)

        message = self.sent().get()
        self.assertIn("2 homework items for today: Mathematics, English", message.body)

    def test_not_before_six(self):
        self.report(self.maths_period, "Exercise 4.2")

        family_homework.send_digest(at=self.evening(hour=17, minute=45), school_id=self.school.id)

        self.assertFalse(self.sent().exists())

    def test_once_a_day_however_often_the_job_runs(self):
        self.report(self.maths_period, "Exercise 4.2")

        for minute in (0, 15, 30):
            family_homework.send_digest(at=self.evening(hour=19, minute=minute), school_id=self.school.id)

        self.assertEqual(1, self.sent().count())

    def test_a_day_with_no_homework_sends_nothing(self):
        self.report(self.maths_period, None)

        self.assertEqual(0, family_homework.send_digest(at=self.evening(), school_id=self.school.id))

    def test_not_for_a_school_without_the_family_app(self):
        self.report(self.maths_period, "Exercise 4.2")
        ModuleSetting.objects.filter(school=self.school, module="family_app").update(school_enabled=False)

        family_homework.send_digest(at=self.evening(), school_id=self.school.id)

        self.assertFalse(self.sent().exists())


class TheParentsSwitch(HomeworkTest):
    """Homework has a switch of its own in the Family app's settings."""

    def sent(self):
        return Message.objects.filter(event=MessageEvent.HOMEWORK_FOR_FAMILY, student=self.child)

    def test_offered_and_on_until_the_parent_turns_it_off(self):
        response = self.parent.get(f"{FAMILY}/notification-settings")

        self.assertEqual(200, response.status_code, response.data)
        self.assertIs(True, response.data["homework"])

    def test_a_parent_who_turned_it_off_is_not_told(self):
        changed = self.parent.patch(f"{FAMILY}/notification-settings", {"homework": False}, format="json")
        self.assertEqual(200, changed.status_code, changed.data)
        self.report(self.maths_period, "Exercise 4.2")

        family_homework.send_digest(at=self.evening(), school_id=self.school.id)

        self.assertFalse(self.sent().exists())

    def test_turning_homework_off_leaves_results_on(self):
        self.parent.patch(f"{FAMILY}/notification-settings", {"homework": False}, format="json")

        data = self.parent.get(f"{FAMILY}/notification-settings").data
        self.assertEqual((False, True), (data["homework"], data["result"]))


class WhereItOpens(HomeworkTest):
    def test_a_tapped_homework_push_and_its_link_open_homework(self):
        from school import message_links, push

        self.report(self.maths_period, "Exercise 4.2")
        family_homework.send_digest(at=self.evening(), school_id=self.school.id)
        message = Message.objects.get(event=MessageEvent.HOMEWORK_FOR_FAMILY, student=self.child)

        self.assertEqual("/homework", push.route_for(message))
        self.assertTrue(message_links.family_link(MessageEvent.HOMEWORK_FOR_FAMILY).endswith("/f/homework"))
