"""The insight rules (docs/assessments.md, slice 12).

Unit tests: no database, no clock, no school. The module is given a
performance payload and returns sentences, so every threshold can be tested
at the exact point it turns - which is the only place a rule like this is
ever wrong.

The rule that matters most is the one that produces nothing: a confident
sentence drawn from a single mark is worse than silence.
"""

from unittest import TestCase

from school import insights


def subject(
    name="Mathematics",
    subject_id=1,
    average="34.00",
    previous=None,
    change=None,
    assessments=3,
    absent=0,
):
    return {
        "subject_id": subject_id,
        "subject_name": name,
        "assessments": assessments,
        "absent": absent,
        "average_percentage": average,
        "grade": None,
        "class_average_percentage": None,
        "previous_average_percentage": previous,
        "change": change,
    }


def payload(
    subjects=None,
    weak_below=40,
    attendance_rate=90,
    previous_term="Term 1",
    overall=None,
    marked=(14, 4, 0),
):
    rows = subjects if subjects is not None else [subject()]
    present, absent, leave = marked

    return {
        "term": {"id": 2, "name": "Term 2"},
        "previous_term": None if previous_term is None else {"id": 1, "name": previous_term},
        "subjects": rows,
        "overall": overall
        or {
            "subjects": len(rows),
            "assessments": sum(row["assessments"] for row in rows),
            "absent": sum(row["absent"] for row in rows),
        },
        "attendance": {
            "attendance_rate": attendance_rate,
            "present": present,
            "absent": absent,
            "leave": leave,
        },
        "weak_below_percentage": weak_below,
    }


def codes(found) -> list:
    return [row["code"] for row in found]


def one(found, code) -> dict:
    return next(row for row in found if row["code"] == code)


class SayingNothing(TestCase):
    def test_a_single_test_says_nothing_at_all(self):
        found = insights.for_performance(payload([subject(assessments=1, average="12.00", change="-40.00")]))

        self.assertEqual([], found, "one test is not a trend, whatever it says")

    def test_a_student_with_no_marks_says_nothing(self):
        self.assertEqual([], insights.for_performance(payload([])))

    def test_a_subject_with_no_average_is_not_called_weak(self):
        # Every test missed: there is no figure to be below anything.
        found = insights.for_performance(payload([subject(average=None, assessments=3, absent=3)]))

        self.assertNotIn(insights.WEAK_SUBJECT, codes(found))

    def test_a_school_that_has_no_weak_mark_flags_nothing(self):
        found = insights.for_performance(payload(weak_below=None))

        self.assertNotIn(insights.WEAK_SUBJECT, codes(found))


class WeakSubjects(TestCase):
    def test_below_the_school_s_mark_is_said_with_both_numbers(self):
        found = insights.for_performance(payload([subject(average="34.00")], weak_below=40))

        weak = one(found, insights.WEAK_SUBJECT)
        self.assertEqual("Mathematics is at 34%, below the school's 40% mark.", weak["message"])
        self.assertEqual({"average": "34", "threshold": "40"}, weak["numbers"])
        self.assertEqual("Mathematics", weak["subject_name"])

    def test_exactly_on_the_mark_is_not_below_it(self):
        found = insights.for_performance(payload([subject(average="40.00")], weak_below=40))

        self.assertNotIn(insights.WEAK_SUBJECT, codes(found), "'below' means below")

    def test_a_hair_under_is(self):
        found = insights.for_performance(payload([subject(average="39.99")], weak_below=40))

        self.assertEqual("Mathematics is at 39.99%, below the school's 40% mark.", one(found, insights.WEAK_SUBJECT)["message"])

    def test_a_school_that_moved_its_mark_is_read_back(self):
        found = insights.for_performance(payload([subject(average="45.00")], weak_below=50))

        self.assertIn("below the school's 50% mark", one(found, insights.WEAK_SUBJECT)["message"])

    def test_every_weak_subject_is_named_once(self):
        found = insights.for_performance(
            payload([subject(name="Mathematics", average="30.00"), subject(name="Science", subject_id=2, average="20.00")])
        )

        self.assertEqual(
            ["Mathematics", "Science"],
            [row["subject_name"] for row in found if row["code"] == insights.WEAK_SUBJECT],
        )

    def test_a_student_weak_in_nothing_hears_nothing_about_it(self):
        found = insights.for_performance(payload([subject(average="88.00")]))

        self.assertNotIn(insights.WEAK_SUBJECT, codes(found))


class MovingEitherWay(TestCase):
    def test_a_fall_of_ten_points_is_said(self):
        found = insights.for_performance(
            payload([subject(name="Science", average="60.00", previous="70.00", change="-10.00")], weak_below=40)
        )

        slipping = one(found, insights.SLIPPING)
        self.assertEqual("Science has fallen 10 points since Term 1.", slipping["message"])
        self.assertEqual({"change": "-10", "average": "60", "previous": "70"}, slipping["numbers"])

    def test_a_rise_of_ten_points_is_said(self):
        found = insights.for_performance(
            payload([subject(name="English", average="72.00", previous="62.00", change="10.00")])
        )

        self.assertEqual("English is up 10 points since Term 1.", one(found, insights.IMPROVING)["message"])

    def test_nine_points_is_the_ordinary_movement_of_one_hard_paper(self):
        found = insights.for_performance(payload([subject(average="71.00", previous="62.00", change="9.00")]))

        self.assertEqual([], codes(found))

    def test_a_subject_with_nothing_to_compare_against_says_nothing_about_change(self):
        found = insights.for_performance(payload([subject(average="80.00", change=None)]))

        self.assertNotIn(insights.SLIPPING, codes(found))
        self.assertNotIn(insights.IMPROVING, codes(found))

    def test_the_sentence_names_the_term_it_is_measured_against(self):
        found = insights.for_performance(
            payload([subject(average="50.00", previous="70.00", change="-20.00")], previous_term="Autumn")
        )

        self.assertIn("since Autumn", one(found, insights.SLIPPING)["message"])

    def test_without_a_named_term_the_sentence_still_reads(self):
        found = insights.for_performance(
            payload([subject(average="50.00", previous="70.00", change="-20.00")], previous_term=None)
        )

        self.assertEqual("Mathematics has fallen 20 points.", one(found, insights.SLIPPING)["message"])

    def test_two_rules_can_fire_on_one_subject(self):
        found = insights.for_performance(
            payload([subject(average="30.00", previous="55.00", change="-25.00")], weak_below=40)
        )

        self.assertEqual([insights.WEAK_SUBJECT, insights.SLIPPING], codes(found))


class MissedTests(TestCase):
    def test_exactly_a_third_is_said(self):
        found = insights.for_performance(
            payload([subject(assessments=3, absent=1, average="60.00")], weak_below=40)
        )

        missed = one(found, insights.MISSED_TESTS)
        self.assertEqual("Absent for 1 of 3 tests this term.", missed["message"])
        self.assertEqual({"absent": 1, "tests": 3}, missed["numbers"])

    def test_less_than_a_third_is_not(self):
        found = insights.for_performance(payload([subject(assessments=4, absent=1, average="60.00")]))

        self.assertNotIn(insights.MISSED_TESTS, codes(found))

    def test_it_counts_the_term_rather_than_each_subject(self):
        # One missed test in each of three subjects is the same fortnight
        # away from school, and is worth saying once.
        found = insights.for_performance(
            payload([
                subject(name="Mathematics", assessments=2, absent=1, average="60.00"),
                subject(name="Science", subject_id=2, assessments=2, absent=1, average="60.00"),
                subject(name="English", subject_id=3, assessments=2, absent=1, average="60.00"),
            ])
        )

        self.assertEqual(1, codes(found).count(insights.MISSED_TESTS))
        self.assertEqual("Absent for 3 of 6 tests this term.", one(found, insights.MISSED_TESTS)["message"])

    def test_missing_nothing_is_not_an_insight(self):
        found = insights.for_performance(payload([subject(assessments=4, absent=0, average="60.00")]))

        self.assertNotIn(insights.MISSED_TESTS, codes(found))

    def test_a_term_of_one_test_says_nothing_even_if_it_was_missed(self):
        found = insights.for_performance(
            payload([subject(assessments=1, absent=1, average=None)], overall={"assessments": 1, "absent": 1})
        )

        self.assertEqual([], codes(found))


class AttendanceBeside(TestCase):
    def test_it_is_offered_beside_a_weak_subject(self):
        found = insights.for_performance(
            payload([subject(average="34.00")], weak_below=40, attendance_rate=68)
        )

        attendance = one(found, insights.ATTENDANCE)
        self.assertEqual("Attendance is 68% this term.", attendance["message"])
        self.assertEqual(["Mathematics"], attendance["numbers"]["weak_subjects"])

    def test_it_is_not_offered_where_nothing_is_weak(self):
        found = insights.for_performance(payload([subject(average="88.00")], attendance_rate=41))

        self.assertNotIn(insights.ATTENDANCE, codes(found), "a fact about the register, not about the child")

    def test_exactly_seventy_five_is_not_under_it(self):
        found = insights.for_performance(payload([subject(average="34.00")], attendance_rate=75))

        self.assertNotIn(insights.ATTENDANCE, codes(found))

    def test_a_hair_under_is(self):
        found = insights.for_performance(payload([subject(average="34.00")], attendance_rate=74.9))

        self.assertEqual("Attendance is 74.9% this term.", one(found, insights.ATTENDANCE)["message"])

    def test_a_term_nobody_took_the_register_for_says_nothing(self):
        # 0% because the register was never taken is a fact about the
        # school's paperwork, not about the child.
        found = insights.for_performance(
            payload([subject(average="34.00")], attendance_rate=0, marked=(0, 0, 0))
        )

        self.assertNotIn(insights.ATTENDANCE, codes(found))

    def test_a_register_that_was_taken_and_shows_nought_still_says_it(self):
        found = insights.for_performance(
            payload([subject(average="34.00")], attendance_rate=0, marked=(0, 12, 0))
        )

        self.assertEqual("Attendance is 0% this term.", one(found, insights.ATTENDANCE)["message"])

    def test_a_term_with_no_rate_at_all_says_nothing(self):
        found = insights.for_performance(payload([subject(average="34.00")], attendance_rate=None))

        self.assertNotIn(insights.ATTENDANCE, codes(found))

    def test_it_is_said_once_however_many_subjects_are_weak(self):
        found = insights.for_performance(
            payload(
                [subject(name="Mathematics", average="30.00"), subject(name="Science", subject_id=2, average="20.00")],
                attendance_rate=60,
            )
        )

        self.assertEqual(1, codes(found).count(insights.ATTENDANCE))
        self.assertEqual(["Mathematics", "Science"], one(found, insights.ATTENDANCE)["numbers"]["weak_subjects"])


class HowTheyRead(TestCase):
    def test_a_whole_percentage_loses_its_decimals(self):
        self.assertEqual("34", insights.plain("34.00"))
        self.assertEqual("74.9", insights.plain("74.90"))
        self.assertEqual("40", insights.plain(40))

    def test_every_insight_carries_a_code_a_sentence_and_its_numbers(self):
        found = insights.for_performance(
            payload([subject(average="30.00", previous="55.00", change="-25.00", assessments=3, absent=1)],
                    attendance_rate=60)
        )

        self.assertTrue(found)
        for row in found:
            self.assertIn(row["code"], (
                insights.WEAK_SUBJECT, insights.SLIPPING, insights.IMPROVING,
                insights.MISSED_TESTS, insights.ATTENDANCE,
            ))
            self.assertTrue(row["message"].endswith("."), row["message"])
            self.assertTrue(row["numbers"], f"nothing to show for {row['code']}")
