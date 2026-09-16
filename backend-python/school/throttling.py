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
