""""Please call me" and replies to notices (docs/parent-student-app.md, F5,
decided 2026-11-17).

What this file guards that a quick read would not:

- **A call request goes where the parent chose** - the class teacher, or
  every School Admin for the office - in the inbox only, never by SMS; one
  open request per child to each, and the school's note of the call stays
  with the school.
- **Only the person it was for, or the school's admins, mark it called**;
  a teacher sees their own requests and nobody else's; never another school.
- **A notice asks only parents it reaches**, and each parent answers once per
  child the notice is about - changing their mind replaces the answer, and
  nothing is taken after the closing day.
- **The school sees the counts and who has not answered.**
"""

import datetime as dt

from django.utils import timezone

from school import factories, notifications
from school.enums import MessageChannel, MessageEvent
from school.models import Announcement, AnnouncementReply, CallRequest, Message, ModuleSetting
from school.tests.test_family_f1_api import FAMILY, FamilyAppTest


class F5Test(FamilyAppTest):
    def setUp(self):
        super().setUp()
        self.teacher = factories.UserFactory(school=self.school, role="TEACHER", first_name="Neha", last_name="Iyer")
        self.other_teacher = factories.UserFactory(school=self.school, role="TEACHER")
        school_class = factories.SchoolClassFactory(academic_year=self.year, school=self.school, name="Class 6", level=6)
        self.section = factories.ClassSectionFactory(school_class=school_class, name="A", class_teacher=self.teacher)
        self.child.class_section = self.section
        self.child.save(update_fields=["class_section"])


# -- "Please call me" ---------------------------------------------------------------------


class CallTest(F5Test):
    def ask(self, recipient="class_teacher", reason="About the maths homework this week.", **extra):
        return self.parent.post(f"{FAMILY}/children/{self.child.id}/call-requests",
                                {"recipient": recipient, "reason": reason, **extra}, format="json")


class AParentAsksForACall(CallTest):
    def test_the_class_teacher_hears_of_it_in_their_inbox_only(self):
        response = self.ask(preferred_time="After 5 pm")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(("class_teacher", "open", "After 5 pm"),
                         (response.data["recipient"], response.data["status"], response.data["preferred_time"]))
        messages = Message.objects.filter(event=MessageEvent.CALL_REQUEST)
        self.assertEqual({(self.teacher.id, MessageChannel.IN_APP)}, {(m.user_id, m.channel) for m in messages})
        self.assertIn("maths homework", messages.first().body)

    def test_the_office_means_the_schools_admins(self):
        self.ask(recipient="office")

        told = set(Message.objects.filter(event=MessageEvent.CALL_REQUEST).values_list("user_id", flat=True))
        self.assertIn(self.admin.id, told)
        self.assertNotIn(self.teacher.id, told)

    def test_a_class_with_no_class_teacher_points_to_the_office(self):
        self.section.class_teacher = None
        self.section.save(update_fields=["class_teacher"])

        response = self.ask()

        self.assertEqual(422, response.status_code)
        self.assertIn("recipient", response.data["details"]["errors"])

    def test_a_reason_and_a_recipient_are_needed(self):
        self.assertIn("reason", self.ask(reason="hi").data["details"]["errors"])
        self.assertIn("recipient", self.ask(recipient="principal").data["details"]["errors"])

    def test_one_open_request_to_each(self):
        self.ask()

        again = self.ask()
        self.assertEqual(409, again.status_code)
        self.assertEqual("CALL_REQUEST_OPEN", again.data["code"])
        self.assertEqual(201, self.ask(recipient="office").status_code, "the office is a different person to ask")
        self.assertEqual(2, CallRequest.objects.count())

    def test_another_familys_child_is_not_found(self):
        other = self.other_family_child()

        response = self.parent.get(f"{FAMILY}/children/{other.id}/call-requests")

        self.assertEqual(404, response.status_code)


class TheSchoolCallsBack(CallTest):
    def setUp(self):
        super().setUp()
        self.ask()
        self.request = CallRequest.objects.get()

    def listed_for(self, user):
        response = self.as_user(user).get("/api/v1/call-requests")
        self.assertEqual(200, response.status_code, getattr(response, "data", None))
        return response.data["data"]

    def test_the_class_teacher_and_the_admin_see_it_with_the_number_to_call(self):
        [row] = self.listed_for(self.teacher)
        self.assertEqual(self.parent_user.name, row["parent"]["name"])
        self.assertTrue(row["parent"]["mobile"])
        self.assertEqual([self.request.id], [r["id"] for r in self.listed_for(self.admin)])

    def test_another_teacher_and_another_school_do_not(self):
        outsider = factories.UserFactory(school=factories.SchoolFactory(), role="SCHOOL_ADMIN")

        self.assertEqual([], self.listed_for(self.other_teacher))
        self.assertEqual([], self.listed_for(outsider))

    def test_marked_called_the_parent_sees_it_but_not_the_schools_note(self):
        response = self.as_user(self.teacher).post(f"/api/v1/call-requests/{self.request.id}/called",
                                                   {"outcome_note": "Spoke to the mother; fine."}, format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(("called", "Spoke to the mother; fine."), (response.data["status"], response.data["outcome_note"]))
        [mine] = self.parent.get(f"{FAMILY}/children/{self.child.id}/call-requests").data["data"]
        self.assertEqual("called", mine["status"])
        self.assertNotIn("outcome_note", mine)

    def test_another_teacher_cannot_mark_it_but_the_admin_can(self):
        self.assertEqual(403, self.as_user(self.other_teacher).post(
            f"/api/v1/call-requests/{self.request.id}/called").status_code)
        self.assertEqual(200, self.as_user(self.admin).post(
            f"/api/v1/call-requests/{self.request.id}/called").status_code)


# -- Replies to notices -------------------------------------------------------------------


class ReplyTest(F5Test):
    def setUp(self):
        super().setUp()
        ModuleSetting.objects.update_or_create(
            school=self.school, module="communication",
            defaults={"platform_enabled": True, "school_enabled": True, "settings": {},
                      "created_at": timezone.now(), "updated_at": timezone.now()},
        )

    def publish(self, **extra):
        body = {"title": "Science museum trip", "body": "The class goes to the museum next Friday.",
                "audience_type": "class_section", "audience_id": self.section.id, "channels": "sms_in_app",
                "school_id": self.school.id, **extra}
        response = self.as_user(self.admin).post("/api/v1/announcements", body, format="json")
        if response.status_code == 201:
            # The fan-out to guardians is a queued job; here it runs at once,
            # as the F1 tests do, so the parent's app gets its copy.
            announcement = Announcement.objects.get(pk=response.data["id"])
            notifications.notify_guardian(MessageEvent.ANNOUNCEMENT_PUBLISHED, self.child, {}, announcement=announcement)
        return response

    def notice(self):
        notices = self.parent.get(f"{FAMILY}/notices").data["data"]
        return next(n for n in notices if n["reply"] is not None)

    def reply(self, notice_id, answer=True, student=None, note=None):
        return self.parent.post(f"{FAMILY}/notices/{notice_id}/reply",
                                {"student_id": (student or self.child).id, "answer": answer, "note": note},
                                format="json")


class TheSchoolAsks(ReplyTest):
    def test_a_notice_carries_its_question(self):
        response = self.publish(reply_question="Can your child come on the trip?")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("Can your child come on the trip?", response.data["reply_question"])

    def test_only_a_notice_that_reaches_parents_can_ask(self):
        response = self.publish(audience_type="teachers", audience_id=None, reply_question="Coming to the meeting?")

        self.assertEqual(422, response.status_code)
        self.assertIn("reply_question", response.data["details"]["errors"])

    def test_the_closing_day_cannot_be_past_or_without_a_question(self):
        past = (self.today() - dt.timedelta(days=1)).isoformat()

        self.assertIn("reply_by", self.publish(reply_question="Coming?", reply_by=past).data["details"]["errors"])
        self.assertIn("reply_by", self.publish(reply_by=self.today().isoformat()).data["details"]["errors"])


class AParentAnswers(ReplyTest):
    def setUp(self):
        super().setUp()
        self.publish(reply_question="Can your child come on the trip?")
        self.announcement = Announcement.objects.get()

    def test_the_notice_asks_about_their_child(self):
        reply = self.notice()["reply"]

        self.assertEqual("Can your child come on the trip?", reply["question"])
        self.assertEqual([(self.child.id, None)], [(c["student_id"], c["answer"]) for c in reply["children"]])

    def test_an_answer_is_kept_and_a_change_of_mind_replaces_it(self):
        notice_id = self.notice()["id"]

        self.assertEqual(200, self.reply(notice_id, True, note="Packed lunch").status_code)
        response = self.reply(notice_id, False)

        self.assertEqual([False], [c["answer"] for c in response.data["children"]])
        self.assertEqual(1, AnnouncementReply.objects.count())

    def test_a_child_the_notice_is_not_about_is_not_found(self):
        classmate_elsewhere = self.other_family_child()

        response = self.reply(self.notice()["id"], True, student=classmate_elsewhere)

        self.assertEqual(404, response.status_code)

    def test_after_the_closing_day_nothing_is_taken(self):
        notice_id = self.notice()["id"]
        Announcement.objects.filter(pk=self.announcement.id).update(reply_by=self.today() - dt.timedelta(days=1))

        response = self.reply(notice_id, True)

        self.assertEqual(409, response.status_code)
        self.assertEqual("REPLIES_CLOSED", response.data["code"])

    def test_the_school_sees_the_counts_and_who_has_not_answered(self):
        classmate = factories.StudentFactory(class_section=self.section, school=self.school, first_name="Diya")
        self.reply(self.notice()["id"], True)

        response = self.as_user(self.admin).get(f"/api/v1/announcements/{self.announcement.id}/replies")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual((1, 0, 1), (response.data["yes"], response.data["no"], response.data["waiting"]))
        waiting = [row["student_id"] for row in response.data["students"] if row["answer"] is None]
        self.assertEqual([classmate.id], waiting)
        self.assertEqual({"yes": 1, "no": 0},
                         self.as_user(self.admin).get(f"/api/v1/announcements/{self.announcement.id}").data["reply_counts"])

    def test_a_notice_that_asked_nothing_has_no_replies_page(self):
        self.publish(title="Holiday on Monday", body="The school is closed on Monday for the festival.")
        plain = Announcement.objects.exclude(pk=self.announcement.id).get()

        self.assertEqual(404, self.as_user(self.admin).get(f"/api/v1/announcements/{plain.id}/replies").status_code)
