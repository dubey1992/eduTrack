"""The audit writer (school/audit.py): what it records, and what it never does."""

import datetime as dt
from decimal import Decimal

from django.test import RequestFactory, TestCase

from school import audit, factories
from school.models import AuditLog


class TheAuditLog(TestCase):
    def test_it_records_who_what_where_and_the_values_either_side(self):
        school = factories.SchoolFactory()
        actor = factories.UserFactory(school=school)
        request = RequestFactory().post("/", REMOTE_ADDR="203.0.113.9", HTTP_X_FORWARDED_FOR="10.0.0.1")

        entry = audit.record(
            actor=actor, action="salary.saved", module="payroll", entity_type="salary_profile", entity_id=7,
            school_id=school.id, old={"basic_salary": Decimal("100.00")},
            new={"basic_salary": Decimal("150.50"), "effective": dt.date(2026, 9, 1)}, request=request,
        )

        entry.refresh_from_db()
        self.assertEqual(
            (actor.id, school.id, "salary.saved", "payroll", "salary_profile", 7),
            (entry.user_id, entry.school_id, entry.action, entry.module, entry.entity_type, entry.entity_id),
        )
        self.assertEqual({"basic_salary": "100.00"}, entry.old_values)
        self.assertEqual({"basic_salary": "150.50", "effective": "2026-09-01"}, entry.new_values)
        # The address the connection came from - never a header the caller wrote.
        self.assertEqual("203.0.113.9", entry.ip)
        self.assertIsNotNone(entry.created_at)

    def test_it_never_stores_a_secret_however_deep(self):
        entry = audit.record(
            actor=None, action="user.updated", module="users", entity_type="user", entity_id=1, school_id=None,
            new={"password": "hunter2", "profile": {"token": "abc", "name": "Meena"}, "items": [{"remember_token": "x"}]},
        )

        entry.refresh_from_db()
        self.assertEqual({"profile": {"name": "Meena"}, "items": [{}]}, entry.new_values)
        self.assertIsNone(entry.user_id)
        self.assertEqual(1, AuditLog.objects.count())
