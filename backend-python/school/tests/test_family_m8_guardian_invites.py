"""A second guardian, asked for by a parent (docs/mobile-apps-review.md, M8,
8.5): the parent asks, the school office approves or declines, and nobody is
linked to a child until it approves.
"""

from rest_framework.test import APIClient

from school import factories
from school.enums import UserRole
from school.models import AuditLog, GuardianInvite, GuardianStudent

from . import test_family_f1_api as f1

FAMILY = f1.FAMILY
OFFICE = "/api/v1/guardian-invites"
FATHER = "+91 91234 56780"


class InviteTest(f1.FamilyAppTest):
    def ask(self, child=None, **fields):
        body = {"name": "Rohan Sharma", "mobile": FATHER, "relationship": "father", **fields}
        return self.parent.post(f"{FAMILY}/children/{(child or self.child).id}/guardian-invites", body, format="json")

    def asked(self):
        response = self.ask()
        self.assertEqual(201, response.status_code, response.data)
        return GuardianInvite.objects.get(pk=response.data["id"])

    def office(self, user=None):
        return self.as_user(user or self.admin)


class AParentAsks(InviteTest):
    def test_the_request_waits_for_the_school_and_the_parent_sees_it(self):
        response = self.ask()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(("Rohan Sharma", "father", "pending"), (
            response.data["name"], response.data["relationship"], response.data["status"]))
        self.assertNotIn("mobile", response.data)
        listed = self.parent.get(f"{FAMILY}/children/{self.child.id}/guardian-invites").data["data"]
        self.assertEqual(["pending"], [row["status"] for row in listed])
        # Nothing is linked until the school agrees.
        self.assertEqual(1, GuardianStudent.objects.filter(student=self.child).count())

    def test_name_mobile_and_relationship_are_needed(self):
        for fields in ({"name": ""}, {"mobile": ""}, {"relationship": "uncle"}):
            response = self.ask(**fields)
            self.assertEqual(422, response.status_code, fields)

    def test_the_same_person_cannot_be_asked_for_twice_while_pending(self):
        self.asked()

        response = self.ask(name="Rohan")

        self.assertEqual(422, response.status_code)
        self.assertIn("already asked", response.data["message"])

    def test_somebody_already_a_guardian_cannot_be_asked_for(self):
        response = self.ask(mobile=f1.MOBILE)

        self.assertEqual(422, response.status_code)
        self.assertIn("already a guardian", response.data["message"])

    def test_no_more_than_three_waiting_at_once(self):
        for n in range(3):
            self.assertEqual(201, self.ask(mobile=f"+91 91234 5678{n}").status_code)

        self.assertEqual(422, self.ask(mobile="+91 91234 56789").status_code)

    def test_another_familys_child_is_a_404(self):
        self.assertEqual(404, self.ask(child=self.other_family_child()).status_code)

    def test_signing_in_is_required(self):
        response = APIClient().post(f"{FAMILY}/children/{self.child.id}/guardian-invites", {}, format="json")

        self.assertEqual(401, response.status_code)


class TheOfficeDecides(InviteTest):
    def test_the_office_sees_what_is_waiting_with_the_child_and_who_asked(self):
        self.asked()

        response = self.office().get(OFFICE)

        self.assertEqual(200, response.status_code, response.data)
        [row] = response.data["data"]
        self.assertEqual((self.child.id, "Rohan Sharma"), (row["student_id"], row["name"]))
        self.assertIn("9123456780", row["mobile"].replace(" ", ""))
        self.assertEqual(self.parent_user.name, row["requested_by_name"])

    def test_approving_links_the_guardian_with_the_same_rights_as_any(self):
        invite = self.asked()

        response = self.office().post(f"{OFFICE}/{invite.id}/approve")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("approved", response.data["data"]["status"])
        link = GuardianStudent.objects.get(pk=response.data["data"]["guardian_link_id"])
        self.assertEqual((self.child.id, "father", False), (link.student_id, link.relationship, link.is_primary))
        self.assertEqual("approved", self.parent.get(f"{FAMILY}/children/{self.child.id}/guardian-invites")
                         .data["data"][0]["status"])
        self.assertTrue(AuditLog.objects.filter(action="guardian_invite.approved").exists())

    def test_declining_links_nobody(self):
        invite = self.asked()

        response = self.office().post(f"{OFFICE}/{invite.id}/decline")

        self.assertEqual(("declined", None), (response.data["data"]["status"], response.data["data"]["guardian_link_id"]))
        self.assertEqual(1, GuardianStudent.objects.filter(student=self.child).count())

    def test_a_decided_request_cannot_be_decided_again(self):
        invite = self.asked()
        self.office().post(f"{OFFICE}/{invite.id}/decline")

        response = self.office().post(f"{OFFICE}/{invite.id}/approve")

        self.assertEqual(422, response.status_code)
        self.assertEqual(1, GuardianStudent.objects.filter(student=self.child).count())

    def test_a_teacher_may_not_decide(self):
        invite = self.asked()
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(403, self.office(teacher).post(f"{OFFICE}/{invite.id}/approve").status_code)
        self.assertEqual(403, self.office(teacher).get(OFFICE).status_code)

    def test_another_school_sees_none_and_may_not_decide(self):
        invite = self.asked()
        elsewhere = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)

        self.assertEqual([], self.office(elsewhere).get(OFFICE).data["data"])
        self.assertIn(self.office(elsewhere).post(f"{OFFICE}/{invite.id}/approve").status_code, (403, 404))
        self.assertEqual("pending", GuardianInvite.objects.get(pk=invite.id).status)

    def test_the_list_filters_by_status(self):
        invite = self.asked()
        self.office().post(f"{OFFICE}/{invite.id}/approve")

        self.assertEqual([], self.office().get(OFFICE).data["data"])
        self.assertEqual(1, len(self.office().get(OFFICE, {"status": "approved"}).data["data"]))
        self.assertEqual(422, self.office().get(OFFICE, {"status": "lost"}).status_code)
