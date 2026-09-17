"""The payslip arithmetic, exactly - see school/payroll/calculator.py and
docs/payroll.md. No database: these are the rules, not the plumbing."""

import datetime as dt
from decimal import Decimal

from django.test import SimpleTestCase

from school.payroll import calculator

MON, TUE, WED, THU, FRI = (dt.date(2026, 9, day) for day in (7, 8, 9, 10, 11))
WEEK = [MON, TUE, WED, THU, FRI]


class PaidDays(SimpleTestCase):
    def test_present_leave_and_unmarked_are_paid_half_is_half_absent_is_not(self):
        days = calculator.days(WEEK, {MON: "present", TUE: "leave", WED: "half_day", THU: "absent"}, None)

        self.assertEqual(
            (5, Decimal("3.5"), Decimal("1"), 1, 1, 0),
            (days.working, days.paid, days.absent, days.half, days.unmarked, days.before_joining),
        )

    def test_a_register_nobody_took_docks_nobody(self):
        self.assertEqual(Decimal("5"), calculator.days(WEEK, {}, None).paid)

    def test_days_before_joining_are_not_paid(self):
        days = calculator.days(WEEK, {}, joining_date=WED)

        self.assertEqual((Decimal("3"), 2), (days.paid, days.before_joining))

    def test_a_mark_before_joining_does_not_count_either(self):
        self.assertEqual(Decimal("0"), calculator.days([MON], {MON: "present"}, joining_date=TUE).paid)


class ProRating(SimpleTestCase):
    def test_everything_scales_by_paid_over_working_days(self):
        self.assertEqual(Decimal("27857.14"), calculator.prorate(Decimal("30000"), Decimal("19.5"), 21))

    def test_halves_round_up_to_the_cent(self):
        # 0.125 x 1 / 1... built so the exact result ends in a half cent:
        # 12.345 -> 12.35 (Python's banker's rounding would say 12.34).
        self.assertEqual(Decimal("12.35"), calculator.prorate(Decimal("24.69"), Decimal("1"), 2))

    def test_a_full_month_pays_the_full_amount(self):
        self.assertEqual(Decimal("30000.00"), calculator.prorate(Decimal("30000"), Decimal("22"), 22))

    def test_a_month_without_a_working_day_pays_in_full(self):
        self.assertEqual(Decimal("30000.00"), calculator.prorate(Decimal("30000"), Decimal("0"), 0))

    def test_nothing_paid_is_nothing(self):
        self.assertEqual(Decimal("0.00"), calculator.prorate(Decimal("30000"), Decimal("0"), 22))


class Totals(SimpleTestCase):
    def test_net_is_earnings_less_deductions(self):
        figures = calculator.totals([("earning", Decimal("100.10")), ("earning", Decimal("50")), ("deduction", Decimal("20.05"))])

        self.assertEqual(
            (Decimal("150.10"), Decimal("20.05"), Decimal("130.05"), Decimal("0.00")),
            (figures.gross_earnings, figures.total_deductions, figures.net_pay, figures.shortfall),
        )

    def test_net_never_goes_below_zero_and_the_shortfall_is_kept(self):
        figures = calculator.totals([("earning", Decimal("100")), ("deduction", Decimal("130.50"))])

        self.assertEqual((Decimal("0.00"), Decimal("30.50")), (figures.net_pay, figures.shortfall))
