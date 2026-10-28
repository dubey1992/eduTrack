"""The fee arithmetic on its own, without a database (docs/fees.md, F1): the
installment-plan splitter and the installment checks a structure must pass.
Over HTTP, see test_fees_set_up_api.py."""

import datetime as dt
from decimal import Decimal

from django.test import SimpleTestCase

from school.fees import plan
from school.fees.requests import installment_problems, plain

START = dt.date(2026, 4, 1)
END = dt.date(2027, 3, 31)


def D(value: str) -> Decimal:
    return Decimal(value)


class Splitting(SimpleTestCase):
    def test_an_even_amount_splits_evenly(self):
        self.assertEqual([D("1000.00")] * 12, plan.split(D("12000.00"), 12))

    def test_the_remainder_goes_on_the_last_installment(self):
        self.assertEqual([D("333.33"), D("333.33"), D("333.34")], plan.split(D("1000.00"), 3))
        self.assertEqual([D("0.01"), D("0.01"), D("0.03")], plan.split(D("0.05"), 3))

    def test_the_parts_always_add_up_to_the_amount(self):
        for amount, count in (("12345.67", 12), ("99.99", 4), ("1.00", 7), ("9999999999.99", 24)):
            parts = plan.split(D(amount), count)
            self.assertEqual(D(amount), sum(parts), (amount, count))
            self.assertEqual(count, len(parts))

    def test_one_installment_is_the_whole_amount(self):
        self.assertEqual([D("500.50")], plan.split(D("500.50"), 1))


class DueDays(SimpleTestCase):
    def test_a_day_past_the_end_of_the_month_is_its_last_day(self):
        self.assertEqual(dt.date(2027, 2, 28), plan.on_day(2027, 2, 31, START, END))
        self.assertEqual(dt.date(2026, 4, 30), plan.on_day(2026, 4, 31, START, END))

    def test_february_in_a_leap_year_has_29_days(self):
        self.assertEqual(
            dt.date(2028, 2, 29), plan.on_day(2028, 2, 31, dt.date(2027, 4, 1), dt.date(2028, 3, 31))
        )

    def test_a_due_date_is_kept_inside_the_academic_year(self):
        start, end = dt.date(2026, 4, 15), dt.date(2027, 3, 5)

        self.assertEqual(start, plan.on_day(2026, 4, 10, start, end))
        self.assertEqual(end, plan.on_day(2027, 3, 10, start, end))

    def test_months_between_spans_the_year_inclusive(self):
        months = plan.months_between(START, END)

        self.assertEqual(12, len(months))
        self.assertEqual(((2026, 4), (2027, 3)), (months[0], months[-1]))


class Suggestions(SimpleTestCase):
    def test_monthly_is_one_per_calendar_month_labelled_by_month(self):
        rows = plan.suggest("monthly", D("12000.00"), START, END, due_day=10)

        self.assertEqual(12, len(rows))
        self.assertEqual(("April 2026", dt.date(2026, 4, 10), D("1000.00")), tuple(rows[0].values()))
        self.assertEqual(("March 2027", dt.date(2027, 3, 10), D("1000.00")), tuple(rows[-1].values()))

    def test_monthly_on_the_31st_lands_on_each_months_last_day(self):
        rows = plan.suggest("monthly", D("1200.00"), START, END, due_day=31)
        dates = {row["label"]: row["due_date"] for row in rows}

        self.assertEqual(dt.date(2027, 2, 28), dates["February 2027"])
        self.assertEqual(dt.date(2026, 6, 30), dates["June 2026"])
        self.assertEqual(dt.date(2026, 7, 31), dates["July 2026"])

    def test_quarterly_is_four_quarters_three_months_apart(self):
        rows = plan.suggest("quarterly", D("1000.00"), START, END, due_day=10)

        self.assertEqual(["Quarter 1", "Quarter 2", "Quarter 3", "Quarter 4"], [row["label"] for row in rows])
        self.assertEqual(
            [dt.date(2026, 4, 10), dt.date(2026, 7, 10), dt.date(2026, 10, 10), dt.date(2027, 1, 10)],
            [row["due_date"] for row in rows],
        )
        self.assertEqual([D("250.00")] * 4, [row["amount"] for row in rows])

    def test_per_term_is_one_per_term_due_on_its_first_day(self):
        terms = [plan.Term("Term 1", dt.date(2026, 4, 1)), plan.Term("Term 2", dt.date(2026, 9, 1)),
                 plan.Term("Term 3", dt.date(2027, 1, 4))]

        rows = plan.suggest("term", D("100.00"), START, END, terms=terms)

        self.assertEqual(
            [("Term 1", dt.date(2026, 4, 1), D("33.33")), ("Term 2", dt.date(2026, 9, 1), D("33.33")),
             ("Term 3", dt.date(2027, 1, 4), D("33.34"))],
            [tuple(row.values()) for row in rows],
        )

    def test_per_term_without_terms_is_refused(self):
        with self.assertRaises(plan.NoTerms):
            plan.suggest("term", D("100.00"), START, END)

        self.assertEqual(0, plan.count_for("term", START, END, []))

    def test_yearly_and_one_time_are_one_installment_on_the_first_day_of_the_year(self):
        self.assertEqual([{"label": "Annual", "due_date": START, "amount": D("5000.00")}],
                         plan.suggest("yearly", D("5000.00"), START, END, due_day=25))
        self.assertEqual([{"label": "One-time", "due_date": START, "amount": D("5000.00")}],
                         plan.suggest("one_time", D("5000.00"), START, END))


class InstallmentChecks(SimpleTestCase):
    def rows(self, *items):
        return [{"label": label, "due_date": due, "amount": amount} for label, due, amount in items]

    def test_good_installments_are_numbered_in_order(self):
        cleaned, problems = installment_problems(
            self.rows(("  April ", "2026-04-10", "6000"), ("October", "2026-10-10", "6000.00")), D("12000.00"), START, END
        )

        self.assertEqual([], problems)
        self.assertEqual(
            [(1, "April", dt.date(2026, 4, 10), D("6000.00")), (2, "October", dt.date(2026, 10, 10), D("6000.00"))],
            [(row["sequence"], row["label"], row["due_date"], row["amount"]) for row in cleaned],
        )

    def test_the_sum_must_match_the_fee_exactly(self):
        _, problems = installment_problems(
            self.rows(("A", "2026-04-10", "5000"), ("B", "2026-10-10", "6000")), D("12000.00"), START, END
        )

        self.assertEqual(["The installments add up to 11,000.00 but the fee is 12,000.00."], problems)

    def test_a_due_date_outside_the_year_names_the_installment_and_the_boundary(self):
        _, problems = installment_problems(
            self.rows(("A", "2026-03-31", "1"), ("B", "2026-06-10", "1"), ("C", "2027-05-10", "1")), D("3.00"), START, END
        )

        self.assertIn("Installment 1 is due on 2026-03-31, before the academic year starts (2026-04-01).", problems)
        self.assertIn("Installment 3 is due on 2027-05-10, after the academic year ends (2027-03-31).", problems)

    def test_the_last_day_of_the_year_is_inside_it(self):
        _, problems = installment_problems(self.rows(("A", "2027-03-31", "1"), ("B", "2027-03-31", "1")),
                                           D("2.00"), START, END)

        self.assertEqual([], problems, "equal due dates are in order")

    def test_due_dates_must_not_go_backwards(self):
        _, problems = installment_problems(
            self.rows(("A", "2026-06-10", "1"), ("B", "2026-05-10", "1")), D("2.00"), START, END
        )

        self.assertEqual(
            ["Installment 2 is due before installment 1. List the installments in the order they fall due."], problems
        )

    def test_every_problem_with_every_installment_is_reported_at_once(self):
        _, problems = installment_problems(
            [{"label": "", "due_date": "not a date", "amount": "0"},
             {"label": "x" * 61, "amount": "1.005"},
             "nonsense"],
            D("100.00"), START, END,
        )

        self.assertEqual(
            [
                "Installment 1 needs a label.",
                "Installment 1's due date must be a valid date, like 2026-04-01.",
                "Installment 1's amount must be more than zero.",
                "Installment 2's label must not be longer than 60 characters.",
                "Installment 2 needs a due date.",
                "Installment 2's amount can have at most 2 decimal places.",
                "Installment 3 needs a label.",
                "Installment 3 needs a due date.",
                "Installment 3 needs an amount.",
            ],
            problems,
        )

    def test_the_sum_is_not_compared_when_an_amount_is_already_wrong(self):
        _, problems = installment_problems(self.rows(("A", "2026-04-10", "abc")), D("100.00"), START, END)
        self.assertEqual(["Installment 1's amount must be a number."], problems)

        _, problems = installment_problems(self.rows(("A", "2026-04-10", "50")), None, START, END)
        self.assertEqual([], problems, "the fee's own amount was invalid and is reported there")

    def test_the_list_itself(self):
        self.assertEqual(["The installments field is required."], installment_problems(None, D("1"), START, END)[1])
        self.assertEqual(["The installments must be a list."], installment_problems("x", D("1"), START, END)[1])
        self.assertEqual(["Add at least one installment."], installment_problems([], D("1"), START, END)[1])

        many = self.rows(*[("M", "2026-04-10", "1")] * 25)
        self.assertEqual(["A fee can have at most 24 installments."], installment_problems(many, D("25"), START, END)[1])

        enough = self.rows(*[("M", "2026-04-10", "1")] * 24)
        self.assertEqual([], installment_problems(enough, D("24"), START, END)[1])

    def test_amounts_are_printed_plainly(self):
        self.assertEqual("12,000.00", plain(D("12000")))
        self.assertEqual("0.50", plain(D("0.5")))
