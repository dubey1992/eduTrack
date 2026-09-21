"""Module settings and the permissions matrix (docs/settings.md).

What this file guards:

- **With nothing saved, nothing changes.** The matrix's defaults reproduce
  every policy's old answer, and a school with no module row has everything
  on. The rest of the suite passing with an empty matrix is the real proof;
  the tests here check the edges of that claim.
- **A switched-off module is refused everywhere**, with its own code, and
  disappears from /me - not just hidden by the app.
- **The matrix is a ceiling and a grant, but never widens scope.** A teacher
  raised to "manage" students may add one, and still cannot read a section
  that is not theirs.
- **Who edits what.** The platform switch and the matrix are the Super
  Admin's; the school switch and the settings are the school's; strangers
  get nothing.
- **Every setting does something.** Each one has a test that trips it.
"""

import datetime as dt
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, modules, notifications, permissions, tokens
from school.enums import UserRole
from school.models import AuditLog, Message, ModuleSetting, QueuedJob, RolePermission


# A fixed Wednesday, so a test about days of notice is not at the mercy of
# the day the suite happens to run.
WEDNESDAY = dt.datetime(2026, 9, 23, 9, 0, tzinfo=dt.timezone.utc)


MODULES = "/api/v1/settings/modules"
MATRIX = "/api/v1/settings/permissions"


class SettingsTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(timezone="Asia/Kolkata")
        self.year = factories.AcademicYearFactory(school=self.school, is_current=True)
        self.school_class = factories.SchoolClassFactory(academic_year=self.year, school=self.school, name="Grade 8")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.staff = factories.UserFactory(school=self.school, role=UserRole.STAFF)
        self.section = factories.ClassSectionFactory(school_class=self.school_class, name="A", class_teacher=self.teacher)
        self.other_section = factories.ClassSectionFactory(school_class=self.school_class, name="B")
        self.student = factories.StudentFactory(school=self.school, class_section=self.section, admission_number="ADM-1")
        self.other_student = factories.StudentFactory(
            school=self.school, class_section=self.other_section, admission_number="ADM-2"
        )
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        self.elsewhere = factories.SchoolFactory()
        self.stranger = factories.UserFactory(school=self.elsewhere, role=UserRole.SCHOOL_ADMIN)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]

    def switch(self, module: str, user=None, **body):
        return self.as_user(user or self.admin).put(f"{MODULES}/{module}", body, format="json")

    def set_level(self, role: str, module: str, level: str):
        response = self.as_user(self.root).put(MATRIX, {"matrix": {role: {module: level}}}, format="json")
        self.assertEqual(200, response.status_code, response.data)

        return response


# -- module settings ------------------------------------------------------------


class ReadingModules(SettingsTest):
    def test_a_school_with_nothing_saved_has_every_module_on_with_defaults(self):
        response = self.as_user(self.admin).get(MODULES)

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual([m.key for m in modules.MODULES], [row["module"] for row in response.data])

        attendance = next(row for row in response.data if row["module"] == "attendance")
        self.assertEqual(
            {"platform_enabled": True, "school_enabled": True, "enabled": True, "switchable": True,
             "can_change_platform": False, "settings": {"max_backdate_days": 30}},
            {key: attendance[key] for key in ("platform_enabled", "school_enabled", "enabled", "switchable",
                                               "can_change_platform", "settings")},
        )
        self.assertEqual("max_backdate_days", attendance["settings_schema"][0]["key"])
        self.assertFalse(next(row for row in response.data if row["module"] == "students")["switchable"])
        self.assertFalse(ModuleSetting.objects.exists(), "reading never writes a row")

    def test_a_super_admin_names_the_school_and_may_move_the_platform_switch(self):
        client = self.as_user(self.root)

        self.assertEqual(422, client.get(MODULES).status_code, "no school named")

        response = client.get(f"{MODULES}?school_id={self.school.id}")
        self.assertEqual(200, response.status_code)
        self.assertTrue(response.data[0]["can_change_platform"])

    def test_teachers_and_strangers_do_not_read_them(self):
        self.assertEqual(403, self.as_user(self.teacher).get(MODULES).status_code)
        self.assertEqual(403, self.as_user(self.stranger).get(f"{MODULES}?school_id={self.school.id}").status_code)

    def test_me_says_which_modules_are_on_and_what_the_role_may_do(self):
        me = self.as_user(self.teacher).get("/api/v1/me").data

        self.assertEqual("view", me["permissions"]["students"])
        self.assertEqual("manage", me["permissions"]["attendance"])
        self.assertEqual("none", me["permissions"]["payroll"])
        self.assertTrue(me["modules"]["attendance"])
        self.assertTrue(me["modules"]["students"])

        # A Super Admin belongs to no school: every module on, every level full.
        root = self.as_user(self.root).get("/api/v1/me").data
        self.assertEqual("manage", root["permissions"]["payroll"])
        self.assertTrue(all(root["modules"].values()))


class SwitchingModules(SettingsTest):
    def test_the_school_switches_a_module_off_and_the_api_refuses_it_by_name(self):
        response = self.switch("attendance", school_enabled=False)

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual((True, False, False), (
            response.data["platform_enabled"], response.data["school_enabled"], response.data["enabled"],
        ))

        register = self.as_user(self.teacher).get(
            f"/api/v1/attendance/register?class_section_id={self.section.id}&date=2026-09-09"
        )
        self.assertEqual(403, register.status_code)
        self.assertEqual("MODULE_DISABLED", register.data["code"])
        self.assertEqual("Student Attendance is switched off for this school.", register.data["message"])

        # The admin's own list is refused too - off is off for everybody.
        self.assertEqual(403, self.as_user(self.admin).get("/api/v1/attendance").status_code)
        self.assertFalse(self.as_user(self.teacher).get("/api/v1/me").data["modules"]["attendance"])

        # Other modules and the school next door are untouched.
        self.assertEqual(200, self.as_user(self.admin).get("/api/v1/students").status_code)
        self.assertTrue(modules.is_enabled(self.elsewhere.id, "attendance"))

    def test_switching_it_back_on_restores_it(self):
        self.switch("attendance", school_enabled=False)
        self.switch("attendance", school_enabled=True)

        self.assertEqual(200, self.as_user(self.admin).get("/api/v1/attendance").status_code)

    def test_the_platform_switch_wins_and_belongs_to_the_super_admin(self):
        refused = self.switch("attendance", platform_enabled=False)
        self.assertEqual(422, refused.status_code)
        self.assertEqual(["Only the Super Admin can grant or withdraw a module."], self.errors(refused)["platform_enabled"])

        withdrawn = self.as_user(self.root).put(
            f"{MODULES}/attendance", {"school_id": self.school.id, "platform_enabled": False}, format="json"
        )
        self.assertEqual(200, withdrawn.status_code, withdrawn.data)
        self.assertFalse(withdrawn.data["enabled"])

        # The school switch is still on, and turning it on again changes nothing.
        back = self.switch("attendance", school_enabled=True)
        self.assertEqual((False, True, False), (back.data["platform_enabled"], back.data["school_enabled"], back.data["enabled"]))
        self.assertEqual(403, self.as_user(self.admin).get("/api/v1/attendance").status_code)

    def test_the_spine_cannot_be_switched_off(self):
        response = self.switch("students", school_enabled=False)

        self.assertEqual(422, response.status_code)
        self.assertEqual(["Students cannot be switched off."], self.errors(response)["school_enabled"])

    def test_an_unknown_module_is_a_404_and_an_empty_change_is_refused(self):
        self.assertEqual(404, self.switch("library").status_code)
        self.assertEqual(422, self.switch("attendance").status_code)

    def test_strangers_cannot_switch_another_schools_modules(self):
        response = self.as_user(self.stranger).put(
            f"{MODULES}/attendance?school_id={self.school.id}", {"school_enabled": False}, format="json"
        )

        self.assertEqual(403, response.status_code)
        self.assertTrue(modules.is_enabled(self.school.id, "attendance"))

    def test_a_switch_is_in_the_audit_trail(self):
        self.switch("payroll", school_enabled=False)

        entry = AuditLog.objects.get(entity_type="module_setting")
        self.assertEqual(("settings", self.school.id, self.admin.id), (entry.module, entry.school_id, entry.user_id))
        self.assertEqual(False, entry.new_values["school_enabled"])


class ModuleOwnSettings(SettingsTest):
    def test_settings_are_saved_merged_and_returned(self):
        response = self.switch("attendance", settings={"max_backdate_days": 3})

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual({"max_backdate_days": 3}, response.data["settings"])
        self.assertEqual(3, modules.setting(self.school.id, "attendance", "max_backdate_days"))
        self.assertEqual(30, modules.setting(self.elsewhere.id, "attendance", "max_backdate_days"))

    def test_bad_settings_are_named_one_by_one(self):
        response = self.switch(
            "attendance", settings={"max_backdate_days": 400, "colour": "blue", "max_backdate_days_x": 1}
        )

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            ["Days a register may be marked late must be between 0 and 365.",
             '"colour" is not a setting of Student Attendance.',
             '"max_backdate_days_x" is not a setting of Student Attendance.'],
            self.errors(response)["settings"],
        )

        self.assertEqual(
            ["Days a register may be marked late must be a whole number."],
            self.errors(self.switch("attendance", settings={"max_backdate_days": "seven"}))["settings"],
        )
        self.assertEqual(
            ["Email payslips when a run is finalized must be true or false."],
            self.errors(self.switch("payroll", settings={"email_payslips_on_finalize": "yes"}))["settings"],
        )

    def test_a_register_cannot_be_marked_further_back_than_the_setting_allows(self):
        self.switch("attendance", settings={"max_backdate_days": 0})
        today = dt.datetime.now(dt.timezone.utc).date()
        # The most recent weekday before today, so the only refusal is the setting's.
        day = today - dt.timedelta(days=1)
        while day.weekday() >= 5:
            day -= dt.timedelta(days=1)

        response = self.as_user(self.admin).post("/api/v1/attendance", {
            "class_section_id": self.section.id, "attendance_date": day.isoformat(),
            "records": [{"student_id": self.student.id, "status": "present"}],
        }, format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("SETTING_REFUSED", response.data["code"])
        self.assertEqual("Attendance can only be marked for today.", response.data["message"])

    def test_leave_needs_the_notice_the_school_asks_for(self):
        factories.StaffProfileFactory(school=self.school, user=self.teacher)
        self.switch("leave", settings={"min_notice_days": 7})
        # The clock is pinned to a Wednesday, so "too soon" is genuinely too
        # soon. Read from the real date, the next Monday is exactly seven days
        # away when the suite runs on a Monday - which satisfies a seven-day
        # notice rather than breaking it, and the test failed every Monday.
        clock = mock.patch("django.utils.timezone.now", return_value=WEDNESDAY)
        clock.start()
        self.addCleanup(clock.stop)

        today = WEDNESDAY.date()
        soon = today + dt.timedelta(days=(7 - today.weekday()) % 7 or 7)
        later = soon + dt.timedelta(days=7)

        client = self.as_user(self.teacher)
        refused = client.post("/api/v1/leaves", {
            "leave_type": "casual", "start_date": soon.isoformat(), "end_date": soon.isoformat(), "reason": "Family function.",
        }, format="json")
        self.assertEqual(422, refused.status_code, refused.data)
        self.assertEqual("Leave must be applied for at least 7 days in advance.", refused.data["message"])

        accepted = client.post("/api/v1/leaves", {
            "leave_type": "casual", "start_date": later.isoformat(), "end_date": later.isoformat(), "reason": "Family function.",
        }, format="json")
        self.assertEqual(201, accepted.status_code, accepted.data)

    def test_a_report_filed_after_the_window_is_refused(self):
        science = factories.DepartmentFactory(school=self.school, name="Science")
        factories.StaffProfileFactory(school=self.school, user=self.teacher, department=science)
        subject = factories.SubjectFactory(department=science)
        entry = factories.TimetableEntryFactory(
            school=self.school, class_section=self.section, period=factories.PeriodFactory(school=self.school),
            day_of_week="wednesday", subject=subject, teacher=self.teacher,
        )
        self.switch("teaching_reports", settings={"filing_window_days": 1})

        response = self.as_user(self.teacher).post("/api/v1/teaching-reports", {
            "timetable_entry_id": entry.id, "report_date": "2026-09-09", "topic_taught": "Newton's laws",
        }, format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("A report can only be filed up to 1 day after the period.", response.data["message"])

    def test_payslips_are_not_emailed_when_the_school_says_so(self):
        accountant = factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT)
        factories.StaffProfileFactory(school=self.school, user=accountant, employee_id="ACC-1")
        profile = factories.StaffProfileFactory(school=self.school, user=self.teacher, employee_id="TCH-1")
        factories.SalaryProfileFactory(staff_profile=profile, basic_salary="30000.00")
        self.switch("payroll", settings={"email_payslips_on_finalize": False})

        client = self.as_user(accountant)
        run = client.post("/api/v1/payroll/runs", {"year": 2026, "month": 8}, format="json")
        self.assertEqual(201, run.status_code, run.data)
        finalized = client.post(f"/api/v1/payroll/runs/{run.data['id']}/finalize")
        self.assertEqual(200, finalized.status_code, finalized.data)

        self.assertFalse(QueuedJob.objects.filter(name="payslip_email").exists())

    def test_communication_switched_off_records_nothing(self):
        self.student.guardian_mobile = "+91 9000000000"
        self.student.save()
        self.switch("communication", school_enabled=False)

        messages = notifications.notify_guardian("attendance.absent", self.student, {"class_name": "Grade 8 A"})

        self.assertEqual([], messages)
        self.assertFalse(Message.objects.exists())


# -- the permissions matrix -----------------------------------------------------------


class ReadingTheMatrix(SettingsTest):
    def test_admins_read_the_defaults_and_only_the_super_admin_may_edit(self):
        response = self.as_user(self.admin).get(MATRIX)

        self.assertEqual(200, response.status_code, response.data)
        self.assertFalse(response.data["can_edit"])
        self.assertEqual([r for r in permissions.EDITABLE_ROLES], [row["value"] for row in response.data["roles"]])
        self.assertEqual(response.data["defaults"], response.data["matrix"])
        self.assertEqual("view", response.data["matrix"]["TEACHER"]["students"])
        self.assertEqual(["none", "view", "manage"], [level["value"] for level in response.data["levels"]])

        self.assertTrue(self.as_user(self.root).get(MATRIX).data["can_edit"])
        self.assertEqual(403, self.as_user(self.teacher).get(MATRIX).status_code)

    def test_only_the_super_admin_saves_or_resets(self):
        body = {"matrix": {"TEACHER": {"students": "manage"}}}

        self.assertEqual(403, self.as_user(self.admin).put(MATRIX, body, format="json").status_code)
        self.assertEqual(403, self.as_user(self.admin).post(f"{MATRIX}/reset").status_code)
        self.assertFalse(RolePermission.objects.exists())


class EditingTheMatrix(SettingsTest):
    def test_raising_a_teacher_to_manage_lets_them_write_but_not_widen_their_reach(self):
        client = self.as_user(self.teacher)
        payload = {
            "class_section_id": self.section.id, "admission_number": "ADM-9", "first_name": "Zara",
            "last_name": "Khan", "guardian_name": "Nadia Khan",
        }
        self.assertEqual(403, client.post("/api/v1/students", payload, format="json").status_code)

        self.set_level("TEACHER", "students", "manage")

        self.assertEqual(201, client.post("/api/v1/students", payload, format="json").status_code)
        self.assertEqual("manage", client.get("/api/v1/me").data["permissions"]["students"])
        # Still the class teacher's own section only.
        self.assertEqual(200, client.get(f"/api/v1/students/{self.student.id}").status_code)
        self.assertEqual(403, client.get(f"/api/v1/students/{self.other_student.id}").status_code)
        self.assertEqual(403, client.patch(f"/api/v1/students/{self.other_student.id}", {"first_name": "X"}, format="json").status_code)

    def test_lowering_a_role_to_none_shuts_the_module(self):
        self.set_level("TEACHER", "students", "none")

        client = self.as_user(self.teacher)
        self.assertEqual(403, client.get("/api/v1/students").status_code)
        self.assertEqual(403, client.get(f"/api/v1/students/{self.student.id}").status_code)
        self.assertEqual("none", client.get("/api/v1/me").data["permissions"]["students"])

        # Other roles and other modules are untouched.
        self.assertEqual(200, self.as_user(self.admin).get("/api/v1/students").status_code)
        self.assertEqual(200, client.get(f"/api/v1/attendance/register?class_section_id={self.section.id}&date=2026-09-09").status_code)

    def test_view_reads_but_does_not_write(self):
        factories.StaffProfileFactory(school=self.school, user=self.staff)
        self.set_level("STAFF", "leave", "view")

        client = self.as_user(self.staff)
        self.assertEqual(200, client.get("/api/v1/leaves").status_code)
        refused = client.post("/api/v1/leaves", {
            "leave_type": "casual", "start_date": "2026-10-05", "end_date": "2026-10-05", "reason": "Family function.",
        }, format="json")
        self.assertEqual(403, refused.status_code)

    def test_a_group_admin_follows_the_school_admin_row_and_the_super_admin_follows_nothing(self):
        group_admin = factories.UserFactory(school=self.school, role=UserRole.GROUP_ADMIN)
        # With the defaults, a group admin reads what a school admin reads.
        self.assertEqual(200, self.as_user(group_admin).get("/api/v1/attendance").status_code)

        self.set_level("SCHOOL_ADMIN", "attendance", "none")

        self.assertEqual(403, self.as_user(self.admin).get("/api/v1/attendance").status_code)
        self.assertEqual(403, self.as_user(group_admin).get("/api/v1/attendance").status_code)
        self.assertEqual(200, self.as_user(self.root).get(f"/api/v1/attendance?school_id={self.school.id}").status_code)

    def test_reports_are_gated_by_the_matrix_on_top_of_their_own_readers(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        client = self.as_user(hod)
        url = "/api/v1/reports/staff-attendance?from=2026-09-01&to=2026-09-10"

        self.assertEqual(200, client.get(url).status_code)

        self.set_level("HOD", "reports", "none")
        self.assertEqual(403, client.get(url).status_code)

        # Granting "view" never adds a report a role was not a reader of.
        self.set_level("STAFF", "reports", "view")
        self.assertEqual(403, self.as_user(self.staff).get(url).status_code)

    def test_only_the_cells_that_differ_are_stored_and_reset_restores_the_defaults(self):
        self.set_level("TEACHER", "students", "view")
        self.assertFalse(RolePermission.objects.exists(), "the default again is not a row")

        self.set_level("TEACHER", "students", "none")
        self.assertEqual(1, RolePermission.objects.count())
        self.assertTrue(AuditLog.objects.filter(action="permission.changed", module="settings").exists())

        # Back to the default: the row goes, rather than a default being stored.
        self.set_level("TEACHER", "students", "view")
        self.assertFalse(RolePermission.objects.exists())

        self.set_level("TEACHER", "students", "none")

        reset = self.as_user(self.root).post(f"{MATRIX}/reset")
        self.assertEqual(200, reset.status_code)
        self.assertFalse(RolePermission.objects.exists())
        self.assertEqual("view", reset.data["matrix"]["TEACHER"]["students"])
        self.assertEqual(200, self.as_user(self.teacher).get("/api/v1/students").status_code)

    def test_a_bad_matrix_is_refused_by_name(self):
        response = self.as_user(self.root).put(
            MATRIX,
            {"matrix": {"SUPER_ADMIN": {"students": "manage"}, "TEACHER": {"library": "view", "students": "full"}}},
            format="json",
        )

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            ['"SUPER_ADMIN" is not a role whose permissions can be edited.',
             '"library" is not a module in the matrix.',
             '"full" is not a level; use none, view or manage.'],
            self.errors(response)["matrix"],
        )
        self.assertEqual(422, self.as_user(self.root).put(MATRIX, {"matrix": {}}, format="json").status_code)

    def test_a_module_switched_off_beats_the_matrix(self):
        self.set_level("TEACHER", "attendance", "manage")
        self.switch("attendance", school_enabled=False)

        response = self.as_user(self.teacher).get(
            f"/api/v1/attendance/register?class_section_id={self.section.id}&date=2026-09-09"
        )
        self.assertEqual("MODULE_DISABLED", response.data["code"])
