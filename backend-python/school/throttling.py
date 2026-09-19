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
