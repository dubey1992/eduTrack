"""Guardians and family accounts (docs/parent-student-app.md, Phase F0).

Two halves, one set of rules (school/family.py):

- **GuardianService** is the school office's side. A student's guardians are
  people, linked to one or more students; the office adds, edits and unlinks
  them, records consent, and issues the one-time setup code a parent uses to
  register their phone. The student's own guardian columns stay the primary
  contact, and are kept in step with the primary link both ways.
- **FamilyAuthService** is the parent's side: register a phone with the setup
  code, sign in with mobile + passcode on that phone, sign out, and say who
  they are and which children they see.

Every sign-in attempt writes what it must - a wrong guess counted, a lock set
- before any error is raised, so a failure is recorded whatever happens next.
"""

from __future__ import annotations

import datetime as dt
import math

from django.db import transaction
from django.db.models import F
from django.utils import timezone

from . import audit, family, hashing, modules, tokens
from .enums import StudentStatus, UserRole, UserStatus
from .errors import (
    AccountInactive,
    DeviceNotRegistered,
    FamilyLocked,
    GuardianProblem,
    ModuleDisabled,
    SetupCodeRejected,
    WrongPasscode,
)
from .fields import as_utc
from .models import AuditLog, FamilyCredential, FamilyDevice, Guardian, GuardianStudent, Student, User

MODULE = "family_app"


def family_app_on(school_id) -> bool:
    return modules.is_enabled(school_id, MODULE)


def assert_family_app_on(school_id) -> None:
    if not family_app_on(school_id):
        raise ModuleDisabled(modules.get(MODULE).label)


class GuardianService:
    """The school office's side of guardians."""

    @staticmethod
    def links_of(student: Student):
        """The student's guardians, the primary contact first."""
        return (
            GuardianStudent.objects.select_related("guardian", "guardian__user")
            .filter(student_id=student.id)
            .order_by("-is_primary", "guardian__name", "id")
        )

    @staticmethod
    def find_or_make(school_id: int, name: str, mobile: str | None, email: str | None) -> Guardian:
        """The school's guardian with this number - the same person across
        siblings - or a new one. Without a number, always a new one: a name
        alone does not say two records are one person."""
        login = family.login_mobile(mobile)
        now = timezone.now()

        if login is not None:
            found = Guardian.objects.filter(school_id=school_id, login_mobile=login).first()
            if found is not None:
                if email and not found.email:
                    Guardian.objects.filter(pk=found.pk).update(email=email, updated_at=now)
                    found.email = email
                return found

        return Guardian.objects.create(
            school_id=school_id, name=name.strip()[:150], login_mobile=login, email=email or None,
            created_at=now, updated_at=now,
        )

    @classmethod
    def add(cls, student: Student, data: dict, actor: User) -> GuardianStudent:
        with transaction.atomic():
            guardian = cls.find_or_make(student.school_id, data["name"], data.get("mobile"), data.get("email"))

            if GuardianStudent.objects.filter(guardian_id=guardian.id, student_id=student.id).exists():
                raise GuardianProblem("This guardian is already linked to the student.")

            primary = data.get("is_primary", False) or not GuardianStudent.objects.filter(student_id=student.id).exists()
            now = timezone.now()
            link = GuardianStudent.objects.create(
                guardian=guardian, student=student, relationship=data.get("relationship") or "guardian",
                is_primary=False, created_at=now, updated_at=now,
            )

            if primary:
                cls.make_primary(link)

            audit.record(action="guardian.linked", module="students", entity_type="student", entity_id=student.id,
                         school_id=student.school_id, new={"guardian_id": guardian.id, "name": guardian.name,
                                                            "relationship": link.relationship, "primary": primary})

        return GuardianStudent.objects.select_related("guardian").get(pk=link.pk)

    @classmethod
    def update(cls, link: GuardianStudent, data: dict, actor: User) -> GuardianStudent:
        """Edits the person (for every child they are linked to) and this
        link. A new number moves their sign-in with them."""
        guardian = link.guardian
        before = {"name": guardian.name, "mobile": guardian.login_mobile, "email": guardian.email,
                  "relationship": link.relationship, "primary": link.is_primary}
        now = timezone.now()

        with transaction.atomic():
            changes = {}
            if "name" in data:
                changes["name"] = data["name"].strip()[:150]
            if "email" in data:
                changes["email"] = data["email"] or None
            if "mobile" in data:
                login = family.login_mobile(data["mobile"])
                taken = (
                    login is not None
                    and Guardian.objects.filter(school_id=guardian.school_id, login_mobile=login)
                    .exclude(pk=guardian.pk).exists()
                )
                if taken:
                    raise GuardianProblem(
                        "Another guardian in this school already has that mobile number. "
                        "Link that guardian to the student instead."
                    )
                changes["login_mobile"] = login
                FamilyCredential.objects.filter(user_id=guardian.user_id).update(login_mobile=login or "",
                                                                                 updated_at=now)

            if changes:
                Guardian.objects.filter(pk=guardian.pk).update(updated_at=now, **changes)

            if "relationship" in data:
                GuardianStudent.objects.filter(pk=link.pk).update(relationship=data["relationship"], updated_at=now)

            link.refresh_from_db()
            if data.get("is_primary") or link.is_primary:
                # The student's columns describe the primary contact, so they
                # follow an edit to that person.
                cls.make_primary(link)

            audit.record(action="guardian.updated", module="students", entity_type="student",
                         entity_id=link.student_id, school_id=guardian.school_id, old=before,
                         new={**{k: v for k, v in changes.items() if k != "login_mobile"},
                              "mobile": changes.get("login_mobile", guardian.login_mobile),
                              "relationship": data.get("relationship", link.relationship)})

        return GuardianStudent.objects.select_related("guardian", "guardian__user").get(pk=link.pk)

    @classmethod
    def unlink(cls, link: GuardianStudent, actor: User) -> None:
        """Takes a guardian off one student. A guardian left with no children
        here can no longer sign in: their account is switched off and every
        session ends. The person stays on record."""
        guardian = link.guardian
        student = link.student

        if GuardianStudent.objects.filter(student_id=student.id).count() <= 1:
            raise GuardianProblem("A student needs at least one guardian. Add the new one before removing this one.")

        with transaction.atomic():
            was_primary = link.is_primary
            GuardianStudent.objects.filter(pk=link.pk).delete()

            if was_primary:
                successor = cls.links_of(student).first()
                if successor is not None:
                    cls.make_primary(successor)

            if not GuardianStudent.objects.filter(guardian_id=guardian.id).exists() and guardian.user_id:
                User.objects.filter(pk=guardian.user_id).update(status=UserStatus.INACTIVE, updated_at=timezone.now())
                tokens.revoke_all(guardian.user)
                FamilyDevice.objects.filter(user_id=guardian.user_id, revoked_at__isnull=True).update(
                    revoked_at=timezone.now(), updated_at=timezone.now()
                )

            audit.record(action="guardian.unlinked", module="students", entity_type="student", entity_id=student.id,
                         school_id=student.school_id, old={"guardian_id": guardian.id, "name": guardian.name})

    @staticmethod
    def make_primary(link: GuardianStudent) -> None:
        """This link becomes the student's primary contact, and the student's
        guardian columns - which alerts, imports and lists read - say so."""
        now = timezone.now()
        GuardianStudent.objects.filter(student_id=link.student_id).exclude(pk=link.pk).update(is_primary=False,
                                                                                              updated_at=now)
        GuardianStudent.objects.filter(pk=link.pk).update(is_primary=True, updated_at=now)
        guardian = Guardian.objects.get(pk=link.guardian_id)
        Student.objects.filter(pk=link.student_id).update(
            guardian_name=guardian.name, guardian_mobile=guardian.login_mobile, guardian_email=guardian.email,
            updated_at=now,
        )

    @classmethod
    def follow_student(cls, student: Student) -> None:
        """After the student's own guardian columns were written - the student
        form, an import - the primary link follows them. A different number is
        a different person: they become the primary contact, and the earlier
        one stays linked, no longer primary."""
        if not (student.guardian_name or "").strip():
            return

        login = family.login_mobile(student.guardian_mobile)
        primary = GuardianStudent.objects.select_related("guardian").filter(student_id=student.id,
                                                                           is_primary=True).first()
        now = timezone.now()

        if primary is not None and primary.guardian.login_mobile == login:
            Guardian.objects.filter(pk=primary.guardian_id).update(
                name=student.guardian_name.strip()[:150], email=student.guardian_email or primary.guardian.email,
                updated_at=now,
            )
            return

        guardian = cls.find_or_make(student.school_id, student.guardian_name, student.guardian_mobile,
                                    student.guardian_email)
        link = GuardianStudent.objects.filter(guardian_id=guardian.id, student_id=student.id).first()
        if link is None:
            link = GuardianStudent.objects.create(guardian=guardian, student=student, relationship="guardian",
                                                  is_primary=False, created_at=now, updated_at=now)

        GuardianStudent.objects.filter(student_id=student.id).exclude(pk=link.pk).update(is_primary=False,
                                                                                         updated_at=now)
        GuardianStudent.objects.filter(pk=link.pk).update(is_primary=True, updated_at=now)

    # -- the Family app, from the office ---------------------------------------

    @staticmethod
    def credential_of(guardian: Guardian) -> FamilyCredential | None:
        return FamilyCredential.objects.filter(user_id=guardian.user_id).first() if guardian.user_id else None

    @staticmethod
    def devices_of(guardian: Guardian):
        if not guardian.user_id:
            return FamilyDevice.objects.none()
        return FamilyDevice.objects.filter(user_id=guardian.user_id).order_by("-created_at", "-id")

    @classmethod
    def issue_setup_code(cls, guardian: Guardian, actor: User, consent: bool) -> tuple[str, dt.datetime]:
        """A fresh one-time code for the parent's letter, replacing any earlier
        one. Shown once, stored only as a hash. The first time, this makes the
        family account; it needs the school's Family app switched on, a mobile
        number to sign in with, and the guardian's consent noted."""
        assert_family_app_on(guardian.school_id)

        if not guardian.login_mobile:
            raise GuardianProblem("Add the guardian's mobile number first: it is what they sign in with.")

        if guardian.consent_at is None and not consent:
            raise GuardianProblem("Note that the guardian has agreed to use the Family app before issuing a code.")

        if not GuardianStudent.objects.filter(guardian_id=guardian.id, student__status=StudentStatus.ACTIVE).exists():
            raise GuardianProblem("This guardian has no student at the school today.")

        code = family.new_setup_code()
        now = timezone.now()
        expires = now + dt.timedelta(days=family.SETUP_CODE_DAYS)

        with transaction.atomic():
            if guardian.consent_at is None:
                Guardian.objects.filter(pk=guardian.pk).update(consent_at=now, consent_recorded_by_id=actor.id,
                                                               updated_at=now)

            user = cls.account_of(guardian, now)
            FamilyCredential.objects.update_or_create(
                user_id=user.id,
                defaults={
                    "school_id": guardian.school_id, "login_mobile": guardian.login_mobile,
                    "setup_code": hashing.make(code), "setup_code_expires_at": expires,
                    "setup_code_issued_by_id": actor.id, "updated_at": now,
                },
                create_defaults={
                    "school_id": guardian.school_id, "login_mobile": guardian.login_mobile,
                    "setup_code": hashing.make(code), "setup_code_expires_at": expires,
                    "setup_code_issued_by_id": actor.id, "created_at": now, "updated_at": now,
                },
            )
            audit.record(action="family.setup_code_issued", module="students", entity_type="guardian",
                         entity_id=guardian.id, school_id=guardian.school_id, new={"expires_at": expires})

        return code, expires

    @staticmethod
    def account_of(guardian: Guardian, now) -> User:
        """The guardian's family account, made the first time it is needed,
        and switched back on if unlinking had switched it off."""
        if guardian.user_id:
            User.objects.filter(pk=guardian.user_id).update(status=UserStatus.ACTIVE, updated_at=now)
            return User.objects.get(pk=guardian.user_id)

        first, _, last = guardian.name.partition(" ")
        user = User.objects.create(
            first_name=first or guardian.name, last_name=last, email=family.placeholder_email(),
            mobile=guardian.login_mobile, password=hashing.make(family.new_device_secret()),
            role=UserRole.PARENT, school_id=guardian.school_id, is_sub_admin=False, must_change_password=False,
            status=UserStatus.ACTIVE, created_at=now, updated_at=now,
        )
        Guardian.objects.filter(pk=guardian.pk).update(user_id=user.id, updated_at=now)
        guardian.user_id = user.id

        return user

    @staticmethod
    def revoke_device(guardian: Guardian, device: FamilyDevice) -> None:
        """A lost or replaced phone: it can no longer sign in, and every
        session of the account ends - a session cannot say which phone it was."""
        now = timezone.now()

        with transaction.atomic():
            FamilyDevice.objects.filter(pk=device.pk).update(revoked_at=now, updated_at=now)
            ended = tokens.revoke_all(guardian.user)
            audit.record(action="family.device_revoked", module="students", entity_type="guardian",
                         entity_id=guardian.id, school_id=guardian.school_id,
                         new={"device": device.name, "sessions_ended": ended})


class FamilyAuthService:
    """The parent's side: register a phone, sign in, sign out."""

    MODULE = "auth"

    @staticmethod
    def lock_minutes_left(credential: FamilyCredential) -> int:
        """Minutes until a lock lifts, 0 when there is none."""
        if credential.locked_at is None:
            return 0

        left = as_utc(credential.locked_at) + dt.timedelta(minutes=family.LOCK_MINUTES) - timezone.now()
        return max(0, math.ceil(left.total_seconds() / 60))

    @classmethod
    def assert_not_locked(cls, credential: FamilyCredential) -> None:
        minutes = cls.lock_minutes_left(credential)

        if minutes > 0:
            raise FamilyLocked(minutes)

        if credential.locked_at is not None:
            # The lock has run out: a fresh start.
            FamilyCredential.objects.filter(pk=credential.pk).update(locked_at=None, failed_attempts=0,
                                                                    updated_at=timezone.now())
            credential.locked_at = None
            credential.failed_attempts = 0

    @classmethod
    def count_failure(cls, credential: FamilyCredential) -> int:
        FamilyCredential.objects.filter(pk=credential.pk).update(failed_attempts=F("failed_attempts") + 1)
        attempts = FamilyCredential.objects.values_list("failed_attempts", flat=True).get(pk=credential.pk)
        user = credential.user

        audit.record(actor=user, action="user.sign_in_failed", module=cls.MODULE, entity_type="user",
                     entity_id=user.id, school_id=user.school_id, new={"attempts": attempts, "method": "family"})

        if attempts >= family.MAX_ATTEMPTS:
            FamilyCredential.objects.filter(pk=credential.pk).update(locked_at=timezone.now())
            audit.record(actor=user, action="user.locked", module=cls.MODULE, entity_type="user",
                         entity_id=user.id, school_id=user.school_id, new={"attempts": attempts, "method": "family"})

        return attempts

    @classmethod
    def count_setup_failure(cls, credential: FamilyCredential) -> None:
        """A wrong setup code: five since it was issued cancel it, and the
        office issues another. It never locks the account."""
        user = credential.user
        audit.record(actor=user, action="family.setup_failed", module=cls.MODULE, entity_type="user",
                     entity_id=user.id, school_id=user.school_id)

        issued_at = as_utc(credential.setup_code_expires_at) - dt.timedelta(days=family.SETUP_CODE_DAYS)
        attempts = AuditLog.objects.filter(action="family.setup_failed", entity_type="user", entity_id=user.id,
                                           created_at__gte=issued_at).count()

        if attempts >= family.MAX_ATTEMPTS:
            FamilyCredential.objects.filter(pk=credential.pk).update(setup_code=None, setup_code_expires_at=None,
                                                                    updated_at=timezone.now())

    @classmethod
    def setup(cls, mobile: str, setup_code: str, passcode: str, device_name: str | None, user_agent: str | None):
        """Registers this phone with the office's setup code and sets the
        passcode. Returns (user, token, device secret) - the secret, once.

        A parent with children in two schools has a code waiting in each; the
        code says which."""
        now = timezone.now()
        waiting = list(
            FamilyCredential.objects.select_related("user").filter(
                login_mobile=family.login_mobile(mobile), setup_code__isnull=False, setup_code_expires_at__gt=now
            )
        )
        matched = next((c for c in waiting if hashing.check(setup_code, c.setup_code)), None)

        if matched is None:
            if not waiting:
                # Nobody waiting: checked against a hash of nothing, so the
                # answer takes as long as a wrong code, and counted nowhere.
                hashing.check(setup_code, hashing.NO_SUCH_ACCOUNT)
            for credential in waiting:
                cls.count_setup_failure(credential)
            raise SetupCodeRejected()

        credential = matched
        cls.assert_not_locked(credential)
        user = credential.user

        if not user.is_active():
            raise AccountInactive()

        assert_family_app_on(user.school_id)

        secret = family.new_device_secret()
        name = (device_name or tokens.describe_device(user_agent) or "A phone")[:120]

        with transaction.atomic():
            FamilyCredential.objects.filter(pk=credential.pk).update(
                passcode=hashing.make(passcode), setup_code=None, setup_code_expires_at=None, failed_attempts=0,
                locked_at=None, updated_at=now,
            )
            FamilyDevice.objects.create(user_id=user.id, name=name, secret=family.device_digest(secret),
                                        last_used_at=now, created_at=now, updated_at=now)
            audit.record(actor=user, action="family.device_registered", module=cls.MODULE, entity_type="user",
                         entity_id=user.id, school_id=user.school_id, new={"device": name})
            token = tokens.issue(user, user_agent)

        return user, token, secret

    @classmethod
    def login(cls, mobile: str, passcode: str, device_secret: str, user_agent: str | None):
        """Mobile + passcode, on a phone registered to that number."""
        device = FamilyDevice.objects.filter(secret=family.device_digest(device_secret), revoked_at__isnull=True).first()
        credential = (
            FamilyCredential.objects.select_related("user")
            .filter(user_id=device.user_id, login_mobile=family.login_mobile(mobile)).first()
            if device is not None else None
        )

        # An unknown number and a phone not registered to it are one answer;
        # without a registered phone the passcode is not checked at all.
        if credential is None:
            raise DeviceNotRegistered()

        cls.assert_not_locked(credential)

        if not credential.passcode or not hashing.check(passcode, credential.passcode):
            attempts = cls.count_failure(credential)
            left = family.MAX_ATTEMPTS - attempts

            if left <= 0:
                raise FamilyLocked(family.LOCK_MINUTES)

            raise WrongPasscode(f"Wrong passcode. {left} {'try' if left == 1 else 'tries'} left.")

        user = credential.user

        if not user.is_active():
            raise AccountInactive()

        assert_family_app_on(user.school_id)

        now = timezone.now()
        FamilyCredential.objects.filter(pk=credential.pk).update(failed_attempts=0, updated_at=now)
        FamilyDevice.objects.filter(pk=device.pk).update(last_used_at=now, updated_at=now)
        token = tokens.issue(user, user_agent)
        audit.record(actor=user, action="user.signed_in", module=cls.MODULE, entity_type="user", entity_id=user.id,
                     school_id=user.school_id, new={"device": device.name, "method": "family"})

        return user, token

    @staticmethod
    def children_of(user: User):
        """The students a family account sees: the parent's linked children who
        are at the school today, never anybody else's."""
        return (
            Student.objects.select_related("class_section__school_class")
            .filter(guardian_links__guardian__user_id=user.id, school_id=user.school_id,
                    status=StudentStatus.ACTIVE)
            .order_by("first_name", "id")
            .distinct()
        )
