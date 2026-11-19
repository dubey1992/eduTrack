"""A parent's absence note (docs/parent-student-app.md, F5, decided 2026-11-17).

What this file guards that a quick read would not:

- **A note never marks the register.** It sits beside the child on the
  register for its days; the teacher still marks it.
- **The class teacher hears of it in their inbox, never by SMS,** and
  acknowledging it is what the parent sees.
- **The parent's rules each say what to fix:** no past days, nothing more
  than 30 days ahead, a real reason, at least one day the school is open,
  and no second note over days already covered - the first is shown instead.
- **Who sees a note:** the school's staff who read attendance; a teacher only
  the classes they keep the register of; never another school.
"""

import datetime as dt
import io

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone
from PIL import Image

from school import factories
from school.enums import MessageChannel, MessageEvent
from school.models import AbsenceNote, Attendance, Holiday, Message
from school.tests.test_family_f1_api import FAMILY, FamilyAppTest

MEDIA = __import__("tempfile").mkdtemp()


def png() -> bytes:
    out = io.BytesIO()
    Image.new("RGB", (60, 40), (200, 50, 50)).save(out, format="PNG")
    return out.getvalue()


@override_settings(MEDIA_ROOT=MEDIA)
class NotesTest(FamilyAppTest):
    def setUp(self):
        super().setUp()
        self.teacher = factories.UserFactory(school=self.school, role="TEACHER", first_name="Neha", last_name="Iyer")
        self.other_teacher = factories.UserFactory(school=self.school, role="TEACHER")
        school_class = factories.SchoolClassFactory(academic_year=self.year, school=self.school, name="Class 6", level=6)
        self.section = factories.ClassSectionFactory(school_class=school_class, name="A", class_teacher=self.teacher)
        self.child.class_section = self.section
        self.child.save(update_fields=["class_section"])

    def day(self, offset: int) -> str:
        return (self.today() + dt.timedelta(days=offset)).isoformat()

    def send(self, start=1, end=2, reason="Fever since last night; the doctor says two days of rest.", **extra):
        return self.parent.post(
            f"{FAMILY}/children/{self.child.id}/absence-notes",
            {"start_date": self.day(start), "end_date": self.day(end), "reason": reason, **extra},
            format="multipart" if "photo" in extra else "json",
        )

    def errors(self, response):
        return response.data.get("details", {}).get("errors", {})


class AParentSendsANote(NotesTest):
    def test_it_is_kept_and_listed_for_the_parent(self):
        response = self.send()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("sent", response.data["status"])
        [listed] = self.parent.get(f"{FAMILY}/children/{self.child.id}/absence-notes").data["data"]
        self.assertEqual((self.day(1), self.day(2)), (listed["start_date"], listed["end_date"]))

    def test_the_class_teacher_hears_of_it_in_their_inbox_only(self):
        self.send()

        messages = Message.objects.filter(event=MessageEvent.ABSENCE_NOTE)
        self.assertEqual({(self.teacher.id, MessageChannel.IN_APP)}, {(m.user_id, m.channel) for m in messages})
        self.assertIn("Fever since last night", messages.first().body)

    def test_it_never_marks_the_register(self):
        self.send(start=0, end=0)

        self.assertFalse(Attendance.objects.filter(student=self.child).exists())

    def test_a_photo_of_the_doctors_note_is_kept(self):
        response = self.send(photo=SimpleUploadedFile("note.png", png(), content_type="image/png"))

        self.assertEqual(201, response.status_code, response.data)
        self.assertTrue(response.data["has_photo"])

    def test_a_file_that_is_not_a_photo_is_refused(self):
        response = self.send(photo=SimpleUploadedFile("note.pdf", b"%PDF-1.4 not a photo", content_type="application/pdf"))

        self.assertEqual(422, response.status_code)
        self.assertIn("photo", self.errors(response))
        self.assertFalse(AbsenceNote.objects.exists())


class TheParentsRules(NotesTest):
    def test_no_days_in_the_past(self):
        response = self.send(start=-1, end=1)

        self.assertEqual(422, response.status_code)
        self.assertEqual(["The first day can't be in the past."], self.errors(response)["start_date"])

    def test_the_last_day_not_before_the_first(self):
        self.assertIn("end_date", self.errors(self.send(start=3, end=2)))

    def test_no_more_than_30_days_ahead(self):
        self.assertEqual(["Notes can be sent up to 30 days ahead."], self.errors(self.send(start=1, end=31))["end_date"])

    def test_a_real_reason(self):
        self.assertIn("reason", self.errors(self.send(reason="sick")))

    def test_days_the_school_is_closed_tell_it_nothing(self):
        Holiday.objects.create(school=self.school, name="Diwali", type="religious",
                               start_date=self.today() + dt.timedelta(days=1),
                               end_date=self.today() + dt.timedelta(days=2),
                               created_at=timezone.now(), updated_at=timezone.now())

        response = self.send()

        self.assertEqual(422, response.status_code)
        self.assertIn("closed on all of those days", response.data["message"])

    def test_days_already_covered_show_the_first_note_instead(self):
        self.send(start=1, end=3)

        response = self.send(start=2, end=4)

        self.assertEqual(409, response.status_code)
        self.assertEqual("ABSENCE_NOTE_ALREADY_SENT", response.data["code"])
        self.assertEqual(self.day(1), response.data["details"]["note"]["start_date"])
        self.assertEqual(1, AbsenceNote.objects.count())


class OnlyTheirOwnChild(NotesTest):
    def test_another_familys_child_is_not_found(self):
        other = self.other_family_child()

        response = self.parent.get(f"{FAMILY}/children/{other.id}/absence-notes")

        self.assertEqual(404, response.status_code)

    def test_a_staff_session_is_refused(self):
        response = self.as_user(self.admin).get(f"{FAMILY}/children/{self.child.id}/absence-notes")

        self.assertEqual("NOT_A_FAMILY_ACCOUNT", response.data["code"])


class TheSchoolSeesTheNotes(NotesTest):
    def setUp(self):
        super().setUp()
        self.send(start=0, end=1, photo=SimpleUploadedFile("note.png", png(), content_type="image/png"))
        self.note = AbsenceNote.objects.get()

    def listed_for(self, user):
        response = self.as_user(user).get("/api/v1/absence-notes")
        self.assertEqual(200, response.status_code, getattr(response, "data", None))
        return [row["id"] for row in response.data["data"]]

    def test_the_class_teacher_and_the_admin_see_it(self):
        self.assertEqual([self.note.id], self.listed_for(self.teacher))
        self.assertEqual([self.note.id], self.listed_for(self.admin))

    def test_a_teacher_of_another_class_does_not(self):
        self.assertEqual([], self.listed_for(self.other_teacher))

    def test_another_schools_admin_does_not(self):
        other_school = factories.SchoolFactory()
        outsider = factories.UserFactory(school=other_school, role="SCHOOL_ADMIN")

        self.assertEqual([], self.listed_for(outsider))

    def test_the_class_teacher_acknowledges_and_the_parent_sees_it(self):
        response = self.as_user(self.teacher).post(f"/api/v1/absence-notes/{self.note.id}/acknowledge")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(("acknowledged", "Neha Iyer"), (response.data["status"], response.data["acknowledged_by"]))
        [listed] = self.parent.get(f"{FAMILY}/children/{self.child.id}/absence-notes").data["data"]
        self.assertEqual("acknowledged", listed["status"])
        # Who read it, and when - for the parent too (4.2).
        self.assertEqual("Neha Iyer", listed["acknowledged_by"])
        self.assertIsNotNone(listed["acknowledged_at"])

    def test_a_teacher_of_another_class_cannot_acknowledge(self):
        response = self.as_user(self.other_teacher).post(f"/api/v1/absence-notes/{self.note.id}/acknowledge")

        self.assertEqual(403, response.status_code)

    def test_the_photo_is_shown_to_those_who_may_see_it_only(self):
        self.assertEqual(200, self.as_user(self.teacher).get(f"/api/v1/absence-notes/{self.note.id}/photo").status_code)
        self.assertEqual(403, self.as_user(self.other_teacher).get(f"/api/v1/absence-notes/{self.note.id}/photo").status_code)

    def test_the_register_shows_the_note_beside_the_child(self):
        response = self.as_user(self.teacher).get(
            "/api/v1/attendance/register", {"class_section_id": self.section.id, "date": self.day(0)}
        )

        self.assertEqual(200, response.status_code, response.data)
        row = next(s for s in response.data["students"] if s["student_id"] == self.child.id)
        self.assertEqual(("sent", True), (row["absence_note"]["status"], row["absence_note"]["has_photo"]))
        self.assertIsNone(row["status"], "the note is not a mark")
