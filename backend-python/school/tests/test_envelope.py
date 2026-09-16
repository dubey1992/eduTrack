"""The envelope, on the paths that never reach a view.

Found by the contract suite on its first run against this backend: asking for
an endpoint that is not ported yet returned an HTML page, and the Flutter
client reads that as a parse failure rather than as a 404. Every path under
the API has to answer `{code, message, details}` - including the 143 this
backend cannot serve yet.
"""

from django.test import TestCase, override_settings

from school import factories, tokens


# DEBUG is on in development, and with it on Django shows its own
# route-listing page instead of calling handler404. Production runs with it
# off, so that is what this asserts.
@override_settings(DEBUG=False, ALLOWED_HOSTS=["*"])
class AnUnknownPath(TestCase):
    def test_a_route_that_does_not_exist_is_json(self):
        response = self.client.get("/api/v1/schools")

        self.assertEqual(404, response.status_code)
        self.assertEqual("application/json", response["Content-Type"])
        self.assertEqual("NOT_FOUND", response.json()["code"])
        self.assertEqual({}, response.json()["details"])

    def test_an_endpoint_not_ported_yet_answers_the_same_way(self):
        # The case that matters while the port is half done: the client asks
        # for something Laravel serves and this backend does not, and has to
        # get a readable answer rather than a document.
        for path in ("/api/v1/payments", "/api/v1/staff", "/api/v1/attendance"):
            with self.subTest(path=path):
                response = self.client.get(path)

                self.assertEqual(404, response.status_code)
                self.assertEqual("NOT_FOUND", response.json()["code"])

    def test_a_signed_in_caller_gets_the_same_404(self):
        user = factories.UserFactory()

        response = self.client.get(
            "/api/v1/payments", HTTP_AUTHORIZATION="Bearer " + tokens.issue(user)
        )

        self.assertEqual(404, response.status_code)
        self.assertEqual("NOT_FOUND", response.json()["code"])
