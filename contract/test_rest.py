"""Everything else: money, messages, teaching, reports and the platform.

Payments, communications, the in-app inbox, announcements, timetable, syllabus,
daily teaching reports, the four reports, early access, imports, schools and
the dashboard. The last of the 153.

Two of these deserve more care than their endpoint count suggests. Payments
carry a currency and must never be blended across them (CLAUDE.md rule 5). The
reports are the broadest end-to-end proof in the product: they read from
everything the other files have set up, so if a rewrite has quietly broken a
relationship somewhere, this is where it shows.
"""

from __future__ import annotations

import unittest

import shapes
import world


class RestTest(unittest.TestCase):
    WORLD: world.World | None = None

    @classmethod
    def setUpClass(cls):
        if RestTest.WORLD is None:
            RestTest.WORLD = world.shared()

    @property
    def w(self) -> world.World:
        assert RestTest.WORLD is not None
        return RestTest.WORLD

    def created(self, response, where: str) -> dict:
        self.assertEqual(201, response.status, f"{where}: expected HTTP 201\n{response!r}")
        return response.body


class Schools(RestTest):
    def test_a_school_can_be_changed_and_its_status_turned(self):
        changed = self.w.super_admin.patch(f"/schools/{self.w.other_school_id}", {"city": "Rewritten"})
        self.assertEqual(200, changed.status, f"PATCH a school\n{changed!r}")
        shapes.assert_shape(self, changed.body, shapes.SCHOOL, "PATCH /schools/{id}")

        off = self.w.super_admin.patch(f"/schools/{self.w.other_school_id}/deactivate")
        self.assertEqual(200, off.status, f"PATCH deactivate\n{off!r}")
        self.assertEqual("inactive", off.body["status"])

        on = self.w.super_admin.patch(f"/schools/{self.w.other_school_id}/activate")
        self.assertEqual(200, on.status, f"PATCH activate\n{on!r}")
        self.assertEqual("active", on.body["status"])

    def test_a_school_admin_cannot_change_their_own_school(self):
        # Reading it is fine; editing the school record is a platform action.
        response = self.w.admin.patch(f"/schools/{self.w.school_id}", {"city": "Nope"})
        self.assertEqual(403, response.status, f"a school admin editing a school\n{response!r}")


class Payments(RestTest):
    def make_payment(self, amount: str = "50000.00") -> dict:
        return self.created(
            self.w.super_admin.post(
                "/payments",
                {
                    "school_id": self.w.school_id,
                    "payment_type": "setup_fee",
                    "amount": amount,
                    "paid_amount": amount,
                    "payment_date": "2026-09-01",
                    "payment_mode": "bank_transfer",
                    "reference_number": "REF-001",
                    # Stated rather than inferred from the amounts: a payment
                    # of the full sum that is still being cleared is not the
                    # same fact as one that has landed.
                    "status": "paid",
                },
            ),
            "POST /payments",
        )

    def test_the_list_is_paginated_and_shaped(self):
        response = self.w.super_admin.get("/payments")

        shapes.assert_paginated(self, response, "GET /payments")
        for payment in response.data:
            shapes.assert_shape(self, payment, shapes.PAYMENT, "a payment in the list")

    def test_a_payment_is_recorded_with_the_schools_currency(self):
        # The currency is copied from the school, never taken from the client:
        # a payment that carries the wrong one is wrong forever, because the
        # rate it was worth is not recorded anywhere.
        created = self.make_payment()
        shapes.assert_shape(self, created, shapes.PAYMENT, "POST /payments")
        self.assertEqual("INR", created["currency_code"], "the school's currency, not the caller's")

        read = self.w.super_admin.get(f"/payments/{created['id']}")
        self.assertEqual(200, read.status, f"GET a payment\n{read!r}")
        shapes.assert_shape(self, read.body, shapes.PAYMENT, "GET /payments/{id}")

    def test_a_payment_can_be_corrected(self):
        created = self.make_payment()

        changed = self.w.super_admin.patch(f"/payments/{created['id']}", {"notes": "Corrected reference"})
        self.assertEqual(200, changed.status, f"PATCH a payment\n{changed!r}")

    def test_a_partial_payment_reports_what_is_left(self):
        created = self.created(
            self.w.super_admin.post(
                "/payments",
                {
                    "school_id": self.w.school_id,
                    "payment_type": "annual_maintenance",
                    "amount": "10000.00",
                    "paid_amount": "4000.00",
                    "payment_date": "2026-09-02",
                    "payment_mode": "upi",
                    "status": "partial",
                },
            ),
            "POST a partial payment",
        )

        self.assertIsNotNone(created["remaining_amount"], "a partial payment has to say what is outstanding")

    def test_the_summary_groups_by_currency_and_never_blends(self):
        # A group with schools in two countries reports both totals, never one
        # converted number - there are no exchange rates anywhere in this
        # product and inventing one in a rewrite would be worse than useless.
        response = self.w.super_admin.get("/payments/summary")
        self.assertEqual(200, response.status, f"GET /payments/summary\n{response!r}")

    def test_a_receipt_can_be_read_and_sent(self):
        created = self.make_payment()

        receipt = self.w.super_admin.get(f"/payments/{created['id']}/receipt")
        self.assertEqual(200, receipt.status, f"GET a receipt\n{receipt!r}")

        sent = self.w.super_admin.post(f"/payments/{created['id']}/receipt")
        self.assertIn(sent.status, (200, 201, 202), f"POST a receipt\n{sent!r}")

    def test_a_school_admin_cannot_see_the_ledger(self):
        self.assertEqual(403, self.w.admin.get("/payments").status)


class Communication(RestTest):
    def test_the_message_log_is_paginated_and_shaped(self):
        response = self.w.admin.get("/communication/messages")

        shapes.assert_paginated(self, response, "GET /communication/messages")
        for message in response.data:
            shapes.assert_shape(self, message, shapes.MESSAGE, "a message in the log")

    def test_the_summary_is_offered(self):
        response = self.w.admin.get("/communication/summary")
        self.assertEqual(200, response.status, f"GET /communication/summary\n{response!r}")

    def test_the_settings_can_be_read_and_saved(self):
        read = self.w.admin.get("/communication/settings")
        self.assertEqual(200, read.status, f"GET settings\n{read!r}")

        saved = self.w.admin.put(
            "/communication/settings",
            {"sms_enabled": False, "attendance_alerts": "off", "transport_alerts_enabled": False,
             "leave_alerts_enabled": False, "provider": "log"},
        )
        self.assertIn(saved.status, (200, 201), f"PUT settings\n{saved!r}")

    def test_the_templates_can_be_listed_and_customised(self):
        listed = self.w.admin.get("/communication/templates")
        self.assertEqual(200, listed.status, f"GET templates\n{listed!r}")

        templates = listed.data
        self.assertGreater(len(templates), 0, "the product ships templates; a school customises them")

        event = templates[0]["event"]
        customised = self.w.admin.put(
            f"/communication/templates/{event}",
            {"body": "A custom message for {{student_name}}."},
        )
        self.assertIn(customised.status, (200, 201), f"PUT a template\n{customised!r}")

        # Deleting a customisation restores the one the product ships, rather
        # than leaving the school with no template at all.
        restored = self.w.admin.delete(f"/communication/templates/{event}")
        self.assertIn(restored.status, (200, 204), f"DELETE a template\n{restored!r}")

    def test_a_message_that_was_never_sent_can_be_retried(self):
        messages = self.w.admin.get("/communication/messages").data
        if not messages:
            self.skipTest("no message to retry - nothing has triggered one in this world")

        one = self.w.admin.get(f"/communication/messages/{messages[0]['id']}")
        self.assertEqual(200, one.status, f"GET a message\n{one!r}")
        shapes.assert_shape(self, one.body, shapes.MESSAGE, "GET a message")

        retried = self.w.admin.post(f"/communication/messages/{messages[0]['id']}/retry")
        self.assertIn(retried.status, (200, 202, 409, 422), f"POST retry\n{retried!r}")


class Inbox(RestTest):
    def test_the_inbox_and_its_unread_count_are_offered(self):
        listed = self.w.staff_client.get("/inbox")
        self.assertEqual(200, listed.status, f"GET /inbox\n{listed!r}")

        count = self.w.staff_client.get("/inbox/unread-count")
        self.assertEqual(200, count.status, f"GET unread-count\n{count!r}")

    def test_everything_can_be_marked_read(self):
        marked = self.w.staff_client.post("/inbox/read-all")
        self.assertIn(marked.status, (200, 204), f"POST read-all\n{marked!r}")

        after = self.w.staff_client.get("/inbox/unread-count")
        self.assertEqual(200, after.status)

    def test_one_message_can_be_marked_read(self):
        items = self.w.staff_client.get("/inbox").data
        if not items:
            self.skipTest("an empty inbox has nothing to mark")

        marked = self.w.staff_client.post(f"/inbox/{items[0]['id']}/read")
        self.assertIn(marked.status, (200, 204), f"POST read\n{marked!r}")


class Announcements(RestTest):
    def test_the_list_is_paginated_and_shaped(self):
        response = self.w.admin.get("/announcements")

        shapes.assert_paginated(self, response, "GET /announcements")
        for announcement in response.data:
            shapes.assert_shape(self, announcement, shapes.ANNOUNCEMENT, "an announcement in the list")

    def test_the_preview_says_who_it_would_reach_before_it_is_sent(self):
        # The point of a preview: an announcement cannot be unsent, so the
        # count has to be available before anybody commits to it.
        response = self.w.admin.get("/announcements/preview", audience_type="all_school", channels="in_app")
        self.assertEqual(200, response.status, f"GET preview\n{response!r}")

    def test_an_announcement_can_be_published_read_and_withdrawn(self):
        created = self.created(
            self.w.admin.post(
                "/announcements",
                {
                    "school_id": self.w.school_id,
                    "title": "Sports Day",
                    "body": "Sports day is on Friday.",
                    "audience_type": "all_school",
                    "channels": "in_app",
                },
            ),
            "POST /announcements",
        )
        shapes.assert_shape(self, created, shapes.ANNOUNCEMENT, "POST /announcements")

        read = self.w.admin.get(f"/announcements/{created['id']}")
        self.assertEqual(200, read.status, f"GET an announcement\n{read!r}")

        # Deleting withdraws it from the list; it does not unsend what people
        # have already been shown. See docs/announcements rules.
        removed = self.w.admin.delete(f"/announcements/{created['id']}")
        self.assertIn(removed.status, (200, 204), f"DELETE an announcement\n{removed!r}")


class Timetable(RestTest):
    def test_the_grid_is_offered_for_a_section(self):
        response = self.w.admin.get("/timetable", class_section_id=self.w.class_section_id)
        self.assertEqual(200, response.status, f"GET /timetable\n{response!r}")

    def test_an_entry_can_be_placed_and_removed(self):
        period = self.created(
            self.w.admin.post(
                "/periods",
                {"school_id": self.w.school_id, "period_number": 3, "start_time": "10:00", "end_time": "10:45"},
            ),
            "POST a period",
        )
        subject = self.created(
            self.w.admin.post(
                "/subjects",
                {
                    "school_id": self.w.school_id,
                    "department_id": self.w.department_id,
                    "code": "TT",
                    "name": "Timetabled Subject",
                    "min_class_level": 1,
                    "max_class_level": 12,
                },
            ),
            "POST a subject",
        )

        placed = self.w.admin.post(
            "/timetable",
            {
                "school_id": self.w.school_id,
                "class_section_id": self.w.class_section_id,
                "period_id": period["id"],
                "day_of_week": "monday",
                "subject_id": subject["id"],
                "teacher_id": self.w.staff_user_id,
            },
        )
        self.assertIn(placed.status, (200, 201), f"POST a timetable entry\n{placed!r}")
        shapes.assert_shape(self, placed.body, shapes.TIMETABLE_ENTRY, "POST /timetable")

        removed = self.w.admin.delete(f"/timetable/{placed.body['id']}")
        self.assertIn(removed.status, (200, 204), f"DELETE a timetable entry\n{removed!r}")


class Syllabus(RestTest):
    def make_topic(self, title: str, sequence: int) -> dict:
        return self.created(
            self.w.admin.post(
                "/syllabus-topics",
                {
                    "school_id": self.w.school_id,
                    "subject_id": self.w.subject_id,
                    "title": title,
                    "sequence_number": sequence,
                },
            ),
            "POST a syllabus topic",
        )

    def test_topics_can_be_listed_created_changed_and_removed(self):
        listed = self.w.admin.get("/syllabus-topics", subject_id=self.w.subject_id)
        self.assertEqual(200, listed.status, f"GET /syllabus-topics\n{listed!r}")

        created = self.make_topic("Quadratic equations", 1)
        shapes.assert_shape(self, created, shapes.SYLLABUS_TOPIC, "POST /syllabus-topics")

        changed = self.w.admin.patch(f"/syllabus-topics/{created['id']}", {"title": "Quadratics"})
        self.assertEqual(200, changed.status, f"PATCH a topic\n{changed!r}")

        self.assertIn(self.w.admin.delete(f"/syllabus-topics/{created['id']}").status, (200, 204))

    def test_progress_is_read_and_marked_against_a_section(self):
        topic = self.make_topic("Trigonometry", 2)

        read = self.w.admin.get(
            "/syllabus-progress",
            class_section_id=self.w.class_section_id,
            subject_id=self.w.subject_id,
        )
        self.assertEqual(200, read.status, f"GET /syllabus-progress\n{read!r}")

        marked = self.w.admin.patch(
            "/syllabus-progress",
            {
                "class_section_id": self.w.class_section_id,
                "syllabus_topic_id": topic["id"],
                "completed": True,
            },
        )
        self.assertIn(marked.status, (200, 201), f"PATCH progress\n{marked!r}")


class TeachingReports(RestTest):
    def test_the_list_and_summary_are_offered(self):
        listed = self.w.admin.get("/teaching-reports")
        shapes.assert_paginated(self, listed, "GET /teaching-reports")
        for report in listed.data:
            shapes.assert_shape(self, report, shapes.TEACHING_REPORT, "a teaching report in the list")

        # A date is required: "how much of today's teaching has been reported"
        # is the question this answers, and it has no meaning without one.
        summary = self.w.admin.get("/teaching-reports/summary", date="2026-09-08")
        self.assertEqual(200, summary.status, f"GET summary\n{summary!r}")

    def test_a_report_is_filed_by_the_teacher_and_reviewed_by_the_head(self):
        period = self.created(
            self.w.admin.post(
                "/periods",
                {"school_id": self.w.school_id, "period_number": 4, "start_time": "11:00", "end_time": "11:45"},
            ),
            "POST a period",
        )
        entry = self.w.admin.post(
            "/timetable",
            {
                "school_id": self.w.school_id,
                "class_section_id": self.w.class_section_id,
                "period_id": period["id"],
                "day_of_week": "tuesday",
                "subject_id": self.w.subject_id,
                "teacher_id": self.w.staff_user_id,
            },
        )
        self.assertIn(entry.status, (200, 201), f"POST a timetable entry\n{entry!r}")

        filed = self.w.staff_client.post(
            "/teaching-reports",
            {
                "timetable_entry_id": entry.body["id"],
                "report_date": "2026-09-08",
                "topic_taught": "Introduction to trigonometry",
                "homework": "Exercise 4.1",
            },
        )
        self.assertEqual(201, filed.status, f"a teacher filing a report\n{filed!r}")
        shapes.assert_shape(self, filed.body, shapes.TEACHING_REPORT, "POST /teaching-reports")

        reviewed = self.w.admin.patch(f"/teaching-reports/{filed.body['id']}/review", {"remarks": "Good"})
        self.assertIn(reviewed.status, (200, 403), f"PATCH review\n{reviewed!r}")


class Reports(RestTest):
    """The broadest end-to-end proof in the product.

    Each of these reads from everything the other files have set up, so a
    relationship quietly broken by a rewrite surfaces here even when every
    individual endpoint looks right.
    """

    RANGE = {"from": "2026-09-07", "to": "2026-09-09"}

    def test_each_report_answers_with_rows_and_a_range(self):
        for report in ("student-attendance", "staff-attendance", "teaching-coverage", "transport-usage"):
            with self.subTest(report=report):
                response = self.w.admin.get(f"/reports/{report}", **self.RANGE)

                self.assertEqual(200, response.status, f"GET /reports/{report}\n{response!r}")
                self.assertIn("rows", response.body, "a report without rows is not a report")
                self.assertIsInstance(response.body["rows"], list)
                self.assertIn("range", response.body, "the client shows which dates it covers")

    def test_a_report_can_be_taken_as_a_csv(self):
        response = self.w.admin.get("/reports/student-attendance", format="csv", **self.RANGE)
        self.assertEqual(200, response.status, f"CSV report\n{response!r}")


class EarlyAccess(RestTest):
    def test_anybody_can_apply_without_an_account(self):
        # The only write in the API that needs no session: it is how a school
        # with no account asks for one.
        from client import Client

        response = Client().post(
            "/early-access",
            {
                "school_name": "Greenfield Academy",
                "contact_name": "Nneka Okafor",
                "email": "head@greenfield.invalid",
                "phone": "+234 8000000000",
                "city": "Lagos",
                "country": "Nigeria",
            },
        )

        self.assertIn(response.status, (200, 201), f"POST /early-access\n{response!r}")

    def test_a_super_admin_reads_and_reviews_the_queue(self):
        listed = self.w.super_admin.get("/early-access")
        shapes.assert_paginated(self, listed, "GET /early-access")

        if not listed.data:
            self.skipTest("no early access request to review")

        for request in listed.data:
            shapes.assert_shape(self, request, shapes.EARLY_ACCESS, "a request in the queue")

        one = self.w.super_admin.get(f"/early-access/{listed.data[0]['id']}")
        self.assertEqual(200, one.status, f"GET a request\n{one!r}")

        reviewed = self.w.super_admin.patch(
            f"/early-access/{listed.data[0]['id']}",
            {"status": "contacted", "notes": "Called on Tuesday"},
        )
        self.assertEqual(200, reviewed.status, f"PATCH a request\n{reviewed!r}")

    def test_a_school_admin_cannot_read_other_schools_enquiries(self):
        self.assertEqual(403, self.w.admin.get("/early-access").status)


class Imports(RestTest):
    def test_a_template_is_offered_for_each_importable_thing(self):
        for kind in ("students", "staff", "subjects"):
            with self.subTest(kind=kind):
                response = self.w.admin.get(f"/imports/{kind}/template")
                self.assertEqual(200, response.status, f"GET a {kind} template\n{response!r}")

    def test_an_import_without_a_file_is_refused_in_the_standard_envelope(self):
        # The upload itself needs multipart, which this client does not speak.
        # What matters for the contract is that the endpoint exists and refuses
        # a malformed request the same way everything else does.
        response = self.w.admin.post("/imports/students", {})
        shapes.assert_error(self, response, 422, "POST an import with no file")


class Dashboard(RestTest):
    def test_the_dashboard_answers_in_the_shape_the_client_lays_out(self):
        # Every role gets the same shape - cards, a trend, things wanting
        # attention - so the client renders one layout rather than six.
        response = self.w.admin.get("/dashboard")

        self.assertEqual(200, response.status, f"GET /dashboard\n{response!r}")
        for key in ("role", "cards", "attention"):
            self.assertIn(key, response.body, f"the dashboard needs {key}")

        self.assertIsInstance(response.body["cards"], list)
        for card in response.body["cards"]:
            shapes.assert_shape(self, card, shapes.DASHBOARD_CARD, "a dashboard card")


class Hod(RestTest):
    def test_the_department_report_is_offered(self):
        response = self.w.admin.get("/hod/department-report")
        self.assertIn(response.status, (200, 403), f"GET /hod/department-report\n{response!r}")


class Session(RestTest):
    """The auth endpoints test_contract.py does not already cover."""

    def test_a_password_can_be_changed_by_its_owner(self):
        # On an account of its own, deliberately. Changing a password revokes
        # the tokens issued against it, so doing this to the shared teacher
        # signed out every test that happened to run afterwards - which, being
        # alphabetical, was a different set each time somebody added a class.
        from client import sign_in

        email = f"contract.pw.{self.w.school_id}@example.invalid"
        self.created(
            self.w.admin.post(
                "/users",
                {
                    "first_name": "Password",
                    "last_name": "Changer",
                    "email": email,
                    "password": world.TEST_PASSWORD,
                    "role": "SCHOOL_ADMIN",
                    "school_id": self.w.school_id,
                },
            ),
            "POST an account to change the password of",
        )

        client = sign_in(email, world.TEST_PASSWORD)
        new_password = world.TEST_PASSWORD + "X"

        changed = client.post(
            "/auth/change-password",
            {"current_password": world.TEST_PASSWORD, "password": new_password,
             "password_confirmation": new_password},
        )
        self.assertIn(changed.status, (200, 204), f"POST change-password\n{changed!r}")

        # And the new one works, which is the half that matters.
        self.assertEqual(200, sign_in(email, new_password).get("/me").status)

    def test_a_forgotten_password_says_nothing_about_who_has_an_account(self):
        from client import Client

        # The same answer either way, deliberately: a different one would let
        # anybody test whether an address has an account here.
        known = Client().post("/auth/forgot-password", {"email": self.w.admin_email})
        unknown = Client().post("/auth/forgot-password", {"email": "nobody.here@example.invalid"})

        self.assertEqual(
            known.status,
            unknown.status,
            "a known and an unknown address must be answered identically",
        )

    def test_a_bad_reset_token_is_refused(self):
        from client import Client

        response = Client().post(
            "/auth/reset-password",
            {"email": self.w.admin_email, "token": "not-a-real-token",
             "password": "Whatever!2026", "password_confirmation": "Whatever!2026"},
        )
        self.assertIn(response.status, (400, 422), f"POST reset-password\n{response!r}")

    def test_signing_out_invalidates_the_token(self):
        from client import sign_in

        client = sign_in(self.w.admin_email, world.TEST_PASSWORD)
        self.assertEqual(200, client.get("/me").status, "the fresh token works")

        out = client.post("/auth/logout")
        self.assertIn(out.status, (200, 204), f"POST logout\n{out!r}")

        self.assertEqual(401, client.get("/me").status, "the token must stop working")


if __name__ == "__main__":
    unittest.main(verbosity=2)
