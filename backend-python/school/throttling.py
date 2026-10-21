"""Rate limits, where a limit is the only thing between an endpoint and a script.

Ported from the `login` limiter in Laravel's RateServiceProvider. It is two
limits, not one, and both matter:

 - **5 a minute per account and address**, which is what stops one attacker
   guessing one person's password.
 - **30 a minute per address**, which is looser on purpose. A whole school
   office behind one NAT address signing in on a Monday morning is not an
   attack, and a single per-IP limit tight enough to stop guessing would lock
   out the office.

Both answer the standard envelope with `TOO_MANY_REQUESTS` (see errors.py), so
the client can tell "slow down" from "wrong password" and say so.
"""

from __future__ import annotations

from rest_framework.throttling import SimpleRateThrottle


class LoginThrottle(SimpleRateThrottle):
    """One attacker guessing one account, as opposed to one office."""

    scope = "login"
    rate = "5/min"

    def get_cache_key(self, request, view) -> str:
        email = str(request.data.get("email", "")).strip().lower()

        return self.cache_format % {
            "scope": self.scope,
            "ident": f"{email}|{self.get_ident(request)}",
        }


class LoginAddressThrottle(SimpleRateThrottle):
    """One office, as opposed to one attacker."""

    scope = "login-address"
    rate = "30/min"

    def get_cache_key(self, request, view) -> str:
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}


class EarlyAccessThrottle(SimpleRateThrottle):
    """The marketing page's signup form: a public write with no account behind
    it. Five a minute is more than any school needs and less than any bot
    wants. The panel's reads share the address but not the limit."""

    scope = "early-access"
    rate = "5/min"

    def get_cache_key(self, request, view) -> str | None:
        if request.method != "POST":
            return None

        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}


class MarketingContentThrottle(SimpleRateThrottle):
    """The homepage's words, read by anybody who opens the page.

    Generous rather than tight: this is a public page and a classroom of
    thirty behind one school address opening it at once is ordinary
    traffic, not an attack. The limit is here so a script cannot make the
    endpoint a cheap way to hammer the database - which the cache in front
    of it already makes unlikely (docs/marketing-content.md).
    """

    scope = "marketing-content"
    rate = "120/min"

    def get_cache_key(self, request, view) -> str | None:
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}


class PasswordResetThrottle(SimpleRateThrottle):
    """Tighter than signing in: each attempt can send a real email, so this is
    also a way to fill somebody's inbox."""

    scope = "password-reset"
    rate = "3/min"

    def get_cache_key(self, request, view) -> str:
        email = str(request.data.get("email", "")).strip().lower()

        return self.cache_format % {"scope": self.scope, "ident": f"{email}|{self.get_ident(request)}"}


class PasswordResetAddressThrottle(SimpleRateThrottle):
    scope = "password-reset-address"
    rate = "10/min"

    def get_cache_key(self, request, view) -> str:
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}


class AttendantThrottle(SimpleRateThrottle):
    """One phone number being guessed at, as opposed to one office. The
    passcode's own lock (five wrong, then an administrator) is the real
    guard; this stops a script hammering the lock into place."""

    scope = "attendant-login"
    rate = "5/min"

    def get_cache_key(self, request, view) -> str:
        from .attendants import login_mobile

        mobile = login_mobile(str(request.data.get("mobile", ""))) or ""

        return self.cache_format % {"scope": self.scope, "ident": f"{mobile}|{self.get_ident(request)}"}


class AttendantAddressThrottle(SimpleRateThrottle):
    """A depot where every attendant signs in at once, as opposed to one
    attacker."""

    scope = "attendant-login-address"
    rate = "30/min"

    def get_cache_key(self, request, view) -> str:
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}


class MapsLookupThrottle(SimpleRateThrottle):
    """Every call here costs money (docs/maps.md).

    Per user rather than per address, because the thing being limited is a
    search box somebody is holding a key down in, not an attacker. Generous
    enough that placing a dozen stops in a sitting never hits it: the cache
    means only a query nobody has typed today reaches Google at all.
    """

    scope = "maps-lookup"
    rate = "60/min"

    def get_cache_key(self, request, view) -> str:
        return self.cache_format % {"scope": self.scope, "ident": request.user.pk or self.get_ident(request)}


class DevicePushThrottle(SimpleRateThrottle):
    """The fingerprint readers' own endpoint (docs/biometric.md, B4).

    Per serial rather than per address: a school's devices sit behind one
    NAT address, and a limit tight enough to matter per address would throttle
    the school rather than the problem. A serial is the only thing a device
    says about itself, so it is also the only thing worth counting.

    Sixty a minute is far more than the firmware's own polling interval and
    far less than a leaked serial is worth to anybody. A device with no
    serial at all is not counted here - it is refused before it gets this
    far, and counting it would let one bad request spend a real device's
    allowance.
    """

    scope = "device-push"
    rate = "60/min"

    def get_cache_key(self, request, view) -> str | None:
        serial = (request.GET.get("SN") or request.GET.get("sn") or "").strip()

        if not serial:
            return None

        return self.cache_format % {"scope": self.scope, "ident": serial[:64]}
