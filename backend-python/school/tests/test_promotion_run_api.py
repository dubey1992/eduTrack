"""Running a promotion (docs/promotion.md).

A promotion moves a whole class in one act, so the tests here are about the
four outcomes and - more importantly - about the ways a run must refuse:

- a roster that changed since the list was drawn up, which is two
  administrators on two screens and the reason the run locks the class;
- a student who already has a place in the target year, named rather than
  skipped;
- a failure part-way through, after which nothing at all may survive: no
  batch row, no enrollment, no repointed student;
- and the year a retained child repeats, which must exist before anybody is
  told they are repeating it.

What a run leaves behind is the other half: a batch anybody can read back,
a history for each child covering both years, and one audit entry naming
the counts and the students.
"""

import datetime as dt
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import EnrollmentStatus, StudentStatus, UserRole
from school.models import AuditLog, PromotionBatch, Student, StudentEnrollment

URL = "/api/v1/promotions"


class RunTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.this_year = factories.AcademicYearFactory(
            school=self.school,
            name="2026-27",
            start_date=dt.date(2026, 4, 1),
            end_date=dt.date(2027, 3, 31),
            is_current=True,
        )
        self.next_year = factories.AcademicYearFactory(
            school=self.school,
            name="2027-28",
            start_date=dt.date(2027, 4, 1),
            end_date=dt.date(2028, 3, 31),
            is_current=False,
        )

        self.grade_8 = factories.SchoolClassFactory(
            academic_year=self.this_year, school=self.school, name="Grade 8", level=8
        )
        self.section = factories.ClassSectionFactory(school_class=self.grade_8, name="A")

        # Next year's Grade 8 (for anybody held back) and Grade 9 (for
        # everybody else).
        self.next_grade_8 = factories.SchoolClassFactory(
            academic_year=self.next_year, school=self.school, name="Grade 8", level=8
        )
        self.next_grade_8_a = factories.ClassSectionFactory(school_class=self.next_grade_8, name="A")
        self.grade_9 = factories.SchoolClassFactory(
            academic_year=self.next_year, school=self.school, name="Grade 9", level=9
        )
        self.grade_9_a = factories.ClassSectionFactory(school_class=self.grade_9, name="A")

        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

        self.aarav = self.student("Aarav", "ADM-1", roll_number="1")
        self.bina = self.student("Bina", "ADM-2", roll_number="2")
        self.chetan = self.student("Chetan", "ADM-3", roll_number="3")

        for student in (self.aarav, self.bina, self.chetan):
            self.studying(student)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def student(self, first_name: str, admission_number: str, **fields):
        return factories.StudentFactory(
            school=self.school,
            class_section=self.section,
            first_name=first_name,
            admission_number=admission_number,
            **fields,
        )

    def studying(self, student) -> StudentEnrollment:
        """The row the backfill or an admission would have written."""
        return factories.StudentEnrollmentFactory(
            student=student,
            school=self.school,
            academic_year=self.this_year,
            school_class=self.grade_8,
            class_section=self.section,
            roll_number=student.roll_number,
            status=EnrollmentStatus.STUDYING,
        )

    def body(self, outcomes=None, **overrides) -> dict:
        payload = {
            "class_section_id": self.section.id,
            "to_academic_year_id": self.next_year.id,
            "outcomes": outcomes
            if outcomes is not None
            else [
                {"student_id": self.aarav.id, "outcome": "promote"},
                {"student_id": self.bina.id, "outcome": "promote"},
                {"student_id": self.chetan.id, "outcome": "promote"},
            ],
        }
        payload.update(overrides)

        return payload

    def promote(self, client=None, **kwargs):
        """Not called run(): that is TestCase's own, and overriding it makes
        the runner call this instead."""
        return (client or self.client).post(URL, self.body(**kwargs), format="json")

    def enrollments_of(self, student):
        return {row.academic_year_id: row for row in StudentEnrollment.objects.filter(student_id=student.id)}

    def reloaded(self, student) -> Student:
        return Student.objects.get(pk=student.id)


class TheFourOutcomes(RunTestCase):
    def test_a_whole_class_moves_up_and_the_batch_says_so(self):
        response = self.promote()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(3, response.data["promoted_count"])
        self.assertEqual(0, response.data["retained_count"])
        self.assertEqual("Grade 8 A", response.data["from_class_section_name"])
        self.assertEqual("Grade 9 A", response.data["to_class_section_name"])
        self.assertEqual("2027-28", response.data["to_academic_year_name"])
        self.assertEqual(self.admin.name, response.data["run_by_name"])

        for student in (self.aarav, self.bina, self.chetan):
            rows = self.enrollments_of(student)
            self.assertEqual(EnrollmentStatus.PROMOTED, rows[self.this_year.id].status)
            self.assertEqual(EnrollmentStatus.STUDYING, rows[self.next_year.id].status)
            self.assertEqual(self.grade_9_a.id, rows[self.next_year.id].class_section_id)
            self.assertEqual(self.grade_9_a.id, self.reloaded(student).class_section_id)

    def test_a_retained_student_repeats_the_same_class_in_the_new_year(self):
        self.promote(
            outcomes=[
                {"student_id": self.aarav.id, "outcome": "promote"},
                {"student_id": self.bina.id, "outcome": "retain"},
            ]
        )

        rows = self.enrollments_of(self.bina)

        self.assertEqual(EnrollmentStatus.RETAINED, rows[self.this_year.id].status)
        self.assertEqual(self.next_grade_8_a.id, rows[self.next_year.id].class_section_id, "Grade 8 again, next year")
        self.assertEqual(self.next_grade_8_a.id, self.reloaded(self.bina).class_section_id)
        self.assertEqual(StudentStatus.ACTIVE, self.reloaded(self.bina).status)

    def test_a_graduated_student_keeps_the_record_and_loses_the_class(self):
        self.promote(outcomes=[{"student_id": self.chetan.id, "outcome": "graduate"}])

        rows = self.enrollments_of(self.chetan)
        student = self.reloaded(self.chetan)

        self.assertEqual(EnrollmentStatus.GRADUATED, rows[self.this_year.id].status)
        self.assertNotIn(self.next_year.id, rows, "they finished: there is no next year")
        self.assertIsNone(student.class_section_id)
        self.assertEqual(StudentStatus.GRADUATED, student.status)

    def test_a_student_left_out_has_their_year_closed_and_nothing_else_touched(self):
        self.aarav.status = StudentStatus.INACTIVE
        self.aarav.save(update_fields=["status"])

        self.promote(outcomes=[{"student_id": self.aarav.id, "outcome": "leave"}])

        rows = self.enrollments_of(self.aarav)
        student = self.reloaded(self.aarav)

        self.assertEqual(EnrollmentStatus.LEFT, rows[self.this_year.id].status)
        self.assertNotIn(self.next_year.id, rows)
        self.assertEqual(self.section.id, student.class_section_id, "they had already gone; nothing is repointed")
        self.assertEqual(StudentStatus.INACTIVE, student.status)

    def test_one_batch_can_do_all_four(self):
        self.chetan.status = StudentStatus.INACTIVE
        self.chetan.save(update_fields=["status"])
        fourth = self.student("Deepa", "ADM-4")
        self.studying(fourth)

        response = self.promote(
            outcomes=[
                {"student_id": self.aarav.id, "outcome": "promote"},
                {"student_id": self.bina.id, "outcome": "retain"},
                {"student_id": self.chetan.id, "outcome": "leave"},
                {"student_id": fourth.id, "outcome": "graduate"},
            ]
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(
            {"promoted": 1, "retained": 1, "graduated": 1, "left": 1},
            {
                "promoted": response.data["promoted_count"],
                "retained": response.data["retained_count"],
                "graduated": response.data["graduated_count"],
                "left": response.data["left_count"],
            },
        )
        self.assertEqual(4, response.data["student_count"])

    def test_a_student_left_out_of_the_batch_is_left_alone(self):
        self.promote(outcomes=[{"student_id": self.aarav.id, "outcome": "promote"}])

        untouched = self.enrollments_of(self.bina)

        self.assertEqual(EnrollmentStatus.STUDYING, untouched[self.this_year.id].status)
        self.assertEqual(self.section.id, self.reloaded(self.bina).class_section_id)

    def test_the_new_row_remembers_where_it_came_from(self):
        self.promote(outcomes=[{"student_id": self.aarav.id, "outcome": "promote"}])

        rows = self.enrollments_of(self.aarav)
        batch = PromotionBatch.objects.get()

        self.assertEqual(batch.id, rows[self.this_year.id].promotion_batch_id)
        self.assertEqual(batch.id, rows[self.next_year.id].promotion_batch_id)
        self.assertEqual(
            rows[self.this_year.id].id,
            rows[self.next_year.id].promoted_from_enrollment_id,
            "the chain is what makes a history readable backwards",
        )

    def test_a_year_nobody_recorded_is_closed_rather_than_skipped(self):
        # A student admitted before the history table existed, whom the
        # backfill never reached: the promotion must not leave a hole where
        # their last year should be.
        StudentEnrollment.objects.filter(student_id=self.aarav.id).delete()

        self.promote(outcomes=[{"student_id": self.aarav.id, "outcome": "promote"}])

        rows = self.enrollments_of(self.aarav)
        self.assertEqual(EnrollmentStatus.PROMOTED, rows[self.this_year.id].status)
        self.assertEqual(self.section.id, rows[self.this_year.id].class_section_id)


class WhenARunMustRefuse(RunTestCase):
    def test_a_class_that_changed_since_the_list_was_drawn_up(self):
        stranger = factories.StudentFactory(
            school=self.school,
            class_section=factories.ClassSectionFactory(school_class=self.grade_8, name="B"),
            first_name="Elsewhere",
            admission_number="ADM-9",
        )

        response = self.promote(
            outcomes=[
                {"student_id": self.aarav.id, "outcome": "promote"},
                {"student_id": stranger.id, "outcome": "promote"},
            ]
        )

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("ROSTER_CHANGED", response.data["code"])
        self.assertEqual(0, PromotionBatch.objects.count())
        self.assertEqual(self.section.id, self.reloaded(self.aarav).class_section_id, "nobody moved")

    def test_a_student_who_already_has_a_place_next_year(self):
        factories.StudentEnrollmentFactory(
            student=self.bina,
            school=self.school,
            academic_year=self.next_year,
            school_class=self.grade_9,
            class_section=self.grade_9_a,
        )

        response = self.promote()

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("ALREADY_ENROLLED", response.data["code"])
        self.assertIn("Bina", response.data["message"], "being told which child is the point")
        self.assertEqual(0, PromotionBatch.objects.count())

    def test_running_the_same_batch_twice(self):
        self.assertEqual(201, self.promote().status_code)

        again = self.promote()

        self.assertEqual(409, again.status_code, again.data)
        self.assertEqual("ALREADY_ENROLLED", again.data["code"])
        self.assertEqual(1, PromotionBatch.objects.count(), "the second run wrote nothing")

    def test_an_empty_class(self):
        empty = factories.ClassSectionFactory(school_class=self.grade_8, name="C")

        response = self.promote(class_section_id=empty.id, outcomes=[{"student_id": self.aarav.id, "outcome": "promote"}])

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("NOTHING_TO_PROMOTE", response.data["code"])

    def test_a_batch_that_names_nobody(self):
        response = self.promote(outcomes=[])

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("outcomes", response.data["details"]["errors"])

    def test_the_same_student_twice_with_two_answers(self):
        response = self.promote(
            outcomes=[
                {"student_id": self.aarav.id, "outcome": "promote"},
                {"student_id": self.aarav.id, "outcome": "graduate"},
            ]
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("outcomes.1.student_id", response.data["details"]["errors"])

    def test_an_outcome_that_is_not_one(self):
        response = self.promote(outcomes=[{"student_id": self.aarav.id, "outcome": "expelled"}])

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("outcomes.0.outcome", response.data["details"]["errors"])

    def test_promoting_into_the_same_year(self):
        response = self.promote(to_academic_year_id=self.this_year.id)

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("SAME_ACADEMIC_YEAR", response.data["code"])

    def test_another_school_s_year(self):
        elsewhere = factories.AcademicYearFactory(school=factories.SchoolFactory(), name="2027-28", is_current=False)

        response = self.promote(to_academic_year_id=elsewhere.id)

        self.assertEqual(404, response.status_code, response.data)
        self.assertEqual("TARGET_YEAR_NOT_FOUND", response.data["code"])

    def test_a_target_section_in_the_wrong_year(self):
        response = self.promote(to_class_section_id=self.section.id)

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("TARGET_SECTION_MISMATCH", response.data["code"])

    def test_retaining_a_child_into_a_year_that_has_no_such_class(self):
        self.next_grade_8_a.delete()
        self.next_grade_8.delete()

        response = self.promote(outcomes=[{"student_id": self.bina.id, "outcome": "retain"}])

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("RETAIN_CLASS_MISSING", response.data["code"])
        self.assertEqual(0, PromotionBatch.objects.count())
        self.assertEqual(
            EnrollmentStatus.STUDYING,
            self.enrollments_of(self.bina)[self.this_year.id].status,
            "the year is not closed by a run that failed",
        )

    def test_promoting_a_class_with_nothing_above_it(self):
        self.grade_9_a.delete()
        self.grade_9.delete()

        response = self.promote(outcomes=[{"student_id": self.aarav.id, "outcome": "promote"}])

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("RETAIN_CLASS_MISSING", response.data["code"])
        self.assertIn("no class above", response.data["message"])


class NothingSurvivesAFailure(RunTestCase):
    def test_a_failure_on_the_last_student_undoes_the_whole_batch(self):
        """Two students moved, the third throws: none of it may survive."""
        from school.promotion import PromotionRun

        original = PromotionRun.repoint
        calls = {"n": 0}

        def explode_on_the_third(*args, **kwargs):
            calls["n"] += 1

            if calls["n"] == 3:
                raise RuntimeError("the database went away")

            return original(*args, **kwargs)

        # Called as the service rather than through the client, so the
        # failure is the one being tested rather than whatever the test
        # client does with an unhandled error.
        with mock.patch.object(PromotionRun, "repoint", staticmethod(explode_on_the_third)):
            with self.assertRaises(RuntimeError):
                PromotionRun.run(self.section, self.body(), self.admin)

        self.assertEqual(0, PromotionBatch.objects.count(), "no batch row")
        self.assertEqual(
            0,
            StudentEnrollment.objects.filter(academic_year_id=self.next_year.id).count(),
            "no enrollment in the new year",
        )
        self.assertEqual(
            3,
            StudentEnrollment.objects.filter(
                academic_year_id=self.this_year.id, status=EnrollmentStatus.STUDYING
            ).count(),
            "and every year still open",
        )

        for student in (self.aarav, self.bina, self.chetan):
            self.assertEqual(self.section.id, self.reloaded(student).class_section_id)


class WhatTheRunLeavesBehind(RunTestCase):
    def test_the_history_lists_the_batch_newest_first(self):
        self.promote(outcomes=[{"student_id": self.aarav.id, "outcome": "promote"}])

        response = self.client.get(URL)

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(1, len(response.data["data"]))
        self.assertEqual("Grade 8 A", response.data["data"][0]["from_class_section_name"])

    def test_the_history_can_be_asked_about_one_year_from_either_end(self):
        self.promote(outcomes=[{"student_id": self.aarav.id, "outcome": "promote"}])

        from_side = self.client.get(URL, {"academic_year_id": self.this_year.id})
        to_side = self.client.get(URL, {"academic_year_id": self.next_year.id})
        elsewhere = self.client.get(
            URL, {"academic_year_id": factories.AcademicYearFactory(school=self.school, is_current=False).id}
        )

        self.assertEqual(1, len(from_side.data["data"]))
        self.assertEqual(1, len(to_side.data["data"]))
        self.assertEqual(0, len(elsewhere.data["data"]))

    def test_one_batch_reads_back_student_by_student(self):
        self.promote(
            outcomes=[
                {"student_id": self.aarav.id, "outcome": "promote"},
                {"student_id": self.bina.id, "outcome": "retain"},
                {"student_id": self.chetan.id, "outcome": "graduate"},
            ]
        )
        batch = PromotionBatch.objects.get()

        response = self.client.get(f"{URL}/{batch.id}")
        rows = {row["name"]: row for row in response.data["students"]}

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(3, len(rows))
        self.assertEqual("promoted", rows[self.aarav.name]["outcome"])
        self.assertEqual("Grade 9", rows[self.aarav.name]["to_class_name"])
        self.assertEqual("retained", rows[self.bina.name]["outcome"])
        self.assertEqual("Grade 8", rows[self.bina.name]["to_class_name"], "repeating means the same class")
        self.assertEqual("graduated", rows[self.chetan.name]["outcome"])
        self.assertIsNone(rows[self.chetan.name]["to_class_name"], "they finished")

    def test_the_audit_names_the_counts_and_the_students(self):
        self.promote(
            outcomes=[
                {"student_id": self.aarav.id, "outcome": "promote"},
                {"student_id": self.bina.id, "outcome": "graduate"},
            ]
        )

        entry = AuditLog.objects.get(action="promotion.completed")

        self.assertEqual("academic", entry.module)
        self.assertEqual(self.school.id, entry.school_id)
        self.assertEqual(self.admin.id, entry.user_id)
        self.assertEqual(1, entry.new_values["counts"]["promote"])
        self.assertEqual([self.aarav.id], entry.new_values["students"]["promote"])
        self.assertEqual([self.bina.id], entry.new_values["students"]["graduate"])
        self.assertEqual("Grade 8 A", entry.new_values["from"])

    def test_one_entry_for_the_whole_run_rather_than_one_per_child(self):
        self.promote()

        self.assertEqual(1, AuditLog.objects.filter(action="promotion.completed").count())


class WhoMayRunIt(RunTestCase):
    def test_a_teacher_may_not(self):
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        self.assertEqual(403, self.promote(client=teacher).status_code)
        self.assertEqual(0, PromotionBatch.objects.count())

    def test_an_hod_may_not(self):
        hod = self.as_user(factories.UserFactory(school=self.school, role=UserRole.HOD))

        self.assertEqual(403, self.promote(client=hod).status_code)

    def test_a_super_admin_reads_the_history_and_runs_nothing(self):
        self.promote()
        root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        self.assertEqual(403, self.promote(client=root).status_code, "the platform's owner is not a member of staff")
        self.assertEqual(200, root.get(URL).status_code)

    def test_another_school_reaches_neither_the_run_nor_the_batch(self):
        self.promote(outcomes=[{"student_id": self.aarav.id, "outcome": "promote"}])
        batch = PromotionBatch.objects.get()
        outsider = self.as_user(factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN))

        self.assertEqual(403, self.promote(client=outsider).status_code)
        self.assertEqual(403, outsider.get(f"{URL}/{batch.id}").status_code)
        self.assertEqual(0, len(outsider.get(URL).data["data"]))

    def test_a_teacher_may_still_read_what_was_done(self):
        # Academics is readable to a teacher, and "what happened to my class
        # last year" is ordinary academic information.
        self.promote(outcomes=[{"student_id": self.aarav.id, "outcome": "promote"}])
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        self.assertEqual(200, teacher.get(URL).status_code)

    def test_a_group_admin_promotes_a_branch(self):
        branch_admin = factories.UserFactory(school=self.school, role=UserRole.GROUP_ADMIN)

        self.assertEqual(201, self.promote(client=self.as_user(branch_admin)).status_code)
