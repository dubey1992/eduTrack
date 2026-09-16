"""The contract the Flutter apps depend on, asserted over HTTP.

Run against Laravel today and against Django tomorrow. Nothing in here knows
which is answering, and that is the point: when every test passes against the
Python backend, the Python backend is finished for these endpoints and the
Flutter apps need no change at all.

    python contract/run.py

See contract/README.md for the environment it needs.
"""

from __future__ import annotations

import unittest

import shapes
import world
from client import Client, sign_in

WORLD: world.World | None = None


def setUpModule() -> None:
    """One school, built once, shared by every test below."""
    global WORLD
    WORLD = world.build()


def tearDownModule() -> None:
    if WORLD is not None:
        world.demolish(WORLD)


class ContractTest(unittest.TestCase):
    """Convenience for reaching the shared world."""

    @property
    def w(self) -> world.World:
        assert WORLD is not None
        return WORLD


# ---------------------------------------------------------------------------


class Authentication(ContractTest):
    def test_signing_in_returns_a_token_and_the_session_user(self):
        response = Client().post(
            "/auth/login",
            {"email": self.w.admin_email, "password": world.TEST_PASSWORD},
        )

        self.assertEqual(200, response.status, f"login\n{response!r}")
        self.assertIn("token", response.body, "the client stores this to stay signed in")
        self.assertIsInstance(response.body["token"], str)
        shapes.assert_shape(self, response.body["user"], shapes.SESSION_USER, "login user")

    def test_the_wrong_password_is_refused_in_the_standard_envelope(self):
        response = Client().post(
            "/auth/login",
            {"email": self.w.admin_email, "password": "definitely-not-the-password"},
        )

        # 401 with the standard envelope, not 422. Wrong credentials are not a
        # malformed request - the form was fine, the answer was no - and the
        # client shows `message` rather than marking up a field.
        shapes.assert_error(self, response, 401, "login with a bad password")
        self.assertEqual("UNAUTHENTICATED", response.body["code"])

    def test_me_describes_the_holder_of_the_token(self):
        response = self.w.admin.get("/me")

        self.assertEqual(200, response.status, f"/me\n{response!r}")
        shapes.assert_shape(self, response.body, shapes.SESSION_USER, "/me")
        self.assertEqual(self.w.admin_email, response.body["email"])

    def test_no_token_is_401_not_a_redirect(self):
        response = Client().get("/me")

        self.assertEqual(
            401,
            response.status,
            "an unauthenticated API call must answer 401; a redirect to a login page "
            f"is a web convention the client cannot read\n{response!r}",
        )

    def test_a_rubbish_token_is_401(self):
        response = Client(token="not-a-real-token").get("/me")

        self.assertEqual(401, response.status, f"/me with a bad token\n{response!r}")


class Envelopes(ContractTest):
    """The two shapes every endpoint in the API shares."""

    def test_a_list_is_paginated_with_meta(self):
        shapes.assert_paginated(self, self.w.admin.get("/students"), "GET /students")

    def test_pagination_honours_per_page(self):
        response = self.w.admin.get("/students", per_page=1)

        shapes.assert_paginated(self, response, "GET /students?per_page=1")
        self.assertEqual(1, response.body["meta"]["per_page"])

    def test_a_missing_record_is_404_in_the_standard_envelope(self):
        shapes.assert_error(self, self.w.admin.get("/students/99999999"), 404, "GET a missing student")

    def test_a_validation_failure_names_the_field(self):
        response = self.w.admin.post("/students", {"first_name": "Nobody"})

        shapes.assert_validation_error(self, response, "admission_number", "POST /students with nothing")


class Students(ContractTest):
    def test_the_list_returns_students_in_the_promised_shape(self):
        response = self.w.admin.get("/students")

        shapes.assert_paginated(self, response, "GET /students")
        self.assertGreaterEqual(len(response.data), 1, "the world built a student; it should be here")

        for student in response.data:
            shapes.assert_shape(self, student, shapes.STUDENT, "a student in the list")

    def test_one_student_is_returned_in_the_promised_shape(self):
        response = self.w.admin.get(f"/students/{self.w.student_id}")

        self.assertEqual(200, response.status, f"GET a student\n{response!r}")
        shapes.assert_shape(self, response.body, shapes.STUDENT, "GET /students/{id}")

    def test_a_student_can_be_admitted_and_comes_back_whole(self):
        response = self.w.admin.post(
            "/students",
            {
                "school_id": self.w.school_id,
                "class_section_id": self.w.class_section_id,
                "admission_number": "CON-NEW-01",
                "first_name": "Zainab",
                "last_name": "Okafor",
                "guardian_name": "Nneka Okafor",
            },
        )

        self.assertEqual(201, response.status, f"POST /students\n{response!r}")
        shapes.assert_shape(self, response.body, shapes.STUDENT, "POST /students")
        self.assertEqual(self.w.school_id, response.body["school_id"], "never the school the client asked for")

    def test_a_duplicate_admission_number_is_refused(self):
        payload = {
            "school_id": self.w.school_id,
            "class_section_id": self.w.class_section_id,
            "admission_number": "CON-DUP-01",
            "first_name": "First",
            "last_name": "Arrival",
            "guardian_name": "A Guardian",
        }

        self.assertEqual(201, self.w.admin.post("/students", payload).status)
        shapes.assert_validation_error(
            self,
            self.w.admin.post("/students", payload),
            "admission_number",
            "POST a duplicate admission number",
        )

    def test_a_student_can_be_edited(self):
        response = self.w.admin.patch(f"/students/{self.w.student_id}", {"first_name": "Renamed"})

        self.assertEqual(200, response.status, f"PATCH a student\n{response!r}")
        shapes.assert_shape(self, response.body, shapes.STUDENT, "PATCH /students/{id}")
        self.assertEqual("Renamed", response.body["first_name"])

    def test_the_search_finds_a_student_in_any_case(self):
        # The difference that crossing to PostgreSQL would otherwise have lost
        # silently. Asserted here too because the contract is what the client
        # sees, not what the database does.
        response = self.w.admin.get("/students", search="renamed")

        shapes.assert_paginated(self, response, "GET /students?search=")
        self.assertIn("Renamed", [s["first_name"] for s in response.data])


class SchoolIsolation(ContractTest):
    """The rules that matter more than any shape in this file.

    Every one of these is a school reading another school's records if the
    backend gets it wrong, and a rewrite is exactly when that happens.
    """

    def test_an_admin_cannot_read_another_schools_student(self):
        response = self.w.other_admin.get(f"/students/{self.w.student_id}")

        self.assertEqual(403, response.status, f"cross-school read must be forbidden\n{response!r}")

    def test_an_admin_cannot_edit_another_schools_student(self):
        response = self.w.other_admin.patch(f"/students/{self.w.student_id}", {"first_name": "Stolen"})

        self.assertEqual(403, response.status, f"cross-school write must be forbidden\n{response!r}")

    def test_a_list_never_includes_another_schools_students(self):
        response = self.w.other_admin.get("/students")

        shapes.assert_paginated(self, response, "the outsider's student list")
        self.assertEqual(
            [],
            [s for s in response.data if s["school_id"] == self.w.school_id],
            "the outsider's list contained students from the other school",
        )

    def test_naming_another_school_in_a_filter_does_not_widen_the_list(self):
        response = self.w.other_admin.get("/students", school_id=self.w.school_id)

        shapes.assert_paginated(self, response, "the outsider filtering by somebody else's school")
        self.assertEqual(
            [],
            [s for s in response.data if s["school_id"] == self.w.school_id],
            "a school_id in the query string widened the result - the client's school_id is never trusted",
        )

    def test_a_school_admin_cannot_create_a_school(self):
        response = self.w.admin.post(
            "/schools",
            {"name": "Should Not Exist", "currency_code": "INR", "timezone": "UTC"},
        )

        self.assertEqual(403, response.status, f"onboarding is a platform action\n{response!r}")

    def test_a_school_admin_cannot_read_the_payments_ledger(self):
        response = self.w.admin.get("/payments")

        self.assertEqual(403, response.status, f"payments are platform business\n{response!r}")


class SuperAdmin(ContractTest):
    def test_a_super_admin_sees_schools_in_the_promised_shape(self):
        response = self.w.super_admin.get("/schools")

        shapes.assert_paginated(self, response, "GET /schools")
        for school in response.data:
            shapes.assert_shape(self, school, shapes.SCHOOL, "a school in the list")

    def test_a_super_admin_reads_one_school(self):
        response = self.w.super_admin.get(f"/schools/{self.w.school_id}")

        self.assertEqual(200, response.status, f"GET a school\n{response!r}")
        shapes.assert_shape(self, response.body, shapes.SCHOOL, "GET /schools/{id}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
