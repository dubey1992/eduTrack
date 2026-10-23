"""Which origins the API accepts, read from the one .env both stacks share.

The trap these guard: Laravel's CORS_ALLOWED_ORIGINS set, Django's
DJANGO_CORS_ORIGINS not, and Django silently keeping its development default
on a live server. That is exactly what happened on the first deployment.
"""

from django.test import SimpleTestCase

from config.cors import DEVELOPMENT, allowed_origins


class AllowedOrigins(SimpleTestCase):
    def test_djangos_own_key_wins(self):
        env = {"DJANGO_CORS_ORIGINS": "https://a.example", "CORS_ALLOWED_ORIGINS": "https://b.example"}
        self.assertEqual(["https://a.example"], allowed_origins(env))

    def test_laravels_key_is_honoured_when_djangos_is_absent(self):
        """The one that bit: a live .env with only the Laravel key."""
        env = {"CORS_ALLOWED_ORIGINS": "https://school365ai.com,https://www.school365ai.com"}
        self.assertEqual(["https://school365ai.com", "https://www.school365ai.com"], allowed_origins(env))

    def test_laravels_wildcard_is_not_an_origin(self):
        """`*` is what the example ships with; it must never reach a live
        server as 'allow everything', and django-cors-headers would refuse
        it as an origin anyway."""
        self.assertEqual(DEVELOPMENT.split(","), allowed_origins({"CORS_ALLOWED_ORIGINS": "*"}))

    def test_nothing_set_means_development(self):
        self.assertEqual(DEVELOPMENT.split(","), allowed_origins({}))

    def test_whitespace_and_empty_entries_are_dropped(self):
        env = {"DJANGO_CORS_ORIGINS": " https://a.example , ,https://b.example "}
        self.assertEqual(["https://a.example", "https://b.example"], allowed_origins(env))
