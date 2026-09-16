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
    # Deliberately fictional rather than "an endpoint not ported yet". An
    # earlier version of this test used /api/v1/schools as its example and
    # started failing the moment schools were ported - the test rotting on
    # progress rather than on a bug. What is being asserted is that an
    # *unrouted* path answers the envelope, and a path that will never be a
    # route says that without a maintenance cost.
    NOWHERE = "/api/v1/there-is-no-such-thing"

    def test_a_route_that_does_not_exist_is_json(self):
        response = self.client.get(self.NOWHERE)

        self.assertEqual(404, response.status_code)
        self.assertEqual("application/json", response["Content-Type"])
        self.assertEqual("NOT_FOUND", response.json()["code"])
        self.assertEqual({}, response.json()["details"])

    def test_every_verb_answers_the_same_way(self):
        # The case that matters while the port is half done: the client asks
        # for something Laravel serves and this backend does not, and has to
        # get a readable answer rather than a document - whatever verb it used.
        for verb in ("get", "post", "patch", "put", "delete"):
            with self.subTest(verb=verb):
                response = getattr(self.client, verb)(self.NOWHERE)

                self.assertEqual(404, response.status_code)
                self.assertEqual("NOT_FOUND", response.json()["code"])

    def test_a_signed_in_caller_gets_the_same_404(self):
        user = factories.UserFactory()

        response = self.client.get(
            self.NOWHERE, HTTP_AUTHORIZATION="Bearer " + tokens.issue(user)
        )

        self.assertEqual(404, response.status_code)
        self.assertEqual("NOT_FOUND", response.json()["code"])
