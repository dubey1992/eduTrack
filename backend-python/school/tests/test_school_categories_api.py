"""School categories (docs/school-categories.md), over HTTP and in the jobs
they change.

Monday 14 September 2026 on a UTC platform calendar. A school is demo, in
trial, live or testing - beside its status, never instead of it. A trial
carries the day it ends, and ending only ever warns. Platform figures are
live and trial schools alone, and a testing school never sends an SMS or a
WhatsApp on School365ai's account.
"""

import datetime as dt
from unittest import mock

from django.core.cache import cache
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from school import factories, jobs, marketing, tokens
from school.enums import UserRole
from school.models import AuditLog, Message, School
from school.views import marketing_content

NOW = dt.datetime(2026, 9, 14, 12, 0, tzinfo=dt.timezone.utc)


def a_payload(**overrides) -> dict:
    body = {
        "name": "Greenfield Academy",
        "email": "head@greenfield.invalid",
        "phone": "+234 8000000000",
        "address": "1 Test Road",
        "city": "Lagos",
        "state": "Lagos",
        "country": "Nigeria",
        "postal_code": "100001",
        "currency_code": "NGN",
        "timezone": "Africa/Lagos",
    }
    body.update(overrides)

    return body


def client_for(user) -> APIClient:
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

    return client


@override_settings(PLATFORM_TIMEZONE="UTC")
class CategoryTestCase(TestCase):
    def setUp(self):
        cache.clear()
        clock = mock.patch("django.utils.timezone.now", return_value=NOW)
        clock.start()
        self.addCleanup(clock.stop)

        self.root = client_for(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

    def errors(self, response) -> dict:
        self.assertEqual(422, response.status_code, response.data)

        return response.data["details"]["errors"]


class Creating(CategoryTestCase):
    def test_a_school_left_uncategorised_is_live(self):
        response = self.root.post("/api/v1/schools", a_payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(("live", "Live", None), (response.data["category"], response.data["category_label"],
                                                  response.data["trial_ends_on"]))

    def test_a_trial_carries_the_day_it_ends_and_how_long_is_left(self):
        response = self.root.post(
            "/api/v1/schools", a_payload(category="trial", trial_ends_on="2026-10-14"), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(("In Trial", "10/14/2026", 30), (response.data["category_label"],
                                                         response.data["trial_ends_label"],
                                                         response.data["trial_days_left"]))

    def test_a_trial_without_an_end_or_already_over_is_refused(self):
        missing = self.root.post("/api/v1/schools", a_payload(category="trial"), format="json")
        past = self.root.post(
            "/api/v1/schools", a_payload(category="trial", trial_ends_on="2026-09-13"), format="json"
        )

        self.assertEqual({"trial_ends_on": ["Enter the day the trial ends."]}, self.errors(missing))
        self.assertEqual({"trial_ends_on": ["The trial cannot end before today."]}, self.errors(past))

    def test_an_end_date_on_anything_but_a_trial_is_dropped(self):
        response = self.root.post(
            "/api/v1/schools", a_payload(category="demo", trial_ends_on="2026-10-14"), format="json"
        )

        self.assertEqual(("demo", None), (response.data["category"], response.data["trial_ends_on"]))

    def test_an_unknown_category_is_refused(self):
        response = self.root.post("/api/v1/schools", a_payload(category="premium"), format="json")

        self.assertEqual({"category": ["The selected category is invalid."]}, self.errors(response))


class Editing(CategoryTestCase):
    def setUp(self):
        super().setUp()
        self.school = factories.SchoolFactory(category="trial", trial_ends_on=dt.date(2026, 9, 1))

    def patch(self, client=None, **body):
        return (client or self.root).patch(f"/api/v1/schools/{self.school.id}", body, format="json")

    def test_moving_a_trial_to_live_clears_its_end_date_and_is_audited(self):
        response = self.patch(category="live")

        self.assertEqual(200, response.status_code, response.data)
        self.school.refresh_from_db()
        self.assertEqual(("live", None), (self.school.category, self.school.trial_ends_on))
        entry = AuditLog.objects.filter(entity_type="school", entity_id=self.school.id).latest("id")
        self.assertEqual(("trial", "live"), (entry.old_values["category"], entry.new_values["category"]))

    def test_an_ended_trial_saved_unchanged_is_not_refused(self):
        response = self.patch(name="Renamed", trial_ends_on="2026-09-01")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(-13, response.data["trial_days_left"])

    def test_extending_a_trial_into_the_past_is_refused(self):
        response = self.patch(trial_ends_on="2026-09-10")

        self.assertEqual({"trial_ends_on": ["The trial cannot end before today."]}, self.errors(response))

    def test_only_the_super_admin_categorises(self):
        for role in (UserRole.SCHOOL_ADMIN, UserRole.GROUP_ADMIN):
            with self.subTest(role=role):
                admin = client_for(factories.UserFactory(school=self.school, role=role))
                self.assertEqual(403, self.patch(admin, category="live").status_code)

        self.school.refresh_from_db()
        self.assertEqual("trial", self.school.category)


class Listing(CategoryTestCase):
    def test_the_school_list_filters_by_category(self):
        factories.SchoolFactory(name="Demo One", category="demo")
        factories.SchoolFactory(name="Live One")

        response = self.root.get("/api/v1/schools", {"category": "demo"})

        self.assertEqual(["Demo One"], [row["name"] for row in response.data["data"]])


class TheDashboard(CategoryTestCase):
    def dashboard(self) -> dict:
        response = self.root.get("/api/v1/dashboard")
        self.assertEqual(200, response.status_code, response.data)

        return response.data

    def test_demo_and_testing_schools_are_named_but_not_counted(self):
        factories.SchoolFactory()
        factories.SchoolFactory(category="demo")
        factories.SchoolFactory(category="testing")

        schools = next(card for card in self.dashboard()["cards"] if card["key"] == "schools")

        self.assertEqual(("1", "1 active, 2 demo or testing not counted"), (schools["value"], schools["hint"]))

    def test_trials_ended_or_ending_within_two_weeks_are_flagged_soonest_first(self):
        factories.SchoolFactory(name="Ended", category="trial", trial_ends_on=dt.date(2026, 9, 10))
        factories.SchoolFactory(name="Today", category="trial", trial_ends_on=dt.date(2026, 9, 14))
        factories.SchoolFactory(name="Soon", category="trial", trial_ends_on=dt.date(2026, 9, 15))
        factories.SchoolFactory(name="Later", category="trial", trial_ends_on=dt.date(2026, 10, 30))
        factories.SchoolFactory(name="Off", category="trial", trial_ends_on=dt.date(2026, 9, 1), status="inactive")

        notes = [note["message"] for note in self.dashboard()["attention"]]

        self.assertEqual(
            [
                "Ended's trial ended on 09/10/2026. Move it to Live, or make it inactive.",
                "Today's trial ends today.",
                "Soon's trial ends in 1 day, on 09/15/2026.",
            ],
            notes,
        )


class Sending(CategoryTestCase):
    def queued(self, category, channel):
        message = factories.MessageFactory(
            school=factories.SchoolFactory(category=category), channel=channel, status="queued",
            recipient_email="parent@example.invalid", sent_at=None,
        )
        jobs.send_message(message.id)

        return Message.objects.get(pk=message.id)

    def test_a_testing_school_sends_no_sms_or_whatsapp(self):
        for channel in ("sms", "whatsapp"):
            with self.subTest(channel=channel):
                message = self.queued("testing", channel)
                self.assertEqual(("skipped", "Not sent: this is a testing school."),
                                 (message.status, message.failure_reason))

    def test_a_demo_school_sends_its_sms_and_a_testing_school_its_email(self):
        self.assertEqual("sent", self.queued("demo", "sms").status)
        self.assertNotEqual("skipped", self.queued("testing", "email").status)


class TheHomepage(TestCase):
    def setUp(self):
        cache.clear()

    def test_the_homepage_counts_live_and_trial_schools_only(self):
        factories.SchoolFactory()
        factories.SchoolFactory(category="trial", trial_ends_on=dt.date(2026, 10, 1))
        factories.SchoolFactory(category="demo")
        factories.SchoolFactory(category="testing")

        self.assertEqual(2, marketing_content.figures()[marketing.SCHOOLS])
        self.assertEqual(4, School.objects.count())
