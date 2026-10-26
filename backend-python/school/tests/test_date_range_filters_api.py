"""Day / week / month in the apps: `date_from` and `date_to` on every list the
staff app filters (docs/teacher-app.md, "Filters by period").

Both ends are inclusive dates on the school's calendar. A date that cannot be
read is no filter at all - the same as a junk id - never a 500.
"""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import MessageChannel, MessageStatus, UserRole
from school.tests import test_assessments_api as assessment_tests
from school.tests import test_teaching_reports_api as report_tests


def client_for(user) -> APIClient:
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))
    return client


class ReportsByPeriod(report_tests.TeachingReportCase):
    def setUp(self):
        super().setUp()
        self.monday = self.file(report_date="2026-09-14").data["id"]
        self.next_monday = self.file(report_date="2026-09-21").data["id"]

    def ids(self, **query):
        response = self.as_user(self.teacher).get("/api/v1/teaching-reports", {"mine": 1, **query})
        self.assertEqual(200, response.status_code)
        return sorted(row["id"] for row in response.data["data"])

    def test_a_day(self):
        self.assertEqual([self.monday], self.ids(date_from="2026-09-14", date_to="2026-09-14"))

    def test_a_week_includes_both_ends(self):
        self.assertEqual([self.next_monday], self.ids(date_from="2026-09-21", date_to="2026-09-27"))

    def test_a_month(self):
        self.assertEqual(sorted([self.monday, self.next_monday]), self.ids(date_from="2026-09-01", date_to="2026-09-30"))

    def test_a_date_that_is_not_one_is_no_filter(self):
        self.assertEqual(sorted([self.monday, self.next_monday]), self.ids(date_from="last-tuesday"))


class TestsByPeriod(assessment_tests.AssessmentTestCase):
    def setUp(self):
        super().setUp()
        self.april = self.existing(assessment_date=dt.date(2026, 4, 15))
        self.may = self.existing(assessment_date=dt.date(2026, 5, 4))

    def ids(self, **query):
        response = self.as_user(self.teacher).get("/api/v1/assessments", {"mine": 1, **query})
        self.assertEqual(200, response.status_code)
        return [row["id"] for row in response.data["data"]]

    def test_only_the_tests_sat_in_the_range(self):
        self.assertEqual([self.may.id], self.ids(date_from="2026-05-01", date_to="2026-05-31"))
        self.assertEqual([self.april.id], self.ids(date_from="2026-04-15", date_to="2026-04-15"))


class LeaveByPeriod(TestCase):
    """Any request that touches the range - leave that started last week and
    runs into this one belongs to this week too."""

    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        profile = factories.StaffProfileFactory(school=self.school, user=self.teacher)
        self.across = factories.StaffLeaveFactory(
            staff_profile=profile, start_date=dt.date(2026, 9, 18), end_date=dt.date(2026, 9, 22)
        )
        self.later = factories.StaffLeaveFactory(
            staff_profile=profile, start_date=dt.date(2026, 10, 5), end_date=dt.date(2026, 10, 5)
        )

    def ids(self, **query):
        response = client_for(self.teacher).get("/api/v1/leaves", {"mine": 1, **query})
        self.assertEqual(200, response.status_code)
        return [row["id"] for row in response.data["data"]]

    def test_leave_overlapping_the_week_is_in_it(self):
        self.assertEqual([self.across.id], self.ids(date_from="2026-09-21", date_to="2026-09-27"))

    def test_leave_outside_the_range_is_not(self):
        self.assertEqual([], self.ids(date_from="2026-09-23", date_to="2026-10-04"))


class InboxByPeriod(TestCase):
    """By the day a message arrived at the school: a Kolkata school's day
    starts at 18:30 UTC the evening before."""

    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(timezone="Asia/Kolkata")
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

    def message(self, at: dt.datetime):
        return factories.MessageFactory(
            school=self.school, event="general.message", category="general", channel=MessageChannel.IN_APP,
            recipient_name=self.teacher.name, user=self.teacher, body="Hello", status=MessageStatus.SENT,
            created_at=at,
        )

    def ids(self, **query):
        response = client_for(self.teacher).get("/api/v1/inbox", query)
        self.assertEqual(200, response.status_code)
        return [row["id"] for row in response.data["data"]]

    def test_a_day_is_the_schools_day_not_utcs(self):
        utc = dt.timezone.utc
        # 26 October 00:30 in Kolkata is 25 October 19:00 UTC.
        early = self.message(dt.datetime(2026, 10, 25, 19, 0, tzinfo=utc))
        # 25 October 23:00 in Kolkata is 25 October 17:30 UTC.
        late_evening_before = self.message(dt.datetime(2026, 10, 25, 17, 30, tzinfo=utc))

        self.assertEqual([early.id], self.ids(date_from="2026-10-26", date_to="2026-10-26"))
        self.assertEqual([late_evening_before.id], self.ids(date_from="2026-10-25", date_to="2026-10-25"))
