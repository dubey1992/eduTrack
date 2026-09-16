"""Staff leave, over HTTP.

Four rules carry this module, and most of the file is here to hold them
down:

**Applying is self-service.** Whose leave it is comes off the actor's own
employment record, never off the request - the identity half of the rule that
never trusts a client's `school_id`.

**A School Admin's own request approves itself**, because nobody else is
senior enough to decide it. A Sub Admin's does not.

**Approving writes the register.** Every working day in the range is marked
`leave` on staff attendance, and weekends and holidays inside it are left
alone - they are not attendance days.

**Nobody reviews their own leave**, whatever their role. An HOD heads the
department they belong to, so without a check for it they would pass the
department test for their own request.

Dates are fixed rather than relative to today, so the weekday rules mean the
same thing whichever day the suite runs on.
"""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.clock import SchoolClock
from school.enums import LeaveStatus, MessageEvent, UserRole
from school.models import Holiday, Message, StaffAttendance, StaffLeave

A_MONDAY = dt.date(2026, 9, 21)
A_TUESDAY = dt.date(2026, 9, 22)
A_SATURDAY = dt.date(2026, 9, 19)
A_SUNDAY = dt.date(2026, 9, 20)


class StaffLeaveTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(timezone="Asia/Kolkata")
        self.science = factories.DepartmentFactory(school=self.school, name="Science")
        self.arts = factories.DepartmentFactory(school=self.school, name="Arts")

        self.hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        self.science.hod_user = self.hod
        self.science.save()
        self.hod_profile = self.employee(self.hod, self.science)

        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.teacher_profile = self.employee(self.teacher, self.science)

        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

    # -- helpers ------------------------------------------------------------

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def employee(self, user, department):
        return factories.StaffProfileFactory(
            school=user.school, user=user, department=department
        )

    def payload(self, **overrides) -> dict:
        body = {
            "leave_type": "casual",
            "start_date": A_MONDAY.isoformat(),
            "end_date": A_TUESDAY.isoformat(),
            "reason": "Family function.",
        }
        body.update(overrides)

        return body

    def holiday(self, date, school=None):
        return Holiday.objects.create(
            school_id=(school or self.school).id,
            name="Founders Day",
            type="school_event",
            start_date=date,
            end_date=date,
        )

    # -- applying -----------------------------------------------------------

    def test_a_teacher_applies_for_their_own_leave(self):
        response = self.as_user(self.teacher).post(
            "/api/v1/leaves", self.payload(), format="json"
        )

        self.assertEqual(201, response.status_code)
        self.assertEqual(LeaveStatus.PENDING, response.data["status"])
        self.assertEqual(self.teacher_profile.id, response.data["staff_profile_id"])
        self.assertEqual(self.teacher.name, response.data["staff_name"])
        self.assertEqual("Science", response.data["department_name"])
        self.assertEqual(self.teacher.name, response.data["applied_by_name"])
        self.assertIsNone(response.data["reviewed_by_name"])

    def test_an_hod_applies_for_their_own_leave(self):
        response = self.as_user(self.hod).post(
            "/api/v1/leaves", self.payload(), format="json"
        )

        self.assertEqual(201, response.status_code)
        self.assertEqual(LeaveStatus.PENDING, response.data["status"])

    def test_a_school_admins_own_leave_approves_itself_and_reaches_the_register(self):
        profile = self.employee(self.admin, None)

        response = self.as_user(self.admin).post(
            "/api/v1/leaves", self.payload(), format="json"
        )

        self.assertEqual(201, response.status_code)
        self.assertEqual(LeaveStatus.APPROVED, response.data["status"])
        self.assertEqual(self.admin.name, response.data["reviewed_by_name"])
        self.assertTrue(
            StaffAttendance.objects.filter(
                staff_profile_id=profile.id, attendance_date=A_MONDAY, status="leave"
            ).exists()
        )

    def test_a_sub_admins_own_leave_still_waits_for_a_decision(self):
        sub_admin = factories.UserFactory(
            school=self.school, role=UserRole.SCHOOL_ADMIN, is_sub_admin=True
        )
        self.employee(sub_admin, None)

        response = self.as_user(sub_admin).post(
            "/api/v1/leaves", self.payload(), format="json"
        )

        self.assertEqual(201, response.status_code)
        self.assertEqual(LeaveStatus.PENDING, response.data["status"])

    def test_an_account_with_no_employment_record_is_told_what_is_missing(self):
        # Allowed by role, so this is not a 403 - the row simply is not there
        # yet, and the message names who can create it.
        without_a_profile = factories.UserFactory(
            school=self.school, role=UserRole.TEACHER
        )

        response = self.as_user(without_a_profile).post(
            "/api/v1/leaves", self.payload(), format="json"
        )

        self.assertEqual(409, response.status_code)
        self.assertEqual("STAFF_PROFILE_REQUIRED", response.data["code"])

    def test_a_school_admin_with_no_employment_record_gets_the_same_answer(self):
        response = self.as_user(self.admin).post(
            "/api/v1/leaves", self.payload(), format="json"
        )

        self.assertEqual(409, response.status_code)
        self.assertEqual("STAFF_PROFILE_REQUIRED", response.data["code"])

    def test_a_super_admin_never_applies(self):
        # There is no school to apply against.
        super_admin = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        response = self.as_user(super_admin).post(
            "/api/v1/leaves", self.payload(), format="json"
        )

        self.assertEqual(403, response.status_code)

    # -- what a request may say ---------------------------------------------

    def test_an_unknown_leave_type_is_refused(self):
        response = self.as_user(self.teacher).post(
            "/api/v1/leaves", self.payload(leave_type="sabbatical"), format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertIn("leave_type", response.data["details"]["errors"])

    def test_a_reason_longer_than_the_column_is_refused(self):
        response = self.as_user(self.teacher).post(
            "/api/v1/leaves", self.payload(reason="x" * 501), format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertIn("reason", response.data["details"]["errors"])

    def test_an_end_date_before_the_start_is_refused(self):
        response = self.as_user(self.teacher).post(
            "/api/v1/leaves",
            self.payload(start_date=A_TUESDAY.isoformat(), end_date=A_MONDAY.isoformat()),
            format="json",
        )

        self.assertEqual(422, response.status_code)
        self.assertIn("end_date", response.data["details"]["errors"])

    def test_remarks_longer_than_the_column_are_refused(self):
        leave = factories.StaffLeaveFactory(staff_profile=self.teacher_profile)

        response = self.as_user(self.admin).patch(
            f"/api/v1/leaves/{leave.id}/approve", {"remarks": "x" * 501}, format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertIn("remarks", response.data["details"]["errors"])

    def test_a_second_live_request_for_the_same_days_is_refused(self):
        factories.StaffLeaveFactory(
            staff_profile=self.teacher_profile, start_date=A_MONDAY, end_date=A_TUESDAY
        )

        response = self.as_user(self.teacher).post(
            "/api/v1/leaves", self.payload(), format="json"
        )

        self.assertEqual(409, response.status_code)
        self.assertEqual("LEAVE_OVERLAP", response.data["code"])

    def test_leave_entirely_on_a_weekend_is_refused(self):
        response = self.as_user(self.teacher).post(
            "/api/v1/leaves",
            self.payload(
                start_date=A_SATURDAY.isoformat(), end_date=A_SUNDAY.isoformat()
            ),
            format="json",
        )

        self.assertEqual(409, response.status_code)
        self.assertEqual("LEAVE_ON_NON_WORKING_DAYS", response.data["code"])

    def test_leave_entirely_on_a_holiday_is_refused(self):
        self.holiday(A_MONDAY)

        response = self.as_user(self.teacher).post(
            "/api/v1/leaves",
            self.payload(start_date=A_MONDAY.isoformat(), end_date=A_MONDAY.isoformat()),
            format="json",
        )

        self.assertEqual(409, response.status_code)
        self.assertEqual("LEAVE_ON_NON_WORKING_DAYS", response.data["code"])

    def test_leave_spanning_a_holiday_and_a_working_day_is_accepted(self):
        self.holiday(A_MONDAY)

        response = self.as_user(self.teacher).post(
            "/api/v1/leaves", self.payload(), format="json"
        )

        self.assertEqual(201, response.status_code)

    # -- deciding -----------------------------------------------------------

    def test_an_hod_approves_leave_for_their_own_department(self):
        leave = factories.StaffLeaveFactory(staff_profile=self.teacher_profile)

        response = self.as_user(self.hod).patch(
            f"/api/v1/leaves/{leave.id}/approve", {"remarks": "Fine."}, format="json"
        )

        self.assertEqual(200, response.status_code)
        self.assertEqual(LeaveStatus.APPROVED, response.data["status"])
        self.assertEqual(self.hod.name, response.data["reviewed_by_name"])
        self.assertEqual("Fine.", response.data["review_remarks"])

    def test_approving_marks_every_working_day_in_the_range(self):
        leave = factories.StaffLeaveFactory(
            staff_profile=self.teacher_profile, start_date=A_MONDAY, end_date=A_TUESDAY
        )

        self.as_user(self.admin).patch(
            f"/api/v1/leaves/{leave.id}/approve", {}, format="json"
        )

        marked = StaffAttendance.objects.filter(
            staff_profile_id=self.teacher_profile.id, status="leave"
        ).values_list("attendance_date", flat=True)

        self.assertEqual([A_MONDAY, A_TUESDAY], sorted(marked))

    def test_approving_leaves_weekends_and_holidays_unmarked(self):
        # Those days are not attendance days at all, and marking them would
        # contradict the calendar that refuses attendance on them.
        self.holiday(A_TUESDAY)
        leave = factories.StaffLeaveFactory(
            staff_profile=self.teacher_profile, start_date=A_SATURDAY, end_date=A_TUESDAY
        )

        self.as_user(self.admin).patch(
            f"/api/v1/leaves/{leave.id}/approve", {}, format="json"
        )

        marked = StaffAttendance.objects.filter(
            staff_profile_id=self.teacher_profile.id
        ).values_list("attendance_date", flat=True)

        self.assertEqual([A_MONDAY], sorted(marked))

    def test_approving_tells_the_applicant(self):
        leave = factories.StaffLeaveFactory(staff_profile=self.teacher_profile)

        self.as_user(self.admin).patch(
            f"/api/v1/leaves/{leave.id}/approve", {}, format="json"
        )

        messages = Message.objects.filter(user_id=self.teacher.id)

        self.assertTrue(messages.exists())
        self.assertEqual(MessageEvent.LEAVE_APPROVED, messages.first().event)
        self.assertIn("has been approved", messages.first().body)

    def test_rejecting_tells_the_applicant_and_writes_no_attendance(self):
        leave = factories.StaffLeaveFactory(staff_profile=self.teacher_profile)

        response = self.as_user(self.admin).patch(
            f"/api/v1/leaves/{leave.id}/reject", {"remarks": "Too short notice."},
            format="json",
        )

        self.assertEqual(200, response.status_code)
        self.assertEqual(LeaveStatus.REJECTED, response.data["status"])
        self.assertEqual(0, StaffAttendance.objects.count())
        self.assertEqual(
            MessageEvent.LEAVE_REJECTED,
            Message.objects.filter(user_id=self.teacher.id).first().event,
        )

    def test_an_hod_cannot_decide_for_another_department(self):
        outsider = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        leave = factories.StaffLeaveFactory(
            staff_profile=self.employee(outsider, self.arts)
        )

        response = self.as_user(self.hod).patch(
            f"/api/v1/leaves/{leave.id}/approve", {}, format="json"
        )

        self.assertEqual(403, response.status_code)

    def test_an_hod_cannot_decide_their_own_request(self):
        # They head the department they belong to, so the department check
        # alone would let this through.
        leave = factories.StaffLeaveFactory(staff_profile=self.hod_profile)

        response = self.as_user(self.hod).patch(
            f"/api/v1/leaves/{leave.id}/approve", {}, format="json"
        )

        self.assertEqual(403, response.status_code)

    def test_a_teacher_cannot_decide_their_own_request(self):
        leave = factories.StaffLeaveFactory(staff_profile=self.teacher_profile)

        response = self.as_user(self.teacher).patch(
            f"/api/v1/leaves/{leave.id}/approve", {}, format="json"
        )

        self.assertEqual(403, response.status_code)

    def test_a_school_admin_cannot_decide_another_schools_request(self):
        elsewhere = factories.SchoolFactory()
        stranger = factories.UserFactory(school=elsewhere, role=UserRole.TEACHER)
        leave = factories.StaffLeaveFactory(
            staff_profile=factories.StaffProfileFactory(
                school=elsewhere, user=stranger, department=None
            )
        )

        response = self.as_user(self.admin).patch(
            f"/api/v1/leaves/{leave.id}/approve", {}, format="json"
        )

        self.assertEqual(403, response.status_code)

    def test_a_super_admin_decides_anywhere(self):
        super_admin = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        leave = factories.StaffLeaveFactory(staff_profile=self.teacher_profile)

        response = self.as_user(super_admin).patch(
            f"/api/v1/leaves/{leave.id}/approve", {}, format="json"
        )

        self.assertEqual(200, response.status_code)

    def test_a_decision_is_taken_once(self):
        leave = factories.StaffLeaveFactory(
            staff_profile=self.teacher_profile, status=LeaveStatus.APPROVED
        )

        response = self.as_user(self.admin).patch(
            f"/api/v1/leaves/{leave.id}/reject", {}, format="json"
        )

        self.assertEqual(409, response.status_code)
        self.assertEqual("LEAVE_ALREADY_REVIEWED", response.data["code"])

    # -- what the list shows ------------------------------------------------

    def test_a_teacher_sees_only_their_own_history(self):
        factories.StaffLeaveFactory(staff_profile=self.teacher_profile)
        factories.StaffLeaveFactory(staff_profile=self.hod_profile)

        response = self.as_user(self.teacher).get("/api/v1/leaves")

        self.assertEqual(200, response.status_code)
        self.assertEqual(1, len(response.data["data"]))
        self.assertEqual(
            self.teacher_profile.id, response.data["data"][0]["staff_profile_id"]
        )

    def test_an_hod_sees_their_whole_department(self):
        factories.StaffLeaveFactory(staff_profile=self.teacher_profile)
        factories.StaffLeaveFactory(staff_profile=self.hod_profile)
        outsider = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        factories.StaffLeaveFactory(staff_profile=self.employee(outsider, self.arts))

        response = self.as_user(self.hod).get("/api/v1/leaves")

        self.assertEqual(2, len(response.data["data"]))

    def test_a_school_admin_sees_only_their_own_school(self):
        factories.StaffLeaveFactory(staff_profile=self.teacher_profile)
        elsewhere = factories.SchoolFactory()
        stranger = factories.UserFactory(school=elsewhere, role=UserRole.TEACHER)
        factories.StaffLeaveFactory(
            staff_profile=factories.StaffProfileFactory(
                school=elsewhere, user=stranger, department=None
            )
        )

        response = self.as_user(self.admin).get("/api/v1/leaves")

        self.assertEqual(1, len(response.data["data"]))
        self.assertEqual(self.school.id, response.data["data"][0]["school_id"])

    def test_the_list_filters_by_status_and_department(self):
        factories.StaffLeaveFactory(staff_profile=self.teacher_profile)
        approved = factories.StaffLeaveFactory(
            staff_profile=self.teacher_profile,
            status=LeaveStatus.APPROVED,
            start_date=dt.date(2026, 10, 5),
            end_date=dt.date(2026, 10, 6),
        )

        by_status = self.as_user(self.admin).get("/api/v1/leaves?status=approved")
        by_department = self.as_user(self.admin).get(
            f"/api/v1/leaves?department_id={self.arts.id}"
        )

        self.assertEqual([approved.id], [row["id"] for row in by_status.data["data"]])
        self.assertEqual([], by_department.data["data"])

    def test_the_list_never_shows_a_row_twice_when_two_arrive_together(self):
        # Ordered by created_at alone, two requests applied for in the same
        # second sit in no fixed order, and paging shows one twice while
        # skipping another. The id breaks the tie.
        same_instant = factories.StaffLeaveFactory(
            staff_profile=self.teacher_profile
        ).created_at
        second = factories.StaffLeaveFactory(
            staff_profile=self.hod_profile, created_at=same_instant
        )

        pages = [
            self.as_user(self.admin).get(f"/api/v1/leaves?per_page=1&page={page}")
            for page in (1, 2)
        ]
        seen = [page.data["data"][0]["id"] for page in pages]

        self.assertEqual(2, len(set(seen)))
        self.assertEqual(second.id, seen[0])

    # -- the stat cards -----------------------------------------------------

    def test_the_summary_counts_over_the_same_visibility_as_the_list(self):
        # "Today" is the school's, not the server's - a school in Kolkata is
        # already on tomorrow while a UTC server is not, and these are
        # calendar dates.
        today = dt.date.fromisoformat(SchoolClock.for_school(self.school).date())
        factories.StaffLeaveFactory(staff_profile=self.teacher_profile)
        factories.StaffLeaveFactory(
            staff_profile=self.hod_profile,
            status=LeaveStatus.APPROVED,
            start_date=today - dt.timedelta(days=1),
            end_date=today + dt.timedelta(days=1),
        )

        response = self.as_user(self.admin).get("/api/v1/leaves/summary")

        self.assertEqual(200, response.status_code)
        self.assertEqual(1, response.data["pending"])
        self.assertEqual(1, response.data["on_leave_today"])
        self.assertEqual(0, response.data["rejected"])

    def test_the_summary_is_scoped_to_the_actors_own_leave_for_a_teacher(self):
        factories.StaffLeaveFactory(staff_profile=self.hod_profile)

        response = self.as_user(self.teacher).get("/api/v1/leaves/summary")

        self.assertEqual(0, response.data["pending"])

    def test_a_leave_row_carries_nothing_extra(self):
        leave = factories.StaffLeaveFactory(staff_profile=self.teacher_profile)

        response = self.as_user(self.admin).get("/api/v1/leaves")

        self.assertEqual(
            {
                "id", "school_id", "staff_profile_id", "employee_id", "staff_name",
                "department_name", "leave_type", "start_date", "end_date", "reason",
                "status", "applied_by_name", "reviewed_by_name", "review_remarks",
                "created_at",
            },
            set(response.data["data"][0]),
        )
        self.assertEqual(leave.id, response.data["data"][0]["id"])
        self.assertEqual(1, StaffLeave.objects.count())
