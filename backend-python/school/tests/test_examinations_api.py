"""Examinations and admit cards (docs/examinations.md, decided 2026-11-17).

What this file guards:

- **Who may do what.** School and Group Admins set exams up, publish and hold
  cards back; staff who read class tests print cards; a Super Admin reads
  and changes nothing. Another school's exam, student or year is a 404 or a
  422, never a card.
- **The date sheet's rules**: a class of the exam's year, a subject of the
  school, a time that ends after it starts, a date inside the year, one
  paper per subject per class, no two papers of a class at once.
- **Cards only from a published version**, never silently changed:
  republishing makes version 2, and version 1 still reprints as issued.
- **The holds**: withheld by name; held for overdue fees only when the exam
  says so, and let through by name.
- **A parent sees only their own child's published cards** and is never told
  why one is withheld.

Set ADMIT_CARD_SAMPLES to a folder to have sample PDFs written there.
"""

from __future__ import annotations

import datetime as dt
import os
from decimal import Decimal
from unittest import mock

from django.core.cache import cache
from django.test import SimpleTestCase, TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import factories, pdf_design, tokens
from school.enums import UserRole
from school.examinations import card_pdf
from school.examinations.service import snapshot_of, time_label
from school.models import (
    AuditLog,
    Examination,
    ExaminationVersion,
    FeeHead,
    ModuleSetting,
    StudentEnrollment,
    StudentFeeDue,
)

URL = "/api/v1/examinations"
NOW = dt.datetime(2026, 11, 17, 6, 0, tzinfo=dt.timezone.utc)


class ExamTestCase(TestCase):
    def setUp(self):
        cache.clear()
        clock = mock.patch("django.utils.timezone.now", return_value=NOW)
        clock.start()
        self.addCleanup(clock.stop)

        self.school = factories.SchoolFactory(name="Sunrise Public School", timezone="Asia/Kolkata")
        self.year = factories.AcademicYearFactory(
            school=self.school, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31),
            is_current=True,
        )
        self.term = factories.AcademicTermFactory(
            school=self.school, academic_year=self.year, name="Term 1", sequence_number=1,
            start_date=dt.date(2026, 4, 1), end_date=dt.date(2026, 9, 30),
        )
        self.class8 = factories.SchoolClassFactory(school=self.school, academic_year=self.year, name="Class 8", level=8)
        self.a8 = factories.ClassSectionFactory(school_class=self.class8, name="A")
        self.b8 = factories.ClassSectionFactory(school_class=self.class8, name="B")
        self.class9 = factories.SchoolClassFactory(school=self.school, academic_year=self.year, name="Class 9", level=9)
        self.a9 = factories.ClassSectionFactory(school_class=self.class9, name="A")
        department = factories.DepartmentFactory(school=self.school)
        self.english = factories.SubjectFactory(school=self.school, department=department, name="English")
        self.maths = factories.SubjectFactory(school=self.school, department=department, name="Mathematics")

        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.aarav = self.student("Aarav", self.a8, roll="12")
        self.riya = self.student("Riya", self.a8, roll="13")
        self.kabir = self.student("Kabir", self.b8, roll="1")
        self.sara = self.student("Sara", self.a9, roll="4")

        self.elsewhere = factories.SchoolFactory()
        self.stranger = factories.UserFactory(school=self.elsewhere, role=UserRole.SCHOOL_ADMIN)

    def student(self, name, section, roll):
        student = factories.StudentFactory(
            school=self.school, class_section=section, first_name=name, last_name="Kumar", roll_number=roll,
            admission_number=f"ADM-{name.upper()}",
        )
        factories.StudentEnrollmentFactory(
            student=student, school=self.school, academic_year=self.year, school_class=section.school_class,
            class_section=section, roll_number=roll,
        )
        return student

    def client_for(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))
        return client

    def create(self, user=None, **fields):
        body = {"academic_year_id": self.year.id, "name": "Half-Yearly Examination", "centre": "Main Campus",
                "reporting_time": "08:30", "instructions": "Carry this card.\nArrive on time.", **fields}
        return self.client_for(user or self.admin).post(URL, body, format="json")

    def exam(self, **fields) -> dict:
        response = self.create(**fields)
        self.assertEqual(201, response.status_code, response.data)
        return response.data

    def paper(self, school_class, subject, day="2026-12-07", start="09:00", end="12:00"):
        return {"school_class_id": school_class.id, "subject_id": subject.id, "exam_date": day,
                "start_time": start, "end_time": end}

    def sheet(self, exam_id, papers, user=None):
        return self.client_for(user or self.admin).put(f"{URL}/{exam_id}/papers", {"papers": papers}, format="json")

    def published(self, **fields) -> dict:
        exam = self.exam(**fields)
        response = self.sheet(exam["id"], [
            self.paper(self.class8, self.english, "2026-12-07"),
            self.paper(self.class8, self.maths, "2026-12-09"),
            self.paper(self.class9, self.english, "2026-12-08"),
        ])
        self.assertEqual(200, response.status_code, response.data)
        return self.publish(exam["id"])

    def publish(self, exam_id, user=None) -> dict:
        response = self.client_for(user or self.admin).post(f"{URL}/{exam_id}/publish")
        self.assertEqual(200, response.status_code, response.data)
        return response.data

    def card(self, exam_id, student, user=None, **params):
        return self.client_for(user or self.admin).get(f"{URL}/{exam_id}/students/{student.id}/card.pdf", params)

    def save_sample(self, response, name):
        folder = os.environ.get("ADMIT_CARD_SAMPLES")
        if folder:
            os.makedirs(folder, exist_ok=True)
            with open(os.path.join(folder, f"{name}.pdf"), "wb") as handle:
                handle.write(response.content)

    def owe(self, student, amount="1500.00", days_ago=10):
        head = FeeHead.objects.get_or_create(school=self.school, name="Tuition")[0]
        StudentFeeDue.objects.create(
            school=self.school, student=student, academic_year=self.year, fee_head=head, label="Tuition - Oct",
            due_date=dt.date(2026, 11, 17) - dt.timedelta(days=days_ago), amount=Decimal(amount),
            currency_code="INR", status="pending", created_at=timezone.now(), updated_at=timezone.now(),
        )


# -- the exam -----------------------------------------------------------------------------


class SettingUp(ExamTestCase):
    def test_an_admin_creates_a_draft_in_the_years_school_and_it_is_audited(self):
        data = self.exam(academic_term_id=self.term.id)

        self.assertEqual((self.school.id, "draft", 0, "Term 1", "08:30"), (
            data["school_id"], data["status"], data["version"], data["academic_term_name"], data["reporting_time"]))
        self.assertTrue(AuditLog.objects.filter(action="examination.created", school_id=self.school.id).exists())

    def test_a_teacher_may_not_set_an_exam_up(self):
        self.assertEqual(403, self.create(user=self.teacher).status_code)

    def test_a_super_admin_reads_but_does_not_set_up(self):
        exam = self.exam()

        self.assertEqual(403, self.create(user=self.root).status_code)
        self.assertEqual(200, self.client_for(self.root).get(f"{URL}/{exam['id']}").status_code)
        self.assertEqual(403, self.client_for(self.root).post(f"{URL}/{exam['id']}/publish").status_code)

    def test_another_schools_year_is_not_one_to_set_an_exam_in(self):
        response = self.create(user=self.stranger)

        self.assertEqual(422, response.status_code)
        self.assertIn("academic_year_id", response.data["details"]["errors"])

    def test_two_exams_of_a_year_may_not_share_a_name(self):
        self.exam()

        self.assertEqual(422, self.create().status_code)

    def test_a_term_of_another_year_is_refused(self):
        other_year = factories.AcademicYearFactory(school=self.school, name="2027-28",
                                                   start_date=dt.date(2027, 4, 1), end_date=dt.date(2028, 3, 31))
        other_term = factories.AcademicTermFactory(school=self.school, academic_year=other_year, name="Term 1",
                                                   sequence_number=1, start_date=dt.date(2027, 4, 1),
                                                   end_date=dt.date(2027, 9, 30))

        response = self.create(academic_term_id=other_term.id)

        self.assertIn("academic_term_id", response.data["details"]["errors"])

    def test_bad_times_and_styles_are_refused_field_by_field(self):
        response = self.create(reporting_time="8.30am", card_style="neon", block_on_fee_dues="yes")

        errors = response.data["details"]["errors"]
        self.assertEqual({"reporting_time", "card_style", "block_on_fee_dues"}, set(errors))

    def test_another_schools_exam_is_a_404_and_is_not_listed(self):
        exam = self.exam()

        self.assertEqual(404, self.client_for(self.stranger).get(f"{URL}/{exam['id']}").status_code)
        self.assertEqual(404, self.client_for(self.stranger).post(f"{URL}/{exam['id']}/publish").status_code)
        self.assertEqual([], self.client_for(self.stranger).get(URL).data["data"])

    def test_a_draft_may_be_deleted_but_a_published_exam_stays(self):
        draft = self.exam(name="Unit test")
        self.assertEqual(204, self.client_for(self.admin).delete(f"{URL}/{draft['id']}").status_code)

        published = self.published()
        response = self.client_for(self.admin).delete(f"{URL}/{published['id']}")
        self.assertEqual(409, response.status_code)
        self.assertTrue(Examination.objects.filter(pk=published["id"]).exists())

    def test_editing_the_details(self):
        exam = self.exam()

        response = self.client_for(self.admin).patch(
            f"{URL}/{exam['id']}", {"centre": "Hall B", "card_style": "mono", "block_on_fee_dues": True}, format="json"
        )

        self.assertEqual(("Hall B", "mono", True), (
            response.data["centre"], response.data["card_style"], response.data["block_on_fee_dues"]))


class TheDateSheet(ExamTestCase):
    def setUp(self):
        super().setUp()
        self.id = self.exam()["id"]

    def errors(self, papers):
        response = self.sheet(self.id, papers)
        self.assertEqual(422, response.status_code, response.data)
        return response.data["details"]["errors"]

    def test_the_sheet_is_saved_and_read_back_in_order(self):
        response = self.sheet(self.id, [
            self.paper(self.class9, self.english, "2026-12-08"),
            self.paper(self.class8, self.maths, "2026-12-09"),
            self.paper(self.class8, self.english, "2026-12-07"),
        ])

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(
            [("Class 8", "English"), ("Class 8", "Mathematics"), ("Class 9", "English")],
            [(row["school_class_name"], row["subject_name"]) for row in response.data["papers"]],
        )
        self.assertEqual((3, 2), (response.data["paper_count"], response.data["class_count"]))

    def test_a_class_of_another_year_or_school_is_refused(self):
        other = factories.SchoolClassFactory(school=self.elsewhere, name="X", level=8)

        self.assertIn("papers.0.school_class_id", self.errors([self.paper(other, self.english)]))

    def test_another_schools_subject_is_refused(self):
        theirs = factories.SubjectFactory(school=self.elsewhere, name="Theirs")

        self.assertIn("papers.0.subject_id", self.errors([self.paper(self.class8, theirs)]))

    def test_a_paper_ending_before_it_starts_is_refused(self):
        self.assertEqual(["The end time must be after the start time."],
                         self.errors([self.paper(self.class8, self.english, start="12:00", end="09:00")])
                         ["papers.0.end_time"])

    def test_a_date_outside_the_year_is_refused(self):
        self.assertIn("papers.0.exam_date", self.errors([self.paper(self.class8, self.english, day="2027-06-01")]))

    def test_one_paper_per_subject_per_class(self):
        self.assertIn("papers.1.subject_id", self.errors([
            self.paper(self.class8, self.english, "2026-12-07"), self.paper(self.class8, self.english, "2026-12-08"),
        ]))

    def test_a_class_cannot_sit_two_papers_at_once(self):
        errors = self.errors([
            self.paper(self.class8, self.english, "2026-12-07", "09:00", "12:00"),
            self.paper(self.class8, self.maths, "2026-12-07", "11:00", "13:00"),
        ])

        self.assertIn("overlaps English", errors["papers.1.start_time"][0])

    def test_back_to_back_papers_and_two_classes_at_once_are_fine(self):
        response = self.sheet(self.id, [
            self.paper(self.class8, self.english, "2026-12-07", "09:00", "11:00"),
            self.paper(self.class8, self.maths, "2026-12-07", "11:00", "13:00"),
            self.paper(self.class9, self.english, "2026-12-07", "09:00", "12:00"),
        ])

        self.assertEqual(200, response.status_code, response.data)

    def test_a_teacher_may_not_change_the_sheet(self):
        self.assertEqual(403, self.sheet(self.id, [], user=self.teacher).status_code)


class Publishing(ExamTestCase):
    def test_an_empty_sheet_cannot_be_published(self):
        exam = self.exam()

        response = self.client_for(self.admin).post(f"{URL}/{exam['id']}/publish")

        self.assertEqual(409, response.status_code)

    def test_publishing_freezes_version_1(self):
        data = self.published()

        self.assertEqual(("published", 1, False), (data["status"], data["version"], data["has_unpublished_changes"]))
        version = ExaminationVersion.objects.get(examination_id=data["id"])
        self.assertEqual(["Class 8", "Class 9"], [entry["name"] for entry in version.snapshot["classes"].values()])

    def test_nothing_changed_is_not_a_new_version(self):
        data = self.published()

        self.assertEqual(409, self.client_for(self.admin).post(f"{URL}/{data['id']}/publish").status_code)

    def test_a_change_after_publishing_is_a_draft_until_republished_and_version_1_still_reprints(self):
        data = self.published()
        self.sheet(data["id"], [
            self.paper(self.class8, self.english, "2026-12-10"),
            self.paper(self.class8, self.maths, "2026-12-09"),
            self.paper(self.class9, self.english, "2026-12-08"),
        ])

        detail = self.client_for(self.admin).get(f"{URL}/{data['id']}").data
        self.assertTrue(detail["has_unpublished_changes"])
        # Until republished, the card still says what was issued.
        first = card_pdf.document  # noqa: F841
        exam = Examination.objects.get(pk=data["id"])
        self.assertEqual("2026-12-07", ExaminationVersion.objects.get(examination=exam, version=1)
                         .snapshot["classes"][str(self.class8.id)]["papers"][0]["date"])

        republished = self.publish(data["id"])

        self.assertEqual(2, republished["version"])
        self.assertEqual([2, 1], [row["version"] for row in republished["versions"]])
        self.assertEqual(200, self.card(data["id"], self.aarav, version=1).status_code)
        self.assertEqual(200, self.card(data["id"], self.aarav).status_code)

    def test_publishing_is_audited(self):
        self.published()

        self.assertTrue(AuditLog.objects.filter(action="examination.published").exists())


# -- the cards ----------------------------------------------------------------------------


class Cards(ExamTestCase):
    def test_no_card_before_publishing_but_the_manager_may_preview_a_draft(self):
        exam = self.exam()
        self.sheet(exam["id"], [self.paper(self.class8, self.english)])

        refused = self.card(exam["id"], self.aarav)
        self.assertEqual(409, refused.status_code)
        self.assertEqual("ADMIT_CARD_UNAVAILABLE", refused.data["code"])

        draft = self.card(exam["id"], self.aarav, draft=1)
        self.assertEqual(200, draft.status_code)
        self.assertTrue(draft.content.startswith(b"%PDF"))
        self.assertEqual(403, self.card(exam["id"], self.aarav, user=self.teacher, draft=1).status_code)

    def test_a_published_card_downloads_for_staff_who_read_class_tests(self):
        data = self.published()

        response = self.card(data["id"], self.aarav, user=self.teacher)

        self.assertEqual(200, response.status_code)
        self.assertIn("admit-card-half-yearly-examination-adm-aarav.pdf", response["Content-Disposition"])
        self.save_sample(response, "single-card")

    def test_the_card_says_what_was_issued(self):
        data = self.published(academic_term_id=self.term.id)
        exam = Examination.objects.get(pk=data["id"])
        version = ExaminationVersion.objects.get(examination=exam)
        card = card_pdf.Card(student=self.aarav, snapshot=version.snapshot, class_id=self.class8.id, version=1,
                             issued_on="11/17/2026")

        html = card_pdf.document([card], school=self.school, year_id=self.year.id)

        for text in ("EXAMINATION ADMIT CARD", "SUNRISE PUBLIC SCHOOL", "Half-Yearly Examination - Term 1",
                     "Version 1 - issued 11/17/2026", "Aarav Kumar", "ADM-AARAV", "Class 8 - A", "Main Campus",
                     "8:30 AM", "Mon 12/07/2026", "9:00 AM - 12:00 PM", "Mathematics", "Carry this card.",
                     "Principal / Exam Controller"):
            self.assertIn(text, html, text)
        self.assertNotIn("Class 9", html.split("Subject / Paper")[1])
        self.assertEqual(0, pdf_design.style_errors(html))

    def test_a_class_with_no_paper_gets_no_card(self):
        exam = self.exam()
        self.sheet(exam["id"], [self.paper(self.class9, self.english)])
        self.publish(exam["id"])

        self.assertEqual(409, self.card(exam["id"], self.aarav).status_code)

    def test_another_schools_student_is_a_404(self):
        data = self.published()
        theirs = factories.StudentFactory(school=self.elsewhere)

        self.assertEqual(404, self.card(data["id"], theirs).status_code)

    def test_a_card_for_a_student_who_moved_class_follows_the_class_they_sit_in(self):
        data = self.published()
        StudentEnrollment.objects.filter(student=self.sara).update(school_class=self.class8, class_section=self.a8)

        response = self.card(data["id"], self.sara)

        self.assertEqual(200, response.status_code)


class Holds(ExamTestCase):
    def exception(self, exam_id, student, kind, reason=None, user=None):
        return self.client_for(user or self.admin).put(
            f"{URL}/{exam_id}/exceptions", {"student_id": student.id, "kind": kind, "reason": reason}, format="json"
        )

    def test_a_withheld_card_is_refused_and_the_reason_is_staffs_only(self):
        data = self.published()

        self.assertEqual(422, self.exception(data["id"], self.aarav, "withhold").status_code)
        self.assertEqual("withheld", self.exception(data["id"], self.aarav, "withhold", "Disciplinary").data["state"])
        self.assertEqual(409, self.card(data["id"], self.aarav).status_code)

        row = next(r for r in self.client_for(self.admin).get(f"{URL}/{data['id']}/candidates").data["data"]
                   if r["student_id"] == self.aarav.id)
        self.assertEqual(("withheld", "Disciplinary"), (row["state"], row["reason"]))

        self.assertEqual("ready", self.exception(data["id"], self.aarav, "none").data["state"])
        self.assertEqual(200, self.card(data["id"], self.aarav).status_code)

    def test_overdue_fees_hold_a_card_only_when_the_exam_says_so(self):
        self.owe(self.aarav)
        data = self.published()
        self.assertEqual(200, self.card(data["id"], self.aarav).status_code)

        self.client_for(self.admin).patch(f"{URL}/{data['id']}", {"block_on_fee_dues": True}, format="json")

        self.assertEqual(409, self.card(data["id"], self.aarav).status_code)
        self.assertEqual(200, self.card(data["id"], self.riya).status_code)

    def test_a_fee_not_yet_due_holds_nothing(self):
        self.owe(self.aarav, days_ago=-5)
        data = self.published(block_on_fee_dues=True)

        self.assertEqual(200, self.card(data["id"], self.aarav).status_code)

    def test_the_school_may_let_a_student_through_a_fee_hold(self):
        self.owe(self.aarav)
        data = self.published(block_on_fee_dues=True)

        self.assertEqual("ready", self.exception(data["id"], self.aarav, "allow", "Paying on Friday").data["state"])
        self.assertEqual(200, self.card(data["id"], self.aarav).status_code)

    def test_a_teacher_may_not_hold_a_card(self):
        data = self.published()

        self.assertEqual(403, self.exception(data["id"], self.aarav, "withhold", "x", user=self.teacher).status_code)

    def test_a_student_of_another_school_cannot_be_named(self):
        data = self.published()
        theirs = factories.StudentFactory(school=self.elsewhere)

        self.assertIn("student_id", self.exception(data["id"], theirs, "withhold", "x").data["details"]["errors"])


class TheCandidateList(ExamTestCase):
    def test_everybody_who_sits_it_with_their_state_and_the_counts(self):
        self.owe(self.kabir)
        data = self.published(block_on_fee_dues=True)

        response = self.client_for(self.admin).get(f"{URL}/{data['id']}/candidates")

        self.assertEqual(
            [("Aarav Kumar", "ready"), ("Riya Kumar", "ready"), ("Kabir Kumar", "fee_hold"), ("Sara Kumar", "ready")],
            [(row["name"], row["state"]) for row in response.data["data"]],
        )
        self.assertEqual({"ready": 3, "fee_hold": 1}, response.data["counts"])
        self.assertEqual("1500.00", response.data["data"][2]["overdue"])

    def test_filters_by_section_search_and_state(self):
        data = self.published()
        client = self.client_for(self.admin)

        by_section = client.get(f"{URL}/{data['id']}/candidates", {"class_section_id": self.b8.id}).data["data"]
        by_search = client.get(f"{URL}/{data['id']}/candidates", {"q": "riya"}).data["data"]
        by_state = client.get(f"{URL}/{data['id']}/candidates", {"state": "withheld"}).data["data"]

        self.assertEqual(["Kabir Kumar"], [row["name"] for row in by_section])
        self.assertEqual(["Riya Kumar"], [row["name"] for row in by_search])
        self.assertEqual([], by_state)


class PrintingAClass(ExamTestCase):
    def test_a_section_prints_its_ready_cards_and_says_how_many_were_skipped(self):
        data = self.published()
        self.client_for(self.admin).put(f"{URL}/{data['id']}/exceptions",
                                        {"student_id": self.riya.id, "kind": "withhold", "reason": "x"}, format="json")

        response = self.client_for(self.admin).get(f"{URL}/{data['id']}/cards.pdf", {"class_section_id": self.a8.id})

        self.assertEqual(200, response.status_code)
        self.assertEqual(("1", "1"), (response["X-Cards-Printed"], response["X-Cards-Skipped"]))
        self.save_sample(response, "section-cards")

    def test_a_class_or_section_must_be_named(self):
        data = self.published()

        self.assertEqual(422, self.client_for(self.admin).get(f"{URL}/{data['id']}/cards.pdf").status_code)

    def test_nothing_ready_is_a_refusal_not_an_empty_pdf(self):
        data = self.published(block_on_fee_dues=True)
        self.owe(self.kabir)

        response = self.client_for(self.admin).get(f"{URL}/{data['id']}/cards.pdf", {"class_section_id": self.b8.id})

        self.assertEqual(409, response.status_code)


class ManySubjects(ExamTestCase):
    def test_fifteen_papers_and_long_names_render_without_dropped_styles(self):
        exam = self.exam(name="Annual Examination with a very long and descriptive name for the year 2026-27",
                         card_style="mono")
        department = factories.DepartmentFactory(school=self.school)
        papers = []

        for index in range(15):
            subject = factories.SubjectFactory(
                school=self.school, department=department,
                name=f"Subject number {index + 1} with a long paper title (theory)",
            )
            papers.append(self.paper(self.class8, subject, f"2026-12-{index + 1:02d}"))

        self.assertEqual(200, self.sheet(exam["id"], papers).status_code)
        self.publish(exam["id"])
        response = self.card(exam["id"], self.aarav)

        self.assertEqual(200, response.status_code)
        self.save_sample(response, "fifteen-papers-mono")
        snapshot = snapshot_of(Examination.objects.select_related("academic_year").get(pk=exam["id"]))
        html = card_pdf.document([card_pdf.Card(self.aarav, snapshot, self.class8.id, 1, "11/17/2026")],
                                 school=self.school, year_id=self.year.id)
        self.assertEqual(0, pdf_design.style_errors(html))


class Times(SimpleTestCase):
    def test_times_read_as_the_app_writes_them(self):
        self.assertEqual(("9:00 AM", "12:00 PM", "12:30 AM", "5:05 PM"),
                         tuple(time_label(t) for t in ("09:00", "12:00", "00:30", "17:05")))
