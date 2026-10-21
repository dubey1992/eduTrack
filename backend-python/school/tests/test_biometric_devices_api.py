"""Fingerprint readers, and who is enrolled on them (docs/biometric.md, B1).

A registry and nothing more - no punch is read until B2. What it settles
first is the part that takes the longest in practice: what hardware a school
has, and which device id belongs to which member of staff.

Two rules carry the weight, and both come from the same fact - **a device
identifies itself by its serial number and nothing else**:

- A serial is unique across the platform, not within a school. Two schools
  claiming one would make "whose punch is this?" unanswerable.
- An enrolment id is unique *within* a school. Two schools number their own
  staff from 1 and neither is wrong.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import AuditLog, BiometricDevice

DEVICES = "/api/v1/biometric/devices"


class DeviceTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(name="Abbey Road School")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.other = factories.SchoolFactory(name="Elsewhere High")
        self.stranger = factories.UserFactory(school=self.other, role=UserRole.SCHOOL_ADMIN)
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        # Readers on the wall: biometric arrives switched off, so a test
        # about it has to say the school asked for it (school/modules.py).
        factories.ModuleSettingFactory(school=self.school, module="biometric")
        factories.ModuleSettingFactory(school=self.other, module="biometric")

    def client_as(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def add(self, user=None, **overrides):
        body = {"name": "Front gate", "serial_number": "ZK-0001", "location": "Reception"}
        body.update(overrides)

        return self.client_as(user or self.admin).post(DEVICES, body, format="json")


class Registering(DeviceTest):
    def test_a_device_is_recorded_against_the_school(self):
        response = self.add()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(
            ("Front gate", "ZK-0001", "Reception", self.school.id),
            (
                response.data["name"],
                response.data["serial_number"],
                response.data["location"],
                response.data["school_id"],
            ),
        )

    def test_it_has_not_been_heard_from_yet(self):
        # Null, not an invented timestamp: a device registered this morning
        # and never heard from is a different thing from one that stopped
        # talking on Tuesday, and only this tells them apart.
        self.assertIsNone(self.add().data["last_seen_at"])

    def test_a_serial_is_stored_the_way_a_device_will_send_it(self):
        # Read off a sticker and typed in, it is the same serial whichever
        # case somebody uses; the device itself sends exactly one of them.
        response = self.add(serial_number="  zk-0002  ")

        self.assertEqual("ZK-0002", response.data["serial_number"])

    def test_a_location_is_optional(self):
        response = self.add(location="")

        self.assertEqual(201, response.status_code, response.data)

    def test_registering_one_is_audited(self):
        self.add()

        self.assertTrue(AuditLog.objects.filter(entity_type="biometric_device").exists())


class OneSerialOneDevice(DeviceTest):
    def test_the_same_serial_twice_is_refused(self):
        self.add()

        response = self.add(name="Back gate")

        self.assertEqual(422, response.status_code)
        self.assertIn("serial_number", response.data["details"]["errors"])

    def test_another_school_cannot_claim_it_either(self):
        """Across the platform, not within a school: the serial is how an
        unauthenticated device says who it is."""
        self.add()

        response = self.add(user=self.stranger)

        self.assertEqual(422, response.status_code)
        self.assertIn("serial_number", response.data["details"]["errors"])

    def test_the_refusal_does_not_say_which_school_has_it(self):
        # That would tell one customer about another.
        self.add()

        said = str(self.add(user=self.stranger).data)

        self.assertNotIn("Abbey Road", said)

    def test_a_device_can_be_renamed_without_tripping_over_itself(self):
        device = self.add().data

        response = self.client_as(self.admin).patch(
            f"{DEVICES}/{device['id']}",
            {"name": "Main entrance", "serial_number": device["serial_number"]},
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("Main entrance", response.data["name"])


class WhoSeesWhat(DeviceTest):
    def test_a_school_sees_only_its_own(self):
        self.add()
        self.add(user=self.stranger, serial_number="ZK-9999")

        rows = self.client_as(self.admin).get(DEVICES).data["data"]

        self.assertEqual(["ZK-0001"], [row["serial_number"] for row in rows])

    def test_a_super_admin_sees_every_one(self):
        self.add()
        self.add(user=self.stranger, serial_number="ZK-9999")

        rows = self.client_as(self.root).get(DEVICES).data["data"]

        self.assertEqual({"ZK-0001", "ZK-9999"}, {row["serial_number"] for row in rows})

    def test_another_schools_device_is_not_reachable_by_its_id(self):
        theirs = self.add(user=self.stranger, serial_number="ZK-9999").data

        self.assertEqual(403, self.client_as(self.admin).get(f"{DEVICES}/{theirs['id']}").status_code)
        self.assertEqual(403, self.client_as(self.admin).delete(f"{DEVICES}/{theirs['id']}").status_code)

    def test_a_teacher_may_not_register_hardware(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(403, self.add(user=teacher).status_code)


class FindingOne(DeviceTest):
    def setUp(self):
        super().setUp()
        self.add(name="Front gate", serial_number="ZK-0001", location="Reception")
        self.add(name="Staff room", serial_number="ZK-0002", location="First floor")

    def names(self, **params) -> list[str]:
        return [row["name"] for row in self.client_as(self.admin).get(DEVICES, params).data["data"]]

    def test_by_name(self):
        self.assertEqual(["Staff room"], self.names(q="staff"))

    def test_by_serial(self):
        self.assertEqual(["Front gate"], self.names(q="0001"))

    def test_by_location(self):
        self.assertEqual(["Staff room"], self.names(q="floor"))

    def test_the_ones_never_heard_from_come_first(self):
        """A device registered and never heard from is the one somebody has
        to go and look at."""
        from django.utils import timezone

        BiometricDevice.objects.filter(serial_number="ZK-0001").update(last_seen_at=timezone.now())

        self.assertEqual(["Staff room", "Front gate"], self.names())


class Removing(DeviceTest):
    def test_a_device_can_be_removed(self):
        device = self.add().data

        self.assertEqual(204, self.client_as(self.admin).delete(f"{DEVICES}/{device['id']}").status_code)
        self.assertFalse(BiometricDevice.objects.filter(pk=device["id"]).exists())

    def test_removing_one_is_audited(self):
        device = self.add().data
        self.client_as(self.admin).delete(f"{DEVICES}/{device['id']}")

        self.assertTrue(
            AuditLog.objects.filter(entity_type="biometric_device", action__endswith="deleted").exists()
        )


class Enrolment(DeviceTest):
    """Which id a member of staff has on the devices."""

    def add_staff(self, user=None, **overrides):
        body = {
            "first_name": "Asha",
            "last_name": "Nair",
            "email": f"asha{overrides.get('employee_id', 'EMP-1')}@example.invalid",
            "mobile": "+91 9800000001",
            "role": UserRole.TEACHER,
            "password": "Orchard7Lane",
            "employee_id": "EMP-1",
            "joining_date": "2026-01-05",
        }
        body.update(overrides)

        return self.client_as(user or self.admin).post("/api/v1/staff", body, format="json")

    def test_somebody_can_be_enrolled_when_they_are_added(self):
        response = self.add_staff(biometric_user_id="17")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("17", response.data["biometric_user_id"])

    def test_most_staff_are_not_enrolled_at_all(self):
        response = self.add_staff()

        self.assertEqual(201, response.status_code, response.data)
        self.assertIsNone(response.data["biometric_user_id"])

    def test_a_blank_is_nobody_rather_than_a_clash(self):
        self.assertEqual(201, self.add_staff(employee_id="EMP-1", biometric_user_id="").status_code)

        second = self.add_staff(employee_id="EMP-2", biometric_user_id="")

        self.assertEqual(201, second.status_code, second.data)
        self.assertIsNone(second.data["biometric_user_id"])

    def test_two_people_cannot_share_an_id_at_one_school(self):
        self.add_staff(employee_id="EMP-1", biometric_user_id="17")

        response = self.add_staff(employee_id="EMP-2", biometric_user_id="17")

        self.assertEqual(422, response.status_code)
        self.assertIn("biometric_user_id", response.data["details"]["errors"])

    def test_two_schools_may_both_have_a_number_seventeen(self):
        """Two schools number their own staff from 1 and neither is wrong."""
        self.add_staff(employee_id="EMP-1", biometric_user_id="17")

        response = self.add_staff(
            user=self.stranger, employee_id="EMP-1", biometric_user_id="17",
            email="asha.elsewhere@example.invalid",
        )

        self.assertEqual(201, response.status_code, response.data)


class TheSharedSecret(DeviceTest):
    """What a device sends with its punches, where the firmware can send
    one (docs/biometric.md, B4). Write-only on purpose: anybody who could
    read it could post punches for that school, and the set of people who
    may look at this register is wider than that."""

    def test_it_can_be_set_when_a_device_is_registered(self):
        response = self.add(push_key="s3cret")

        self.assertEqual(201, response.status_code, response.data)
        self.assertTrue(response.data["has_push_key"])
        self.assertEqual("s3cret", BiometricDevice.objects.get(serial_number="ZK-0001").push_key)

    def test_it_is_never_read_back(self):
        self.add(push_key="s3cret")

        listed = self.client_as(self.admin).get(DEVICES).data["data"][0]
        self.assertNotIn("push_key", listed)
        self.assertTrue(listed["has_push_key"])

    def test_a_device_without_one_says_so(self):
        response = self.add()

        self.assertFalse(response.data["has_push_key"])

    def test_an_empty_one_is_no_key_rather_than_an_empty_string(self):
        """"" would answer "yes, a key is set" at the push endpoint and
        refuse every device that cannot send one."""
        response = self.add(push_key="")

        self.assertFalse(response.data["has_push_key"])
        self.assertIsNone(BiometricDevice.objects.get(serial_number="ZK-0001").push_key)

    def test_it_can_be_cleared_later(self):
        device = self.add(push_key="s3cret").data

        response = self.client_as(self.admin).patch(
            f"{DEVICES}/{device['id']}", {"push_key": ""}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertFalse(response.data["has_push_key"])

    def test_it_never_reaches_the_audit_trail(self):
        """The trail should not be the one place a secret can be found."""
        self.add(push_key="s3cret")

        for entry in AuditLog.objects.filter(module="staff_attendance"):
            self.assertNotIn("s3cret", str(entry.new_values))
            self.assertNotIn("push_key", (entry.new_values or {}))
