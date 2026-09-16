"""People, and what happens to them daily.

Admin accounts, teaching and non-teaching staff, the rest of the student
endpoints, and the two attendance registers plus leave. This is the part of the
product a school touches every morning, and the part it notices within minutes
if a rewrite gets it wrong.

The register endpoints get more attention than their count suggests. They are
the only place in the API that answers with a *composed* document rather than a
record - a roster with a student's status against each name - and a client that
cannot read it cannot take attendance at all.
"""

from __future__ import annotations

import unittest

import shapes
import world


class PeopleTest(unittest.TestCase):
    WORLD: world.World | None = None

    @classmethod
    def setUpClass(cls):
        if PeopleTest.WORLD is None:
            PeopleTest.WORLD = world.shared()

    @property
    def w(self) -> world.World:
        assert PeopleTest.WORLD is not None
        return PeopleTest.WORLD

    def created(self, response, where: str) -> dict:
        self.assertEqual(201, response.status, f"{where}: expected HTTP 201\n{response!r}")
        return response.body


class AdminUsers(PeopleTest):
    def test_the_list_is_paginated_and_shaped(self):
        response = self.w.admin.get("/users")

        shapes.assert_paginated(self, response, "GET /users")
        for user in response.data:
            shapes.assert_shape(self, user, shapes.USER, "a user in the list")

    def test_an_account_can_be_created_read_and_changed(self):
        created = self.created(
            self.w.admin.post(
                "/users",
                {
                    "first_name": "Sub",
                    "last_name": "Admin",
                    "email": f"contract.sub.{self.w.school_id}@example.invalid",
                    "password": world.TEST_PASSWORD,
                    "role": "SCHOOL_ADMIN",
                    "school_id": self.w.school_id,
                },
            ),
            "POST /users",
        )
        shapes.assert_shape(self, created, shapes.USER, "POST /users")
        self.assertEqual(self.w.school_id, created["school_id"], "never the school the client asked for")

        read = self.w.admin.get(f"/users/{created['id']}")
        self.assertEqual(200, read.status, f"GET a user\n{read!r}")
        shapes.assert_shape(self, read.body, shapes.USER, "GET /users/{id}")

        changed = self.w.admin.patch(f"/users/{created['id']}", {"first_name": "Renamed"})
        self.assertEqual(200, changed.status, f"PATCH a user\n{changed!r}")
        self.assertEqual("Renamed", changed.body["first_name"])

    def test_an_account_can_be_deactivated_and_brought_back(self):
        created = self.created(
            self.w.admin.post(
                "/users",
                {
                    "first_name": "Temporary",
                    "last_name": "Admin",
                    "email": f"contract.temp.{self.w.school_id}@example.invalid",
                    "password": world.TEST_PASSWORD,
                    "role": "SCHOOL_ADMIN",
                    "school_id": self.w.school_id,
                },
            ),
            "POST a user to deactivate",
        )

        off = self.w.admin.patch(f"/users/{created['id']}/deactivate")
        self.assertEqual(200, off.status, f"PATCH deactivate\n{off!r}")
        self.assertEqual("inactive", off.body["status"])

        on = self.w.admin.patch(f"/users/{created['id']}/activate")
        self.assertEqual(200, on.status, f"PATCH activate\n{on!r}")
        self.assertEqual("active", on.body["status"])

    def test_an_address_already_in_use_is_refused(self):
        shapes.assert_validation_error(
            self,
            self.w.admin.post(
                "/users",
                {
                    "first_name": "Clash",
                    "last_name": "Admin",
                    "email": self.w.admin_email,
                    "password": world.TEST_PASSWORD,
                    "role": "SCHOOL_ADMIN",
                    "school_id": self.w.school_id,
                },
            ),
            "email",
            "POST a duplicate address",
        )

    def test_another_school_cannot_read_this_accounts(self):
        mine = self.w.admin.get("/users").data
        self.assertGreaterEqual(len(mine), 1)

        response = self.w.other_admin.get(f"/users/{mine[0]['id']}")
        self.assertEqual(403, response.status, f"cross-school read\n{response!r}")


class Staff(PeopleTest):
    def test_the_list_is_paginated_and_shaped(self):
        response = self.w.admin.get("/staff")

        shapes.assert_paginated(self, response, "GET /staff")
        for member in response.data:
            shapes.assert_shape(self, member, shapes.STAFF, "an employee in the list")

    def test_an_employee_is_onboarded_with_a_login_and_a_profile(self):
        # One call creates both. A rewrite that creates the profile without the
        # account leaves somebody who exists on a roster and cannot sign in.
        created = self.created(
            self.w.admin.post(
                "/staff",
                {
                    "school_id": self.w.school_id,
                    "first_name": "Priya",
                    "last_name": "Sharma",
                    "email": f"contract.teacher.{self.w.school_id}@example.invalid",
                    "password": world.TEST_PASSWORD,
                    "role": "TEACHER",
                    "employee_id": f"EMP-{self.w.school_id}",
                    "department_id": self.w.department_id,
                    "designation": "Teacher",
                    "joining_date": "2026-04-01",
                },
            ),
            "POST /staff",
        )
        shapes.assert_shape(self, created, shapes.STAFF, "POST /staff")
        self.assertGreater(created["user_id"], 0, "the employment record has to point at a login")

        read = self.w.admin.get(f"/staff/{created['id']}")
        self.assertEqual(200, read.status, f"GET an employee\n{read!r}")
        shapes.assert_shape(self, read.body, shapes.STAFF, "GET /staff/{id}")

        changed = self.w.admin.patch(f"/staff/{created['id']}", {"designation": "Senior Teacher"})
        self.assertEqual(200, changed.status, f"PATCH an employee\n{changed!r}")

    def test_another_school_cannot_read_this_staff(self):
        mine = self.w.admin.get("/staff").data
        if not mine:
            self.skipTest("no staff to check against")

        response = self.w.other_admin.get(f"/staff/{mine[0]['id']}")
        self.assertEqual(403, response.status, f"cross-school read\n{response!r}")


class Students(PeopleTest):
    """The endpoints test_contract.py does not already cover."""

    def test_a_student_can_be_deactivated_and_brought_back(self):
        off = self.w.admin.patch(f"/students/{self.w.student_id}/deactivate")
        self.assertEqual(200, off.status, f"PATCH deactivate\n{off!r}")
        self.assertEqual("inactive", off.body["status"])

        on = self.w.admin.patch(f"/students/{self.w.student_id}/activate")
        self.assertEqual(200, on.status, f"PATCH activate\n{on!r}")
        self.assertEqual("active", on.body["status"])

    def test_another_school_cannot_deactivate_this_student(self):
        # Worth asserting separately from reading: a rewrite can get the read
        # right and leave a write unguarded, and this is the one that does harm.
        response = self.w.other_admin.patch(f"/students/{self.w.student_id}/deactivate")
        self.assertEqual(403, response.status, f"cross-school deactivate\n{response!r}")


class StudentAttendance(PeopleTest):
    DATE = "2026-09-07"  # A Monday, so no weekend rule gets in the way.

    def test_the_register_is_a_roster_the_client_can_render(self):
        response = self.w.admin.get(
            "/attendance/register",
            class_section_id=self.w.class_section_id,
            date=self.DATE,
        )

        self.assertEqual(200, response.status, f"GET the register\n{response!r}")
        self.assertIsInstance(response.body, dict, "the register is a document, not a list")
        self.assertIn("students", response.body, "a register without a roster is not a register")
        self.assertIsInstance(response.body["students"], list)

        for entry in response.body["students"]:
            shapes.assert_shape(self, entry, shapes.REGISTER_ENTRY, "a name on the register")

    def test_attendance_can_be_submitted_then_corrected(self):
        submitted = self.w.admin.post(
            "/attendance",
            {
                "class_section_id": self.w.class_section_id,
                "attendance_date": self.DATE,
                "records": [{"student_id": self.w.student_id, "status": "present"}],
            },
        )
        self.assertEqual(201, submitted.status, f"POST attendance\n{submitted!r}")

        # Marking is not a one-shot: a register corrected later in the day has
        # to overwrite rather than duplicate.
        corrected = self.w.admin.patch(
            "/attendance",
            {
                "class_section_id": self.w.class_section_id,
                "attendance_date": self.DATE,
                "records": [{"student_id": self.w.student_id, "status": "absent"}],
            },
        )
        self.assertEqual(200, corrected.status, f"PATCH attendance\n{corrected!r}")

        history = self.w.admin.get("/attendance", class_section_id=self.w.class_section_id, date=self.DATE)
        self.assertEqual(200, history.status, f"GET attendance\n{history!r}")
        for record in history.data:
            shapes.assert_shape(self, record, shapes.ATTENDANCE, "an attendance record")

    def test_another_school_cannot_read_this_register(self):
        response = self.w.other_admin.get(
            "/attendance/register",
            class_section_id=self.w.class_section_id,
            date=self.DATE,
        )
        self.assertEqual(403, response.status, f"cross-school register\n{response!r}")


class StaffAttendance(PeopleTest):
    DATE = "2026-09-08"

    def test_the_staff_register_is_a_roster(self):
        response = self.w.admin.get("/staff-attendance/register", date=self.DATE)

        self.assertEqual(200, response.status, f"GET the staff register\n{response!r}")
        self.assertIsInstance(response.body, dict, "the register is a document, not a list")

    def test_the_staff_history_is_shaped(self):
        response = self.w.admin.get("/staff-attendance", date=self.DATE)

        self.assertEqual(200, response.status, f"GET staff attendance\n{response!r}")
        for record in response.data:
            shapes.assert_shape(self, record, shapes.STAFF_ATTENDANCE, "a staff attendance record")


class Leave(PeopleTest):
    def test_the_list_is_paginated_and_shaped(self):
        response = self.w.admin.get("/leaves")

        shapes.assert_paginated(self, response, "GET /leaves")
        for leave in response.data:
            shapes.assert_shape(self, leave, shapes.LEAVE, "a leave request in the list")

    def test_the_summary_is_offered(self):
        response = self.w.admin.get("/leaves/summary")
        self.assertEqual(200, response.status, f"GET /leaves/summary\n{response!r}")

    def test_a_teachers_request_waits_for_a_decision(self):
        raised = self.w.staff_client.post(
            "/leaves",
            {
                "staff_profile_id": self.w.staff_profile_id,
                "leave_type": "casual",
                "start_date": "2026-10-05",
                "end_date": "2026-10-06",
                "reason": "Family commitment",
            },
        )

        self.assertEqual(201, raised.status, f"a teacher applying\n{raised!r}")
        shapes.assert_shape(self, raised.body, shapes.LEAVE, "POST /leaves")
        self.assertEqual("pending", raised.body["status"], "somebody else's leave waits for a decision")

    def test_an_admins_own_request_is_approved_on_the_spot(self):
        # Not a shortcut in the test - a rule in the product. A School Admin is
        # the head of the school, so there is nobody above them to ask, and the
        # request is recorded as approved with them as the reviewer. Written
        # down because a rewrite that makes it pending would leave an approval
        # nobody can ever give.
        raised = self.w.admin.post(
            "/leaves",
            {
                "staff_profile_id": self.w.staff_profile_id,
                "leave_type": "casual",
                "start_date": "2026-10-12",
                "end_date": "2026-10-12",
                "reason": "Raised by the head",
            },
        )

        self.assertEqual(201, raised.status, f"an admin applying\n{raised!r}")
        self.assertEqual("approved", raised.body["status"], "the head of the school approves as they apply")

    def test_a_pending_request_can_be_approved(self):
        raised = self.w.staff_client.post(
            "/leaves",
            {
                "staff_profile_id": self.w.staff_profile_id,
                "leave_type": "casual",
                "start_date": "2026-11-02",
                "end_date": "2026-11-02",
                "reason": "Appointment",
            },
        )
        self.assertEqual(201, raised.status, f"a teacher applying\n{raised!r}")

        approved = self.w.admin.patch(f"/leaves/{raised.body['id']}/approve", {"review_remarks": "Fine"})
        self.assertEqual(200, approved.status, f"PATCH approve\n{approved!r}")
        self.assertEqual("approved", approved.body["status"])

    def test_a_pending_request_can_be_rejected(self):
        raised = self.w.staff_client.post(
            "/leaves",
            {
                "staff_profile_id": self.w.staff_profile_id,
                "leave_type": "casual",
                "start_date": "2026-11-09",
                "end_date": "2026-11-09",
                "reason": "Personal",
            },
        )
        self.assertEqual(201, raised.status, f"a teacher applying\n{raised!r}")

        rejected = self.w.admin.patch(f"/leaves/{raised.body['id']}/reject", {"review_remarks": "Short notice"})
        self.assertEqual(200, rejected.status, f"PATCH reject\n{rejected!r}")
        self.assertEqual("rejected", rejected.body["status"])

    def test_a_decision_cannot_be_taken_twice(self):
        # The other half of the rule, and the one that protects a record:
        # a request that has been answered is answered, and a second reviewer
        # cannot quietly overturn the first.
        raised = self.w.staff_client.post(
            "/leaves",
            {
                "staff_profile_id": self.w.staff_profile_id,
                "leave_type": "casual",
                "start_date": "2026-11-16",
                "end_date": "2026-11-16",
                "reason": "Personal",
            },
        )
        self.assertEqual(201, raised.status)

        self.assertEqual(200, self.w.admin.patch(f"/leaves/{raised.body['id']}/approve").status)

        second = self.w.admin.patch(f"/leaves/{raised.body['id']}/reject", {"review_remarks": "Changed my mind"})

        # 409, not 403. The reviewer is allowed to review - the request has
        # simply already been answered, and conflicting with the current state
        # is what 409 is for. Worth pinning: a rewrite reaching for 403 here
        # would tell the client "you may not", which is a different and wrong
        # thing to show somebody who may.
        shapes.assert_error(self, second, 409, "re-deciding a decided request")


if __name__ == "__main__":
    unittest.main(verbosity=2)
