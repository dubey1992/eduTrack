"""Parent-teacher meetings (docs/mobile-apps-review.md, M12, 8.4).

What this file guards:

- **Who runs what.** Only the school's admins create, change and cancel a
  meeting; the class teacher (or an admin) opens and removes their class's
  slots; another teacher, another school's admin and a parent cannot.
- **One slot per child, one child per slot.** A second booking for the same
  child moves the first; a second parent after a taken slot hears
  PTM_SLOT_TAKEN.
- **Booking closes at the end of the day before.** On the day nothing moves.
- **Parents are told, once.** When the class's slots first open, when the
  school removes their slot or cancels the meeting, and the evening before.
- **A parent sees free or taken, never by whom.**
"""

import datetime as dt

from rest_framework.test import APIClient

from school import factories, ptm
from school.enums import MessageEvent
from school.models import AuditLog, Message, PtmBooking, PtmMeeting, PtmSlot

from . import test_family_f1_api as f1

FAMILY = f1.FAMILY
API = "/api/v1"


class PtmTest(f1.FamilyAppTest):
    def setUp(self):
        super().setUp()
        self.teacher = factories.UserFactory(school=self.school, role="TEACHER", first_name="Neha", last_name="Iyer")
        self.other_teacher = factories.UserFactory(school=self.school, role="TEACHER")
        school_class = factories.SchoolClassFactory(academic_year=self.year, school=self.school, name="Class 6",
                                                    level=6)
        self.section = factories.ClassSectionFactory(school_class=school_class, name="A", class_teacher=self.teacher)
        self.other_section = factories.ClassSectionFactory(school_class=school_class, name="B")
        self.child.class_section = self.section
        self.child.save(update_fields=["class_section"])
        self.classmate = factories.StudentFactory(class_section=self.section, school=self.school)

    def tomorrow(self, days=1) -> dt.date:
        return self.today() + dt.timedelta(days=days)

    def create(self, user=None, **body):
        payload = {"title": "Term 1 PTM", "meeting_date": self.tomorrow(3).isoformat(),
                   "note": "Please bring the report card.", "section_ids": [self.section.id], **body}
        return self.as_user(user or self.admin).post(f"{API}/ptm-meetings", payload, format="json")

    def meeting(self, days=3, sections=None) -> PtmMeeting:
        return ptm.create_meeting(self.admin, self.school.id, "Term 1 PTM", self.tomorrow(days), None,
                                  [s.id for s in (sections or [self.section])])

    def open(self, meeting, user=None, section=None, starts="09:00", ends="10:00", minutes=10):
        return self.as_user(user or self.teacher).post(
            f"{API}/ptm-meetings/{meeting.id}/sections/{(section or self.section).id}/slots",
            {"starts_at": starts, "ends_at": ends, "slot_minutes": minutes}, format="json",
        )

    def book(self, meeting, slot, child=None, client=None):
        return (client or self.parent).put(
            f"{FAMILY}/children/{(child or self.child).id}/meetings/{meeting.id}/booking", {"slot_id": slot.id},
            format="json",
        )

    def slots(self, meeting, section=None):
        return list(PtmSlot.objects.filter(ptm_meeting=meeting, class_section=section or self.section)
                    .order_by("starts_at"))


class TheOfficeCreatesAMeeting(PtmTest):
    def test_an_admin_creates_it_with_the_classes_taking_part(self):
        response = self.create()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("Term 1 PTM", response.data["title"])
        self.assertEqual("scheduled", response.data["status"])
        self.assertEqual([self.section.id], [s["id"] for s in response.data["sections"]])
        self.assertEqual("Neha Iyer", response.data["sections"][0]["class_teacher"])
        self.assertTrue(AuditLog.objects.filter(action="ptm.created").exists())

    def test_a_teacher_cannot_create_one(self):
        self.assertEqual(403, self.create(self.teacher).status_code)

    def test_the_school_id_in_the_request_is_not_trusted(self):
        elsewhere = factories.SchoolFactory()

        response = self.create(school_id=elsewhere.id)

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, response.data["school_id"])

    def test_another_schools_class_is_refused(self):
        elsewhere = factories.ClassSectionFactory()

        response = self.create(section_ids=[elsewhere.id])

        self.assertEqual(422, response.status_code)
        self.assertEqual("PTM_REFUSED", response.data["code"])

    def test_a_past_date_no_classes_and_a_blank_title_are_refused(self):
        self.assertEqual(422, self.create(meeting_date=(self.today() - dt.timedelta(days=1)).isoformat()).status_code)
        self.assertEqual(422, self.create(section_ids=[]).status_code)
        self.assertEqual(422, self.create(title="  ").status_code)
        self.assertEqual(422, self.create(note="x" * (ptm.NOTE_MAX + 1)).status_code)

    def test_the_date_cannot_move_once_parents_have_booked(self):
        meeting = self.meeting()
        self.open(meeting)
        self.book(meeting, self.slots(meeting)[0])

        response = self.as_user(self.admin).patch(f"{API}/ptm-meetings/{meeting.id}", {
            "title": "Moved", "meeting_date": self.tomorrow(5).isoformat(), "section_ids": [self.section.id],
        }, format="json")

        self.assertEqual(422, response.status_code)

    def test_the_name_changes_and_a_class_is_added(self):
        meeting = self.meeting()

        response = self.as_user(self.admin).patch(f"{API}/ptm-meetings/{meeting.id}", {
            "title": "Renamed", "meeting_date": meeting.meeting_date.isoformat(),
            "section_ids": [self.section.id, self.other_section.id],
        }, format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("Renamed", response.data["title"])
        self.assertEqual(2, len(response.data["sections"]))

    def test_a_class_with_bookings_cannot_be_dropped(self):
        meeting = self.meeting(sections=[self.section, self.other_section])
        self.open(meeting)
        self.book(meeting, self.slots(meeting)[0])

        response = self.as_user(self.admin).patch(f"{API}/ptm-meetings/{meeting.id}", {
            "title": meeting.title, "meeting_date": meeting.meeting_date.isoformat(),
            "section_ids": [self.other_section.id],
        }, format="json")

        self.assertEqual(422, response.status_code)


class WhoSeesTheMeetings(PtmTest):
    def test_the_class_teacher_sees_it_with_their_class_only(self):
        meeting = self.meeting(sections=[self.section, self.other_section])

        response = self.as_user(self.teacher).get(f"{API}/ptm-meetings")

        self.assertEqual(200, response.status_code)
        [row] = response.data["data"]
        self.assertEqual(meeting.id, row["id"])
        self.assertEqual([self.section.id], [s["id"] for s in row["sections"]])

    def test_a_teacher_with_no_class_in_it_sees_nothing(self):
        meeting = self.meeting()

        self.assertEqual([], self.as_user(self.other_teacher).get(f"{API}/ptm-meetings").data["data"])
        self.assertEqual(404, self.as_user(self.other_teacher).get(f"{API}/ptm-meetings/{meeting.id}").status_code)

    def test_another_schools_admin_cannot_see_or_cancel_it(self):
        meeting = self.meeting()
        stranger = factories.UserFactory(school=factories.SchoolFactory(), role="SCHOOL_ADMIN")

        self.assertEqual([], self.as_user(stranger).get(f"{API}/ptm-meetings").data["data"])
        self.assertEqual(404, self.as_user(stranger).post(f"{API}/ptm-meetings/{meeting.id}/cancel").status_code)

    def test_past_meetings_are_listed_apart(self):
        meeting = self.meeting()
        PtmMeeting.objects.filter(pk=meeting.id).update(meeting_date=self.today() - dt.timedelta(days=2))

        self.assertEqual([], self.as_user(self.admin).get(f"{API}/ptm-meetings").data["data"])
        self.assertEqual(1, len(self.as_user(self.admin).get(f"{API}/ptm-meetings", {"past": 1}).data["data"]))

    def test_a_parent_session_cannot_reach_the_staff_side(self):
        self.assertIn(self.parent.get(f"{API}/ptm-meetings").status_code, (401, 403))


class TheTeacherOpensSlots(PtmTest):
    def test_a_range_is_cut_into_slots_and_the_parents_are_told_once(self):
        meeting = self.meeting()

        response = self.open(meeting)

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(["09:00", "09:10", "09:20", "09:30", "09:40", "09:50"],
                         [s["starts_at"] for s in response.data["data"]])
        told = Message.objects.filter(event=MessageEvent.PTM_SLOTS_OPEN, student=self.child)
        self.assertEqual(1, told.count())
        self.assertIn("Neha Iyer", told.first().body)

        self.open(meeting, starts="10:00", ends="10:30")

        self.assertEqual(1, Message.objects.filter(event=MessageEvent.PTM_SLOTS_OPEN, student=self.child).count())
        self.assertEqual(9, len(self.slots(meeting)))

    def test_opening_the_same_range_twice_adds_nothing(self):
        meeting = self.meeting()
        self.open(meeting)

        self.open(meeting, starts="09:05", ends="09:55", minutes=10)

        self.assertEqual(6, len(self.slots(meeting)))

    def test_an_admin_may_open_slots_but_another_teacher_may_not(self):
        meeting = self.meeting()

        # Not their class: the meeting is not theirs to see at all.
        self.assertEqual(404, self.open(meeting, user=self.other_teacher).status_code)
        self.assertEqual(201, self.open(meeting, user=self.admin).status_code)
        self.assertEqual(self.teacher.id, self.slots(meeting)[0].teacher_user_id)

    def test_bad_lengths_and_ranges_are_refused(self):
        meeting = self.meeting()

        self.assertEqual(422, self.open(meeting, minutes=4).status_code)
        self.assertEqual(422, self.open(meeting, minutes=61).status_code)
        self.assertEqual(422, self.open(meeting, starts="10:00", ends="09:00").status_code)
        self.assertEqual(422, self.open(meeting, starts="09:00", ends="09:05", minutes=10).status_code)
        self.assertEqual(422, self.open(meeting, starts="nine", ends="10:00").status_code)
        self.assertEqual(422, self.open(meeting, starts="06:00", ends="21:00", minutes=5).status_code)

    def test_a_class_not_taking_part_is_refused(self):
        meeting = self.meeting()

        self.assertEqual(422, self.open(meeting, user=self.admin, section=self.other_section).status_code)

    def test_removing_a_booked_slot_tells_the_parent(self):
        meeting = self.meeting()
        self.open(meeting)
        slot = self.slots(meeting)[0]
        self.book(meeting, slot)

        response = self.as_user(self.teacher).delete(f"{API}/ptm-slots/{slot.id}")

        self.assertEqual(204, response.status_code)
        self.assertFalse(PtmBooking.objects.exists())
        told = Message.objects.get(event=MessageEvent.PTM_BOOKING_CANCELLED, student=self.child)
        self.assertIn("9:00 AM", told.body)

    def test_another_teacher_cannot_remove_a_slot(self):
        meeting = self.meeting()
        self.open(meeting)

        self.assertEqual(404, self.as_user(self.other_teacher).delete(
            f"{API}/ptm-slots/{self.slots(meeting)[0].id}").status_code)

    def test_the_teacher_sees_who_booked_with_the_mobile(self):
        meeting = self.meeting()
        self.open(meeting)
        self.book(meeting, self.slots(meeting)[1])

        response = self.as_user(self.teacher).get(f"{API}/ptm-meetings/{meeting.id}/sections/{self.section.id}/slots")

        self.assertEqual(200, response.status_code)
        booked = response.data["data"][1]["booking"]
        self.assertEqual(self.child.id, booked["student"]["id"])
        self.assertEqual(self.parent_user.name, booked["parent"]["name"])
        self.assertTrue(booked["parent"]["mobile"])
        self.assertIsNone(response.data["data"][0]["booking"])


class AParentBooks(PtmTest):
    def setUp(self):
        super().setUp()
        self.ptm = self.meeting()
        self.open(self.ptm)
        self.first, self.second = self.slots(self.ptm)[:2]

    def test_the_parent_sees_the_meeting_with_free_slots(self):
        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/meetings")

        self.assertEqual(200, response.status_code, response.data)
        [row] = response.data["data"]
        self.assertEqual("Term 1 PTM", row["title"])
        self.assertEqual("Neha Iyer", row["teacher_name"])
        self.assertTrue(row["booking_open"])
        self.assertIsNone(row["my_slot"])
        self.assertTrue(all(s["free"] for s in row["slots"]))

    def test_booking_then_moving_keeps_one_slot_per_child(self):
        self.assertEqual(200, self.book(self.ptm, self.first).status_code)

        response = self.book(self.ptm, self.second)

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(self.second.id, response.data["my_slot"]["id"])
        self.assertEqual(1, PtmBooking.objects.filter(student=self.child).count())
        self.assertTrue(AuditLog.objects.filter(action="ptm.moved").exists())

    def test_a_taken_slot_is_shown_taken_but_not_by_whom(self):
        PtmBooking.objects.create(school=self.school, ptm_meeting=self.ptm, ptm_slot=self.first,
                                  student=self.classmate, booked_by=self.admin)

        row = self.parent.get(f"{FAMILY}/children/{self.child.id}/meetings").data["data"][0]

        taken = row["slots"][0]
        self.assertFalse(taken["free"])
        self.assertFalse(taken["mine"])
        self.assertNotIn("student", taken)

    def test_a_second_parent_after_the_same_slot_hears_it_was_taken(self):
        PtmBooking.objects.create(school=self.school, ptm_meeting=self.ptm, ptm_slot=self.first,
                                  student=self.classmate, booked_by=self.admin)

        response = self.book(self.ptm, self.first)

        self.assertEqual(409, response.status_code)
        self.assertEqual("PTM_SLOT_TAKEN", response.data["code"])

    def test_cancelling_frees_the_slot(self):
        self.book(self.ptm, self.first)

        response = self.parent.delete(f"{FAMILY}/children/{self.child.id}/meetings/{self.ptm.id}/booking")

        self.assertEqual(200, response.status_code)
        self.assertIsNone(response.data["my_slot"])
        self.assertFalse(PtmBooking.objects.exists())

    def test_on_the_day_booking_is_closed(self):
        PtmMeeting.objects.filter(pk=self.ptm.id).update(meeting_date=self.today())

        response = self.book(self.ptm, self.first)

        self.assertEqual(422, response.status_code)
        self.assertEqual("PTM_BOOKING_CLOSED", response.data["code"])
        self.assertFalse(self.parent.get(f"{FAMILY}/children/{self.child.id}/meetings").data["data"][0]["booking_open"])

    def test_another_classes_slot_is_refused(self):
        self.ptm.sections.create(class_section=self.other_section)
        self.open(self.ptm, user=self.admin, section=self.other_section)
        theirs = self.slots(self.ptm, self.other_section)[0]

        self.assertEqual(422, self.book(self.ptm, theirs).status_code)

    def test_another_familys_child_and_a_meeting_not_for_the_class_are_404(self):
        stranger = self.other_family_child()
        elsewhere = self.meeting(sections=[self.other_section])

        self.assertEqual(404, self.book(self.ptm, self.first, child=stranger).status_code)
        self.assertEqual(404, self.book(elsewhere, self.first).status_code)

    def test_a_cancelled_meeting_disappears_and_its_parents_are_told(self):
        self.book(self.ptm, self.first)

        response = self.as_user(self.admin).post(f"{API}/ptm-meetings/{self.ptm.id}/cancel")

        self.assertEqual(200, response.status_code)
        self.assertEqual("cancelled", response.data["status"])
        self.assertEqual([], self.parent.get(f"{FAMILY}/children/{self.child.id}/meetings").data["data"])
        self.assertTrue(Message.objects.filter(event=MessageEvent.PTM_BOOKING_CANCELLED, student=self.child).exists())

    def test_a_teacher_cannot_cancel_the_meeting(self):
        self.assertEqual(403, self.as_user(self.teacher).post(f"{API}/ptm-meetings/{self.ptm.id}/cancel").status_code)

    def test_signing_in_is_required(self):
        self.assertEqual(401, APIClient().get(f"{FAMILY}/children/{self.child.id}/meetings").status_code)


class TheEveningBefore(PtmTest):
    def setUp(self):
        super().setUp()
        self.ptm = self.meeting(days=1)
        self.open(self.ptm)
        self.book(self.ptm, self.slots(self.ptm)[2])

    def evening(self, hour=18):
        from school.clock import SchoolClock

        return SchoolClock.for_school(self.school).now().replace(hour=hour, minute=0, second=0, microsecond=0)

    def test_the_family_and_the_teacher_are_reminded_once(self):
        told = ptm.send_reminders(at=self.evening())

        self.assertEqual(2, told)
        family = Message.objects.get(event=MessageEvent.PTM_REMINDER, student=self.child)
        self.assertIn("9:20 AM", family.body)
        teacher = Message.objects.get(event=MessageEvent.PTM_TEACHER_REMINDER, user=self.teacher)
        self.assertIn("1 parent booked", teacher.body)

        self.assertEqual(0, ptm.send_reminders(at=self.evening(hour=20)))

    def test_nothing_before_five(self):
        self.assertEqual(0, ptm.send_reminders(at=self.evening(hour=9)))

    def test_never_by_sms(self):
        ptm.send_reminders(at=self.evening())

        self.assertEqual({"in_app"}, set(Message.objects.filter(
            event__in=[MessageEvent.PTM_REMINDER, MessageEvent.PTM_TEACHER_REMINDER]).values_list("channel", flat=True)))
