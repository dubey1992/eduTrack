"""Platform analytics, A7 (docs/analytics.md), over HTTP.

Monday 14 September 2026 on a UTC platform calendar. The whole of
School365ai, for the Super Admin alone: the roll and accounts now, each
month's new schools, sign-ins, messages, payments and requests, each school's
recent activity, and how many schools use each module. Payments are never
added across currencies.
"""

import datetime as dt
from decimal import Decimal
from unittest import mock

from django.core.cache import cache
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import AuditLog, DemoRequest, EarlyAccessRequest, Payment, School

URL = "/api/v1/analytics/platform"
NOW = dt.datetime(2026, 9, 14, 12, 0, tzinfo=dt.timezone.utc)
SPAN = {"from": "2026-08-01", "to": "2026-09-14"}


def client_for(user) -> APIClient:
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

    return client


def at(day: str, hour: int = 9) -> dt.datetime:
    return dt.datetime.combine(dt.date.fromisoformat(day), dt.time(hour), tzinfo=dt.timezone.utc)


@override_settings(PLATFORM_TIMEZONE="UTC")
class PlatformTestCase(TestCase):
    def setUp(self):
        cache.clear()
        clock = mock.patch("django.utils.timezone.now", return_value=NOW)
        clock.start()
        self.addCleanup(clock.stop)

        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        self.sunrise = factories.SchoolFactory(name="Sunrise School", city="Pune", timezone="UTC", currency_code="INR")
        self.lagos = factories.SchoolFactory(name="Lagos Academy", city="Lagos", timezone="UTC", currency_code="NGN")
        self.closed = factories.SchoolFactory(name="Closed School", timezone="UTC", status="inactive")
        School.objects.filter(pk=self.sunrise.pk).update(created_at=at("2026-09-02"))
        School.objects.filter(pk__in=[self.lagos.pk, self.closed.pk]).update(created_at=at("2026-08-10"))

        section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(
                academic_year=factories.AcademicYearFactory(school=self.sunrise), school=self.sunrise
            )
        )
        factories.StudentFactory(class_section=section)
        factories.StudentFactory(class_section=section)
        self.admin = factories.UserFactory(school=self.sunrise, role=UserRole.SCHOOL_ADMIN)
        factories.StaffProfileFactory(user=self.admin)

    def signed_in(self, user, when):
        AuditLog.objects.create(
            school_id=user.school_id, user=user, action="user.signed_in", module="auth", entity_type="user",
            entity_id=user.id, created_at=when,
        )

    def paid(self, school, amount, currency, day, status="paid"):
        Payment.objects.create(
            school=school, payment_type="setup_fee", amount=Decimal(amount), paid_amount=Decimal(amount),
            currency_code=currency, payment_date=dt.date.fromisoformat(day), payment_mode="upi", status=status,
            created_by=self.root, created_at=NOW, updated_at=NOW,
        )

    def look(self, user=None, **params):
        response = client_for(user or self.root).get(URL, {**SPAN, **params})
        self.assertEqual(200, response.status_code, getattr(response, "data", response))

        return response.data

    def month(self, data, start):
        return next(month for month in data["months"] if month["from"] == start)


class Now(PlatformTestCase):
    def test_the_roll_and_the_accounts_across_every_school(self):
        totals = self.look()["totals"]

        self.assertEqual(
            {"schools_active": 2, "schools_inactive": 1, "students": 2, "staff": 1},
            {key: totals[key] for key in ("schools_active", "schools_inactive", "students", "staff")},
        )


class MonthByMonth(PlatformTestCase):
    def test_new_schools_sign_ins_and_the_people_signing_in(self):
        other = factories.UserFactory(school=self.lagos, role=UserRole.SCHOOL_ADMIN)
        self.signed_in(self.admin, at("2026-09-03"))
        self.signed_in(self.admin, at("2026-09-04"))
        self.signed_in(other, at("2026-09-05"))
        self.signed_in(other, at("2026-08-20"))

        data = self.look()
        september, august = self.month(data, "2026-09-01"), self.month(data, "2026-08-01")

        self.assertEqual((1, 3, 2), (september["new_schools"], september["sign_ins"], september["active_users"]))
        self.assertEqual((2, 1, 1), (august["new_schools"], august["sign_ins"], august["active_users"]))

    def test_messages_per_channel_sent_and_failed(self):
        factories.MessageFactory(school=self.sunrise, channel="sms", status="sent", created_at=at("2026-09-03"))
        factories.MessageFactory(school=self.sunrise, channel="sms", status="failed", created_at=at("2026-09-03"))
        factories.MessageFactory(school=self.lagos, channel="whatsapp", status="sent", created_at=at("2026-09-04"))
        # Not sent anywhere: skipped, still queued, or the inbox.
        factories.MessageFactory(school=self.lagos, channel="sms", status="skipped", created_at=at("2026-09-04"))
        factories.MessageFactory(school=self.lagos, channel="in_app", status="sent", created_at=at("2026-09-04"))

        messages = self.month(self.look(), "2026-09-01")["messages"]

        self.assertEqual(
            {"sms": {"sent": 1, "failed": 1}, "whatsapp": {"sent": 1, "failed": 0}, "email": {"sent": 0, "failed": 0}},
            messages,
        )

    def test_payments_per_currency_never_added_together(self):
        self.paid(self.sunrise, "50000.00", "INR", "2026-09-02")
        self.paid(self.sunrise, "10000.00", "INR", "2026-09-09", status="partial")
        self.paid(self.lagos, "300000.00", "NGN", "2026-09-10")
        self.paid(self.lagos, "999.00", "NGN", "2026-09-11", status="cancelled")

        payments = self.month(self.look(), "2026-09-01")["payments"]

        self.assertEqual(
            [{"currency_code": "INR", "amount": "60000.00"}, {"currency_code": "NGN", "amount": "300000.00"}],
            payments,
        )

    def test_early_access_and_demo_requests(self):
        EarlyAccessRequest.objects.create(
            school_name="A", contact_name="B", email="a@x.test", phone="+911", city="C", country="IN", status="new",
            created_at=at("2026-09-01"), updated_at=NOW,
        )
        DemoRequest.objects.create(
            contact_name="D", school_name="E", email="d@x.test", phone="+912", country="IN",
            preferred_date=dt.date(2026, 9, 20), status="new", created_at=at("2026-09-08"), updated_at=NOW,
        )

        september = self.month(self.look(), "2026-09-01")

        self.assertEqual((1, 1), (september["early_access_requests"], september["demo_requests"]))


class EachSchool(PlatformTestCase):
    def test_busiest_first_with_the_school_that_has_gone_quiet_below(self):
        other = factories.UserFactory(school=self.lagos, role=UserRole.SCHOOL_ADMIN)
        self.signed_in(self.admin, at("2026-09-10"))
        self.signed_in(self.admin, at("2026-09-12"))
        self.signed_in(other, at("2026-07-01"))  # long before the last 30 days
        factories.MessageFactory(school=self.sunrise, channel="sms", status="sent", created_at=at("2026-09-12"))

        schools = self.look()["schools"]

        self.assertEqual(["Sunrise School", "Lagos Academy", "Closed School"], [s["name"] for s in schools])
        sunrise, lagos = schools[0], schools[1]
        self.assertEqual((2, 1, 2, 1), (sunrise["students"], sunrise["staff"], sunrise["recent_sign_ins"],
                                        sunrise["recent_messages"]))
        self.assertEqual("09/12/2026", sunrise["last_sign_in_label"])
        self.assertEqual((0, "07/01/2026"), (lagos["recent_sign_ins"], lagos["last_sign_in_label"]))
        self.assertIsNone(schools[2]["last_sign_in"])


class Modules(PlatformTestCase):
    def test_how_many_active_schools_have_each_module_on(self):
        factories.ModuleSettingFactory(school=self.lagos, module="transport", school_enabled=False)

        modules = {row["module"]: row for row in self.look()["modules"]}

        self.assertEqual((1, 2), (modules["transport"]["schools_on"], modules["transport"]["schools"]))
        self.assertEqual(2, modules["attendance"]["schools_on"])


class WhoSees(PlatformTestCase):
    def test_the_super_admin_alone(self):
        group = factories.UserFactory(school=self.sunrise, role=UserRole.GROUP_ADMIN)

        for user in (self.admin, group):
            with self.subTest(role=user.role):
                self.assertEqual(403, client_for(user).get(URL, SPAN).status_code)
        self.assertEqual(401, APIClient().get(URL).status_code)

    def test_the_range_is_checked(self):
        future = client_for(self.root).get(URL, {"to": "2026-12-01"})
        long = client_for(self.root).get(URL, {"from": "2024-01-01"})

        self.assertEqual({"to": ["Analytics cannot run past today."]}, future.data["details"]["errors"])
        self.assertEqual({"from": ["Platform analytics covers at most 24 months. Pick a shorter range."]},
                         long.data["details"]["errors"])

    def test_with_no_range_the_last_twelve_months(self):
        data = self.look(**{"from": "", "to": ""})

        self.assertEqual(12, len(data["months"]))
