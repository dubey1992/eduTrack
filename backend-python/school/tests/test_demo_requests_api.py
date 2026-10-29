"""Demo requests (decided 2026-10-29): the marketing page's "Request a Demo"
form and the Super Admin's list of them.

Asking is public and throttled; one open request per address, filled in but
never overwritten; the Super Admins are emailed through the queue; reading
and updating the list is the Super Admin's alone.
"""

import datetime as dt
from unittest import mock

from django.core import mail
from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, jobs, queue, tokens
from school.enums import UserRole
from school.models import AuditLog, DemoRequest, QueuedJob

URL = "/api/v1/demo-requests"
NOW = dt.datetime(2026, 10, 29, 6, 0, tzinfo=dt.timezone.utc)


def client_for(user=None) -> APIClient:
    client = APIClient()
    if user is not None:
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

    return client


def form(**overrides) -> dict:
    return {
        "contact_name": "Priya Nair",
        "school_name": "Greenfield High",
        "email": "priya@greenfield.test",
        "phone": "+91 9876543210",
        "city": "Pune",
        "country": "India",
        "expected_students": 850,
        "preferred_date": "2026-11-05",
        "preferred_time": "morning",
        "timezone": "Asia/Kolkata",
        "message": "We would like to see attendance and fees.",
        **overrides,
    }


class DemoRequestTestCase(TestCase):
    def setUp(self):
        cache.clear()
        clock = mock.patch("django.utils.timezone.now", return_value=NOW)
        clock.start()
        self.addCleanup(clock.stop)
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN, email="root@school365ai.test")

    def ask(self, **overrides):
        return client_for().post(URL, form(**overrides), format="json")

    def errors(self, response) -> dict:
        self.assertEqual(422, response.status_code, response.data)

        return response.data["details"]["errors"]


class Asking(DemoRequestTestCase):
    def test_a_request_is_kept_and_the_super_admin_told_through_the_queue(self):
        response = self.ask()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("Thanks - we will be in touch to confirm a time for your demo.", response.data["message"])
        request = DemoRequest.objects.get()
        self.assertEqual(
            ("Greenfield High", dt.date(2026, 11, 5), "morning", "Asia/Kolkata", "new"),
            (request.school_name, request.preferred_date, request.preferred_time, request.timezone, request.status),
        )
        self.assertEqual(["demo_request_email"], list(QueuedJob.objects.values_list("name", flat=True)))
        self.assertTrue(AuditLog.objects.filter(entity_type="demo_request", entity_id=request.id).exists())

    def test_what_is_required(self):
        response = client_for().post(URL, {}, format="json")

        self.assertEqual(
            {"contact_name", "school_name", "email", "phone", "country", "preferred_date"},
            set(self.errors(response)),
        )

    def test_the_optional_parts_may_be_left_out(self):
        response = self.ask(city="", expected_students=None, preferred_time="", timezone="", message="")

        self.assertEqual(201, response.status_code, response.data)
        request = DemoRequest.objects.get()
        self.assertEqual((None, None, None, None), (request.city, request.preferred_time, request.timezone,
                                                    request.expected_students))

    def test_a_phone_needs_its_country_code(self):
        self.assertEqual(
            {"phone": ["Include the country code, like +91 9876543210."]}, self.errors(self.ask(phone="98765"))
        )

    def test_the_day_is_not_past_and_not_too_far_off(self):
        self.assertEqual({"preferred_date": ["Pick a day that has not passed."]},
                         self.errors(self.ask(preferred_date="2026-10-20")))
        self.assertEqual({"preferred_date": ["Pick a day within the next six months."]},
                         self.errors(self.ask(preferred_date="2027-06-01")))
        # Yesterday by the platform's date is still today somewhere.
        self.assertEqual(201, self.ask(preferred_date="2026-10-28").status_code)

    def test_a_part_of_the_day_or_nothing(self):
        self.assertEqual({"preferred_time": ["Pick morning, afternoon or evening."]},
                         self.errors(self.ask(preferred_time="midnight")))

    def test_an_unknown_timezone_is_dropped_rather_than_refused(self):
        self.assertEqual(201, self.ask(timezone="Mars/Olympus").status_code)

        self.assertIsNone(DemoRequest.objects.get().timezone)

    def test_asking_again_keeps_the_first_and_never_overwrites_it(self):
        self.ask(city="", school_name="Greenfield High")
        self.ask(city="Mumbai", school_name="Someone Else's School")

        request = DemoRequest.objects.get()
        self.assertEqual(("Greenfield High", "Mumbai"), (request.school_name, request.city))
        self.assertEqual(1, QueuedJob.objects.count(), "the Super Admin is told once")
        self.assertTrue(AuditLog.objects.filter(action="demo_request.asked_again").exists())

    def test_asking_after_the_first_is_done_is_a_new_request(self):
        self.ask()
        DemoRequest.objects.update(status="done")

        self.ask()

        self.assertEqual(2, DemoRequest.objects.count())

    def test_the_form_is_throttled(self):
        statuses = [self.ask(email=f"p{n}@greenfield.test").status_code for n in range(6)]

        self.assertEqual([201] * 5 + [429], statuses)


class TheEmail(DemoRequestTestCase):
    def test_every_active_super_admin_is_told_and_a_reply_goes_to_the_school(self):
        factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN, email="second@school365ai.test")
        factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN, email="gone@school365ai.test",
                              status="inactive")
        self.ask()

        jobs.send_demo_request_email(DemoRequest.objects.get().id)

        sent = mail.outbox[0]
        self.assertEqual("Demo request: Greenfield High", sent.subject)
        self.assertEqual({"root@school365ai.test", "second@school365ai.test"}, set(sent.to))
        self.assertEqual(["priya@greenfield.test"], sent.reply_to)
        self.assertIn("Preferred: 11/05/2026, morning (Asia/Kolkata)", sent.body)
        self.assertIn("Phone: +91 9876543210", sent.body)

    def test_the_queued_job_runs_it(self):
        self.ask()

        job = queue.reserve()
        queue.run(job)

        self.assertEqual(1, len(mail.outbox))


class TheList(DemoRequestTestCase):
    def test_the_super_admin_reads_it_newest_first(self):
        self.ask(email="first@greenfield.test", school_name="First School")
        self.ask(email="second@greenfield.test", school_name="Second School")

        response = client_for(self.root).get(URL)

        self.assertEqual(200, response.status_code)
        self.assertEqual(["Second School", "First School"], [row["school_name"] for row in response.data["data"]])
        row = response.data["data"][0]
        self.assertEqual(("2026-11-05", "Morning", "New"),
                         (row["preferred_date"], row["preferred_time_label"], row["status_label"]))
        self.assertEqual(2, response.data["meta"]["total"])

    def test_filtered_by_status_and_searched(self):
        self.ask(email="first@greenfield.test", school_name="First School")
        self.ask(email="second@greenfield.test", school_name="Second School")
        DemoRequest.objects.filter(school_name="First School").update(status="scheduled")

        scheduled = client_for(self.root).get(URL, {"status": "scheduled"}).data["data"]
        searched = client_for(self.root).get(URL, {"q": "second"}).data["data"]

        self.assertEqual(["First School"], [row["school_name"] for row in scheduled])
        self.assertEqual(["Second School"], [row["school_name"] for row in searched])

    def test_nobody_else_reads_it(self):
        school_admin = factories.UserFactory(role=UserRole.SCHOOL_ADMIN)

        self.assertEqual(401, client_for().get(URL).status_code)
        self.assertEqual(403, client_for(school_admin).get(URL).status_code)

    def test_the_super_admin_records_what_was_done(self):
        self.ask()
        request = DemoRequest.objects.get()

        response = client_for(self.root).patch(
            f"{URL}/{request.id}", {"status": "scheduled", "notes": "Booked for 11am IST."}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(("scheduled", "Booked for 11am IST.", self.root.name),
                         (response.data["status"], response.data["notes"], response.data["reviewed_by_name"]))
        self.assertTrue(AuditLog.objects.filter(action="demo_request.reviewed").exists())

    def test_an_unknown_status_is_refused(self):
        self.ask()
        request = DemoRequest.objects.get()

        response = client_for(self.root).patch(f"{URL}/{request.id}", {"status": "maybe"}, format="json")

        self.assertEqual({"status": ["The selected status is invalid."]}, self.errors(response))

    def test_nobody_else_updates_it(self):
        self.ask()
        request = DemoRequest.objects.get()
        school_admin = factories.UserFactory(role=UserRole.SCHOOL_ADMIN)

        response = client_for(school_admin).patch(f"{URL}/{request.id}", {"status": "done"}, format="json")

        self.assertEqual(403, response.status_code)
        self.assertEqual("new", DemoRequest.objects.get().status)
