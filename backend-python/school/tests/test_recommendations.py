"""The recommendation rules (docs/insights.md, slice 2).

Unit tests, like the insight rules they sit beside: no database, no clock,
no school. The module is handed a performance payload and returns
sentences, so every threshold can be tested at the exact point it turns.

A finding says what the numbers are; a recommendation says what somebody
could do next. The line neither crosses: it suggests an action a teacher
was always free to take - revise a chapter, offer a re-sit, speak to a
guardian - and never advises how to teach.

The rule that matters most is still the one that produces nothing.
"""

from unittest import TestCase

from school import insights
from school.tests.test_insights import codes, one, payload, subject


def topic(name="Trigonometry", topic_id=1, average="35.00", assessments=2, absent=0):
    return {
        "topic_id": topic_id,
        "topic_name": name,
        "assessments": assessments,
        "absent": absent,
        "average_percentage": average,
    }


def advice(**kwargs) -> list:
    return insights.recommendations_for(payload(**kwargs))


class WhenThereIsNothingToSuggest(TestCase):
    def test_a_term_with_nothing_wrong_suggests_nothing(self):
        """Silence is the right answer more often than anything else."""
        self.assertEqual([], advice(subjects=[subject(average="78.00")]))

    def test_nothing_is_suggested_from_a_single_result(self):
        self.assertEqual([], advice(subjects=[subject(average="12.00", assessments=1)]))

    def test_two_results_are_enough(self):
        self.assertEqual(
            [insights.PRACTISE_SUBJECT],
            codes(advice(subjects=[subject(average="12.00", assessments=2)])),
        )

    def test_a_school_that_keeps_no_weak_mark_is_told_nothing_is_weak(self):
        self.assertEqual([], codes(advice(subjects=[subject(average="12.00")], weak_below=None)))

    def test_exactly_on_the_mark_is_not_below_it(self):
        self.assertEqual([], codes(advice(subjects=[subject(average="40.00")], weak_below=40)))


class RevisingTheRightThing(TestCase):
    def weak_with_topics(self, topics, average="34.00", assessments=4):
        rows = [subject(average=average, assessments=assessments)]
        rows[0]["topics"] = topics

        return rows

    def test_a_weak_subject_names_the_chapters_that_are_weak(self):
        rows = self.weak_with_topics([topic("Trigonometry", 1, "20.00"), topic("Vectors", 2, "85.00")])

        row = one(advice(subjects=rows), insights.REVISE_TOPICS)

        self.assertIn("Revise Trigonometry in Mathematics", row["message"])
        self.assertNotIn("Vectors", row["message"], "a chapter that is fine is not revision")
        self.assertEqual(["Trigonometry"], row["numbers"]["topics"])

    def test_several_weak_chapters_read_as_a_sentence(self):
        rows = self.weak_with_topics(
            [topic("Trigonometry", 1, "20.00"), topic("Vectors", 2, "25.00"), topic("Calculus", 3, "30.00")],
            average="30.00",
            assessments=6,
        )

        row = one(advice(subjects=rows), insights.REVISE_TOPICS)

        self.assertIn("Revise Trigonometry, Vectors and Calculus in Mathematics", row["message"])

    def test_a_chapter_nobody_measured_is_not_revision(self):
        """Absent for every test on it: there is nothing to revise because
        of, and the student may know it perfectly well."""
        rows = self.weak_with_topics([topic("Waves", 1, None, assessments=2, absent=2)])

        row = one(advice(subjects=rows), insights.PRACTISE_SUBJECT)

        self.assertNotIn("Waves", row["message"])

    def test_a_weak_subject_with_no_chapters_asks_for_practice_instead(self):
        row = one(advice(subjects=[subject(average="34.00")]), insights.PRACTISE_SUBJECT)

        self.assertIn("Set extra practice in Mathematics", row["message"])
        self.assertIn("34%", row["message"])

    def test_it_never_names_the_chapters_and_the_subject_both(self):
        """Naming the chapters is strictly better advice; saying both would
        be telling somebody the same thing twice."""
        rows = self.weak_with_topics([topic("Trigonometry", 1, "20.00")])

        found = codes(advice(subjects=rows))

        self.assertIn(insights.REVISE_TOPICS, found)
        self.assertNotIn(insights.PRACTISE_SUBJECT, found)

    def test_the_class_average_is_quoted_where_there_is_one(self):
        rows = [subject(average="34.00")]
        rows[0]["class_average_percentage"] = "61.00"

        row = one(advice(subjects=rows), insights.PRACTISE_SUBJECT)

        self.assertIn("The class averaged 61%", row["message"])

    def test_a_chapter_exactly_on_the_mark_is_not_weak_either(self):
        rows = self.weak_with_topics([topic("Trigonometry", 1, "40.00")])

        row = one(advice(subjects=rows), insights.PRACTISE_SUBJECT)

        self.assertNotIn("Trigonometry", row["message"])


class WhatChanged(TestCase):
    def test_a_subject_that_has_fallen_far_is_worth_asking_about(self):
        rows = [subject(average="55.00", change="-14.00", previous="69.00")]

        row = one(advice(subjects=rows), insights.CHECK_WHAT_CHANGED)

        self.assertIn("Find out what changed in Mathematics", row["message"])
        self.assertIn("down 14 points since Term 1", row["message"])

    def test_ten_points_is_far_enough(self):
        rows = [subject(average="55.00", change="-10.00")]

        self.assertIn(insights.CHECK_WHAT_CHANGED, codes(advice(subjects=rows)))

    def test_nine_points_is_the_ordinary_movement_of_one_hard_paper(self):
        rows = [subject(average="55.00", change="-9.99")]

        self.assertNotIn(insights.CHECK_WHAT_CHANGED, codes(advice(subjects=rows)))

    def test_a_subject_that_has_risen_needs_nothing_done_to_it(self):
        rows = [subject(average="78.00", change="14.00")]

        self.assertEqual([], codes(advice(subjects=rows)))

    def test_a_term_with_nothing_before_it_names_no_term(self):
        rows = [subject(average="55.00", change="-14.00")]

        row = one(advice(subjects=rows, previous_term=None), insights.CHECK_WHAT_CHANGED)

        self.assertIn("down 14 points.", row["message"])
        self.assertNotIn("since", row["message"])


class MissedTests(TestCase):
    def test_a_third_missed_earns_the_offer_of_a_re_sit(self):
        rows = [subject(average="78.00", assessments=6, absent=2)]

        row = one(advice(subjects=rows), insights.ARRANGE_RESIT)

        self.assertIn("Offer a re-sit for the 2 tests missed, of 6 this term", row["message"])

    def test_one_missed_test_reads_as_one(self):
        rows = [subject(average="78.00", assessments=3, absent=1)]

        self.assertIn("the 1 test missed", one(advice(subjects=rows), insights.ARRANGE_RESIT)["message"])

    def test_fewer_than_a_third_is_not_a_pattern(self):
        rows = [subject(average="78.00", assessments=8, absent=2)]

        self.assertNotIn(insights.ARRANGE_RESIT, codes(advice(subjects=rows)))

    def test_missing_nothing_suggests_nothing(self):
        rows = [subject(average="78.00", assessments=6, absent=0)]

        self.assertNotIn(insights.ARRANGE_RESIT, codes(advice(subjects=rows)))


class AttendanceFirst(TestCase):
    def test_a_child_behind_and_often_away_is_an_attendance_conversation(self):
        row = one(advice(subjects=[subject(average="34.00")], attendance_rate=68), insights.ATTENDANCE_FIRST)

        self.assertIn("Take attendance up with the guardian", row["message"])
        self.assertIn("68%", row["message"])

    def test_good_marks_and_poor_attendance_is_not_one(self):
        """Attendance beside good marks is a fact about the register, not
        something to summon a guardian about."""
        found = codes(advice(subjects=[subject(average="78.00")], attendance_rate=60))

        self.assertNotIn(insights.ATTENDANCE_FIRST, found)

    def test_exactly_seventy_five_is_not_under_it(self):
        found = codes(advice(subjects=[subject(average="34.00")], attendance_rate=75))

        self.assertNotIn(insights.ATTENDANCE_FIRST, found)

    def test_a_term_whose_register_was_never_taken_says_nothing(self):
        """0% there is a fact about the school's paperwork. Summoning a
        guardian over it would be the product accusing somebody on the
        strength of a blank.
        """
        found = codes(advice(subjects=[subject(average="34.00")], attendance_rate=0, marked=(0, 0, 0)))

        self.assertNotIn(insights.ATTENDANCE_FIRST, found)


class HowTheyRead(TestCase):
    def test_they_come_in_the_order_somebody_would_act_on_them(self):
        found = codes(
            advice(
                subjects=[subject(average="34.00", change="-20.00", assessments=6, absent=3)],
                attendance_rate=60,
            )
        )

        self.assertEqual(
            [
                insights.PRACTISE_SUBJECT,
                insights.CHECK_WHAT_CHANGED,
                insights.ARRANGE_RESIT,
                insights.ATTENDANCE_FIRST,
            ],
            found,
        )

    def test_a_recommendation_never_repeats_a_finding_word_for_word(self):
        """They are drawn from the same numbers on purpose, but one says
        what is and the other says what to do."""
        rows = [subject(average="34.00", change="-20.00", assessments=6, absent=3)]
        said = {row["message"] for row in insights.for_performance(payload(subjects=rows))}
        suggested = {row["message"] for row in insights.recommendations_for(payload(subjects=rows))}

        self.assertEqual(set(), said & suggested)

    def test_every_one_carries_the_numbers_it_was_drawn_from(self):
        """A suggestion a teacher cannot check is one they have to take on
        trust, which is the thing this module exists not to ask for."""
        rows = [subject(average="34.00", change="-20.00", assessments=6, absent=3)]

        for row in advice(subjects=rows, attendance_rate=60):
            self.assertTrue(row["numbers"], f"nothing to show for {row['code']}")
            self.assertTrue(row["message"].endswith("."), row["message"])

    def test_a_subject_level_suggestion_names_its_subject(self):
        rows = [subject(average="34.00", change="-20.00")]

        for row in advice(subjects=rows):
            self.assertEqual("Mathematics", row["subject_name"])
            self.assertEqual(1, row["subject_id"])

    def test_a_term_level_suggestion_belongs_to_no_subject(self):
        rows = [subject(average="34.00", assessments=6, absent=3)]

        for code in (insights.ARRANGE_RESIT, insights.ATTENDANCE_FIRST):
            row = one(advice(subjects=rows, attendance_rate=60), code)

            self.assertIsNone(row["subject_id"], code)
            self.assertIsNone(row["subject_name"], code)


class TheChapterAnAverageHides(TestCase):
    """The case the whole topic breakdown exists for.

    A subject at 70% looks like a child who is fine. If the trigonometry
    half of it is at 30%, that is a weak area the average was hiding - and
    a first draft of these rules said nothing about it, because it only
    looked at chapters once the subject itself was weak. A live demo
    caught it.
    """

    def healthy_subject_with_a_weak_chapter(self):
        rows = [subject(average="70.00", assessments=4)]
        rows[0]["topics"] = [topic("Vectors", 1, "90.00"), topic("Trigonometry", 2, "30.00")]

        return rows

    def test_a_weak_chapter_is_suggested_even_when_the_subject_looks_fine(self):
        row = one(advice(subjects=self.healthy_subject_with_a_weak_chapter()), insights.REVISE_TOPICS)

        self.assertIn("Revise Trigonometry in Mathematics", row["message"])

    def test_the_healthy_subject_is_not_also_sent_for_practice(self):
        """Only the chapter is weak; telling somebody to practise the whole
        of a subject they are at 70% in would be wrong."""
        found = codes(advice(subjects=self.healthy_subject_with_a_weak_chapter()))

        self.assertEqual([insights.REVISE_TOPICS], found)

    def test_the_finding_names_the_chapter_and_keeps_the_subject_average_beside_it(self):
        found = insights.for_performance(payload(subjects=self.healthy_subject_with_a_weak_chapter()))
        row = one(found, insights.WEAK_TOPIC)

        self.assertIn("Trigonometry in Mathematics is at 30%", row["message"])
        self.assertEqual("70", row["numbers"]["subject_average"])

    def test_a_school_with_no_weak_mark_flags_no_chapter(self):
        found = codes(advice(subjects=self.healthy_subject_with_a_weak_chapter(), weak_below=None))

        self.assertEqual([], found)

    def test_a_subject_with_every_chapter_healthy_says_nothing(self):
        rows = [subject(average="80.00", assessments=4)]
        rows[0]["topics"] = [topic("Vectors", 1, "90.00"), topic("Trigonometry", 2, "70.00")]

        self.assertEqual([], advice(subjects=rows))

