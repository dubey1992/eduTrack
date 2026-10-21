"""The endpoint the fingerprint readers talk to (docs/biometric.md, B4).

Written against the common ZKTeco push dialect, which is an assumption until
a real device is in front of us - so these tests pin the two things that
will still be true whichever way the dialect turns out:

- **What the firmware is told.** Plain text, at the device's own URLs, with
  the handshake lines it refuses to proceed without. A JSON envelope or a
  404 here is a retry loop, not an error anybody sees.
- **What a device may do.** A serial is not a credential: it is printed on
  the box and sent in the clear. An unknown one is refused and audited, a
  wrong key is refused, a leaked one is rate limited - and everything that
  gets through can still only write a time.

The parsing is deliberately forgiving, because the cost of being wrong is
asymmetric: a line we cannot read is one punch, and a batch we refuse is a
box that resends it for ever.
"""

import datetime as dt

from django.core.cache import cache
from django.test import Client, TestCase

from school import factories
from school.enums import StaffAttendanceStatus, UserRole
from school.models import AuditLog, BiometricDevice, BiometricPunch, StaffAttendance

CDATA = "/iclock/cdata"
GETREQUEST = "/iclock/getrequest"
DEVICECMD = "/iclock/devicecmd"


def _today() -> dt.date:
    """A weekday inside the marking window, so B5 can mark it."""
    today = dt.date.today()

    return today - dt.timedelta(days=(today.weekday() - 2) % 7 or 7)


A_SCHOOL_DAY = _today()


class PushTest(TestCase):
    def setUp(self):
        cache.clear()
        # Asia/Kolkata is +05:30: the half-hour offset is what catches a
        # server that recorded the punch on its own clock.
        self.school = factories.SchoolFactory(name="Abbey Road School", timezone="Asia/Kolkata")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.device = factories.BiometricDeviceFactory(
            school=self.school, serial_number="ZK-0001", name="Front gate"
        )
        self.teacher = factories.StaffProfileFactory(
            school=self.school,
            user=factories.UserFactory(school=self.school, role=UserRole.TEACHER),
            employee_id="EMP-1",
            biometric_user_id="17",
        )
        self.client = Client()

        # Readers on the wall: biometric arrives switched off, so a test
        # about it has to say the school asked for it (school/modules.py).
        factories.ModuleSettingFactory(school=self.school, module="biometric")

    def attlog(self, lines, serial="ZK-0001", **params):
        query = "&".join(f"{key}={value}" for key, value in {"SN": serial, "table": "ATTLOG", **params}.items())

        return self.client.post(
            f"{CDATA}?{query}",
            data="\n".join(lines).encode("utf-8"),
            content_type="application/octet-stream",
        )

    def a_punch(self, at="09:02:17", who="17", date=None):
        return f"{who}\t{(date or A_SCHOOL_DAY).isoformat()} {at}\t1\t1\t0\t0"


class TheHandshake(PushTest):
    def test_a_registered_device_is_told_what_to_send(self):
        response = self.client.get(f"{CDATA}?SN=ZK-0001&options=all&pushver=2.4.1")

        self.assertEqual(200, response.status_code)
        body = response.content.decode()
        self.assertIn("GET OPTION FROM: ZK-0001", body)
        self.assertIn("Stamp=0", body)

    def test_it_is_plain_text(self):
        """A JSON envelope would be answered with a parse error and a retry
        loop, by a box nobody can see the screen of."""
        response = self.client.get(f"{CDATA}?SN=ZK-0001")

        self.assertTrue(response["Content-Type"].startswith("text/plain"))

    def test_a_new_device_is_asked_for_everything_it_holds(self):
        """Stamp=0 is what makes a box deliver its backlog rather than only
        what happens next - the difference between a school's first day
        working and a week of silence."""
        response = self.client.get(f"{CDATA}?SN=ZK-0001")

        self.assertIn("Stamp=0", response.content.decode())

    def test_the_contact_is_recorded(self):
        self.assertIsNone(self.device.last_seen_at)

        self.client.get(f"{CDATA}?SN=ZK-0001")

        self.assertIsNotNone(BiometricDevice.objects.get(pk=self.device.pk).last_seen_at)

    def test_polling_for_commands_is_answered_but_never_given_one(self):
        """This product never sends a device a command. The endpoint exists
        because the firmware treats a 404 as a fault."""
        response = self.client.get(f"{GETREQUEST}?SN=ZK-0001")

        self.assertEqual(200, response.status_code)
        self.assertEqual("OK", response.content.decode().strip())

    def test_a_command_result_is_acknowledged(self):
        response = self.client.post(f"{DEVICECMD}?SN=ZK-0001", data=b"ID=1&Return=0", content_type="text/plain")

        self.assertEqual(200, response.status_code)


class AnUnknownDevice(PushTest):
    def test_a_serial_nobody_registered_is_refused(self):
        response = self.client.get(f"{CDATA}?SN=ZK-9999")

        self.assertEqual(401, response.status_code)

    def test_and_the_attempt_is_audited(self):
        """A device somebody installed and forgot to register looks exactly
        like somebody guessing serials. Both are worth seeing."""
        self.client.get(f"{CDATA}?SN=ZK-9999")

        entry = AuditLog.objects.get(action="biometric.unknown_device")
        self.assertEqual("ZK-9999", entry.new_values["serial_number"])

    def test_no_serial_at_all_is_refused(self):
        self.assertEqual(401, self.client.get(CDATA).status_code)

    def test_its_punches_are_not_recorded(self):
        self.attlog([self.a_punch()], serial="ZK-9999")

        self.assertEqual(0, BiometricPunch.objects.count())


class TheSharedSecret(PushTest):
    def test_a_device_with_no_key_needs_none(self):
        """Older boxes cannot send one, and refusing them would leave a
        school worse off than the upload it already has."""
        self.assertEqual(200, self.client.get(f"{CDATA}?SN=ZK-0001").status_code)

    def test_a_device_with_a_key_is_refused_without_it(self):
        BiometricDevice.objects.filter(pk=self.device.pk).update(push_key="s3cret")

        self.assertEqual(401, self.client.get(f"{CDATA}?SN=ZK-0001").status_code)

    def test_a_wrong_key_is_refused(self):
        BiometricDevice.objects.filter(pk=self.device.pk).update(push_key="s3cret")

        self.assertEqual(401, self.client.get(f"{CDATA}?SN=ZK-0001&key=guess").status_code)

    def test_the_right_key_is_let_through(self):
        BiometricDevice.objects.filter(pk=self.device.pk).update(push_key="s3cret")

        self.assertEqual(200, self.client.get(f"{CDATA}?SN=ZK-0001&key=s3cret").status_code)

    def test_a_refusal_does_not_say_which_of_the_two_was_wrong(self):
        """A probe learns nothing from the difference between "no such
        device" and "wrong key"."""
        BiometricDevice.objects.filter(pk=self.device.pk).update(push_key="s3cret")

        wrong_key = self.client.get(f"{CDATA}?SN=ZK-0001&key=guess")
        no_device = self.client.get(f"{CDATA}?SN=ZK-9999")

        self.assertEqual(wrong_key.status_code, no_device.status_code)
        self.assertEqual(wrong_key.content, no_device.content)


class APushOfPunches(PushTest):
    def test_a_punch_is_recorded_and_counted_back(self):
        response = self.attlog([self.a_punch()])

        self.assertEqual("OK: 1", response.content.decode().strip())
        self.assertEqual(1, BiometricPunch.objects.count())

    def test_it_is_the_schools_wall_clock(self):
        """09:02 at a school in Asia/Kolkata is 03:32 UTC. A server that
        assumed its own zone would move every punch by five and a half
        hours."""
        self.attlog([self.a_punch(at="09:02:00")])

        punch = BiometricPunch.objects.get()
        self.assertEqual(dt.time(3, 32), punch.punched_at.timetz().replace(tzinfo=None))
        self.assertEqual(A_SCHOOL_DAY, punch.local_date)

    def test_it_knows_which_device_it_came_from(self):
        self.attlog([self.a_punch()])

        punch = BiometricPunch.objects.get()
        self.assertEqual(self.device.pk, punch.device_id)
        self.assertEqual("device", punch.source)

    def test_the_raw_line_is_kept(self):
        """The evidence for fixing a dialect we guessed wrong, and for an
        admin asking why check-in says what it says."""
        self.attlog([self.a_punch()])

        self.assertIn("17", BiometricPunch.objects.get().raw)

    def test_a_resend_lands_once(self):
        """Devices resend. A repeat is a repeat, not an error."""
        self.attlog([self.a_punch()])
        response = self.attlog([self.a_punch()])

        self.assertEqual("OK: 0", response.content.decode().strip())
        self.assertEqual(1, BiometricPunch.objects.count())

    def test_a_comma_separated_line_is_read_too(self):
        """Tab is the documented separator; comma appears in the wild."""
        self.attlog([f"17,{A_SCHOOL_DAY.isoformat()} 09:02:17,1,1"])

        self.assertEqual(1, BiometricPunch.objects.count())

    def test_a_stamp_without_seconds_is_read_too(self):
        self.attlog([f"17\t{A_SCHOOL_DAY.isoformat()} 09:02"])

        self.assertEqual(1, BiometricPunch.objects.count())

    def test_a_line_it_cannot_read_is_skipped_not_fatal(self):
        """A box that gets a 500 resends the same unreadable line for ever,
        and the rest of the batch is real attendance."""
        response = self.attlog(["nonsense", self.a_punch(), "", "17\tyesterday"])

        self.assertEqual(200, response.status_code)
        self.assertEqual("OK: 1", response.content.decode().strip())

    def test_an_unmapped_id_is_kept_rather_than_dropped(self):
        self.attlog([self.a_punch(who="99")])

        punch = BiometricPunch.objects.get()
        self.assertEqual("99", punch.biometric_user_id)
        self.assertIsNone(punch.staff_profile_id)

    def test_the_batch_is_audited(self):
        self.attlog([self.a_punch()])

        entry = AuditLog.objects.get(action="biometric.punches_pushed")
        self.assertEqual(1, entry.new_values["accepted"])
        self.assertEqual(self.school.id, entry.school_id)

    def test_another_table_is_acknowledged_and_dropped(self):
        """Operation logs, enrolment changes, photographs. None of them is
        attendance, and storing what we will not read is a liability."""
        response = self.attlog([self.a_punch()], table="OPERLOG")

        self.assertEqual(200, response.status_code)
        self.assertEqual(0, BiometricPunch.objects.count())


class WhatAPushCanReach(PushTest):
    def test_it_marks_the_register_the_same_way_an_upload_does(self):
        """B5, through the device rather than through a file - one path, so
        a school that gets its devices working does not get different
        attendance from one that uploads."""
        self.attlog([self.a_punch(at="09:47:00"), self.a_punch(at="17:30:00")])

        row = StaffAttendance.objects.get(staff_profile_id=self.teacher.id, attendance_date=A_SCHOOL_DAY)
        self.assertEqual(StaffAttendanceStatus.PRESENT, row.status)
        self.assertEqual(dt.time(9, 47), row.check_in)
        self.assertEqual(dt.time(17, 30), row.check_out)

    def test_nobody_is_named_as_having_marked_it(self):
        self.attlog([self.a_punch(at="09:47:00"), self.a_punch(at="17:30:00")])

        row = StaffAttendance.objects.get(staff_profile_id=self.teacher.id, attendance_date=A_SCHOOL_DAY)
        self.assertIsNone(row.marked_by_id)

    def test_it_cannot_overrule_a_status_a_human_set(self):
        """The whole security argument in one test: even a forged push moves
        a time and nothing else."""
        StaffAttendance.objects.create(
            school_id=self.school.id,
            staff_profile_id=self.teacher.id,
            attendance_date=A_SCHOOL_DAY,
            status=StaffAttendanceStatus.LEAVE,
            marked_by_id=self.admin.id,
            created_at=dt.datetime.now(dt.timezone.utc),
            updated_at=dt.datetime.now(dt.timezone.utc),
        )

        self.attlog([self.a_punch(at="09:47:00"), self.a_punch(at="17:30:00")])

        row = StaffAttendance.objects.get(staff_profile_id=self.teacher.id, attendance_date=A_SCHOOL_DAY)
        self.assertEqual(StaffAttendanceStatus.LEAVE, row.status)
        self.assertEqual(dt.time(9, 47), row.check_in)

    def test_a_device_cannot_reach_another_schools_register(self):
        elsewhere = factories.SchoolFactory(name="Elsewhere High", timezone="Asia/Kolkata")
        theirs = factories.StaffProfileFactory(
            school=elsewhere,
            user=factories.UserFactory(school=elsewhere, role=UserRole.TEACHER),
            employee_id="EMP-X",
            biometric_user_id="17",
        )

        self.attlog([self.a_punch()])

        self.assertEqual(self.school.id, BiometricPunch.objects.get().school_id)
        self.assertFalse(StaffAttendance.objects.filter(staff_profile_id=theirs.id).exists())


class TheRateLimit(PushTest):
    def test_a_leaked_serial_cannot_be_used_to_flood(self):
        for _ in range(60):
            self.client.get(f"{CDATA}?SN=ZK-0001")

        self.assertEqual(429, self.client.get(f"{CDATA}?SN=ZK-0001").status_code)

    def test_one_school_does_not_spend_another_devices_allowance(self):
        """Counted per serial, not per address: a school's devices sit
        behind one address and a per-address limit would throttle the
        school rather than the problem."""
        other = factories.BiometricDeviceFactory(school=self.school, serial_number="ZK-0002", name="Side gate")

        for _ in range(60):
            self.client.get(f"{CDATA}?SN=ZK-0001")

        self.assertEqual(200, self.client.get(f"{CDATA}?SN={other.serial_number}").status_code)
