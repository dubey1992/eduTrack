"""The Bus Attendant: signing in on a registered phone, running only their own
routes, marks made offline, and the bus's position (docs/maps.md).

What this file guards that a quick read would not:

- **A passcode is useless without the phone.** Four digits are ten thousand
  guesses, so the passcode is only checked at all on a registered device,
  five wrong guesses lock the account until a person unlocks it, and an
  unknown number and an unregistered phone get the same answer.
- **An attendant reaches their own routes and nothing else** - not another
  route's trips, not the fleet, not the student roll.
- **A mark sent twice is recorded once**, with the time it happened on the
  bus, and a batch with one mark that can no longer apply keeps the rest.
- **Positions are only taken while a trip runs**, from whoever runs it, and
  the guardian's alert says when the child really boarded.
"""

import datetime as dt

from django.test import TestCase

from school import attendants, factories, hashing, tokens
from school.enums import UserRole
from school.models import (
    AttendantCredential,
    AttendantDevice,
    AuditLog,
    Message,
    PersonalAccessToken,
    StaffProfile,
    TransportTrip,
    TransportTripEvent,
    TransportTripLocation,
    TransportTripRider,
    User,
)
from school.services import TripLocationService
from school.tests.test_transport_trips_api import TRIPS, WEDNESDAY, TripTestCase

SETUP = "/api/v1/auth/attendant/setup"
LOGIN = "/api/v1/auth/attendant/login"
MOBILE = "+91 98765 43210"


def at(minutes: int) -> str:
    """An instant `minutes` after the frozen Wednesday morning, as a phone sends it."""
    return (WEDNESDAY + dt.timedelta(minutes=minutes)).isoformat()


class AttendantTest(TripTestCase):
    def setUp(self):
        super().setUp()
        self.attendant_profile = self.make_attendant(MOBILE)
        self.attendant = self.attendant_profile.user
        self.f["route"].attendant_user = self.attendant
        self.f["route"].save()

        # A second route of the same school, run by somebody else.
        self.other = self.ready_route(self.f["school"], name="Lake Road", vehicle_name="Bus 07")

    def make_attendant(self, mobile, school=None, email=None):
        response = self.as_user(self.f["admin"] if school is None else school["admin"]).post("/api/v1/staff", {
            "first_name": "Ravi", "last_name": "Kumar", "email": email, "mobile": mobile, "role": "BUS_ATTENDANT",
            "employee_id": f"ATT-{mobile[-4:]}", "joining_date": "2026-04-01",
        }, format="json")
        self.assertEqual(201, response.status_code, response.data)

        return StaffProfile.objects.select_related("user").get(pk=response.data["id"])

    def code_for(self, profile=None):
        response = self.as_user(self.f["admin"]).post(
            f"/api/v1/staff/{(profile or self.attendant_profile).id}/attendant/setup-code"
        )
        self.assertEqual(201, response.status_code, response.data)

        return response.data["setup_code"]

    def register(self, mobile=MOBILE, passcode="4827", profile=None):
        """Registers a phone the way the app does; returns (token, device secret)."""
        response = self.anon().post(SETUP, {
            "mobile": mobile, "setup_code": self.code_for(profile), "passcode": passcode, "device_name": "Ravi's phone",
        }, format="json")
        self.assertEqual(201, response.status_code, response.data)

        return response.data["token"], response.data["device_secret"]

    def anon(self):
        """Nobody signed in - and a fresh throttle, so the tests about the
        passcode's own lock are not stopped early by the per-minute limit
        (that limit has its own guard in test_security_api)."""
        from django.core.cache import cache
        from rest_framework.test import APIClient

        cache.clear()

        return APIClient()

    def phone(self, token):
        from rest_framework.test import APIClient

        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + token)

        return client

    def login(self, passcode="4827", secret=None, mobile=MOBILE):
        return self.anon().post(LOGIN, {"mobile": mobile, "passcode": passcode, "device_secret": secret}, format="json")


# -- creating an attendant ----------------------------------------------------


class Creating(AttendantTest):
    def test_an_attendant_needs_no_email_and_no_password(self):
        user = self.attendant

        self.assertTrue(attendants.is_placeholder_email(user.email))
        credential = AttendantCredential.objects.get(user=user)
        self.assertEqual(("+919876543210", None, 0), (credential.login_mobile, credential.passcode, credential.failed_attempts))

        row = self.as_user(self.f["admin"]).get(f"/api/v1/staff/{self.attendant_profile.id}").data
        self.assertFalse(row["has_email"])
        self.assertEqual("BUS_ATTENDANT", row["role"])

    def test_a_mobile_is_required_and_must_be_free(self):
        admin = self.as_user(self.f["admin"])
        body = {"first_name": "A", "last_name": "B", "role": "BUS_ATTENDANT", "employee_id": "ATT-9",
                "joining_date": "2026-04-01"}

        missing = admin.post("/api/v1/staff", body, format="json")
        self.assertEqual(
            ["A Bus Attendant signs in with their mobile number, so it is required."],
            missing.data["details"]["errors"]["mobile"],
        )

        # The same number written differently is the same number.
        taken = admin.post("/api/v1/staff", {**body, "mobile": "+91 9876543210"}, format="json")
        self.assertEqual(
            ["Another Bus Attendant already signs in with this mobile number."],
            taken.data["details"]["errors"]["mobile"],
        )

    def test_everybody_else_still_needs_an_email_and_a_password(self):
        response = self.as_user(self.f["admin"]).post("/api/v1/staff", {
            "first_name": "A", "last_name": "B", "role": "TEACHER", "employee_id": "T-9", "joining_date": "2026-04-01",
        }, format="json")

        self.assertEqual({"email", "password"}, {"email", "password"} & set(response.data["details"]["errors"]))

    def test_an_attendant_with_a_real_email_still_cannot_use_the_password_form(self):
        profile = self.make_attendant("+91 91111 22222", email="ravi@example.com")
        User.objects.filter(pk=profile.user_id).update(password=hashing.make("Some-password-1"))

        response = self.anon().post("/api/v1/auth/login", {"email": "ravi@example.com", "password": "Some-password-1"}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertEqual("USE_PASSCODE_SIGN_IN", response.data["code"])

    def test_the_role_cannot_be_switched_in_or_out_from_admin_users(self):
        response = self.as_user(self.f["admin"]).patch(f"/api/v1/users/{self.attendant.id}", {"role": "STAFF"}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("cannot be changed", response.data["details"]["errors"]["role"][0])

    def test_changing_their_mobile_moves_their_sign_in_with_it(self):
        self.as_user(self.f["admin"]).patch(f"/api/v1/users/{self.attendant.id}", {"mobile": "+91 90000 11111"}, format="json")

        self.assertEqual("+919000011111", AttendantCredential.objects.get(user=self.attendant).login_mobile)

    def test_no_email_is_ever_sent_to_the_placeholder(self):
        from school import notifications
        from school.models import CommunicationSetting

        CommunicationSetting.objects.create(school=self.f["school"], **{**notifications.DEFAULTS, "email_enabled": True})

        messages = notifications.notify_staff("leave.approved", self.attendant, {"leave_type": "Casual"})

        email = [m for m in messages if m.channel == "email"][0]
        self.assertEqual(("skipped", None), (email.status, email.recipient_email))


# -- setup codes and registering a phone ------------------------------------


class SettingUp(AttendantTest):
    def test_an_admin_issues_a_one_time_code_that_is_never_stored_in_clear(self):
        code = self.code_for()

        self.assertRegex(code, r"^\d{8}$")
        credential = AttendantCredential.objects.get(user=self.attendant)
        self.assertNotEqual(code, credential.setup_code)
        self.assertTrue(hashing.check(code, credential.setup_code))

        entry = AuditLog.objects.get(action="attendant.setup_code_issued")
        self.assertNotIn(code, str(entry.new_values))

    def test_registering_gives_a_session_and_a_device_secret_kept_only_as_a_digest(self):
        token, secret = self.register()

        self.assertEqual(200, self.phone(token).get("/api/v1/me").status_code)
        device = AttendantDevice.objects.get(user=self.attendant)
        self.assertEqual(attendants.device_digest(secret), device.secret)
        self.assertNotEqual(secret, device.secret)

    def test_a_code_works_once(self):
        code = self.code_for()
        first = self.anon().post(SETUP, {"mobile": MOBILE, "setup_code": code, "passcode": "4827"}, format="json")
        again = self.anon().post(SETUP, {"mobile": MOBILE, "setup_code": code, "passcode": "4827"}, format="json")

        self.assertEqual((201, 401), (first.status_code, again.status_code))

    def test_an_expired_code_is_refused(self):
        code = self.code_for()
        AttendantCredential.objects.filter(user=self.attendant).update(setup_code_expires_at=WEDNESDAY - dt.timedelta(minutes=1))

        response = self.anon().post(SETUP, {"mobile": MOBILE, "setup_code": code, "passcode": "4827"}, format="json")

        self.assertEqual(401, response.status_code)
        self.assertIn("expired", response.data["message"])

    def test_obvious_passcodes_are_refused(self):
        for passcode, sentence in (
            ("1111", "not one digit repeated"), ("1234", "straight run"), ("9876", "straight run"),
            ("12a4", "exactly 4 digits"), ("12345", "exactly 4 digits"),
        ):
            with self.subTest(passcode=passcode):
                response = self.anon().post(SETUP, {"mobile": MOBILE, "setup_code": "00000000", "passcode": passcode}, format="json")
                self.assertEqual(422, response.status_code)
                self.assertIn(sentence, response.data["details"]["errors"]["passcode"][0])

    def test_an_unknown_number_gets_the_same_answer_as_an_unregistered_phone(self):
        response = self.anon().post(SETUP, {"mobile": "+91 99999 99999", "setup_code": "12345678", "passcode": "4827"}, format="json")

        self.assertEqual((401, "DEVICE_NOT_REGISTERED"), (response.status_code, response.data["code"]))

    def test_five_wrong_codes_lock_the_account(self):
        self.code_for()

        for _ in range(4):
            self.anon().post(SETUP, {"mobile": MOBILE, "setup_code": "00000000", "passcode": "4827"}, format="json")

        fifth = self.anon().post(SETUP, {"mobile": MOBILE, "setup_code": "00000000", "passcode": "4827"}, format="json")
        self.assertEqual(401, fifth.status_code)

        locked = self.anon().post(SETUP, {"mobile": MOBILE, "setup_code": self.code_for(), "passcode": "4827"}, format="json")
        self.assertEqual((423, "ACCOUNT_LOCKED"), (locked.status_code, locked.data["code"]))

    def test_who_may_issue_a_code(self):
        url = f"/api/v1/staff/{self.attendant_profile.id}/attendant/setup-code"

        self.assertEqual(403, self.as_user(self.f["teacher"]).post(url).status_code)
        stranger = self.ready_route()["admin"]
        self.assertEqual(403, self.as_user(stranger).post(url).status_code)

        teacher_profile = factories.StaffProfileFactory(school=self.f["school"], user=self.f["teacher"])
        not_one = self.as_user(self.f["admin"]).post(f"/api/v1/staff/{teacher_profile.id}/attendant/setup-code")
        self.assertEqual((422, "NOT_AN_ATTENDANT"), (not_one.status_code, not_one.data["code"]))

    def test_a_switched_off_account_gets_no_code(self):
        User.objects.filter(pk=self.attendant.pk).update(status="inactive")

        response = self.as_user(self.f["admin"]).post(f"/api/v1/staff/{self.attendant_profile.id}/attendant/setup-code")

        self.assertEqual(422, response.status_code)


# -- signing in ------------------------------------------------------------------


class SigningIn(AttendantTest):
    def setUp(self):
        super().setUp()
        _token, self.secret = self.register()

    def test_mobile_passcode_and_device_sign_in_whatever_spacing_the_number_has(self):
        response = self.login(secret=self.secret, mobile="+919876543210")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("BUS_ATTENDANT", response.data["user"]["role"])
        self.assertEqual("manage", response.data["user"]["permissions"]["transport"])
        self.assertEqual("none", response.data["user"]["permissions"]["students"])

    def test_the_passcode_alone_is_not_enough(self):
        for secret in (None, "not-a-registered-device-secret-0000000000"):
            with self.subTest(secret=secret):
                response = self.login(secret=secret)

                self.assertIn(response.status_code, (401, 422))

        # Guessing without the phone is not even counted - there was no check.
        self.assertEqual(0, AttendantCredential.objects.get(user=self.attendant).failed_attempts)

    def test_another_attendants_phone_does_not_sign_this_one_in(self):
        other = self.make_attendant("+91 92222 33333")
        _token, other_secret = self.register(mobile="+91 92222 33333", profile=other)

        response = self.login(secret=other_secret)

        self.assertEqual("DEVICE_NOT_REGISTERED", response.data["code"])

    def test_wrong_passcodes_say_how_many_tries_are_left_and_five_lock_it_for_good(self):
        first = self.login(passcode="0000", secret=self.secret)
        self.assertEqual(("WRONG_PASSCODE", "Wrong passcode. 4 tries left."), (first.data["code"], first.data["message"]))

        for _ in range(3):
            self.login(passcode="0000", secret=self.secret)

        fifth = self.login(passcode="0000", secret=self.secret)
        self.assertEqual((423, "ACCOUNT_LOCKED"), (fifth.status_code, fifth.data["code"]))

        # The right passcode does not undo it, and neither does waiting.
        self.assertEqual(423, self.login(secret=self.secret).status_code)
        self.assertTrue(AuditLog.objects.filter(action="user.locked").exists())

    def test_an_admin_unlocks_it(self):
        for _ in range(5):
            self.login(passcode="0000", secret=self.secret)

        unlocked = self.as_user(self.f["admin"]).post(f"/api/v1/users/{self.attendant.id}/unlock")
        self.assertEqual(200, unlocked.status_code, unlocked.data)

        self.assertEqual(200, self.login(secret=self.secret).status_code)

    def test_a_good_sign_in_starts_the_count_again(self):
        self.login(passcode="0000", secret=self.secret)
        self.login(secret=self.secret)

        self.assertEqual(0, AttendantCredential.objects.get(user=self.attendant).failed_attempts)

    def test_a_switched_off_account_is_told_so(self):
        User.objects.filter(pk=self.attendant.pk).update(status="inactive")

        self.assertEqual(403, self.login(secret=self.secret).status_code)


class Devices(AttendantTest):
    def test_an_admin_sees_the_phones_and_revokes_a_lost_one(self):
        token, secret = self.register()
        url = f"/api/v1/staff/{self.attendant_profile.id}/attendant"

        seen = self.as_user(self.f["admin"]).get(url)
        self.assertEqual(200, seen.status_code, seen.data)
        self.assertEqual(("+919876543210", True, False), (seen.data["login_mobile"], seen.data["has_passcode"], seen.data["is_locked"]))
        self.assertEqual(["Ravi's phone"], [device["name"] for device in seen.data["devices"]])
        self.assertNotIn("passcode", seen.data)

        device_id = seen.data["devices"][0]["id"]
        revoked = self.as_user(self.f["admin"]).delete(f"{url}/devices/{device_id}")
        self.assertEqual(200, revoked.status_code)
        self.assertFalse(revoked.data["devices"][0]["is_active"])

        self.assertEqual(401, self.phone(token).get("/api/v1/me").status_code, "its session ended")
        self.assertEqual("DEVICE_NOT_REGISTERED", self.login(secret=secret).data["code"])

    def test_another_schools_admin_cannot_see_or_revoke(self):
        self.register()
        stranger = self.ready_route()["admin"]
        url = f"/api/v1/staff/{self.attendant_profile.id}/attendant"
        device = AttendantDevice.objects.get(user=self.attendant)

        self.assertEqual(403, self.as_user(stranger).get(url).status_code)
        self.assertEqual(403, self.as_user(stranger).delete(f"{url}/devices/{device.id}").status_code)
        self.assertIsNone(AttendantDevice.objects.get(pk=device.pk).revoked_at)


# -- what an attendant reaches ------------------------------------------------------


class Reach(AttendantTest):
    def test_they_start_and_run_their_own_route(self):
        started = self.start(user=self.attendant)

        self.assertEqual(201, started.status_code, started.data)
        self.assertEqual(200, self.act(started.data["id"], f"/stops/{self.f['stops'][0].id}/reached", self.attendant).status_code)

    def test_they_do_not_touch_another_route(self):
        self.assertEqual(403, self.start(user=self.attendant, route=self.other["route"]).status_code)

        other_trip = self.start(user=self.f["manager"], route=self.other["route"]).data["id"]
        self.assertEqual(403, self.as_user(self.attendant).get(f"{TRIPS}/{other_trip}").status_code)
        self.assertEqual(403, self.rider(other_trip, self.other["students"][0], "boarded", self.attendant).status_code)

        listed = self.as_user(self.attendant).get(TRIPS).data["data"]
        self.assertNotIn(other_trip, [trip["id"] for trip in listed])

    def test_they_do_not_browse_the_fleet_or_the_roll(self):
        client = self.as_user(self.attendant)

        for url in ("/api/v1/transport/vehicles", "/api/v1/transport/drivers", "/api/v1/transport/routes",
                    f"/api/v1/transport/routes/{self.f['route'].id}", "/api/v1/students"):
            with self.subTest(url=url):
                self.assertEqual(403, client.get(url).status_code)

    def test_my_routes_lists_only_theirs_with_todays_trips(self):
        self.start(user=self.attendant)

        response = self.as_user(self.attendant).get("/api/v1/transport/my-routes")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("2026-09-09", response.data["date"])
        self.assertEqual(["Green Park"], [route["name"] for route in response.data["routes"]])
        today = response.data["routes"][0]["today"]
        self.assertEqual(("in_progress", None), (today["pickup"]["status"], today["drop"]))

        self.assertEqual(403, self.as_user(self.f["manager"]).get("/api/v1/transport/my-routes").status_code)

    def test_they_apply_for_their_own_leave_and_see_their_dashboard(self):
        client = self.as_user(self.attendant)

        self.assertEqual(200, client.get("/api/v1/dashboard").status_code)
        applied = client.post("/api/v1/leaves", {
            "leave_type": "casual", "start_date": "2026-09-14", "end_date": "2026-09-14", "reason": "Family function.",
        }, format="json")
        self.assertEqual(201, applied.status_code, applied.data)

    def test_the_matrix_has_a_column_for_them(self):
        matrix = self.as_user(self.f["admin"]).get("/api/v1/settings/permissions").data

        self.assertIn("BUS_ATTENDANT", [role["value"] for role in matrix["roles"]])
        self.assertEqual("manage", matrix["defaults"]["BUS_ATTENDANT"]["transport"])


class AssigningToARoute(AttendantTest):
    def test_an_admin_assigns_an_attendant_of_the_same_school(self):
        other = self.make_attendant("+91 93333 44444")

        response = self.as_user(self.f["admin"]).patch(
            f"/api/v1/transport/routes/{self.other['route'].id}", {"attendant_user_id": other.user_id}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual((other.user_id, "Ravi Kumar"), (response.data["attendant_user_id"], response.data["attendant_name"]))

    def test_anybody_else_is_refused(self):
        stranger_school = self.ready_route()
        foreign = self.make_attendant("+91 94444 55555", school=stranger_school)
        sentence = "The selected attendant is not an active Bus Attendant of this school."

        for user_id in (self.f["teacher"].id, foreign.user_id):
            with self.subTest(user_id=user_id):
                response = self.as_user(self.f["admin"]).patch(
                    f"/api/v1/transport/routes/{self.other['route'].id}", {"attendant_user_id": user_id}, format="json"
                )
                self.assertEqual([sentence], response.data["details"]["errors"]["attendant_user_id"])


# -- marks made offline ----------------------------------------------------------


class Syncing(AttendantTest):
    def setUp(self):
        super().setUp()
        self.trip_id = self.start(user=self.attendant).data["id"]
        # The bus left an hour ago; the marks below were made along the way.
        TransportTrip.objects.filter(pk=self.trip_id).update(started_at=WEDNESDAY - dt.timedelta(hours=1))
        self.arjun, self.aarav, self.meera = self.f["students"]
        self.lake_view, self.central_park = self.f["stops"]

    def sync(self, operations, user=None):
        return self.as_user(user or self.attendant).post(
            f"{TRIPS}/{self.trip_id}/sync", {"operations": operations}, format="json"
        )

    def op(self, client_id, kind, minutes, stop=None, student=None):
        return {"client_id": client_id, "type": kind, "occurred_at": at(minutes),
                "stop_id": stop.id if stop else None, "student_id": student.id if student else None}

    def test_a_batch_is_applied_in_order_with_the_times_it_happened(self):
        response = self.sync([
            self.op("mark-0001", "stop_reached", -20, stop=self.lake_view),
            self.op("mark-0002", "boarded", -19, student=self.arjun),
            self.op("mark-0003", "absent", -18, student=self.aarav),
        ])

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(["applied"] * 3, [result["status"] for result in response.data["results"]])

        rider = TransportTripRider.objects.get(trip_id=self.trip_id, student=self.arjun)
        self.assertEqual(WEDNESDAY - dt.timedelta(minutes=19), rider.boarded_at)
        self.assertEqual(
            {"mark-0001", "mark-0002", "mark-0003"},
            set(TransportTripEvent.objects.filter(trip_id=self.trip_id).exclude(client_id=None).values_list("client_id", flat=True)),
        )

    def test_the_guardians_alert_says_when_the_child_really_boarded(self):
        self.sync([self.op("mark-0001", "boarded", -45, student=self.arjun)])

        alert = Message.objects.get(event="transport.boarded", student=self.arjun)
        # 06:45 UTC on the frozen morning, in the school's zone.
        from school.clock import SchoolClock, TIME

        expected = SchoolClock.for_school(self.f["school"].id).format(WEDNESDAY - dt.timedelta(minutes=45), TIME)
        self.assertIn(expected, alert.body)

    def test_a_batch_sent_twice_is_recorded_once(self):
        batch = [self.op("mark-0001", "boarded", -5, student=self.arjun), self.op("mark-0002", "absent", -4, student=self.aarav)]
        self.sync(batch)
        events = TransportTripEvent.objects.count()
        alerts = Message.objects.count()

        again = self.sync(batch)

        self.assertEqual(["duplicate", "duplicate"], [result["status"] for result in again.data["results"]])
        self.assertEqual((events, alerts), (TransportTripEvent.objects.count(), Message.objects.count()))

    def test_one_mark_that_cannot_apply_does_not_lose_the_rest(self):
        response = self.sync([
            self.op("mark-0001", "absent", -10, student=self.arjun),
            self.op("mark-0002", "boarded", -9, student=self.arjun),
            self.op("mark-0003", "boarded", -8, student=self.aarav),
        ])

        self.assertEqual(["applied", "rejected", "applied"], [result["status"] for result in response.data["results"]])
        self.assertEqual("Already marked absent; it cannot be changed to boarded.", response.data["results"][1]["reason"])

    def test_marks_too_old_in_the_future_or_before_the_trip_are_refused(self):
        response = self.sync([
            self.op("mark-0001", "boarded", -13 * 60, student=self.arjun),
            self.op("mark-0002", "boarded", 30, student=self.aarav),
        ])
        TransportTrip.objects.filter(pk=self.trip_id).update(started_at=WEDNESDAY - dt.timedelta(minutes=5))
        before = self.sync([self.op("mark-0003", "boarded", -30, student=self.meera)])

        reasons = [result["reason"] for result in response.data["results"]] + [before.data["results"][0]["reason"]]
        self.assertEqual(
            ["This mark is more than 12 hours old and was not recorded.",
             "The phone's clock is ahead of the school's; check its date and time.",
             "This mark is from before the trip started."],
            reasons,
        )

    def test_a_stop_or_student_not_on_this_trip_is_refused(self):
        response = self.sync([
            self.op("mark-0001", "stop_reached", -3, stop=self.other["stops"][0]),
            self.op("mark-0002", "boarded", -2, student=self.other["students"][0]),
        ])

        self.assertEqual(
            ["That stop is not on this trip's route.", "That student is not on this trip."],
            [result["reason"] for result in response.data["results"]],
        )

    def test_once_the_office_ends_the_trip_later_marks_are_refused(self):
        self.act(self.trip_id, "/end", self.f["admin"])

        response = self.sync([self.op("mark-0001", "boarded", -1, student=self.arjun)])

        self.assertEqual("The trip had already ended, so this mark was not recorded.", response.data["results"][0]["reason"])

    def test_what_the_office_already_marked_is_accepted_once_without_a_second_alert(self):
        self.rider(self.trip_id, self.arjun, "boarded", self.f["manager"])
        alerts = Message.objects.count()

        response = self.sync([self.op("mark-0001", "boarded", -1, student=self.arjun)])

        self.assertEqual("applied", response.data["results"][0]["status"])
        self.assertEqual(alerts, Message.objects.count())

    def test_ending_the_trip_from_the_phone(self):
        on_board = self.sync([self.op("mark-0001", "boarded", -3, student=self.arjun), self.op("mark-0002", "end", -2)])
        self.assertEqual("rejected", on_board.data["results"][1]["status"])

        done = self.sync([self.op("mark-0003", "dropped", -1, student=self.arjun), self.op("mark-0004", "end", 0)])

        self.assertEqual(["applied", "applied"], [result["status"] for result in done.data["results"]])
        self.assertEqual("completed", done.data["trip"]["status"])

    def test_calling_a_guardian_is_on_the_timeline_and_audited(self):
        self.sync([self.op("mark-0001", "guardian_called", -1, student=self.aarav)])

        event = TransportTripEvent.objects.get(trip_id=self.trip_id, type="guardian_called")
        self.assertEqual(("Aarav Mehta", f"Called {self.aarav.guardian_name}"), (event.student_name, event.note))
        self.assertTrue(AuditLog.objects.filter(action="transport_trip.guardian_called").exists())

    def test_a_malformed_batch_is_refused_whole(self):
        response = self.sync([
            {"client_id": "short", "type": "boarded", "occurred_at": at(0), "student_id": self.arjun.id},
            {"client_id": "mark-0002", "type": "teleported", "occurred_at": at(0)},
            {"client_id": "mark-0003", "type": "boarded", "occurred_at": "2026-09-09T07:00:00", "student_id": self.arjun.id},
            {"client_id": "mark-0004", "type": "stop_reached", "occurred_at": at(0)},
        ])

        self.assertEqual(422, response.status_code)
        self.assertEqual(4, len(response.data["details"]["errors"]["operations"]))

        repeated = self.sync([self.op("mark-0001", "absent", 0, student=self.arjun), self.op("mark-0001", "absent", 0, student=self.aarav)])
        self.assertEqual(["Each mark in a batch needs its own client_id."], repeated.data["details"]["errors"]["operations"])

    def test_another_routes_attendant_cannot_sync_here(self):
        other = self.make_attendant("+91 95555 66666")
        self.other["route"].attendant_user = other.user
        self.other["route"].save()

        self.assertEqual(403, self.sync([self.op("mark-0001", "absent", 0, student=self.arjun)], user=other.user).status_code)


# -- where the bus is -------------------------------------------------------------


class Positions(AttendantTest):
    def setUp(self):
        super().setUp()
        self.trip_id = self.start(user=self.attendant).data["id"]
        TransportTrip.objects.filter(pk=self.trip_id).update(started_at=WEDNESDAY - dt.timedelta(hours=1))
        self.lake_view = self.f["stops"][0]
        self.lake_view.latitude, self.lake_view.longitude = "18.5300000", "73.8500000"
        self.lake_view.save()

    def send(self, points, user=None):
        return self.as_user(user or self.attendant).post(f"{TRIPS}/{self.trip_id}/locations", {"points": points}, format="json")

    def point(self, minutes, lat="18.5200000", lng="73.8500000", accuracy=12):
        return {"latitude": lat, "longitude": lng, "accuracy": accuracy, "speed": 8.5, "heading": 90, "recorded_at": at(minutes)}

    def test_positions_are_kept_and_the_latest_one_is_live_with_the_distance_to_the_next_stop(self):
        response = self.send([self.point(-1), self.point(0, lat="18.5210000")])

        self.assertEqual({"accepted": 2, "refused": 0}, response.data)

        live = self.as_user(self.f["teacher"]).get(f"{TRIPS}/{self.trip_id}/live")
        self.assertEqual(200, live.status_code, live.data)
        self.assertEqual(("18.5210000", 0, False), (
            live.data["position"]["latitude"], live.data["position"]["age_seconds"], live.data["position"]["is_stale"],
        ))
        self.assertEqual("Lake View", live.data["next_stop"]["name"])
        # 0.009 degrees of latitude is almost exactly a kilometre.
        self.assertAlmostEqual(1000, live.data["next_stop"]["straight_line_distance_m"], delta=15)

    def test_an_inaccurate_or_ill_timed_point_is_counted_not_kept(self):
        TransportTrip.objects.filter(pk=self.trip_id).update(started_at=WEDNESDAY - dt.timedelta(minutes=5))

        response = self.send([self.point(0, accuracy=500), self.point(-30), self.point(10), self.point(0)])

        self.assertEqual({"accepted": 1, "refused": 3}, response.data)

    def test_sharing_is_audited_once_not_per_point(self):
        self.send([self.point(-1)])
        self.send([self.point(0)])

        self.assertEqual(1, AuditLog.objects.filter(action="transport_trip.location_shared").count())

    def test_only_a_running_trip_takes_positions_and_only_from_whoever_runs_it(self):
        self.assertEqual(403, self.send([self.point(0)], user=self.f["teacher"]).status_code)

        self.act(self.trip_id, "/end", self.f["admin"])
        self.assertEqual(409, self.send([self.point(0)]).status_code)

    def test_a_stranger_does_not_see_where_the_bus_is(self):
        stranger = self.ready_route()["admin"]

        self.assertEqual(403, self.as_user(stranger).get(f"{TRIPS}/{self.trip_id}/live").status_code)

    def test_old_positions_are_purged_after_thirty_days(self):
        self.send([self.point(0)])
        TransportTripLocation.objects.update(recorded_at=WEDNESDAY - dt.timedelta(days=31))

        self.assertEqual(1, TripLocationService.purge())
        self.assertFalse(TransportTripLocation.objects.exists())


class StopPositions(AttendantTest):
    def setUp(self):
        super().setUp()
        self.f["school"].latitude, self.f["school"].longitude = "18.5204000", "73.8567000"
        self.f["school"].save()
        self.url = f"/api/v1/transport/stops/{self.f['stops'][0].id}"

    def test_a_stop_gets_a_position_near_its_school(self):
        response = self.as_user(self.f["admin"]).patch(self.url, {"latitude": "18.5300000", "longitude": "73.8500000"}, format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(("18.5300000", "73.8500000"), (response.data["latitude"], response.data["longitude"]))

    def test_half_a_position_is_refused(self):
        response = self.as_user(self.f["admin"]).patch(self.url, {"latitude": "18.53"}, format="json")

        self.assertEqual(["Enter a longitude as well, or clear the latitude."], response.data["details"]["errors"]["longitude"])

    def test_a_stop_far_from_its_school_is_caught(self):
        # Latitude and longitude swapped - the usual mistake.
        response = self.as_user(self.f["admin"]).patch(self.url, {"latitude": "73.8500000", "longitude": "18.5300000"}, format="json")

        self.assertEqual(422, response.status_code)
        self.assertIn("wrong way round", response.data["details"]["errors"]["latitude"][0])

    def test_an_attendant_cannot_move_stops(self):
        self.assertEqual(403, self.as_user(self.attendant).patch(self.url, {"latitude": "18.53", "longitude": "73.85"}, format="json").status_code)
