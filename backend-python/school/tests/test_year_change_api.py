"""A school living through a change of year (docs/promotion.md, slice 10).

Every other test in this suite works inside one academic year. This one
promotes a class and then uses the product: takes a register, reads a
timetable, builds next year's timetable, runs a report for last year, opens
last year's published result, imports a student, and tries the things a
graduated child must no longer be part of.

It exists because this is where an integration bug actually appears, and
finding it here is cheaper than finding it in a school. Every check below
failed at least once while this slice was being written.
"""

import datetime as dt
from decimal import Decimal

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import factories, tokens
from school.clock import SchoolClock
from school.enums import (
    AssessmentStatus,
    AttendanceStatus,
    EnrollmentStatus,
    StudentStatus,
    UserRole,
)
from school.models import AcademicYear, Assessment, AssessmentMark, Attendance, Student, StudentEnrollment

# A Wednesday inside the newer year, and in the past: a register may not be
# taken for a day that has not happened.
A_SCHOOL_DAY = dt.date(2026, 9, 16)

STUDENT_HEADINGS = "admission_number,first_name,last_name,class,section,roll_number,guardian_name,guardian_mobile,address"


class YearChangeTestCase(TestCase):
    """Two years, one class in each, and a class that has been promoted."""

    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(timezone="UTC")
        # The years straddle today, so "the new year" is the one being lived
        # and a register in it can be dated without inventing the future.
        self.last_year = factories.AcademicYearFactory(
            school=self.school,
            name="2025-26",
            start_date=dt.date(2025, 4, 1),
            end_date=dt.date(2026, 3, 31),
            is_current=True,
        )
        self.this_year = factories.AcademicYearFactory(
            school=self.school,
            name="2026-27",
            start_date=dt.date(2026, 4, 1),
            end_date=dt.date(2027, 3, 31),
            is_current=False,
        )

        self.grade_8 = factories.SchoolClassFactory(
            academic_year=self.last_year, school=self.school, name="Grade 8", level=8
        )
        self.old_section = factories.ClassSectionFactory(school_class=self.grade_8, name="A")

        self.new_grade_8 = factories.SchoolClassFactory(
            academic_year=self.this_year, school=self.school, name="Grade 8", level=8
        )
        self.new_grade_8_a = factories.ClassSectionFactory(school_class=self.new_grade_8, name="A")
        self.grade_9 = factories.SchoolClassFactory(
            academic_year=self.this_year, school=self.school, name="Grade 9", level=9
        )
        self.new_section = factories.ClassSectionFactory(school_class=self.grade_9, name="A")

        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.client = self.as_user(self.admin)

        self.department = factories.DepartmentFactory(school=self.school, name="Mathematics")
        self.subject = factories.SubjectFactory(
            department=self.department, school=self.school, name="Mathematics", min_class_level=1, max_class_level=12
        )
        self.period = factories.PeriodFactory(school=self.school, period_number=1)

        self.moved = self.student("Aarav", "ADM-1")
        self.finished = self.student("Bina", "ADM-2")

        for student in (self.moved, self.finished):
            factories.StudentEnrollmentFactory(
                student=student,
                school=self.school,
                academic_year=self.last_year,
                school_class=self.grade_8,
                class_section=self.old_section,
                status=EnrollmentStatus.STUDYING,
            )

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def student(self, first_name: str, admission_number: str):
        return factories.StudentFactory(
            school=self.school,
            class_section=self.old_section,
            first_name=first_name,
            admission_number=admission_number,
            guardian_mobile="+91 90000 00001",
        )

    def promote(self):
        """One up, one finished - the state every test below starts from."""
        response = self.client.post(
            "/api/v1/promotions",
            {
                "class_section_id": self.old_section.id,
                "to_academic_year_id": self.this_year.id,
                "outcomes": [
                    {"student_id": self.moved.id, "outcome": "promote"},
                    {"student_id": self.finished.id, "outcome": "graduate"},
                ],
            },
            format="json",
        )
        assert response.status_code == 201, response.data

        return response.data

    def turn_the_year(self):
        """What a school does next: the new year becomes the current one."""
        AcademicYear.objects.filter(school_id=self.school.id).update(is_current=False)
        AcademicYear.objects.filter(pk=self.this_year.id).update(is_current=True)
        cache.clear()

    def reloaded(self, student) -> Student:
        return Student.objects.get(pk=student.id)


class TakingARegisterInTheNewYear(YearChangeTestCase):
    def test_the_new_class_holds_the_students_who_moved_up(self):
        self.promote()
        self.turn_the_year()

        response = self.client.get(
            "/api/v1/attendance/register", {"class_section_id": self.new_section.id, "date": A_SCHOOL_DAY.isoformat()}
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual([self.moved.id], [row["student_id"] for row in response.data["students"]])

    def test_last_year_s_class_is_empty_rather_than_wrong(self):
        self.promote()
        self.turn_the_year()

        response = self.client.get(
            "/api/v1/attendance/register", {"class_section_id": self.old_section.id, "date": A_SCHOOL_DAY.isoformat()}
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual([], response.data["students"], "they are not in that class any more")

    def test_a_graduated_student_cannot_be_marked_present(self):
        self.promote()
        self.turn_the_year()

        response = self.client.post(
            "/api/v1/attendance",
            {
                "class_section_id": self.new_section.id,
                "attendance_date": A_SCHOOL_DAY.isoformat(),
                "records": [{"student_id": self.finished.id, "status": AttendanceStatus.PRESENT}],
            },
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("records", response.data["details"]["errors"])


class TheTimetableAcrossTheChange(YearChangeTestCase):
    def entry(self, section, day="monday"):
        return self.client.post(
            "/api/v1/timetable",
            {
                "class_section_id": section.id,
                "period_id": self.period.id,
                "day_of_week": day,
                "subject_id": self.subject.id,
                "teacher_id": self.teacher.id,
            },
            format="json",
        )

    def test_next_year_s_grid_can_be_built_over_last_year_s(self):
        self.assertEqual(201, self.entry(self.old_section).status_code)
        self.promote()
        self.turn_the_year()

        # The same teacher, the same weekday, the same period - in the new
        # year. A clash check that spanned years would refuse this, and a
        # school could never build its second timetable.
        response = self.entry(self.new_section)

        self.assertEqual(201, response.status_code, response.data)

    def test_a_clash_inside_one_year_is_still_refused(self):
        self.entry(self.new_section)
        other = factories.ClassSectionFactory(school_class=self.grade_9, name="B")

        response = self.entry(other)

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("TEACHER_SCHEDULE_CONFLICT", response.data["code"])

    def test_a_teacher_reads_this_year_s_timetable_only(self):
        self.entry(self.old_section)
        self.promote()
        self.turn_the_year()
        self.entry(self.new_section)

        response = self.client.get("/api/v1/timetable", {"teacher_id": self.teacher.id})

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(
            [self.new_section.id],
            [row["class_section_id"] for row in response.data],
            "last year's grid is not a second timetable to read",
        )

    def test_the_dashboard_counts_this_year_s_periods_once(self):
        # Both years hold the same slot on whatever weekday today is, so a
        # count that spanned years would read two.
        today = SchoolClock.for_school(self.school.id).now().strftime("%A").lower()
        self.entry(self.old_section, day=today)
        self.promote()
        self.turn_the_year()
        self.entry(self.new_section, day=today)

        response = self.as_user(self.teacher).get("/api/v1/dashboard")
        cards = {card["key"]: card["value"] for card in response.data["cards"]}

        self.assertEqual("1", cards["periods"], f"one grid, not two: {cards!r}")

    def test_the_pending_teaching_reports_count_this_year_only(self):
        today = SchoolClock.for_school(self.school.id).now()
        weekday = today.strftime("%A").lower()
        self.entry(self.old_section, day=weekday)
        self.promote()
        self.turn_the_year()
        self.entry(self.new_section, day=weekday)

        response = self.client.get("/api/v1/teaching-reports/summary", {"date": today.date().isoformat()})

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(1, response.data["scheduled"], "last year's grid is not work still owed")

    def test_the_coverage_report_counts_this_year_s_periods(self):
        today = SchoolClock.for_school(self.school.id).now().date()
        weekday = today.strftime("%A").lower()
        self.entry(self.old_section, day=weekday)
        self.promote()
        self.turn_the_year()
        self.entry(self.new_section, day=weekday)

        response = self.client.get(
            "/api/v1/reports/teaching-coverage", {"from": today.isoformat(), "to": today.isoformat()}
        )

        self.assertEqual(200, response.status_code, response.data)
        scheduled = sum(row["periods_scheduled"] for row in response.data["rows"])
        self.assertEqual(1, scheduled, "a second timetable would double what the school was expected to teach")


class LastYearStillReadsAsLastYear(YearChangeTestCase):
    def mark_the_register(self, date: dt.date):
        Attendance.objects.create(
            school=self.school,
            academic_year=self.last_year,
            class_section=self.old_section,
            student=self.moved,
            attendance_date=date,
            status=AttendanceStatus.PRESENT,
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )

    def report(self, **params):
        query = {"from": "2025-09-01", "to": "2025-09-30"}
        query.update(params)

        return self.client.get("/api/v1/reports/student-attendance", query)

    def test_the_report_names_the_class_they_were_in_then(self):
        self.mark_the_register(dt.date(2025, 9, 15))
        self.promote()
        self.turn_the_year()

        response = self.report()
        row = [row for row in response.data["rows"] if row["student_id"] == self.moved.id][0]

        self.assertEqual("Grade 8 A", row["class_section"], "not the class they are in now")
        self.assertEqual(1, row["present"])

    def test_a_student_who_has_since_graduated_is_still_in_it(self):
        Attendance.objects.create(
            school=self.school,
            academic_year=self.last_year,
            class_section=self.old_section,
            student=self.finished,
            attendance_date=dt.date(2025, 9, 15),
            status=AttendanceStatus.PRESENT,
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )
        self.promote()
        self.turn_the_year()

        response = self.report()

        self.assertIn(
            self.finished.id,
            [row["student_id"] for row in response.data["rows"]],
            "they were there all year; dropping them would raise everybody else's percentage",
        )

    def test_a_report_can_still_be_asked_about_last_year_s_class(self):
        self.mark_the_register(dt.date(2025, 9, 15))
        self.promote()
        self.turn_the_year()

        response = self.report(class_section_id=self.old_section.id)

        self.assertEqual([self.moved.id], [row["student_id"] for row in response.data["rows"]])


class LastYearSMarksAreUntouched(YearChangeTestCase):
    def published_test(self) -> Assessment:
        term = factories.AcademicTermFactory(
            academic_year=self.last_year,
            school=self.school,
            name="Term 3",
            sequence_number=3,
            start_date=dt.date(2025, 4, 1),
            end_date=dt.date(2026, 3, 31),
        )
        assessment = factories.AssessmentFactory(
            school=self.school,
            academic_year=self.last_year,
            academic_term=term,
            class_section=self.old_section,
            subject=self.subject,
            title="Final exam",
            max_marks=Decimal("20"),
            status=AssessmentStatus.PUBLISHED,
            published_at=timezone.now(),
            created_by=self.admin,
        )

        for student, marks in ((self.moved, "18"), (self.finished, "15")):
            AssessmentMark.objects.create(
                assessment=assessment,
                student=student,
                school=self.school,
                marks_obtained=Decimal(marks),
                is_absent=False,
                entered_by=self.admin,
                created_at=timezone.now(),
                updated_at=timezone.now(),
            )

        return assessment

    def test_a_published_result_still_lists_the_class_that_sat_it(self):
        assessment = self.published_test()
        self.promote()
        self.turn_the_year()

        response = self.client.get(f"/api/v1/assessments/{assessment.id}/marks")

        self.assertEqual(200, response.status_code, response.data)
        marked = {row["student_id"]: row["marks_obtained"] for row in response.data["entries"]}
        self.assertEqual({self.moved.id: "18.00", self.finished.id: "15.00"}, marked)

    def test_the_result_is_filed_under_the_year_it_was_sat_in(self):
        assessment = self.published_test()
        self.promote()
        self.turn_the_year()

        response = self.client.get(f"/api/v1/assessments/{assessment.id}")

        self.assertEqual(self.last_year.id, response.data["academic_year_id"])
        self.assertEqual("Grade 8 A", response.data["class_section_name"])


class WhatAGraduatedStudentMayNoLongerDo(YearChangeTestCase):
    def test_they_take_no_bus_seat(self):
        self.promote()
        vehicle = factories.VehicleFactory(school=self.school, capacity=40)
        route = factories.TransportRouteFactory(school=self.school, vehicle=vehicle)
        stop = factories.TransportStopFactory(route=route, school=self.school)

        response = self.client.put(
            f"/api/v1/students/{self.finished.id}/transport",
            {"route_id": route.id, "transport_stop_id": stop.id},
            format="json",
        )

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("STUDENT_HAS_FINISHED", response.data["code"])

    def test_they_are_not_promoted_a_second_time(self):
        self.promote()
        # Put them back in a class by hand, the way a mistaken edit might:
        # the roster still refuses to offer them a further year.
        Student.objects.filter(pk=self.finished.id).update(class_section_id=self.new_section.id)

        response = self.client.get(
            "/api/v1/promotions/preview",
            {"class_section_id": self.new_section.id, "to_academic_year_id": self.last_year.id},
        )

        self.assertNotIn(self.finished.id, [row["student_id"] for row in response.data["students"]])

    def test_they_keep_every_record_they_earned(self):
        self.promote()

        history = self.client.get(f"/api/v1/students/{self.finished.id}/enrollments")

        self.assertEqual(200, response_status := history.status_code, history.data)
        self.assertEqual(200, response_status)
        self.assertEqual([EnrollmentStatus.GRADUATED], [row["status"] for row in history.data])

    def test_the_students_list_can_be_asked_for_them(self):
        self.promote()

        response = self.client.get("/api/v1/students", {"status": StudentStatus.GRADUATED})

        self.assertEqual([self.finished.id], [row["id"] for row in response.data["data"]])


class TalkingToAClassThatHasMovedOn(YearChangeTestCase):
    def test_an_announcement_to_last_year_s_section_is_refused_rather_than_sent_to_nobody(self):
        self.promote()
        self.turn_the_year()

        response = self.client.post(
            "/api/v1/announcements",
            {
                "title": "Sports day",
                "body": "Sports day is on Friday.",
                "audience_type": "class_section",
                "audience_id": self.old_section.id,
                "channels": "sms_in_app",
            },
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("UNREACHABLE_AUDIENCE", response.data["code"])

    def test_the_same_announcement_reaches_this_year_s_class(self):
        self.promote()
        self.turn_the_year()

        response = self.client.post(
            "/api/v1/announcements",
            {
                "title": "Sports day",
                "body": "Sports day is on Friday.",
                "audience_type": "class_section",
                "audience_id": self.new_section.id,
                "channels": "sms_in_app",
            },
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(1, response.data["recipients_count"])


class AdmittingIntoTheNewYear(YearChangeTestCase):
    def test_a_bulk_import_lands_in_the_current_year_s_class(self):
        self.promote()
        self.turn_the_year()

        body = "\n".join([STUDENT_HEADINGS, "ADM-9,Chetan,Rao,Grade 8,A,3,Meera Rao,,"]) + "\n"
        response = self.client.post(
            "/api/v1/imports/students",
            {"file": SimpleUploadedFile("students.csv", body.encode("utf-8"), content_type="text/csv")},
            format="multipart",
        )

        self.assertEqual(201, response.status_code, response.data)
        admitted = Student.objects.get(admission_number="ADM-9")
        self.assertEqual(
            self.new_grade_8_a.id,
            admitted.class_section_id,
            "'Grade 8 A' means this year's, not the one that just ended",
        )

    def test_the_admission_records_the_new_year(self):
        self.promote()
        self.turn_the_year()

        response = self.client.post(
            "/api/v1/students",
            {
                "class_section_id": self.new_section.id,
                "admission_number": "ADM-10",
                "first_name": "Deepa",
                "last_name": "Rao",
                "guardian_name": "Meera Rao",
            },
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        enrollment = StudentEnrollment.objects.get(student_id=response.data["id"])
        self.assertEqual(self.this_year.id, enrollment.academic_year_id)
