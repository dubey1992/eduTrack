"""Creates the platform's first Super Admin (docs/deployment.md, step 4).

    python manage.py create_super_admin

The account that onboards the first school, and the only way into a freshly
deployed instance. The Laravel side has done this since the beginning
(database/seeders/SuperAdminSeeder.php); this is the same job on the backend
that actually gets deployed.

**Read from the environment, never from this file.** The repository is not a
safe place for a live credential: anybody who can read a commit could
otherwise sign in as the platform owner. There is deliberately no default
password - a known one on a public host is an open door.

**Safe to run again.** A later deploy re-runs the whole setup, and an account
that already exists is left exactly as it is, so a password the owner has
since changed is never silently reset back to whatever the environment
happens to say.
"""

import os

from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone
from rest_framework import serializers

from school import hashing
from school.enums import UserRole, UserStatus
from school.models import User
from school.validation import PASSWORD_MIN_LENGTH, password_rules


class Command(BaseCommand):
    help = "Create the first Super Admin from SUPER_ADMIN_EMAIL and SUPER_ADMIN_PASSWORD"

    def handle(self, *args, **options):
        email = (os.environ.get("SUPER_ADMIN_EMAIL") or "super.admin@school365ai.com").strip()
        password = os.environ.get("SUPER_ADMIN_PASSWORD") or ""

        if not password:
            raise CommandError(
                "SUPER_ADMIN_PASSWORD is not set. Add it to the environment before "
                "running this; there is deliberately no default, because a known "
                "password on a public host is an open door."
            )

        # Held to the policy the app enforces on everybody else. The first
        # account on the platform is the one with the most to lose, and it is
        # the one account no screen ever validates.
        self._check(password)

        existing = User.objects.filter(email__iexact=email).first()

        if existing is not None:
            self.stdout.write(f"Super Admin {email} already exists (id {existing.id}) - left untouched.")
            return

        now = timezone.now()
        created = User.objects.create(
            first_name=(os.environ.get("SUPER_ADMIN_FIRST_NAME") or "Super").strip(),
            last_name=(os.environ.get("SUPER_ADMIN_LAST_NAME") or "Admin").strip(),
            email=email,
            mobile=os.environ.get("SUPER_ADMIN_MOBILE") or None,
            password=hashing.make(password),
            role=UserRole.SUPER_ADMIN,
            status=UserStatus.ACTIVE,
            school_id=None,
            is_sub_admin=False,
            must_change_password=False,
            created_at=now,
            updated_at=now,
        )

        # The email and the id, and nothing else. Never the password, and
        # never a hash of it: this goes to a terminal, a deploy log, and
        # whatever is scrolling behind somebody at the time.
        self.stdout.write(f"Super Admin created: {created.email} (id {created.id}).")
        self.stdout.write("Sign in, change the password, then clear SUPER_ADMIN_PASSWORD out of the environment.")

    @staticmethod
    def _check(password: str) -> None:
        """The same rules a password typed into the app has to pass.

        Raised as a CommandError rather than a validation error, because the
        reader is an operator at a shell, not a form.
        """
        problems = []

        if len(password) < PASSWORD_MIN_LENGTH:
            problems.append(f"The password must be at least {PASSWORD_MIN_LENGTH} characters.")

        try:
            password_rules(password)
        except serializers.ValidationError as refused:
            problems.extend(str(each) for each in refused.detail)

        if problems:
            raise CommandError("SUPER_ADMIN_PASSWORD is not acceptable: " + " ".join(problems))
