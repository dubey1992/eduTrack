"""The audit trail across the app (Phase 21), and the screen that reads it.

Three kinds of check:

- **Nothing writes unrecorded.** A static sweep of the services: every method
  that creates, saves or deletes a row either records it or is on a short,
  named list of deliberate exceptions. A new write method that forgets fails
  here the day it is written.
- **What an entry says.** Before and after, only what changed, who, from
  where - and never a password.
- **Who may read it.** Each administrator their own scope; nobody else.
"""

import ast
import datetime as dt
import inspect
import io
from csv import reader
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import audit, factories, services, tokens
from school.enums import AttendanceStatus, UserRole
from school.models import AuditLog

# Methods that write without an entry of their own, and why. Anything not
# here that writes must record.
NOT_RECORDED = {
    # Called by entry points that record the change as a whole.
    "AttendanceService.submit", "AttendanceService.update", "StaffAttendanceService.submit",
    "StaffAttendanceService.update", "AcademicYearService._clear_current_for", "UserService.deactivate",
    # Demoting the old default is part of promoting the new one, and the
    # entry for that names both states.
    "GradeScaleService._clear_default_for",
    # A consequence of an approved leave, which is itself recorded.
    "StaffLeaveService.sync_attendance",
    # The trip's own timeline records each stop and rider, with who and when.
    "TransportTripService.reach_stop", "TransportTripService.update_rider", "TransportTripService.record",
    # A reader's own inbox, and a delivery retry: nobody's data changes.
    "MessageService.retry", "MessageService.mark_read", "MessageService.mark_all_read",
    # Retention housekeeping run by cron: old bus positions, nobody's change.
    "TripLocationService.purge",
}

WRITES = ("objects.create(", ".save(", ".delete()", "update_or_create(", "get_or_create(", ").update(")


class EveryWriteIsRecorded(TestCase):
    def test_no_service_method_writes_without_an_audit_entry(self):
        source = inspect.getsource(services)
        unrecorded = []

        for node in ast.parse(source).body:
            if not isinstance(node, ast.ClassDef):
                continue
            for method in node.body:
                if not isinstance(method, ast.FunctionDef):
                    continue
                body = ast.get_source_segment(source, method)
                name = f"{node.name}.{method.name}"
                # Sign-in events record through AuthService._record.
                records = "audit." in body or "._record(" in body
                if any(write in body for write in WRITES) and not records and name not in NOT_RECORDED:
                    unrecorded.append(name)

        self.assertEqual([], unrecorded, "these write without recording - add an audit call or a reason above")


class AuditTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(timezone="UTC")
        self.year = factories.AcademicYearFactory(school=self.school, is_current=True)
        self.section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=self.year, school=self.school, name="Grade 8"),
            name="A",
        )
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))
        return client


class WhatAnEntrySays(AuditTest):
    def test_a_new_student_is_recorded_with_who_and_where(self):
        response = self.as_user(self.admin).post("/api/v1/students", {
            "school_id": self.school.id, "class_section_id": self.section.id, "admission_number": "ADM-1",
            "first_name": "Zainab", "last_name": "Okafor", "guardian_name": "Nneka Okafor",
        }, format="json", REMOTE_ADDR="203.0.113.7")

        entry = AuditLog.objects.get(action="student.created")
        self.assertEqual(
            (self.admin.id, self.school.id, "students", "student", response.data["id"], "203.0.113.7"),
            (entry.user_id, entry.school_id, entry.module, entry.entity_type, entry.entity_id, entry.ip),
        )
        self.assertEqual("Zainab", entry.new_values["first_name"])
        self.assertNotIn("created_at", entry.new_values)

    def test_an_edit_records_only_what_changed_and_an_unchanged_save_nothing(self):
        student = factories.StudentFactory(class_section=self.section, first_name="Zainab", admission_number="ADM-2")
        client = self.as_user(self.admin)

        client.patch(f"/api/v1/students/{student.id}", {"first_name": "Zara"}, format="json")
        client.patch(f"/api/v1/students/{student.id}", {"first_name": "Zara"}, format="json")

        entries = AuditLog.objects.filter(action="student.updated")
        self.assertEqual(1, entries.count())
        self.assertEqual(({"first_name": "Zainab"}, {"first_name": "Zara"}),
                         (entries[0].old_values, entries[0].new_values))

    def test_a_new_account_never_carries_its_password(self):
        self.as_user(self.admin).post("/api/v1/users", {
            "first_name": "Sam", "last_name": "Sub", "email": "sam@example.invalid", "password": "Blue-kettle-42",
            "role": UserRole.SCHOOL_ADMIN,
        }, format="json")

        entry = AuditLog.objects.get(action="user.created")
        self.assertNotIn("password", entry.new_values)
        self.assertNotIn("Blue-kettle-42", str(entry.new_values))

    def test_a_register_is_one_entry_naming_the_marks_and_a_correction_what_they_were(self):
        students = [factories.StudentFactory(class_section=self.section, admission_number=f"A-{n}") for n in range(2)]
        client = self.as_user(self.admin)
        body = {
            "class_section_id": self.section.id, "attendance_date": "2026-09-09",
            "records": [{"student_id": s.id, "status": AttendanceStatus.PRESENT} for s in students],
        }

        with mock.patch("django.utils.timezone.now", return_value=dt.datetime(2026, 9, 10, 9, tzinfo=dt.timezone.utc)):
            client.post("/api/v1/attendance", body, format="json")
            body["records"][1]["status"] = AttendanceStatus.ABSENT
            client.patch("/api/v1/attendance", body, format="json")

        marked, corrected = AuditLog.objects.filter(module="attendance").order_by("id")
        self.assertEqual("attendance.marked", marked.action)
        self.assertEqual(2, len(marked.new_values["marks"]))
        self.assertEqual("attendance.corrected", corrected.action)
        self.assertEqual({str(students[1].id): "present"}, corrected.old_values["marks"])
        self.assertEqual({str(students[1].id): "absent"}, corrected.new_values["marks"])

    def test_the_other_modules_record_too(self):
        # As the authentication would; undone after, so no later test inherits it.
        audit.set_actor(self.admin)
        self.addCleanup(audit.set_actor, None)
        route = services.TransportRouteService.create({"school_id": self.school.id, "name": "Route 9"})
        services.TransportRouteService.delete(route)
        holiday = services.HolidayService.create(
            {"school_id": self.school.id, "name": "Founders Day", "type": "school_event",
             "start_date": dt.date(2026, 10, 2), "end_date": dt.date(2026, 10, 2)}, self.admin,
        )
        next_year = factories.AcademicYearFactory(school=self.school, name="2027-28", is_current=False)
        services.AcademicYearService.set_current(next_year)

        actions = set(AuditLog.objects.values_list("action", flat=True))
        self.assertLessEqual(
            {"transport_route.created", "transport_route.deleted", "holiday.created", "academic_year.set_current"},
            actions,
        )
        self.assertEqual(self.admin.id, AuditLog.objects.get(action="holiday.created", entity_id=holiday.id).user_id)


class WhoMayRead(AuditTest):
    def setUp(self):
        super().setUp()
        self.elsewhere = factories.SchoolFactory(timezone="UTC")
        now = timezone.now()
        self.ours = AuditLog.objects.create(school=self.school, user=self.admin, action="student.created",
                                            module="students", entity_type="student", entity_id=1, created_at=now)
        self.theirs = AuditLog.objects.create(school=self.elsewhere, action="student.created", module="students",
                                              entity_type="student", entity_id=2, created_at=now)
        self.platform = AuditLog.objects.create(school=None, action="user.sign_in_failed", module="auth",
                                                entity_type="user", created_at=now)

    def ids(self, user, **params):
        response = self.as_user(user).get("/api/v1/audit-logs", params)
        self.assertEqual(200, response.status_code, response.data)
        return [row["id"] for row in response.data["data"]]

    def test_a_school_admin_reads_their_own_school_only(self):
        ids = self.ids(self.admin)

        self.assertIn(self.ours.id, ids)
        self.assertNotIn(self.theirs.id, ids)
        self.assertNotIn(self.platform.id, ids)
        self.assertEqual(404, self.as_user(self.admin).get(f"/api/v1/audit-logs/{self.theirs.id}").status_code)

    def test_naming_another_school_does_not_widen_it(self):
        self.assertNotIn(self.theirs.id, self.ids(self.admin, school_id=self.elsewhere.id))

    def test_the_super_admin_reads_everything_including_platform_entries(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.assertLessEqual({self.ours.id, self.theirs.id, self.platform.id}, set(self.ids(root)))

    def test_a_group_admin_reads_their_branches(self):
        branch = factories.SchoolFactory(timezone="UTC", parent_school=self.school)
        group_admin = factories.UserFactory(school=self.school, role=UserRole.GROUP_ADMIN)
        in_branch = AuditLog.objects.create(school=branch, action="student.created", module="students",
                                            entity_type="student", entity_id=3, created_at=timezone.now())

        ids = self.ids(group_admin)

        self.assertIn(in_branch.id, ids)
        self.assertNotIn(self.theirs.id, ids)

    def test_nobody_but_an_administrator_reads_it(self):
        for role in (UserRole.TEACHER, UserRole.HOD, UserRole.ACCOUNTANT, UserRole.STAFF, UserRole.TRANSPORT_MANAGER):
            user = factories.UserFactory(school=self.school, role=role)
            self.assertEqual(403, self.as_user(user).get("/api/v1/audit-logs").status_code, role)
        self.assertEqual(401, APIClient().get("/api/v1/audit-logs").status_code)

    def test_the_filters_narrow_it(self):
        AuditLog.objects.create(school=self.school, action="holiday.created", module="holidays",
                                entity_type="holiday", entity_id=9, created_at=timezone.now())

        self.assertEqual([self.ours.id], self.ids(self.admin, module="students"))
        self.assertEqual([self.ours.id], self.ids(self.admin, user_id=self.admin.id))
        self.assertEqual([], self.ids(self.admin, to="2000-01-01"))

    def test_a_bad_filter_is_422_naming_it(self):
        response = self.as_user(self.admin).get("/api/v1/audit-logs", {"module": "nonsense", "from": "yesterday"})

        self.assertEqual(422, response.status_code)
        self.assertEqual({"module", "from"}, set(response.data["details"]["errors"]))

    def test_an_entry_reads_whole_and_the_list_exports_as_a_csv(self):
        self.ours.old_values = {"first_name": "Zainab"}
        self.ours.new_values = {"first_name": "=HYPERLINK(1)"}
        self.ours.ip = "203.0.113.7"
        self.ours.save()

        entry = self.as_user(self.admin).get(f"/api/v1/audit-logs/{self.ours.id}").data
        csv = self.as_user(self.admin).get("/api/v1/audit-logs", {"format": "csv"})

        self.assertEqual((self.admin.name, "SCHOOL_ADMIN", "203.0.113.7"),
                         (entry["user_name"], entry["user_role"], entry["ip"]))
        self.assertEqual("text/csv; charset=UTF-8", csv["Content-Type"])
        header, row = list(reader(io.StringIO(csv.content.decode("utf-8-sig"))))[:2]
        self.assertEqual(["When (UTC)", "School", "User", "Role", "Module", "Action"], header[:6])
        self.assertEqual(("student.created", '{"first_name": "Zainab"}'), (row[5], row[9]))
        # JSON starts with a brace, so a formula typed into a name inside it
        # never reaches the start of a cell.
        self.assertTrue(row[10].startswith("{"))
