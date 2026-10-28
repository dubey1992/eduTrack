"""The fee reports, the student statement PDF and the dashboard's fee cards
(docs/fees.md, F5; docs/reports.md).

Same school, year and frozen clock as test_fees_dues.py: 2026-27, "now" is
15 July 2026, 11:30 in Kolkata. Aarav (ADM-1, Class 8 - A) owes Class 8's
Tuition: 1,000 due on 10 April, 10 July, 10 October and 10 January.
"""

import datetime as dt
from unittest import mock

from django.db import connection
from django.test.utils import CaptureQueriesContext

from school import factories
from school.enums import UserRole
from school.fees import ledger, statement_pdf
from school.fees.dues import FeeDueService
from school.fees.resources import mode_label
from school.models import FeeReceipt, ModuleSetting, RolePermission, StudentFeeDue
from school.reports import FeeCollectionReport, FeeOutstandingReport, pdf

from .test_fees_adjustments import AdjustmentsTestCase

REPORTS = "/api/v1/reports"
JULY = {"from": "2026-07-01", "to": "2026-07-15"}


def at(moment: dt.datetime):
    return mock.patch("django.utils.timezone.now", return_value=moment)


class FeeReportsTestCase(AdjustmentsTestCase):
    def report(self, kind, user=None, **params):
        return self.as_user(user or self.accountant).get(f"{REPORTS}/{kind}", params)

    def ok(self, kind, user=None, **params) -> dict:
        response = self.report(kind, user, **params)
        self.assertEqual(200, response.status_code, getattr(response, "data", response))

        return response.data

    def charged(self, first_name, **fields):
        student = self.student(first_name, **fields)
        FeeDueService.sync_student(student, self.year)

        return student

    def in_dollars(self, student):
        """A student whose dues are in another currency - as after a school's
        currency was changed."""
        StudentFeeDue.objects.filter(student=student).update(currency_code="USD")

    def cancel(self, receipt_id, reason="Entered twice"):
        response = self.as_user(self.accountant).post(f"/api/v1/fees/receipts/{receipt_id}/cancel", {"reason": reason},
                                                      format="json")
        self.assertEqual(200, response.status_code, response.data)


# -- fee collection -------------------------------------------------------------------


class Collection(FeeReportsTestCase):
    def setUp(self):
        super().setUp()
        self.june = self.paid(amount="50.00", receipt_date="2026-06-20")
        self.upi = self.paid(amount="400.00", receipt_date="2026-07-10", payment_mode="upi", reference="UTR123")
        self.cash = self.paid(amount="1000.00", receipt_date="2026-07-15")
        self.wrong = self.paid(amount="100.00", receipt_date="2026-07-12")
        self.cancel(self.wrong["id"])

    def test_one_line_per_valid_receipt_in_the_range_oldest_first(self):
        data = self.ok("fee-collection", **JULY)

        self.assertEqual([self.upi["receipt_number"], self.cash["receipt_number"]],
                         [row["receipt_number"] for row in data["rows"]])
        self.assertEqual(
            {
                "receipt_id": self.upi["id"], "student_id": self.aarav.id, "receipt_date": "2026-07-10",
                "receipt_number": self.upi["receipt_number"], "admission_number": "ADM-1", "student": "Aarav Shah",
                "class_section": "Class 8 - A", "payment_mode": mode_label("upi"), "reference": "UTR123",
                "received_by": self.accountant.name, "amount": "400.00", "currency_code": "INR",
            },
            data["rows"][0],
        )

    def test_totals_leave_cancelled_receipts_out_and_count_them_beside(self):
        totals = self.ok("fee-collection", **JULY)["totals"]

        self.assertEqual(2, totals["receipts"])
        self.assertEqual([{"currency_code": "INR", "amount": "1400.00"}], totals["collected"])
        self.assertEqual(1, totals["cancelled_receipts"])
        self.assertEqual([{"currency_code": "INR", "amount": "100.00"}], totals["cancelled_amount"])
        self.assertEqual(
            [("cash", "INR", 1, "1000.00"), ("upi", "INR", 1, "400.00")],
            [(line["payment_mode"], line["currency_code"], line["receipts"], line["amount"])
             for line in totals["by_mode"]],
        )

    def test_currencies_are_kept_apart(self):
        bina = self.charged("Bina", last_name="Rao")
        self.in_dollars(bina)
        self.paid(student=bina, amount="10.00", receipt_date="2026-07-14")

        data = self.ok("fee-collection", **JULY)

        self.assertEqual([{"currency_code": "INR", "amount": "1400.00"}, {"currency_code": "USD", "amount": "10.00"}],
                         data["totals"]["collected"])
        self.assertEqual("USD", data["rows"][1]["currency_code"])

    def test_the_previous_period_is_the_same_length_just_before(self):
        data = self.ok("fee-collection", compare=1, **JULY)

        self.assertEqual({"from": "2026-06-16", "to": "2026-06-30"},
                         {key: data["comparison"]["range"][key] for key in ("from", "to")})
        self.assertEqual(1, data["comparison"]["totals"]["receipts"])
        self.assertEqual([{"currency_code": "INR", "amount": "50.00"}], data["comparison"]["totals"]["collected"])

    def test_as_a_csv_and_a_pdf(self):
        csv = self.report("fee-collection", format="csv", **JULY)
        self.assertEqual(200, csv.status_code)
        text = csv.content.decode("utf-8-sig")
        self.assertTrue(text.startswith('Date,Receipt,"Admission no.",Student,Class,"Paid by",Reference,"Received by",'
                                        "Currency,Amount\n"))
        self.assertIn(f'07/10/2026,{self.upi["receipt_number"]},ADM-1,"Aarav Shah","Class 8 - A"', text)
        self.assertIn("UTR123", text)

        document = self.report("fee-collection", format="pdf", **JULY)
        self.assertEqual(200, document.status_code)
        self.assertTrue(document.content.startswith(b"%PDF"))
        self.assertEqual('attachment; filename="fee-collection-2026-07-01-to-2026-07-15.pdf"',
                         document["Content-Disposition"])

        report = FeeCollectionReport()
        built = self.ok("fee-collection", compare=1, **JULY)
        page = pdf.document(report, built, school_label="Sunrise Public School", generated_at="07/15/2026 11:30 AM")
        self.assertIn("Collected (INR)", page)
        self.assertIn("INR 1,400.00", page)
        self.assertIn("previous: INR 50.00", page)
        self.assertNotIn("working days", page)

    def test_the_number_of_queries_does_not_grow_with_the_receipts(self):
        def queries() -> int:
            with CaptureQueriesContext(connection) as captured:
                self.ok("fee-collection", **JULY)
            return len(captured)

        few = queries()
        for day in range(1, 6):
            self.paid(amount="10.00", receipt_date=f"2026-07-0{day}")

        self.assertEqual(few, queries())


# -- outstanding ------------------------------------------------------------------------


class Outstanding(FeeReportsTestCase):
    def test_what_is_owed_on_dues_fallen_due_by_the_day_with_its_age(self):
        self.paid(amount="300.00")  # oldest first: the April installment

        row = self.ok("fee-outstanding", **JULY)["rows"][0]

        self.assertEqual(
            {
                "student_id": self.aarav.id, "admission_number": "ADM-1", "student": "Aarav Shah",
                "class_section": "Class 8 - A", "guardian": self.aarav.guardian_name,
                "guardian_mobile": self.aarav.guardian_mobile,
                "charged": "2000.00", "paid": "300.00", "balance": "1700.00",
                # July: 5 days past due; April: 96.
                "overdue_0_30": "1000.00", "overdue_31_60": "0.00", "overdue_61_plus": "700.00",
                "oldest_due_date": "2026-04-10", "currency_code": "INR",
            },
            row,
        )

    def test_as_at_an_earlier_day_only_what_had_fallen_due_by_then(self):
        data = self.ok("fee-outstanding", **{"from": "2026-06-01", "to": "2026-06-30"})

        self.assertEqual("2026-06-30", data["range"]["as_of"])
        self.assertEqual(("1000.00", "1000.00"), (data["rows"][0]["balance"], data["rows"][0]["overdue_61_plus"]))

    def test_the_age_buckets_turn_over_at_30_31_60_and_61_days(self):
        # As at 15 July: due 15 July (not overdue yet), 15 June (30 days),
        # 14 June (31), 16 May (60) and 15 May (61).
        rows = [
            ("Today", dt.date(2026, 7, 15), "1.00"), ("Thirty", dt.date(2026, 6, 15), "10.00"),
            ("Thirty-one", dt.date(2026, 6, 14), "100.00"), ("Sixty", dt.date(2026, 5, 16), "1000.00"),
            ("Sixty-one", dt.date(2026, 5, 15), "10000.00"),
        ]
        dev = self.student("Dev", section=self.section9, last_name="Kumar")
        self.published(rows, school_class=self.class9)
        FeeDueService.sync_student(dev, self.year)

        line = next(row for row in self.ok("fee-outstanding", **JULY)["rows"] if row["student"] == "Dev Kumar")

        self.assertEqual(
            ("11111.00", "10.00", "1100.00", "10000.00"),
            (line["balance"], line["overdue_0_30"], line["overdue_31_60"], line["overdue_61_plus"]),
        )
        self.assertEqual("2026-05-15", line["oldest_due_date"])

    def test_largest_balance_first_paid_up_students_left_out_and_currencies_apart(self):
        bina = self.charged("Bina", last_name="Rao")
        chen = self.charged("Chen", last_name="Li")
        self.in_dollars(chen)
        self.paid(student=bina, amount="2000.00")  # owes nothing due by today
        self.paid(amount="500.00")

        data = self.ok("fee-outstanding", **JULY)

        self.assertEqual(["Chen Li", "Aarav Shah"], [row["student"] for row in data["rows"]])
        self.assertEqual(2, data["totals"]["students"])
        self.assertEqual(
            [{"currency_code": "INR", "students": 1, "balance": "1500.00", "overdue_0_30": "1000.00",
              "overdue_31_60": "0.00", "overdue_61_plus": "500.00"},
             {"currency_code": "USD", "students": 1, "balance": "2000.00", "overdue_0_30": "1000.00",
              "overdue_31_60": "0.00", "overdue_61_plus": "1000.00"}],
            data["totals"]["by_currency"],
        )

    def test_waived_cancelled_and_discount_covered_dues_are_not_owed(self):
        self.waived(self.due("Tuition - April"))
        self.conceded("percent", "100")

        self.assertEqual([], self.ok("fee-outstanding", **JULY)["rows"])

    def test_a_student_who_has_left_still_owes_what_fell_due(self):
        self.aarav.status = "inactive"
        self.aarav.save()

        self.assertEqual("2000.00", self.ok("fee-outstanding", **JULY)["rows"][0]["balance"])

    def test_csv_pdf_and_queries(self):
        csv = self.report("fee-outstanding", format="csv", **JULY).content.decode("utf-8-sig")
        self.assertIn('"Overdue 0-30 days","Overdue 31-60 days","Overdue 61+ days","Oldest due"\n', csv)
        self.assertIn("04/10/2026", csv)
        self.assertTrue(self.report("fee-outstanding", format="pdf", **JULY).content.startswith(b"%PDF"))

        page = pdf.document(FeeOutstandingReport(), self.ok("fee-outstanding", **JULY),
                            school_label="Sunrise Public School", generated_at="now")
        self.assertIn("Outstanding (INR)", page)
        self.assertIn("Overdue 61+ days (INR)", page)

        def queries() -> int:
            with CaptureQueriesContext(connection) as captured:
                self.ok("fee-outstanding", **JULY)
            return len(captured)

        few = queries()
        for name in ("Bina", "Chen", "Dev", "Esha"):
            self.charged(name)
        self.assertEqual(few, queries())


# -- discounts and waivers ------------------------------------------------------------


class Concessions(FeeReportsTestCase):
    def test_discounts_and_waivers_given_in_the_range(self):
        with at(dt.datetime(2026, 6, 20, 6, 0, tzinfo=dt.timezone.utc)):
            earlier = self.conceded("fixed", "100.00", head=None, reason="Staff child")
        sibling = self.conceded("fixed", "500.00", reason="Sibling")
        self.waived(self.due("Tuition - July"), reason="Hardship case")
        bina = self.charged("Bina", last_name="Rao")
        ended = self.conceded("percent", "10", head=None, student=bina, reason="Scholarship")
        self.revoke(ended["id"])

        data = self.ok("fee-concessions", **JULY)

        self.assertEqual(
            [("Discount", "Aarav Shah"), ("Discount", "Bina Rao"), ("Waiver", "Aarav Shah")],
            [(row["type"], row["student"]) for row in data["rows"]],
        )
        discount, scholarship, waiver = data["rows"]
        self.assertEqual(
            {
                "id": sibling["id"], "student_id": self.aarav.id, "date": "2026-07-15", "type": "Discount",
                "admission_number": "ADM-1", "student": "Aarav Shah", "class_section": "Class 8 - A",
                "fee_type": "Tuition", "detail": "INR 500.00 off each installment",
                # 500 off each of the four installments - the one 100 from
                # the June discount is its own.
                "amount": "2000.00", "reason": "Sibling", "by": self.accountant.name, "status": "Active",
                "currency_code": "INR",
            },
            discount,
        )
        self.assertEqual(("All fee types", "10% off each installment", None, "Ended"),
                         (scholarship["fee_type"], scholarship["detail"], scholarship["amount"], scholarship["status"]))
        # July: 1,000 less 600 of discounts, nothing paid - 400 forgiven.
        self.assertEqual(
            ("Tuition", "Tuition - July", "400.00", "Hardship case", self.accountant.name, "Waived", "INR"),
            (waiver["fee_type"], waiver["detail"], waiver["amount"], waiver["reason"], waiver["by"],
             waiver["status"], waiver["currency_code"]),
        )
        self.assertEqual(
            {"discounts": 2, "discounts_active": 1, "waivers": 1,
             "discounted": [{"currency_code": "INR", "amount": "2000.00"}],
             "waived": [{"currency_code": "INR", "amount": "400.00"}]},
            data["totals"],
        )

        previous = self.ok("fee-concessions", compare=1, **JULY)["comparison"]["totals"]
        self.assertEqual(1, previous["discounts"])
        self.assertIsNotNone(earlier)

    def test_the_day_is_the_schools(self):
        # 20:00 UTC on 30 June is 01:30 on 1 July in Kolkata.
        with at(dt.datetime(2026, 6, 30, 20, 0, tzinfo=dt.timezone.utc)):
            self.conceded("fixed", "100.00")

        self.assertEqual(["2026-07-01"], [row["date"] for row in self.ok("fee-concessions", **JULY)["rows"]])

    def test_csv_and_pdf(self):
        self.conceded("percent", "12.5")

        csv = self.report("fee-concessions", format="csv", **JULY).content.decode("utf-8-sig")
        self.assertIn(
            'Date,Type,"Admission no.",Student,Class,"Fee type",Detail,Currency,Amount,Reason,By,Status\n', csv
        )
        self.assertIn("12.5% off each installment", csv)
        self.assertTrue(self.report("fee-concessions", format="pdf", **JULY).content.startswith(b"%PDF"))


# -- who may read them ------------------------------------------------------------------


class WhoMayRead(FeeReportsTestCase):
    KINDS = ("fee-collection", "fee-outstanding", "fee-concessions")

    def test_the_office_reads_them_and_a_teacher_or_head_does_not(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)

        for kind in self.KINDS:
            with self.subTest(kind=kind):
                self.assertEqual(200, self.report(kind, self.accountant).status_code)
                self.assertEqual(200, self.report(kind, self.admin).status_code)
                self.assertEqual(403, self.report(kind, teacher).status_code)
                self.assertEqual(403, self.report(kind, hod).status_code)

    def test_the_matrix_can_let_a_head_of_department_read_fees(self):
        hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        RolePermission.objects.create(role="HOD", module="fees", level="view")

        self.assertEqual(200, self.report("fee-collection", hod).status_code)

    def test_a_super_admin_names_a_school(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        self.paid()

        self.assertEqual(422, self.report("fee-collection", root).status_code)
        self.assertEqual(1, len(self.ok("fee-collection", root, school_id=self.school.id)["rows"]))

    def test_with_fees_switched_off_it_is_module_disabled(self):
        ModuleSetting.objects.filter(school=self.school, module="fees").update(school_enabled=False)
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        for kind in self.KINDS:
            response = self.report(kind, self.admin)
            self.assertEqual((403, "MODULE_DISABLED"), (response.status_code, response.data["code"]))
            self.assertEqual(403, self.report(kind, root, school_id=self.school.id).status_code)

    def test_another_schools_admin_never_sees_this_schools_money(self):
        other = factories.SchoolFactory(currency_code="USD")
        factories.ModuleSettingFactory(school=other, module="fees")
        their_admin = factories.UserFactory(school=other, role=UserRole.SCHOOL_ADMIN)
        self.paid(receipt_date="2026-07-10")

        data = self.ok("fee-collection", their_admin, school_id=self.school.id, **JULY)

        self.assertEqual([], data["rows"])


class GroupReports(FeeReportsTestCase):
    def setUp(self):
        super().setUp()
        # Sunrise becomes a branch of a group; a second branch has fees off.
        self.group = factories.SchoolFactory(name="A Group", timezone="Asia/Kolkata")
        self.school.parent_school = self.group
        self.school.save()
        self.dark = factories.SchoolFactory(name="Z Branch", parent_school=self.group, timezone="Asia/Kolkata")
        self.group_admin = factories.UserFactory(school=self.group, role=UserRole.GROUP_ADMIN)
        self.paid(receipt_date="2026-07-10")

    def test_the_whole_group_is_every_branch_using_fees(self):
        data = self.ok("fee-collection", self.group_admin, **JULY)

        self.assertTrue(data["group"])
        self.assertEqual(["Sunrise Public School"], [branch["school_name"] for branch in data["branches"]])
        self.assertEqual(("Sunrise Public School", "1000.00"), (data["rows"][0]["school_name"], data["rows"][0]["amount"]))
        self.assertEqual([{"currency_code": "INR", "amount": "1000.00"}], data["totals"]["collected"])

    def test_a_branch_without_fees_is_module_disabled(self):
        response = self.report("fee-collection", self.group_admin, school_id=self.dark.id)

        self.assertEqual((403, "MODULE_DISABLED"), (response.status_code, response.data["code"]))

    def test_a_group_with_no_branch_using_fees_is_module_disabled(self):
        ModuleSetting.objects.filter(school=self.school, module="fees").update(school_enabled=False)

        self.assertEqual(403, self.report("fee-outstanding", self.group_admin).status_code)


# -- the student statement PDF ------------------------------------------------------------


class StatementPdf(FeeReportsTestCase):
    def every_kind_of_line(self):
        """A paid installment, a part-paid one, an overdue fine, a waived
        one, a cancelled one, a discount and a cancelled receipt."""
        self.fines_on(amount=50, grace=5)
        self.run_fines()  # the April installment, 96 days late
        self.conceded("fixed", "100.00", reason="Sibling")
        self.paid(amount="900.00", receipt_date="2026-07-01")  # April, after the discount
        wrong = self.paid(amount="20.00", receipt_date="2026-07-02")
        self.cancel(wrong["id"])
        self.paid(amount="300.00", receipt_date="2026-07-10", payment_mode="cheque", reference="CHQ-0042")
        self.waived(self.due("Late fine - Tuition - April"), reason="First time late")
        StudentFeeDue.objects.filter(student=self.aarav, label="Tuition - January").update(
            status="cancelled", cancelled_reason="fee_changed"
        )

    def test_it_says_everything_a_family_needs(self):
        self.every_kind_of_line()
        found = ledger.statement(self.aarav, self.year, dt.date(2026, 7, 15))

        page = statement_pdf.document(found)

        for expected in (
            "FEE STATEMENT", "Academic year 2026-27", "Sunrise Public School", "Aarav Shah", "ADM-1",
            "Class 8 - A", self.aarav.guardian_name, "07/15/2026 11:30 AM (Asia/Kolkata)",
            "Late fine - Tuition - April", "Waived: First time late", "Not charged: the fee changed",
            "INR 100.00 off each installment", "Sibling", "CHQ-0042", "Cancelled", "Balance due",
            "Of which overdue", "Less waived", "Part paid, overdue", "Paid",
        ):
            self.assertIn(expected, page)

        for receipt in FeeReceipt.objects.filter(student=self.aarav):
            self.assertIn(receipt.receipt_number, page)

        self.assertNotIn("None", page)

    def test_it_is_a_pdf_named_for_the_student_and_the_year(self):
        self.every_kind_of_line()

        response = self.as_user(self.accountant).get(
            f"/api/v1/fees/students/{self.aarav.id}/statement.pdf", {"academic_year_id": self.year.id}
        )

        self.assertEqual(200, response.status_code)
        self.assertEqual("application/pdf", response["Content-Type"])
        self.assertTrue(response.content.startswith(b"%PDF"))
        self.assertEqual('attachment; filename="statement-ADM-1-2026-27.pdf"', response["Content-Disposition"])

    def test_who_may_have_it(self):
        url = f"/api/v1/fees/students/{self.aarav.id}/statement.pdf"
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        other = factories.SchoolFactory()
        factories.ModuleSettingFactory(school=other, module="fees")
        their_admin = factories.UserFactory(school=other, role=UserRole.SCHOOL_ADMIN)
        their_year = factories.AcademicYearFactory(school=other)

        self.assertEqual(200, self.as_user(self.admin).get(url).status_code)
        self.assertEqual(200, self.as_user(root).get(url).status_code)
        self.assertEqual(403, self.as_user(teacher).get(url).status_code)
        self.assertEqual(403, self.as_user(their_admin).get(url).status_code)
        self.assertEqual(422, self.as_user(self.admin).get(url, {"academic_year_id": their_year.id}).status_code)
        self.assertEqual(404, self.as_user(self.admin).get("/api/v1/fees/students/999999/statement.pdf").status_code)

        ModuleSetting.objects.filter(school=self.school, module="fees").update(school_enabled=False)
        self.assertEqual(403, self.as_user(self.admin).get(url).status_code)

    def test_a_student_charged_nothing_still_gets_a_statement(self):
        bina = self.student("Bina", section=self.section9)
        found = ledger.statement(bina, self.year, dt.date(2026, 7, 15))

        page = statement_pdf.document(found)

        self.assertIn("Nothing has been charged to this student for this year.", page)
        self.assertIn("No payments received this year.", page)


# -- the dashboard ----------------------------------------------------------------------------


class DashboardCards(FeeReportsTestCase):
    def dashboard(self, user, **params) -> dict:
        response = self.as_user(user).get("/api/v1/dashboard", params)
        self.assertEqual(200, response.status_code, response.data)

        return {card["key"]: card for card in response.data["cards"]}

    def test_the_office_sees_collected_outstanding_and_overdue(self):
        self.paid(amount="40.00", receipt_date="2026-06-30")  # last month
        self.paid(amount="960.00", receipt_date="2026-07-02")
        self.charged("Bina", last_name="Rao")

        for user in (self.admin, self.accountant):
            cards = self.dashboard(user)
            self.assertEqual(
                ("Fees collected this month", "INR 960.00", "1 receipt in July 2026"),
                (cards["fees_collected"]["label"], cards["fees_collected"]["value"], cards["fees_collected"]["hint"]),
            )
            # Aarav: July's 1,000; Bina: April's and July's.
            self.assertEqual(("INR 3,000.00", "2 students owing on fees already due", "warning"),
                             (cards["fees_outstanding"]["value"], cards["fees_outstanding"]["hint"],
                              cards["fees_outstanding"]["tone"]))
            self.assertEqual(("Students overdue", "2", "warning"),
                             (cards["fees_overdue"]["label"], cards["fees_overdue"]["value"],
                              cards["fees_overdue"]["tone"]))

    def test_the_card_shape_is_the_usual_one(self):
        card = self.dashboard(self.admin)["fees_collected"]

        self.assertEqual({"key", "label", "value", "hint", "tone"}, set(card))
        self.assertEqual("INR 0.00", card["value"])

    def test_a_super_admin_looking_at_the_school_sees_them_and_the_platform_does_not(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.assertIn("fees_outstanding", self.dashboard(root, school_id=self.school.id))
        self.assertNotIn("fees_outstanding", self.dashboard(root))

    def test_nobody_else_and_no_school_without_fees(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.assertFalse({"fees_collected", "fees_outstanding", "fees_overdue"} & set(self.dashboard(teacher)))

        ModuleSetting.objects.filter(school=self.school, module="fees").update(school_enabled=False)
        self.assertNotIn("fees_collected", self.dashboard(self.admin))
        self.assertNotIn("fees_collected", self.dashboard(self.accountant))

    def test_a_group_admin_sees_every_branch_using_fees(self):
        group = factories.SchoolFactory(name="A Group", timezone="Asia/Kolkata")
        self.school.parent_school = group
        self.school.save()
        dollars = factories.SchoolFactory(name="B Branch", parent_school=group, currency_code="USD")
        group_admin = factories.UserFactory(school=group, role=UserRole.GROUP_ADMIN)
        self.paid(amount="1000.00", receipt_date="2026-07-02")

        cards = self.dashboard(group_admin)
        self.assertEqual("INR 1,000.00", cards["fees_collected"]["value"])

        factories.ModuleSettingFactory(school=dollars, module="fees")
        self.assertEqual("INR 1,000.00", self.dashboard(group_admin)["fees_collected"]["value"])

    def test_the_queries_are_bounded(self):
        self.paid(amount="100.00", receipt_date="2026-07-02")

        def queries() -> int:
            with CaptureQueriesContext(connection) as captured:
                self.dashboard(self.accountant)
            return len(captured)

        few = queries()
        for name in ("Bina", "Chen", "Dev"):
            self.paid(student=self.charged(name), amount="100.00", receipt_date="2026-07-02")

        self.assertEqual(few, queries())
