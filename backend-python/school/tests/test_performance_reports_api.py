"""The two performance reports, over HTTP (docs/assessments.md, slice 13).

Built on the same world as the other report tests - Monday 14 September
2026, reporting on Monday 7 to Friday 11 - so the rules those pin hold here
too: every rate out of the days the school actually ran, a group total
recomputed from counts rather than averaged, and the CSV, the PDF and the
screen carrying one set of figures.

What is being protected is mostly *not* arithmetic. It is that a draft says
nothing, that an absentee is not a nought, and that a figure here matches
the same figure on the student's own page - the ways a report can be
confidently wrong.
"""

import datetime as dt
from unittest import mock

from django.core.cache import cache
from django.test import TestCase

from school import factories
from school.enums import UserRole
from school.models import ModuleSetting
from school.reports import ClassPerformanceReport, StudentPerformanceReport, pdf
from school.tests.test_reports_api import FROM, NOW, TO, ReportTestCase, client_for, holiday

REPORTS = ("student-performance", "class-performance")


class PerformanceReportTestCase(ReportTestCase):
    def setUp(self):
        super().setUp()
        self.term = factories.AcademicTermFactory(
            academic_year=self.year, school=self.school, name="Term 1", sequence_number=1,
            start_date=dt.date(2026, 4, 1), end_date=dt.date(2026, 12, 31),
        )
        self.science = factories.DepartmentFactory(school=self.school, name="Science")
        self.physics = factories.SubjectFactory(school=self.school, department=self.science, name="Physics")
        # Its own department, because a subject always has one.
        self.arts = factories.DepartmentFactory(school=self.school, name="Mathematics")
        self.maths = factories.SubjectFactory(school=self.school, department=self.arts, name="Mathematics")
        self.hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        self.science.hod_user = self.hod
        self.science.save()

    def test_for(self, *, subject=None, day="2026-09-08", maximum=100, status="published", section=None,
                 weightage=None, scale=None):
        return factories.AssessmentFactory(
            class_section=section or self.section, school=self.school, academic_year=self.year,
            academic_term=self.term, subject=subject or self.physics, max_marks=maximum,
            assessment_date=day, status=status, weightage=weightage, grade_scale=scale,
            created_by=self.teacher,
        )

    def mark_for(self, assessment, student=None, obtained=None, absent=False):
        return factories.AssessmentMarkFactory(
            assessment=assessment, school=self.school, student=student or self.student,
            marks_obtained=None if absent else obtained, is_absent=absent, entered_by=self.teacher,
        )

    def rows(self, user, report, **params):
        response = self.get(user, report, **params)
        self.assertEqual(200, response.status_code, response.data)

        return response.data["rows"]


class StudentPerformance(PerformanceReportTestCase):
    def test_a_students_average_weighs_each_subject_evenly_not_each_test(self):
        """Two physics tests at 40 and 60, one maths at 90: physics averages
        50, so the student averages 70 - not the 63.3 a mean of the three
        marks would give."""
        self.mark_for(self.test_for(), obtained=40)
        self.mark_for(self.test_for(day="2026-09-09"), obtained=60)
        self.mark_for(self.test_for(subject=self.maths, day="2026-09-10"), obtained=90)

        row = self.rows(self.admin, "student-performance")[0]

        self.assertEqual("ADM-0042", row["admission_number"])
        self.assertEqual(2, row["subjects"])
        self.assertEqual(3, row["assessments"])
        self.assertEqual(70, row["average_percentage"])

    def test_a_draft_counts_for_nothing(self):
        self.mark_for(self.test_for(status="draft"), obtained=90)

        self.assertEqual([], self.rows(self.admin, "student-performance"))

    def test_an_absentee_leaves_the_average_rather_than_scoring_nought(self):
        self.mark_for(self.test_for(), obtained=80)
        self.mark_for(self.test_for(day="2026-09-09"), absent=True)

        row = self.rows(self.admin, "student-performance")[0]

        self.assertEqual(80, row["average_percentage"], "the missed test should not drag the average down")
        self.assertEqual(1, row["absent"])
        self.assertEqual(2, row["assessments"])

    def test_a_student_absent_for_everything_has_no_average_rather_than_a_nought(self):
        self.mark_for(self.test_for(), absent=True)

        row = self.rows(self.admin, "student-performance")[0]

        self.assertIsNone(row["average_percentage"])
        self.assertIsNone(row["grade"])

    def test_the_class_average_covers_the_same_tests_the_student_sat(self):
        """Arjun sits one of the two tests. The class figure beside him is
        the class's average on that test, not on both."""
        sat = self.test_for()
        missed = self.test_for(day="2026-09-09")
        other = factories.StudentFactory(class_section=self.section, first_name="Bina", last_name="Roy")

        self.mark_for(sat, obtained=60)
        self.mark_for(sat, student=other, obtained=40)
        self.mark_for(missed, student=other, obtained=100)

        row = next(row for row in self.rows(self.admin, "student-performance") if row["student"] == "Arjun Kumar")

        self.assertEqual(60, row["average_percentage"])
        self.assertEqual(50, row["class_average_percentage"], "the test Bina alone sat says nothing about Arjun")

    def test_weightages_count_only_where_every_test_in_a_subject_carries_one(self):
        self.mark_for(self.test_for(weightage=30), obtained=40)
        self.mark_for(self.test_for(day="2026-09-09", weightage=70), obtained=80)

        weighted = self.rows(self.admin, "student-performance")[0]["average_percentage"]

        self.assertEqual(68, weighted, "40 at 30 and 80 at 70 is 68, normalised by the weights present")

    def test_a_mixed_subject_falls_back_to_a_plain_mean(self):
        self.mark_for(self.test_for(weightage=30), obtained=40)
        self.mark_for(self.test_for(day="2026-09-09"), obtained=80)

        self.assertEqual(60, self.rows(self.admin, "student-performance")[0]["average_percentage"])

    def test_the_grade_comes_from_the_schools_scale(self):
        scale = factories.GradeScaleFactory(school=self.school, is_default=True)
        factories.GradeBandFactory(grade_scale=scale, label="B", min_percentage=0, max_percentage=79)
        factories.GradeBandFactory(grade_scale=scale, label="A", min_percentage=80, max_percentage=100)

        self.mark_for(self.test_for(), obtained=85)

        self.assertEqual("A", self.rows(self.admin, "student-performance")[0]["grade"])

    def test_attendance_is_out_of_the_days_the_school_actually_ran(self):
        holiday(self.school, "2026-09-09")
        for day in ("2026-09-07", "2026-09-08"):
            self.mark(day, "present")
        self.mark_for(self.test_for(), obtained=50)

        row = self.rows(self.admin, "student-performance")[0]

        self.assertEqual(50, row["attendance_rate"], "2 present out of 4 working days, the holiday not counted")

    def test_below_narrows_to_the_students_under_the_line(self):
        other = factories.StudentFactory(class_section=self.section, first_name="Bina", last_name="Roy")
        self.mark_for(self.test_for(), obtained=90)
        self.mark_for(self.test_for(day="2026-09-09"), student=other, obtained=30)

        rows = self.rows(self.admin, "student-performance", below=50)

        self.assertEqual(["Bina Roy"], [row["student"] for row in rows])

    def test_a_range_with_no_test_in_it_reports_nobody_rather_than_failing(self):
        self.mark_for(self.test_for(day="2026-08-01"), obtained=90)

        response = self.get(self.admin, "student-performance")

        self.assertEqual(200, response.status_code)
        self.assertEqual([], response.data["rows"])
        self.assertEqual(0, response.data["totals"]["students"])
        self.assertIsNone(response.data["totals"]["average_percentage"])

    def test_the_totals_count_the_students_who_have_a_result(self):
        quiet = factories.StudentFactory(class_section=self.section, first_name="Bina", last_name="Roy")
        self.mark_for(self.test_for(), obtained=60)
        self.mark_for(self.test_for(day="2026-09-09"), student=quiet, absent=True)

        totals = self.get(self.admin, "student-performance").data["totals"]

        self.assertEqual(2, totals["students"])
        self.assertEqual(1, totals["students_with_a_result"], "an absentee has no average to be counted in one")
        self.assertEqual(60, totals["average_percentage"])

    def test_the_schools_weak_mark_decides_what_counts_as_weak(self):
        ModuleSetting.objects.create(
            school=self.school, module="assessments", settings={"weak_below_percentage": 50},
            created_at=NOW, updated_at=NOW,
        )
        cache.clear()
        self.mark_for(self.test_for(), obtained=30)
        self.mark_for(self.test_for(subject=self.maths, day="2026-09-09"), obtained=90)

        row = self.rows(self.admin, "student-performance")[0]

        self.assertEqual(1, row["weak_subjects"], "physics is under 50, maths is not")
        # The two count different things, on purpose: a student can have a
        # weak subject and still be well above the mark overall, which is
        # this student - 30 and 90 average 60.
        self.assertEqual(60, row["average_percentage"])
        self.assertEqual(0, self.get(self.admin, "student-performance").data["totals"]["students_below_the_mark"])


class ClassPerformance(PerformanceReportTestCase):
    def test_a_subject_line_carries_its_average_its_best_and_its_worst(self):
        other = factories.StudentFactory(class_section=self.section, first_name="Bina", last_name="Roy")
        test = self.test_for()
        self.mark_for(test, obtained=40)
        self.mark_for(test, student=other, obtained=80)

        row = self.rows(self.admin, "class-performance")[0]

        self.assertEqual("Grade 8 A", row["class_section"])
        self.assertEqual("Physics", row["subject"])
        self.assertEqual("Science", row["department"])
        self.assertEqual(2, row["students"])
        self.assertEqual(1, row["assessments"])
        self.assertEqual(2, row["marks_counted"])
        self.assertEqual(60, row["average_percentage"])
        self.assertEqual(80, row["highest_percentage"])
        self.assertEqual(40, row["lowest_percentage"])

    def test_the_subject_average_is_over_every_mark_not_a_mean_of_student_means(self):
        """One student sits both tests, another sits one. Over the three
        marks the subject averages 60; a mean of the two student means would
        say 65."""
        other = factories.StudentFactory(class_section=self.section, first_name="Bina", last_name="Roy")
        first, second = self.test_for(), self.test_for(day="2026-09-09")
        self.mark_for(first, obtained=30)
        self.mark_for(second, obtained=60)
        self.mark_for(first, student=other, obtained=90)

        self.assertEqual(60, self.rows(self.admin, "class-performance")[0]["average_percentage"])

    def test_a_subject_nobody_sat_is_not_a_line(self):
        self.test_for(subject=self.maths)
        self.mark_for(self.test_for(), obtained=50)

        self.assertEqual(["Physics"], [row["subject"] for row in self.rows(self.admin, "class-performance")])

    def test_an_absentee_is_counted_as_absent_and_left_out_of_the_average(self):
        test = self.test_for()
        other = factories.StudentFactory(class_section=self.section, first_name="Bina", last_name="Roy")
        self.mark_for(test, obtained=80)
        self.mark_for(test, student=other, absent=True)

        row = self.rows(self.admin, "class-performance")[0]

        self.assertEqual(80, row["average_percentage"])
        self.assertEqual(1, row["absent"])
        self.assertEqual(1, row["marks_counted"])
        self.assertEqual(2, row["students"], "an absentee is still one of the class")

    def test_a_head_of_department_sees_their_own_subjects_and_no_others(self):
        self.mark_for(self.test_for(), obtained=50)
        self.mark_for(self.test_for(subject=self.maths, day="2026-09-09"), obtained=90)

        subjects = [row["subject"] for row in self.rows(self.hod, "class-performance")]

        self.assertEqual(["Physics"], subjects, "Mathematics is in no department they head")

    def test_a_department_filter_narrows_to_that_department(self):
        self.mark_for(self.test_for(), obtained=50)
        self.mark_for(self.test_for(subject=self.maths, day="2026-09-09"), obtained=90)

        rows = self.rows(self.admin, "class-performance", department_id=self.science.id)

        self.assertEqual(["Physics"], [row["subject"] for row in rows])


class WhoMayRead(PerformanceReportTestCase):
    def test_an_administrator_and_a_head_of_department_may_read_both(self):
        for report in REPORTS:
            for user in (self.admin, self.hod):
                self.assertEqual(200, self.get(user, report).status_code, f"{report} for {user.role}")

    def test_a_teacher_may_not(self):
        """A class teacher reads one child at a time on the student's page;
        a report across the school is not theirs."""
        for report in REPORTS:
            self.assertEqual(403, self.get(self.teacher, report).status_code, report)

    def test_a_school_admin_cannot_report_on_another_school(self):
        elsewhere = factories.SchoolFactory(name="Other School")

        for report in REPORTS:
            response = self.get(self.admin, report, school_id=elsewhere.id)

            self.assertEqual(200, response.status_code, report)
            self.assertEqual([], response.data["rows"], "another school's id must not widen the scope")

    def test_the_module_being_switched_off_closes_both(self):
        ModuleSetting.objects.create(
            school=self.school, module="reports", school_enabled=False, created_at=NOW, updated_at=NOW,
        )
        cache.clear()

        for report in REPORTS:
            response = self.get(self.admin, report)

            self.assertEqual(403, response.status_code, report)
            self.assertEqual("MODULE_DISABLED", response.data["code"], report)


class Exports(PerformanceReportTestCase):
    def setUp(self):
        super().setUp()
        self.mark_for(self.test_for(), obtained=60)

    def test_both_download_as_csv_named_for_the_period(self):
        for report in REPORTS:
            response = self.get(self.admin, report, format="csv")

            self.assertEqual(200, response.status_code, report)
            self.assertEqual("text/csv; charset=UTF-8", response["Content-Type"], report)
            self.assertEqual(f'attachment; filename="{report}-{FROM}-to-{TO}.csv"', response["Content-Disposition"])

    def test_both_download_as_pdf(self):
        for report in REPORTS:
            response = self.get(self.admin, report, format="pdf")

            self.assertEqual(200, response.status_code, report)
            self.assertEqual("application/pdf", response["Content-Type"], report)
            self.assertTrue(response.content.startswith(b"%PDF"), report)

    def test_the_pdf_rows_are_the_csv_rows(self):
        """Not similar to them - the same list, from the same method, so the
        two cannot drift apart."""
        for report, klass in (("student-performance", StudentPerformanceReport),
                              ("class-performance", ClassPerformanceReport)):
            built = self.get(self.admin, report).data
            document = pdf.document(klass(), built, school_label="Sunrise", generated_at="09/14/2026 12:00 PM")

            for cell in klass().csv_rows(built)[0]:
                if cell is None:
                    continue

                # Figures are right-aligned, words are not, so either cell
                # shape counts - what is being checked is the value.
                self.assertTrue(
                    f"<td>{cell}</td>" in document or f'<td class="num">{cell}</td>' in document,
                    f"{report}: {cell}",
                )

    def test_the_pdf_heading_reads_the_period_the_way_a_person_writes_one(self):
        document = pdf.document(
            StudentPerformanceReport(), self.get(self.admin, "student-performance").data,
            school_label="Sunrise", generated_at="09/14/2026 12:00 PM",
        )

        self.assertIn("09/07/2026 to 09/11/2026", document)
        self.assertNotIn("2026-09-07 to", document)

    def test_a_name_that_would_run_as_a_formula_is_quoted_into_text(self):
        """Anybody can be admitted as "=HYPERLINK(...)"; opened in Excel an
        unquoted export would run it on the machine that downloaded it."""
        self.student.first_name = "=HYPERLINK"
        self.student.last_name = "Kumar"
        self.student.save()

        body = self.get(self.admin, "student-performance", format="csv").content.decode("utf-8")

        self.assertIn("'=HYPERLINK Kumar", body)


class PreviousPeriod(PerformanceReportTestCase):
    def test_each_row_carries_what_it_averaged_before(self):
        self.mark_for(self.test_for(day="2026-09-08"), obtained=80)
        # 2-6 September is the same length, ending the day before this range.
        self.mark_for(self.test_for(day="2026-09-03"), obtained=40)

        row = self.rows(self.admin, "student-performance", compare=1)[0]

        self.assertEqual(80, row["average_percentage"])
        self.assertEqual(40, row["previous"]["average_percentage"])

    def test_a_row_that_did_not_exist_then_carries_nothing_rather_than_a_nought(self):
        self.mark_for(self.test_for(day="2026-09-08"), obtained=80)

        row = self.rows(self.admin, "student-performance", compare=1)[0]

        self.assertIsNone(row["previous"]["average_percentage"], "no result then is not 0% then")

    def test_the_comparison_names_the_period_it_measured(self):
        self.mark_for(self.test_for(), obtained=80)

        comparison = self.get(self.admin, "class-performance", compare=1).data["comparison"]

        self.assertEqual({"from": "2026-09-02", "to": "2026-09-06", "working_days": 3}, comparison["range"])


class AcrossAGroup(TestCase):
    """A Group Admin naming no branch reports on all of them at once."""

    def setUp(self):
        cache.clear()
        clock = mock.patch("django.utils.timezone.now", return_value=NOW)
        clock.start()
        self.addCleanup(clock.stop)

        self.parent = factories.SchoolFactory(name="Sunrise Group", timezone="UTC")
        self.one = factories.SchoolFactory(name="Sunrise North", timezone="UTC", parent_school=self.parent)
        self.two = factories.SchoolFactory(name="Sunrise South", timezone="UTC", parent_school=self.parent)
        self.admin = factories.UserFactory(school=self.parent, role=UserRole.GROUP_ADMIN)

        for school, obtained in ((self.one, 40), (self.two, 80)):
            year = factories.AcademicYearFactory(school=school)
            section = factories.ClassSectionFactory(
                school_class=factories.SchoolClassFactory(academic_year=year, school=school, name="Grade 8"),
                name="A",
            )
            teacher = factories.UserFactory(school=school, role=UserRole.TEACHER)
            assessment = factories.AssessmentFactory(
                class_section=section, school=school, academic_year=year,
                academic_term=factories.AcademicTermFactory(
                    academic_year=year, school=school, start_date=dt.date(2026, 4, 1), end_date=dt.date(2026, 12, 31)
                ),
                subject=factories.SubjectFactory(school=school, name="Physics"),
                max_marks=100, assessment_date="2026-09-08", status="published", created_by=teacher,
            )
            factories.AssessmentMarkFactory(
                assessment=assessment, school=school,
                student=factories.StudentFactory(class_section=section), marks_obtained=obtained,
                is_absent=False, entered_by=teacher,
            )

    def get(self, report, **params):
        return client_for(self.admin).get(f"/api/v1/reports/{report}", {"from": FROM, "to": TO, **params})

    def test_every_row_says_which_branch_it_came_from(self):
        response = self.get("student-performance")

        self.assertEqual(200, response.status_code, response.data)
        self.assertTrue(response.data["group"])
        self.assertEqual(
            {"Sunrise North", "Sunrise South"}, {row["school_name"] for row in response.data["rows"]}
        )

    def test_the_group_average_is_recomputed_rather_than_averaged_from_the_branches(self):
        totals = self.get("student-performance").data["totals"]

        self.assertEqual(3, totals["branches"], "the parent school is in the scope too")
        self.assertEqual(2, totals["students_with_a_result"])
        self.assertEqual(60, totals["average_percentage"], "40 and 80, one student each")

    def test_a_branch_with_nothing_to_report_does_not_break_the_roll_up(self):
        factories.SchoolFactory(name="Sunrise East", timezone="UTC", parent_school=self.parent)

        totals = self.get("class-performance").data["totals"]

        self.assertEqual(4, totals["branches"])
        self.assertEqual(2, totals["marks_counted"])
        self.assertEqual(60, totals["average_percentage"])

    def test_a_group_csv_names_the_branch_in_its_first_column(self):
        body = self.get("class-performance", format="csv").content.decode("utf-8")

        self.assertTrue(body.lstrip("﻿").startswith("School,Class,Subject"), body[:80])
        self.assertIn("Sunrise North", body)


class ThePrintedSheet(PerformanceReportTestCase):
    """What a report PDF has to state to be worth printing.

    The figures are covered elsewhere; this is about the page around them.
    A filtered sheet that looks like an unfiltered one is the defect that
    matters here - somebody will read it as the whole school's.
    """

    def setUp(self):
        super().setUp()
        self.mark_for(self.test_for(), obtained=60)

    def document(self, **params) -> str:
        built = self.get(self.admin, "student-performance", **params).data

        return pdf.document(
            StudentPerformanceReport(), built, school_label="Sunrise Public School",
            generated_at="09/14/2026 12:00 PM",
            filters=[("Class", "Grade 8 A"), ("Below", "50%")] if params else None,
        )

    def test_it_names_the_school_the_report_and_the_period(self):
        document = self.document()

        self.assertIn("Sunrise Public School", document)
        self.assertIn("Student performance", document)
        self.assertIn("09/07/2026 to 09/11/2026", document)
        self.assertIn("5 working days", document)

    def test_an_unfiltered_sheet_says_so_rather_than_saying_nothing(self):
        self.assertIn("None", self.document())

    def test_a_filtered_sheet_states_what_it_was_narrowed_to(self):
        document = self.document(class_section_id=self.section.id, below=50)

        self.assertIn("Class: Grade 8 A", document)
        self.assertIn("Below: 50%", document)

    def test_it_states_how_many_lines_to_expect_and_when_it_was_run(self):
        document = self.document()

        self.assertIn('<td class="key">Rows</td><td class="value">1</td>', document, "one student, one row")
        self.assertIn("09/14/2026 12:00 PM", document)

    def test_the_footer_numbers_the_pages(self):
        document = self.document()

        self.assertIn("page-footer", document)
        self.assertIn("<pdf:pagenumber>", document)
        self.assertIn("<pdf:pagecount>", document)

    def test_the_table_head_is_a_thead_so_it_repeats_on_every_page(self):
        """A hundred students run to several sheets, and a column of
        numbers with no heading on page two is unreadable."""
        document = self.document()

        self.assertIn("<thead>", document)
        self.assertIn("<tbody>", document)

    def test_it_still_renders(self):
        response = self.get(self.admin, "student-performance", format="pdf", class_section_id=self.section.id)

        self.assertEqual(200, response.status_code)
        self.assertTrue(response.content.startswith(b"%PDF"))

    def test_the_view_turns_the_filters_it_was_given_into_labels(self):
        from school.views.reports import filter_labels

        labels = filter_labels({
            "class_section_id": self.section.id, "department_id": self.science.id, "below": 40.0,
        }, [self.section.school_class.school_id])

        self.assertEqual([("Class", "Grade 8 A"), ("Department", "Science"), ("Below", "40%")], labels)

    def test_a_filter_naming_nothing_real_is_left_off_rather_than_printed_blank(self):
        from school.views.reports import filter_labels

        self.assertEqual([], filter_labels({"class_section_id": 9_999_999}, None))

    def test_another_schools_class_or_department_lends_the_sheet_no_name(self):
        # Its rows were already empty; its name must not head the PDF either.
        from school.views.reports import filter_labels

        own_school = self.section.school_class.school_id
        other = factories.SchoolFactory()
        other_section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(
                school=other, academic_year=factories.AcademicYearFactory(school=other)
            )
        )
        other_department = factories.DepartmentFactory(school=other, name="Their Department")

        labels = filter_labels(
            {"class_section_id": other_section.id, "department_id": other_department.id}, [own_school]
        )

        self.assertEqual([], labels)

    def test_a_download_carries_its_filters_to_the_page(self):
        """The seam the other tests miss: they hand filters to document()
        themselves, so nothing proved the view ever sends any."""
        with mock.patch("school.reports.pdf.render", wraps=pdf.render) as render:
            self.get(self.admin, "student-performance", format="pdf",
                     class_section_id=self.section.id, below=50)

        self.assertEqual(
            [("Class", "Grade 8 A"), ("Below", "50%")],
            render.call_args.kwargs["filters"],
        )


class HonestTotalsAndOrder(PerformanceReportTestCase):
    """Fixed 2026-11-18: totals that counted tests and students many times
    over, classes sorted as text, a never-present student shown as "-", and
    a default period that was usually empty."""

    def second_student(self, section=None, **fields):
        return factories.StudentFactory(class_section=section or self.section, **fields)

    def test_tests_held_counts_each_test_once_not_once_per_student(self):
        other = self.second_student()
        physics, maths = self.test_for(), self.test_for(subject=self.maths, day="2026-09-09")
        for student in (self.student, other):
            self.mark_for(physics, student=student, obtained=60)
            self.mark_for(maths, student=student, obtained=70)

        totals = self.get(self.admin, "student-performance").data["totals"]

        self.assertEqual(2, totals["tests_held"])
        self.assertNotIn("assessments", totals)

    def test_a_student_behind_in_two_subjects_is_one_student_behind(self):
        ModuleSetting.objects.update_or_create(
            school=self.school, module="assessments", defaults={"settings": {"weak_below_percentage": 50}},
        )
        self.mark_for(self.test_for(), obtained=30)
        self.mark_for(self.test_for(subject=self.maths, day="2026-09-09"), obtained=20)

        data = self.get(self.admin, "class-performance").data

        self.assertEqual([1, 1], [row["students_below_the_mark"] for row in data["rows"]])
        self.assertEqual(1, data["totals"]["students_below_in_a_subject"])

    def test_classes_sort_by_level_so_class_10_comes_after_class_2(self):
        def section_called(name, level):
            school_class = factories.SchoolClassFactory(academic_year=self.year, school=self.school, name=name, level=level)
            return factories.ClassSectionFactory(school_class=school_class, name="A")

        ten, two = section_called("Class 10", 10), section_called("Class 2", 2)
        for section in (ten, two):
            student = self.second_student(section=section)
            self.mark_for(self.test_for(section=section), student=student, obtained=50)

        students = [row["class_section"] for row in self.rows(self.admin, "student-performance")]
        classes = [row["class_section"] for row in self.rows(self.admin, "class-performance")]

        self.assertEqual(["Class 2 A", "Class 10 A"], [name for name in students if name.startswith("Class")])
        self.assertEqual(["Class 2 A", "Class 10 A"], [name for name in classes if name.startswith("Class")])

    def test_a_student_marked_but_never_present_is_0_percent_not_a_dash(self):
        self.mark_for(self.test_for(), obtained=50)
        self.mark("2026-09-08", "absent")

        row = self.rows(self.admin, "student-performance")[0]

        self.assertEqual(0, row["attendance_rate"])

    def test_nobody_on_any_register_is_still_a_dash(self):
        self.mark_for(self.test_for(), obtained=50)

        self.assertIsNone(self.rows(self.admin, "student-performance")[0]["attendance_rate"])

    def test_with_no_period_asked_for_both_cover_the_term_so_far(self):
        # Term 1 runs 1 April - 31 December; "now" is 14 September.
        self.mark_for(self.test_for(day="2026-04-20"), obtained=80)

        for report in ("student-performance", "class-performance"):
            with self.subTest(report=report):
                data = self.get(self.admin, report, **{"from": None, "to": None}).data
                self.assertEqual(("2026-04-01", "2026-09-14"), (data["range"]["from"], data["range"]["to"]))
                self.assertEqual(1, len(data["rows"]))

    def test_without_terms_the_current_year_so_far(self):
        # A term that has ended: none is current on 14 September.
        self.term.end_date = dt.date(2026, 6, 30)
        self.term.save()
        self.year.end_date, self.year.is_current = dt.date(2027, 3, 31), True
        self.year.save()
        self.mark_for(self.test_for(day="2026-04-20"), obtained=80)

        data = self.get(self.admin, "student-performance", **{"from": None, "to": None}).data

        self.assertEqual((self.year.start_date.isoformat(), "2026-09-14"), (data["range"]["from"], data["range"]["to"]))

    def test_a_period_asked_for_is_kept(self):
        data = self.get(self.admin, "student-performance").data

        self.assertEqual((FROM, TO), (data["range"]["from"], data["range"]["to"]))

    def test_every_other_report_still_defaults_to_this_month(self):
        data = self.get(self.admin, "student-attendance", **{"from": None, "to": None}).data

        self.assertEqual("2026-09-01", data["range"]["from"])


class FollowsTheGradingSystem(PerformanceReportTestCase):
    """Each row is read against its own grading system
    (docs/document-styles.md): marks and percentage, grade points, or grades
    only - never one scale for the whole report."""

    def scale(self, kind, bands, default=False):
        scale = factories.GradeScaleFactory(school=self.school, kind=kind, is_default=default)
        for label, low, high, points, fails in bands:
            factories.GradeBandFactory(
                grade_scale=scale, label=label, min_percentage=low, max_percentage=high,
                grade_point=points, is_failing=fails,
            )

        return scale

    def gpa_scale(self):
        return self.scale("gpa", [("A1", 91, 100, 10, False), ("B1", 71, 90, 8, False),
                                  ("C1", 41, 70, 6, False), ("E", 0, 40, None, True)])

    def grades_scale(self):
        return self.scale("grades", [("Excellent", 80, 100, None, False), ("Good", 50, 79, None, False),
                                     ("Needs help", 0, 49, None, True)])

    def test_a_gpa_scale_gives_the_mean_of_the_subjects_points(self):
        scale = self.gpa_scale()
        self.mark_for(self.test_for(scale=scale), obtained=95)  # physics A1 = 10
        self.mark_for(self.test_for(subject=self.maths, day="2026-09-09", scale=scale), obtained=75)  # B1 = 8

        data = self.get(self.admin, "student-performance").data
        row = data["rows"][0]

        self.assertEqual(("gpa", 9, "B1", 85), (row["grading"], row["gpa"], row["grade"], row["average_percentage"]))
        self.assertEqual((9, 1), (data["totals"]["average_gpa"], data["totals"]["students_with_a_gpa"]))

    def test_a_grades_only_scale_shows_grades_and_no_percentages(self):
        scale = self.grades_scale()
        self.mark_for(self.test_for(scale=scale), obtained=30)  # Needs help - failing
        self.mark_for(self.test_for(subject=self.maths, day="2026-09-09", scale=scale), obtained=90)

        student = self.get(self.admin, "student-performance").data
        row = student["rows"][0]

        self.assertEqual(("grades", "Good", None, None, None),
                         (row["grading"], row["grade"], row["average_percentage"], row["class_average_percentage"],
                          row["gpa"]))
        # Weak = a failing grade, with no percentage line needed.
        self.assertEqual(1, row["weak_subjects"])
        self.assertEqual(1, student["totals"]["students_with_a_result"])
        self.assertNotIn("average_gpa", student["totals"])

        rows = {row["subject"]: row for row in self.rows(self.admin, "class-performance")}
        self.assertEqual(("Needs help", None, None, None, 1),
                         (rows["Physics"]["grade"], rows["Physics"]["average_percentage"],
                          rows["Physics"]["highest_percentage"], rows["Physics"]["lowest_percentage"],
                          rows["Physics"]["students_below_the_mark"]))

    def test_each_class_is_read_against_its_own_scale(self):
        juniors = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=self.year, school=self.school, name="Class 1", level=1),
            name="A",
        )
        junior = factories.StudentFactory(class_section=juniors)
        self.mark_for(self.test_for(section=juniors, scale=self.grades_scale()), student=junior, obtained=85)
        self.mark_for(self.test_for(scale=self.gpa_scale()), obtained=95)

        rows = {row["student_id"]: row for row in self.rows(self.admin, "student-performance")}

        self.assertEqual(("grades", "Excellent", None), (rows[junior.id]["grading"], rows[junior.id]["grade"],
                                                         rows[junior.id]["gpa"]))
        self.assertEqual(("gpa", "A1", 10), (rows[self.student.id]["grading"], rows[self.student.id]["grade"],
                                             rows[self.student.id]["gpa"]))

    def test_class_performance_gives_the_average_points_on_a_gpa_scale(self):
        scale = self.gpa_scale()
        other = factories.StudentFactory(class_section=self.section)
        test = self.test_for(scale=scale)
        self.mark_for(test, obtained=95)  # 10 points
        self.mark_for(test, student=other, obtained=60)  # 6 points

        row = self.rows(self.admin, "class-performance")[0]

        self.assertEqual(("gpa", 8, "B1", 77.5), (row["grading"], row["average_points"], row["grade"],
                                                  row["average_percentage"]))

    def test_a_percentage_scale_is_as_before(self):
        scale = self.scale("percentage", [("A", 80, 100, None, False), ("B", 0, 79, None, False)], default=True)
        self.mark_for(self.test_for(), obtained=85)

        row = self.rows(self.admin, "student-performance")[0]

        self.assertEqual(("percentage", "A", 85, None), (row["grading"], row["grade"], row["average_percentage"],
                                                         row["gpa"]))
        self.assertTrue(scale.is_default)

    def test_the_csv_carries_the_gpa_and_grade_columns(self):
        self.mark_for(self.test_for(scale=self.gpa_scale()), obtained=95)

        student = self.get(self.admin, "student-performance", format="csv").content.decode("utf-8-sig")
        subjects = self.get(self.admin, "class-performance", format="csv").content.decode("utf-8-sig")

        self.assertIn("Grade,GPA", student.splitlines()[0])
        self.assertIn('Grade,"Average points"', subjects.splitlines()[0])
