"""Biometric as a module a school asks for (school/modules.py).

It is the one part of the product that needs hardware on the wall. A school
without readers would find screens that can only ever be empty, so unlike
every other module this one arrives **off**, and a school gets it when it
asks. Everything else about it is the ordinary module contract: off means
hidden and refused, on means it works, and the staff register underneath
carries on either way.

The last of those matters most. Switching biometric off must not change
anybody's attendance: the register is a school's own record, and a module
switch is not allowed to rewrite it.
"""

import datetime as dt
import io

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import BiometricPunch, StaffAttendance

DEVICES = "/api/v1/biometric/devices"
PUNCHES = "/api/v1/biometric/punches"
UPLOAD = f"{PUNCHES}/upload"
ME = "/api/v1/me"
MODULES = "/api/v1/settings/modules"


def _a_school_day() -> dt.date:
    today = dt.date.today()

    return today - dt.timedelta(days=(today.weekday() - 2) % 7 or 7)


A_SCHOOL_DAY = _a_school_day()
ITS_DATE = A_SCHOOL_DAY.strftime("%m/%d/%Y")


class BiometricModuleTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(name="Abbey Road School", timezone="Asia/Kolkata")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def grant(self):
        factories.ModuleSettingFactory(school=self.school, module="biometric")
        cache.clear()

    def register_a_device(self):
        return self.client.post(
            DEVICES,
            {"name": "Front gate", "serial_number": "ZK-0001", "location": "Reception"},
            format="json",
        )

    def switch(self, *, on: bool, user=None):
        """What the Super Admin's settings screen sends."""
        answer = self.as_user(user or self.root).put(
            f"{MODULES}/biometric?school_id={self.school.id}",
            {"platform_enabled": on, "school_enabled": True},
            format="json",
        )
        cache.clear()

        return answer

    def upload(self, lines):
        upload = io.BytesIO(("\n".join(["biometric_user_id,punched_at", *lines]) + "\n").encode("utf-8"))
        upload.name = "punches.csv"

        return self.client.post(UPLOAD, {"file": upload}, format="multipart")


class BeforeAnybodyAsks(BiometricModuleTest):
    def test_a_school_does_not_have_it(self):
        """Unlike every other module, which a school with no row has."""
        enabled = self.client.get(ME).data["modules"]

        self.assertFalse(enabled["biometric"])
        self.assertTrue(enabled["staff_attendance"])

    def test_the_devices_screen_is_refused(self):
        response = self.client.get(DEVICES)

        self.assertEqual(403, response.status_code)
        self.assertEqual("MODULE_DISABLED", response.data["code"])

    def test_registering_a_device_is_refused(self):
        self.assertEqual(403, self.register_a_device().status_code)

    def test_the_punch_log_is_refused(self):
        self.assertEqual(403, self.client.get(PUNCHES).status_code)

    def test_uploading_punches_is_refused(self):
        response = self.upload([f"17,{ITS_DATE} 09:02"])

        self.assertEqual(403, response.status_code)
        self.assertEqual(0, BiometricPunch.objects.count())

    def test_the_settings_screen_shows_it_as_off(self):
        """The screen reads the same registry the server enforces. Reading
        a missing row as "on" is what made it say a school had readers it
        had never been granted."""
        listed = self.as_user(self.root).get(f"{MODULES}?school_id={self.school.id}").data
        rows = {row["module"]: row for row in listed}

        self.assertFalse(rows["biometric"]["platform_enabled"])
        self.assertFalse(rows["biometric"]["enabled"])
        self.assertTrue(rows["staff_attendance"]["enabled"])

    def test_the_message_names_the_module_rather_than_saying_no(self):
        """So the app can say which switch to ask about."""
        self.assertIn("Biometric", self.client.get(DEVICES).data["message"])


class OnceItIsGranted(BiometricModuleTest):
    def test_the_screens_come_back(self):
        self.grant()

        self.assertTrue(self.client.get(ME).data["modules"]["biometric"])
        self.assertEqual(200, self.client.get(DEVICES).status_code)
        self.assertEqual(201, self.register_a_device().status_code)

    def test_a_super_admin_can_grant_it(self):
        """Through the settings screen, which is how a customer asking for
        it actually gets it."""
        response = self.switch(on=True)

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(200, self.client.get(DEVICES).status_code)

    def test_a_school_admin_cannot_grant_themselves_a_module(self):
        """The platform switch is the Super Admin's alone: "on demand of
        the customer" means somebody at the platform said yes."""
        response = self.switch(on=True, user=self.admin)

        self.assertEqual(422, response.status_code)
        self.assertEqual(403, self.client.get(DEVICES).status_code)

    def test_switching_it_off_again_hides_it(self):
        self.grant()
        self.register_a_device()

        self.switch(on=False)

        self.assertEqual(403, self.client.get(DEVICES).status_code)


class TheRegisterUnderneath(BiometricModuleTest):
    """A module switch must not rewrite a school's attendance."""

    def setUp(self):
        super().setUp()
        self.teacher = factories.StaffProfileFactory(
            school=self.school,
            user=factories.UserFactory(school=self.school, role=UserRole.TEACHER),
            employee_id="EMP-1",
            biometric_user_id="17",
        )

    def register(self):
        return self.client.get(
            f"/api/v1/staff-attendance/register?school_id={self.school.id}&date={A_SCHOOL_DAY.isoformat()}"
        )

    def test_it_still_opens_with_biometric_off(self):
        response = self.register()

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(1, len(response.data["staff"]))

    def test_nothing_is_pre_filled_from_devices_that_are_switched_off(self):
        self.grant()
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        # Marked by the punches while the module was on (B5).
        self.assertTrue(StaffAttendance.objects.filter(staff_profile_id=self.teacher.id).exists())

        self.switch(on=False)

        mine = self.register().data["staff"][0]
        self.assertFalse(mine["times_from_device"])

    def test_what_the_devices_already_marked_is_left_exactly_as_it_was(self):
        """Switching a module off takes a screen away; it does not undo a
        day somebody has been marked present for."""
        self.grant()
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])
        before = StaffAttendance.objects.get(staff_profile_id=self.teacher.id)

        self.switch(on=False)

        after = StaffAttendance.objects.get(staff_profile_id=self.teacher.id)
        self.assertEqual((before.status, before.check_in, before.check_out), (after.status, after.check_in, after.check_out))
        self.assertEqual("09:02", self.register().data["staff"][0]["check_in"])


class TheDevicesThemselves(BiometricModuleTest):
    """The push endpoint has no account behind it, so the module switch is
    the only thing that can tell a device to stop."""

    def setUp(self):
        super().setUp()
        self.device = factories.BiometricDeviceFactory(
            school=self.school, serial_number="ZK-0001", name="Front gate"
        )

    def test_a_device_is_refused_while_the_module_is_off(self):
        response = self.client.get(f"/iclock/cdata?SN=ZK-0001")

        self.assertEqual(401, response.status_code)

    def test_and_its_punches_do_not_land(self):
        self.client.post(
            "/iclock/cdata?SN=ZK-0001&table=ATTLOG",
            data=f"17\t{A_SCHOOL_DAY.isoformat()} 09:02:00\t1\t1".encode("utf-8"),
            content_type="application/octet-stream",
        )

        self.assertEqual(0, BiometricPunch.objects.count())

    def test_once_granted_it_is_let_in(self):
        self.grant()

        self.assertEqual(200, self.client.get(f"/iclock/cdata?SN=ZK-0001").status_code)
