"""The printable progress report (docs/assessments.md, slice 14).

Built on the performance tests' world, because it is the performance
payload laid out: the same student, terms and subjects, so a figure that
changed here without changing there would be caught by those tests rather
than hidden behind a PDF.

What is pinned here is the document around the figures - who may print it,
what it must never say about a child, and the one thing it shows that the
screen does not: the grade frozen onto each mark at publish.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal
from unittest import mock

from django.core.cache import cache
from django.utils import timezone

from school import factories, progress_reports
from school.enums import UserRole
from school.models import ModuleSetting
from school.performance import for_student
from school.tests.test_student_performance_api import PerformanceTestCase

NOW = dt.datetime(2026, 9, 14, 12, 0, tzinfo=dt.timezone.utc)


class ProgressReportTestCase(PerformanceTestCase):
    def download(self, client=None, student=None, **params):
        return (client or self.client).get(
            f"/api/v1/students/{(student or self.student).id}/progress-report", params
        )

    def page(self, student=None, term_id=None, school_name="Sunrise Public School") -> str:
        """The document's HTML, which is what the assertions read."""
        payload = for_student(student or self.student, term_id)

        return progress_reports.document(payload, school_name=school_name, generated_at="09/14/2026 12:00 PM")


class WhatItSays(ProgressReportTestCase):
    def test_it_names_the_school_the_child_and_the_term(self):
        self.mark(self.published(), marks="18")

        page = self.page()

        self.assertIn("Sunrise Public School", page)
        self.assertIn("Progress report", page)
        self.assertIn("Aarav", page)
        self.assertIn("ADM-1", page)
        self.assertIn("Grade 8 A", page)
        self.assertIn("Term 2", page)

    def test_the_term_dates_read_the_way_the_rest_of_the_app_writes_a_date(self):
        self.mark(self.published(), marks="18")

        page = self.page()

        self.assertIn("09/01/2026 to 03/31/2027", page)
        self.assertNotIn("2026-09-01", page)

    def test_a_subject_line_carries_the_average_and_the_class_beside_it(self):
        self.mark(self.published(), marks="18")
        self.mark(self.published(), marks="12")

        page = self.page()

        self.assertIn("Mathematics", page)
        self.assertIn("75%", page, "90% and 60%")

    def test_every_test_is_listed_with_the_grade_frozen_onto_it(self):
        """The one thing the screen does not show. A subject average is
        worked out on the way out; a test's grade was decided the day the
        result went out, and that is the one a guardian can question."""
        assessment = self.published()
        mark = self.mark(assessment, marks="18")
        mark.grade = "A1"
        mark.save()

        page = self.page()

        self.assertIn("A1", page)
        self.assertIn("18", page)
        self.assertIn("20", page, "out of")

    def test_the_frozen_grade_is_shown_even_after_the_bands_move_under_it(self):
        scale = factories.GradeScaleFactory(school=self.school, is_default=True)
        band = factories.GradeBandFactory(grade_scale=scale, label="A", min_percentage=0, max_percentage=100)
        mark = self.mark(self.published(grade_scale=scale), marks="18")
        mark.grade = "A1"
        mark.save()

        # The school renames its band afterwards. The published result must
        # not quietly change underneath the family.
        band.label = "Top"
        band.save()

        self.assertIn("A1", self.page())

    def test_an_absence_is_said_in_words_rather_than_left_blank(self):
        """A blank cell reads as a nought, and a nought would be a lie about
        a child who was not there."""
        self.mark(self.published(), is_absent=True)

        page = self.page()

        self.assertIn("Absent", page)

    def test_attendance_is_reported_beside_the_marks(self):
        self.mark(self.published(), marks="18")

        self.assertIn("Attendance", self.page())

    def test_the_page_is_numbered_and_carries_the_child_in_its_footer(self):
        self.mark(self.published(), marks="18")

        page = self.page()

        self.assertIn("page-footer", page)
        self.assertIn("<pdf:pagenumber>", page)
        self.assertIn("<pdf:pagecount>", page)
        self.assertIn("Aarav", page)

    def test_it_states_when_it_was_generated(self):
        self.mark(self.published(), marks="18")

        self.assertIn("09/14/2026 12:00 PM", self.page())


class WhenThereIsNothingToSay(ProgressReportTestCase):
    def test_a_term_with_no_published_result_says_so_in_words(self):
        page = self.page()

        self.assertIn("No result has been published for this term yet.", page)
        # Scoped to a printed figure: the stylesheet itself contains "100%".
        self.assertNotIn("<b>0%</b>", page, "nothing published is not nought")

    def test_a_draft_is_still_nothing(self):
        self.mark(self.draft(), marks="20")

        self.assertIn("No result has been published for this term yet.", self.page())

    def test_a_school_with_no_terms_says_that_instead(self):
        self.term_1.delete()
        self.term_2.delete()

        self.assertIn("has not set its terms out", self.page())

    def test_one_subject_prints_as_readily_as_fifteen(self):
        self.mark(self.published(subject=self.maths), marks="18")

        one = self.page()
        self.assertIn("Mathematics", one)

        for index in range(14):
            subject = factories.SubjectFactory(
                department=self.department, school=self.school, name=f"Subject {index:02d}",
                min_class_level=1, max_class_level=12,
            )
            self.mark(self.published(subject=subject), marks="15")

        many = self.page()

        for index in range(14):
            self.assertIn(f"Subject {index:02d}", many)

    def test_a_student_with_no_register_taken_gets_a_sentence_not_a_nought(self):
        """0% out of 22 working days is the truth about the school's
        paperwork and would be read, on a page going home, as a child who
        attended nothing."""
        self.mark(self.published(), marks="18")

        page = self.page()

        self.assertIn("The register was not taken in this period.", page)
        self.assertNotIn("<b>0%</b>", page)


class NamesAndMarkup(ProgressReportTestCase):
    def test_a_very_long_name_is_printed_rather_than_breaking_the_page(self):
        self.student.first_name = "Bartholomew" * 8
        self.student.save()
        self.mark(self.published(), marks="18")

        self.assertIn("Bartholomew" * 8, self.page())

    def test_a_name_with_markup_in_it_is_printed_not_obeyed(self):
        self.student.first_name = "<b>Aarav</b>"
        self.student.save()
        self.mark(self.published(), marks="18")

        page = self.page(school_name="Sunrise & Co <script>")

        self.assertIn("&lt;b&gt;Aarav&lt;/b&gt;", page)
        self.assertIn("Sunrise &amp; Co &lt;script&gt;", page)
        self.assertNotIn("<script>", page)

    def test_a_zero_survives_being_escaped(self):
        """The receipt's e() reads 0 as nothing, which would blank every
        count on the page."""
        self.mark(self.published(), is_absent=True)
        self.mark(self.published(), marks="0")

        self.assertIn(">0<", self.page())


class TheFile(ProgressReportTestCase):
    def test_it_is_named_for_the_child_and_the_term(self):
        self.mark(self.published(), marks="18")

        response = self.download()

        self.assertEqual(200, response.status_code)
        self.assertEqual("application/pdf", response["Content-Type"])
        self.assertEqual(
            'attachment; filename="progress-report-adm-1-term-2.pdf"', response["Content-Disposition"]
        )

    def test_it_really_is_a_pdf(self):
        self.mark(self.published(), marks="18")

        self.assertTrue(self.download().content.startswith(b"%PDF"))

    def test_a_name_that_would_be_awkward_in_a_filename_is_flattened(self):
        self.student.admission_number = "ADM/001 (new)"
        self.student.save()

        response = self.download()

        self.assertEqual(
            'attachment; filename="progress-report-adm-001--new-term-2.pdf"', response["Content-Disposition"]
        )

    def test_it_can_be_asked_for_one_term_at_a_time(self):
        self.mark(self.published(term=self.term_1), marks="18")

        response = self.download(academic_term_id=self.term_1.id)

        self.assertIn("term-1.pdf", response["Content-Disposition"])

    def test_a_term_of_another_school_is_refused_rather_than_printed(self):
        elsewhere = factories.AcademicYearFactory(school=factories.SchoolFactory())
        theirs = factories.AcademicTermFactory(academic_year=elsewhere, school=elsewhere.school)

        self.assertEqual(422, self.download(academic_term_id=theirs.id).status_code)


class WhoMayPrintWhose(ProgressReportTestCase):
    def test_a_school_admin_may(self):
        self.assertEqual(200, self.download().status_code)

    def test_the_class_teacher_may(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.section.class_teacher = teacher
        self.section.save()

        self.assertEqual(200, self.download(client=self.as_user(teacher)).status_code)

    def test_a_teacher_of_another_class_may_not(self):
        other = factories.ClassSectionFactory(school_class=self.school_class, name="B")
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        other.class_teacher = teacher
        other.save()

        self.assertEqual(403, self.download(client=self.as_user(teacher)).status_code)

    def test_another_schools_administrator_may_not(self):
        elsewhere = factories.SchoolFactory()
        stranger = factories.UserFactory(school=elsewhere, role=UserRole.SCHOOL_ADMIN)

        self.assertIn(self.download(client=self.as_user(stranger)).status_code, (403, 404))

    def test_signing_out_closes_it(self):
        from rest_framework.test import APIClient

        self.assertEqual(401, APIClient().get(f"/api/v1/students/{self.student.id}/progress-report").status_code)

    def test_a_school_with_class_tests_switched_off_has_no_report_to_print(self):
        ModuleSetting.objects.create(
            school=self.school, module="assessments", school_enabled=False,
            created_at=timezone.now(), updated_at=timezone.now(),
        )
        cache.clear()

        response = self.download()

        self.assertEqual(403, response.status_code)
        self.assertEqual("MODULE_DISABLED", response.data["code"])


class TheSchoolsOwnClock(ProgressReportTestCase):
    def test_the_footer_date_is_the_schools_not_the_servers(self):
        """A school in Asia/Kolkata printing at half past nine in the
        evening is on that day, not the UTC one that has not started."""
        self.school.timezone = "Asia/Kolkata"
        self.school.save()
        cache.clear()
        self.mark(self.published(), marks="18")

        # 20:00 UTC on the 14th is 01:30 on the 15th in Kolkata.
        with mock.patch("django.utils.timezone.now", return_value=dt.datetime(2026, 9, 14, 20, 0, tzinfo=dt.timezone.utc)):
            body = self.download().content

        self.assertTrue(body.startswith(b"%PDF"))

        with mock.patch("django.utils.timezone.now", return_value=dt.datetime(2026, 9, 14, 20, 0, tzinfo=dt.timezone.utc)):
            from school.clock import DATE_TIME, SchoolClock

            clock = SchoolClock.for_school(self.school.id)
            self.assertEqual("09/15/2026 1:30 AM", clock.format(clock.now(), DATE_TIME))


class TheSameFiguresAsTheScreen(ProgressReportTestCase):
    def test_the_document_reads_the_payload_the_screen_reads(self):
        """Not similar figures - the same payload object, so the two cannot
        drift apart."""
        self.mark(self.published(), marks="18")
        self.mark(self.published(subject=self.science), marks="10")

        payload = for_student(self.student, None)
        page = progress_reports.document(payload, school_name="Sunrise", generated_at="now")

        for subject in payload["subjects"]:
            self.assertIn(subject["subject_name"], page)
            self.assertIn(f"{subject['average_percentage'].rstrip('0').rstrip('.')}%", page)

    def test_an_insight_from_the_rules_is_printed_as_written(self):
        ModuleSetting.objects.create(
            school=self.school, module="assessments", settings={"weak_below_percentage": 50},
            created_at=timezone.now(), updated_at=timezone.now(),
        )
        cache.clear()
        self.mark(self.published(), marks=Decimal("4"))
        self.mark(self.published(), marks=Decimal("5"))

        payload = for_student(self.student, None)
        page = progress_reports.document(payload, school_name="Sunrise", generated_at="now")

        self.assertTrue(payload["insights"], "the rules should have something to say about 22.5%")
        for insight in payload["insights"]:
            self.assertIn(insight["message"].split(" is ")[0], page)
