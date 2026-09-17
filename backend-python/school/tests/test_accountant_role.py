"""The Accountant, in every module that existed before payroll.

A new role is the riskiest kind of change for isolation: every place that
lists roles either forgets it - locking an employee out of something every
employee has - or, worse, falls through to a branch meant for admins. These
pin both directions for the modules an Accountant touches as an ordinary
employee. Payroll itself is tested in test_payroll_api.py.
"""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import StaffLeave

A_MONDAY = dt.date(2026, 9, 21)


class AccountantTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(timezone="UTC")
        self.department = factories.DepartmentFactory(school=self.school)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

        self.accountant = factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT)
        self.accountant_profile = factories.StaffProfileFactory(user=self.accountant, employee_id="ACC-1")

        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.teacher_profile = factories.StaffProfileFactory(user=self.teacher, employee_id="TCH-1")

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client


class BecomingAnAccountant(AccountantTest):
    def test_an_admin_adds_an_accountant_from_teachers_and_staff(self):
        response = self.as_user(self.admin).post(
            "/api/v1/staff",
            {
                "first_name": "Meena",
                "last_name": "Iyer",
                "email": "meena@example.invalid",
                "password": "AGoodPassword2026",
                "role": UserRole.ACCOUNTANT,
                "employee_id": "ACC-2",
                "designation": "Accountant",
                "joining_date": "2026-04-01",
            },
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(UserRole.ACCOUNTANT, response.data["role"])

    def test_a_school_admin_may_make_somebody_an_accountant_but_not_an_admin(self):
        client = self.as_user(self.admin)

        allowed = client.patch(f"/api/v1/users/{self.teacher.id}", {"role": UserRole.ACCOUNTANT}, format="json")
        refused = client.patch(f"/api/v1/users/{self.accountant.id}", {"role": UserRole.GROUP_ADMIN}, format="json")

        self.assertEqual(200, allowed.status_code, allowed.data)
        self.assertEqual(422, refused.status_code, refused.data)

    def test_the_accountant_cannot_add_staff_or_users(self):
        client = self.as_user(self.accountant)

        self.assertEqual(403, client.get("/api/v1/staff").status_code)
        self.assertEqual(403, client.get("/api/v1/users").status_code)


class AnOrdinaryEmployee(AccountantTest):
    def test_applies_for_leave_and_sees_only_their_own(self):
        StaffLeave.objects.create(
            school=self.school, staff_profile=self.teacher_profile, leave_type="casual", start_date=A_MONDAY,
            end_date=A_MONDAY, reason="Not the accountant's.", status="pending", applied_by=self.teacher,
        )
        client = self.as_user(self.accountant)

        applied = client.post(
            "/api/v1/leaves",
            {"leave_type": "casual", "start_date": "2026-09-22", "end_date": "2026-09-22", "reason": "Audit week."},
            format="json",
        )
        listed = client.get("/api/v1/leaves")
        summary = client.get("/api/v1/leaves/summary")

        self.assertEqual(201, applied.status_code, applied.data)
        self.assertEqual([self.accountant_profile.id], [row["staff_profile_id"] for row in listed.data["data"]])
        self.assertEqual(1, summary.data["pending"])

    def test_cannot_review_leave(self):
        leave = StaffLeave.objects.create(
            school=self.school, staff_profile=self.teacher_profile, leave_type="casual", start_date=A_MONDAY,
            end_date=A_MONDAY, reason="x", status="pending", applied_by=self.teacher,
        )

        response = self.as_user(self.accountant).patch(f"/api/v1/leaves/{leave.id}/approve", {}, format="json")

        self.assertEqual(403, response.status_code)

    def test_is_on_the_staff_register(self):
        response = self.as_user(self.admin).get("/api/v1/staff-attendance/register", {"date": "2026-09-14"})

        self.assertEqual(200, response.status_code, response.data)
        self.assertIn(self.accountant_profile.id, [row["staff_profile_id"] for row in response.data["staff"]])

    def test_reads_the_staff_attendance_report_and_no_other(self):
        client = self.as_user(self.accountant)
        query = {"from": "2026-09-01", "to": "2026-09-11"}

        self.assertEqual(200, client.get("/api/v1/reports/staff-attendance", query).status_code)
        for report in ("student-attendance", "teaching-coverage", "transport-usage"):
            with self.subTest(report=report):
                self.assertEqual(403, client.get(f"/api/v1/reports/{report}", query).status_code)

    def test_the_staff_attendance_report_is_their_own_school_only(self):
        other = factories.SchoolFactory(timezone="UTC")
        factories.StaffProfileFactory(user=factories.UserFactory(school=other, role=UserRole.TEACHER), employee_id="ELSE-1")

        rows = self.as_user(self.accountant).get(
            "/api/v1/reports/staff-attendance", {"from": "2026-09-01", "to": "2026-09-11", "school_id": other.id}
        ).data["rows"]

        self.assertEqual({"ACC-1", "TCH-1"}, {row["employee_id"] for row in rows})

    def test_has_no_admin_or_teaching_access(self):
        client = self.as_user(self.accountant)

        for path in ("/api/v1/students", "/api/v1/attendance", "/api/v1/payments", "/api/v1/communication/messages"):
            with self.subTest(path=path):
                self.assertEqual(403, client.get(path).status_code)

    def test_signs_in_and_gets_a_dashboard(self):
        response = self.as_user(self.accountant).get("/api/v1/dashboard")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual((UserRole.ACCOUNTANT, self.school.id), (response.data["role"], response.data["school_id"]))
