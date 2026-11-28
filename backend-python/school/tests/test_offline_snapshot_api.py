"""What a trusted school computer keeps for working offline
(docs/offline-web.md, O2).

What this file guards: the snapshot is only what the person may already
see online - a teacher their own classes, staff only for those allowed to
see staff, fee dues only for fee roles - never another school's, and
nothing at all when the school has switched offline copies off.
"""

import datetime as dt
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import FeeHead, StudentFeeDue

URL = "/api/v1/offline/snapshot"


class SnapshotTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(currency_code="INR")
        self.year = factories.AcademicYearFactory(
            school=self.school, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        # Fees arrive off until the platform grants them.
        factories.ModuleSettingFactory(school=self.school, module="fees")
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.accountant = factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT)
        school_class = factories.SchoolClassFactory(school=self.school, academic_year=self.year, name="Class 6",
                                                    level=6)
        self.mine = factories.ClassSectionFactory(school_class=school_class, name="A", class_teacher=self.teacher)
        self.theirs = factories.ClassSectionFactory(school_class=school_class, name="B")
        self.asha = factories.StudentFactory(school=self.school, class_section=self.mine, first_name="Asha")
        self.kabir = factories.StudentFactory(school=self.school, class_section=self.theirs, first_name="Kabir")
        self.left = factories.StudentFactory(school=self.school, class_section=self.mine, first_name="Gone",
                                             status="inactive")
        factories.StaffProfileFactory(user=self.teacher)
        head = FeeHead.objects.create(school=self.school, name="Tuition", created_at=timezone.now(),
                                      updated_at=timezone.now())

        def due(student, label, amount, paid="0"):
            return StudentFeeDue.objects.create(
                school=self.school, student=student, academic_year=self.year, fee_head=head, label=label,
                due_date=dt.date(2026, 7, 10), amount=Decimal(amount), paid_amount=Decimal(paid), currency_code="INR",
                status="paid" if paid == amount else ("partial" if paid != "0" else "pending"),
                created_at=timezone.now(), updated_at=timezone.now(),
            )

        due(self.asha, "Term 1", "5000.00", paid="5000.00")
        self.term2 = due(self.asha, "Term 2", "5000.00", paid="1500.00")

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))
        return client

    def snapshot(self, user):
        response = self.as_user(user).get(URL)
        self.assertEqual(200, response.status_code, getattr(response, "data", None))
        return response.data

    def test_an_admin_gets_every_active_student_staff_and_dues(self):
        data = self.snapshot(self.admin)

        self.assertEqual({"Asha", "Kabir"}, {s["name"].split()[0] for s in data["students"]})
        self.assertEqual({"Class 6 A", "Class 6 B"}, {c["name"] for c in data["classes"]})
        self.assertEqual(1, len(data["staff"]))
        self.assertEqual("INR", data["school"]["currency_code"])
        self.assertIn("generated_at", data)

    def test_only_what_is_still_owed_is_kept(self):
        data = self.snapshot(self.admin)

        [line] = data["dues"][str(self.asha.id)]
        self.assertEqual(("Term 2", "3500.00", "INR"), (line["label"], line["balance"], line["currency_code"]))
        self.assertNotIn(str(self.kabir.id), data["dues"])

    def test_a_teacher_keeps_their_own_class_and_nothing_of_fees_or_staff(self):
        data = self.snapshot(self.teacher)

        self.assertEqual(["Asha"], [s["name"].split()[0] for s in data["students"]])
        self.assertIsNone(data["dues"])
        self.assertIsNone(data["staff"])

    def test_an_accountant_keeps_the_dues(self):
        data = self.snapshot(self.accountant)

        self.assertIsNotNone(data["dues"])

    def test_another_schools_records_never_appear(self):
        other = factories.SchoolFactory()
        factories.StudentFactory(school=other, first_name="Stranger")

        data = self.snapshot(self.admin)

        self.assertNotIn("Stranger", [s["name"].split()[0] for s in data["students"]])

    def test_a_school_that_switched_offline_copies_off_gets_nothing(self):
        factories.ModuleSettingFactory(school=self.school, module="students", settings={"offline_copies": False})
        cache.clear()

        response = self.as_user(self.admin).get(URL)

        self.assertEqual(403, response.status_code)
        self.assertEqual("OFFLINE_COPIES_OFF", response.data["code"])

    def test_me_says_whether_the_school_allows_offline_copies(self):
        self.assertTrue(self.as_user(self.admin).get("/api/v1/me").json()["offline_copies"])

    def test_the_bus_crew_and_signed_out_callers_are_refused(self):
        driver = factories.UserFactory(school=self.school, role=UserRole.DRIVER)

        self.assertEqual(403, self.as_user(driver).get(URL).status_code)
        self.assertEqual(401, APIClient().get(URL).status_code)

    def test_asking_too_often_is_slowed_down(self):
        client = self.as_user(self.teacher)
        codes = [client.get(URL).status_code for _ in range(13)]

        self.assertEqual([200] * 12 + [429], codes)
