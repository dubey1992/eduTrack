"""The classic printed report card and the grading systems behind it
(docs/document-styles.md, decided 2026-11-17).

Built on the performance tests' world: one school, 2026-27 with Term 1
(April to August) and Term 2 (September to March), Grade 8 A, Mathematics
and Science, Aarav and his classmate Bina.

Set REPORT_CARD_SAMPLES to a folder to have the scenario PDFs written there.
"""

from __future__ import annotations

import datetime as dt
import os
from decimal import Decimal

from django.test import SimpleTestCase
from django.utils import timezone

from school import factories, pdf_design, progress_reports, report_card, report_card_classic
from school.enums import AssessmentStatus
from school.models import ModuleSetting
from school.performance import for_student
from school.tests.test_student_performance_api import PerformanceTestCase

D = Decimal


class CardTestCase(PerformanceTestCase):
    def setUp(self):
        super().setUp()
        self.english = factories.SubjectFactory(
            department=self.department, school=self.school, name="English", min_class_level=1, max_class_level=12
        )

        for student in (self.student, self.classmate):
            factories.StudentEnrollmentFactory(
                student=student, school=self.school, academic_year=self.year, school_class=self.school_class,
                class_section=self.section,
            )

    def settings(self, **values):
        row, _ = ModuleSetting.objects.get_or_create(
            school=self.school, module="assessments",
            defaults={"platform_enabled": True, "school_enabled": True, "settings": {}},
        )
        row.settings = {**(row.settings or {}), **values}
        row.save()

    def assessment(self, subject, title, max_marks, term=None, held=dt.date(2026, 5, 1), status=AssessmentStatus.PUBLISHED):
        return factories.AssessmentFactory(
            school=self.school, academic_year=self.year, academic_term=term or self.term_1,
            class_section=self.section, subject=subject, title=title, max_marks=D(max_marks),
            assessment_date=held, status=status, published_at=timezone.now(), created_by=self.admin,
        )

    def scale(self, kind="percentage", bands=None, multiplier=None):
        scale = factories.GradeScaleFactory(school=self.school, is_default=True, kind=kind, gpa_multiplier=multiplier)

        for label, low, high, failing, point, words in bands or [
            ("A1", 91, 100, False, None, "Outstanding"), ("A2", 81, 90.99, False, None, None),
            ("B1", 71, 80.99, False, None, None), ("B2", 61, 70.99, False, None, None),
            ("C", 33, 60.99, False, None, None), ("E", 0, 32.99, True, None, "Needs improvement"),
        ]:
            factories.GradeBandFactory(
                grade_scale=scale, label=label, min_percentage=D(str(low)), max_percentage=D(str(high)),
                is_failing=failing, grade_point=None if point is None else D(str(point)), description=words,
            )

        return scale

    def term_1_marks(self):
        """F.A.-I (20), Notebook (10), S.A.-I (50) in Maths and English."""
        fa = self.assessment(self.maths, "F.A.-I", "20", held=dt.date(2026, 5, 1))
        nb = self.assessment(self.maths, "Notebook", "10", held=dt.date(2026, 6, 1))
        sa = self.assessment(self.maths, "S.A.-I", "50", held=dt.date(2026, 8, 1))
        efa = self.assessment(self.english, "F.A.-I", "20", held=dt.date(2026, 5, 2))
        enb = self.assessment(self.english, "Notebook", "10", held=dt.date(2026, 6, 2))
        esa = self.assessment(self.english, "S.A.-I", "50", held=dt.date(2026, 8, 2))
        for test, got in ((fa, "19"), (nb, "8"), (sa, "41"), (efa, "17"), (enb, "9"), (esa, "44")):
            self.mark(test, marks=got)

        return fa, nb, sa

    def card(self, through=None, student=None):
        return report_card.load(student or self.student, through or self.term_1)

    def html(self, through=None, student=None, name=None) -> str:
        html = report_card_classic.document(
            student or self.student, through or self.term_1, school=self.school, generated_at="09/14/2026 12:00 PM"
        )
        self.assertEqual(0, pdf_design.style_errors(html), "xhtml2pdf dropped a cell's styles")
        folder = os.environ.get("REPORT_CARD_SAMPLES")

        if folder and name:
            os.makedirs(folder, exist_ok=True)

            with open(os.path.join(folder, f"{name}.pdf"), "wb") as handle:
                handle.write(pdf_design.render(html, name))

        return html


# -- the marks, added up --------------------------------------------------------------


class RawMarks(CardTestCase):
    def test_a_terms_tests_add_up_out_of_what_they_were_worth(self):
        self.scale()
        self.term_1_marks()

        card, _ = self.card()
        maths = next(row for row in card.subjects if row.name == "Mathematics")
        total = maths.terms[self.term_1.id]

        self.assertEqual((D("68"), D("80"), D("85.00"), "A2"), (total.obtained, total.possible, total.percentage, total.grade))
        self.assertEqual((D("138"), D("160"), D("86.25")), (card.overall.obtained, card.overall.possible, card.overall.percentage))

    def test_the_tests_are_columns_by_title_in_the_order_they_were_held_with_what_they_are_out_of(self):
        self.scale()
        self.term_1_marks()

        html = self.html(name="percentage")

        self.assertLess(html.index("F.A.-I<br/>(20)"), html.index("NOTEBOOK<br/>(10)"))
        self.assertLess(html.index("NOTEBOOK<br/>(10)"), html.index("S.A.-I<br/>(50)"))
        self.assertIn("TERM 1 (80 Marks)", html)
        self.assertIn("FINAL PERCENTAGE : 86.25%", html)

    def test_both_terms_side_by_side_and_added_for_the_year(self):
        self.scale()
        self.term_1_marks()
        sa2 = self.assessment(self.maths, "S.A.-II", "50", term=self.term_2, held=dt.date(2027, 2, 1))
        self.mark(sa2, marks="45")

        card, _ = self.card(through=self.term_2)

        self.assertEqual([self.term_1.id, self.term_2.id], [term.id for term in card.terms])
        self.assertEqual((D("183"), D("210")), (card.overall.obtained, card.overall.possible))
        html = self.html(through=self.term_2, name="two-terms")
        self.assertIn("TERM 2", html)

    def test_a_card_printed_after_term_1_shows_term_1_only(self):
        self.scale()
        self.term_1_marks()

        card, _ = self.card(through=self.term_1)

        self.assertEqual([self.term_1.id], [term.id for term in card.terms])

    def test_absent_prints_ab_and_leaves_the_total_rather_than_counting_nought(self):
        self.scale()
        fa = self.assessment(self.maths, "F.A.-I", "20")
        sa = self.assessment(self.maths, "S.A.-I", "50", held=dt.date(2026, 8, 1))
        self.mark(fa, is_absent=True)
        self.mark(sa, marks="40")

        card, _ = self.card()
        total = card.subjects[0].terms[self.term_1.id]

        self.assertEqual((D("40"), D("50"), D("80.00")), (total.obtained, total.possible, total.percentage))
        self.assertIn("<td>AB</td>", self.html(name="absent"))

    def test_a_subject_without_a_test_prints_a_dash_in_its_column(self):
        self.scale()
        self.mark(self.assessment(self.maths, "Project", "10"), marks="9")
        self.mark(self.assessment(self.english, "F.A.-I", "20"), marks="15")

        html = self.html()

        self.assertIn("<td>-</td>", html)

    def test_a_test_out_of_different_marks_in_different_subjects_shows_each_mark_out_of_its_own(self):
        self.scale()
        self.mark(self.assessment(self.maths, "Unit Test", "25"), marks="20")
        self.mark(self.assessment(self.english, "Unit Test", "20"), marks="15")

        html = self.html()

        self.assertIn("20/25", html)
        self.assertIn("15/20", html)

    def test_a_draft_result_counts_for_nothing(self):
        self.scale()
        self.mark(self.assessment(self.maths, "F.A.-I", "20"), marks="19")
        self.mark(self.assessment(self.maths, "S.A.-I", "50", status=AssessmentStatus.DRAFT), marks="10")

        card, _ = self.card()

        self.assertEqual(D("20"), card.overall.possible)

    def test_no_published_results_says_so_and_prints_no_result(self):
        self.scale()

        html = self.html(name="empty")

        self.assertIn("No published results yet", html)
        self.assertNotIn("RESULT :", html)


# -- grading systems ----------------------------------------------------------------


class GradingSystems(CardTestCase):
    def gpa_scale(self, multiplier=None):
        return self.scale("gpa", [
            ("A1", 91, 100, False, 10, None), ("A2", 81, 90.99, False, 9, None), ("B1", 71, 80.99, False, 8, None),
            ("B2", 61, 70.99, False, 7, None), ("C", 33, 60.99, False, 5, None), ("E", 0, 32.99, True, 0, None),
        ], multiplier=multiplier)

    def test_a_gpa_card_gives_each_subject_its_points_and_the_mean_as_gpa(self):
        self.gpa_scale(multiplier=D("9.5"))
        self.term_1_marks()

        card, _ = self.card()

        # Maths 85% (A2, 9), English 87.5% (A2, 9).
        self.assertEqual((D("9.00"), D("10")), (card.gpa, card.max_point))
        html = self.html(name="gpa")
        self.assertIn("FINAL GPA : 9 / 10", html)
        self.assertIn("EQUIVALENT PERCENTAGE : 85.50%", html)
        self.assertIn("<th>GP</th>", html)

    def test_no_equivalent_percentage_unless_the_school_sets_a_multiplier(self):
        self.gpa_scale()
        self.term_1_marks()

        self.assertNotIn("EQUIVALENT PERCENTAGE", self.html())

    def test_a_grades_only_card_prints_no_marks_and_no_percentages(self):
        self.scale("grades", [
            ("A", 80, 100, False, None, "Outstanding"), ("B", 60, 79.99, False, None, "Very good"),
            ("C", 40, 59.99, False, None, "Good"), ("D", 0, 39.99, True, None, "Needs help"),
        ])
        self.term_1_marks()

        html = self.html(name="grades-only")

        self.assertNotIn("FINAL PERCENTAGE", html)
        self.assertNotIn("F.A.-I", html)
        self.assertIn("FINAL GRADE : A", html)
        self.assertIn("Outstanding", html)

    def test_the_grading_key_lists_the_schools_own_bands(self):
        self.scale()
        self.term_1_marks()

        html = self.html()

        self.assertIn("INSTRUCTIONS AND GRADING SCALE", html)
        self.assertIn("Needs improvement", html)
        self.assertIn("91-100", html)


# -- the result --------------------------------------------------------------------------


class TheResult(CardTestCase):
    def setUp(self):
        super().setUp()
        self.scale()
        self.mark(self.assessment(self.maths, "S.A.-I", "100"), marks="90")
        # English 30%: below the 33% pass mark.
        self.mark(self.assessment(self.english, "S.A.-I", "100"), marks="30")

    def test_every_subject_by_default_a_subject_under_the_pass_mark_fails(self):
        card, _ = self.card()

        self.assertFalse(card.passed)
        self.assertIn("RESULT : NOT QUALIFIED", self.html())

    def test_overall_passes_on_the_years_total(self):
        self.settings(result_rule="overall")

        card, _ = self.card()

        self.assertTrue(card.passed)
        self.assertIn("RESULT : QUALIFIED", self.html())

    def test_the_school_writes_its_own_words(self):
        self.settings(result_rule="overall", result_pass_word="PROMOTED")

        self.assertIn("RESULT : PROMOTED", self.html())

    def test_no_result_when_the_school_prints_none(self):
        self.settings(result_rule="none")

        self.assertNotIn("RESULT :", self.html())

    def test_the_pass_mark_is_the_schools(self):
        self.settings(pass_percentage=25)

        card, _ = self.card()

        self.assertTrue(card.passed)


# -- the rank --------------------------------------------------------------------------


class TheRank(CardTestCase):
    def setUp(self):
        super().setUp()
        self.third = factories.StudentFactory(school=self.school, class_section=self.section, first_name="Chitra")
        factories.StudentEnrollmentFactory(
            student=self.third, school=self.school, academic_year=self.year, school_class=self.school_class,
            class_section=self.section,
        )
        self.scale()
        test = self.assessment(self.maths, "S.A.-I", "100")
        self.mark(test, marks="70")
        self.mark(test, student=self.classmate, marks="90")
        self.mark(test, student=self.third, marks="90")

    def test_not_printed_unless_the_school_asks(self):
        _, extra = self.card()

        self.assertIsNone(extra["rank"])
        self.assertNotIn("RANK :", self.html())

    def test_equal_scores_share_a_place_and_the_next_is_skipped(self):
        self.settings(print_rank=True)

        self.assertEqual(3, self.card()[1]["rank"])
        self.assertEqual(1, self.card(student=self.classmate)[1]["rank"])
        self.assertEqual(1, self.card(student=self.third)[1]["rank"])
        self.assertIn("RANK : 3", self.html(name="rank"))

    def test_classmates_in_another_section_are_not_ranked_against(self):
        self.settings(print_rank=True)
        other_section = factories.ClassSectionFactory(school_class=self.school_class, name="B")
        stranger = factories.StudentFactory(school=self.school, class_section=other_section, first_name="Dev")
        factories.StudentEnrollmentFactory(
            student=stranger, school=self.school, academic_year=self.year, school_class=self.school_class,
            class_section=other_section,
        )
        self.mark(self.assessment(self.maths, "S.A.-I", "100"), student=stranger, marks="99")

        self.assertEqual(1, self.card(student=self.classmate)[1]["rank"])


class Ranking(SimpleTestCase):
    def test_competition_ranking(self):
        scores = {1: D("90"), 2: D("90"), 3: D("70"), 4: D("85")}

        self.assertEqual((1, 1, 4, 3), tuple(report_card.rank_of(scores, n) for n in (1, 2, 3, 4)))
        self.assertIsNone(report_card.rank_of(scores, 9))


# -- the people on it ------------------------------------------------------------------


class ThePeople(CardTestCase):
    def test_the_guardian_when_no_parent_link_names_a_father_or_mother(self):
        self.scale()

        html = self.html()

        self.assertIn("Guardian&#x27;s Name", html)
        self.assertIn("STUDENT<br/>PHOTO", html)

    def test_the_schools_word_to_parents_and_instructions_when_it_writes_them(self):
        self.scale()
        self.settings(report_card_note="Please meet the class teacher on 12 March.",
                      report_card_instructions="Grades follow the board's nine-point scale.")

        html = self.html(name="with-notes")

        self.assertIn("A WORD TO PARENTS", html)
        self.assertIn("Please meet the class teacher on 12 March.", html)
        self.assertIn("nine-point scale", html)


# -- choosing the layout ----------------------------------------------------------------


class ChoosingTheLayout(CardTestCase):
    def test_the_standard_report_is_the_default(self):
        self.scale()
        self.term_1_marks()
        payload = for_student(self.student, self.term_1.id)

        self.assertIsNone(progress_reports.classic_target(payload, self.school))
        self.assertTrue(progress_reports.download_name(payload, self.school).startswith("progress-report-"))

    def test_a_school_that_chooses_classic_gets_it_from_the_download(self):
        self.scale()
        self.term_1_marks()
        self.settings(report_card_style="classic")

        response = self.client.get(
            f"/api/v1/students/{self.student.id}/progress-report", {"academic_term_id": self.term_1.id}
        )

        self.assertEqual(200, response.status_code)
        self.assertTrue(response.content.startswith(b"%PDF"))
        self.assertIn("report-card-adm-1", response["Content-Disposition"])

    def test_the_layout_setting_is_one_of_its_choices(self):
        response = self.client.put(
            "/api/v1/settings/modules/assessments", {"settings": {"report_card_style": "fancy"}}, format="json"
        )

        self.assertEqual(422, response.status_code)


# -- grade scales of every kind ------------------------------------------------------------


class GradeScalesOfEveryKind(CardTestCase):
    URL = "/api/v1/grade-scales"

    def body(self, kind="gpa", **overrides):
        bands = [
            {"label": "A", "min_percentage": "80", "max_percentage": "100", "grade_point": "4", "description": "Excellent"},
            {"label": "B", "min_percentage": "60", "max_percentage": "79.99", "grade_point": "3"},
            {"label": "C", "min_percentage": "40", "max_percentage": "59.99", "grade_point": "2"},
            {"label": "F", "min_percentage": "0", "max_percentage": "39.99", "grade_point": "0", "is_failing": True},
        ]
        return {"name": "US 4.0", "kind": kind, "bands": bands, **overrides}

    def test_a_gpa_scale_keeps_its_points_descriptions_and_multiplier(self):
        response = self.client.post(self.URL, self.body(gpa_multiplier="25"), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(("gpa", "25.00"), (response.data["kind"], response.data["gpa_multiplier"]))
        top = response.data["bands"][0]
        self.assertEqual(("4.00", "Excellent"), (top["grade_point"], top["description"]))

    def test_a_scale_sent_without_a_kind_is_a_percentage_scale_as_before(self):
        body = self.body()
        del body["kind"]

        response = self.client.post(self.URL, body, format="json")

        self.assertEqual("percentage", response.data["kind"])

    def test_a_gpa_band_without_points_is_refused(self):
        body = self.body()
        del body["bands"][1]["grade_point"]

        response = self.client.post(self.URL, body, format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("bands.1.grade_point", response.data["details"]["errors"])

    def test_a_better_band_may_not_carry_fewer_points(self):
        body = self.body()
        body["bands"][0]["grade_point"] = "1"

        response = self.client.post(self.URL, body, format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("fewer points", str(response.data["details"]["errors"]))

    def test_an_unknown_kind_is_refused(self):
        response = self.client.post(self.URL, self.body(kind="stars"), format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("kind", response.data["details"]["errors"])

    def test_a_teacher_may_not_make_a_scale(self):
        from school.enums import UserRole

        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(403, self.as_user(teacher).post(self.URL, self.body(), format="json").status_code)
