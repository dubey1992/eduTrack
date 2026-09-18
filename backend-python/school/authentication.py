"""Who is calling, established from the bearer token.

This is Sanctum's guard, rewritten. It reads the same `personal_access_tokens`
rows Laravel writes (see school/tokens.py for why that is possible at all), so
a session started on one backend keeps working on the other.

Django's own auth is not involved. `users` is Laravel's table, not
`auth_user`, and bolting Django's user model onto it would mean carrying
permissions, groups and a session framework this API has no use for. What DRF
actually needs from `request.user` is `is_authenticated`, which the User model
answers directly.
"""

from __future__ import annotations

from rest_framework.authentication import BaseAuthentication, get_authorization_header

from . import audit, tokens
from .enums import UserStatus
from .models import User


class SanctumTokenAuthentication(BaseAuthentication):
    keyword = "Bearer"

    def authenticate(self, request):
        """Returns (user, token) for a good token, None for no token at all.

        None rather than an exception for a *missing* header: that is what
        tells DRF the request is anonymous, which the permission classes then
        turn into a 401. A *bad* token is also None here, deliberately - the
        client is told "not signed in", and gets no way to tell a token that
        never existed from one that has been revoked.
        """
        header = get_authorization_header(request).split()

        if not header or header[0].lower() != self.keyword.lower().encode():
            return None

        if len(header) != 2:
            return None

        token = tokens.find(header[1].decode(errors="replace"))

        if token is None:
            return None

        # An expired session is gone for good: deleting it here keeps the
        # list of signed-in devices honest without a clean-up job.
        if tokens.has_expired(token):
            token.delete()
            return None

        # Sanctum's morph. Anything else in this column is a token for some
        # other kind of holder, and is not a user session.
        if token.tokenable_type != tokens.TOKENABLE_TYPE:
            return None

        user = User.objects.filter(pk=token.tokenable_id).select_related("school").first()

        if user is None:
            return None

        # A deactivated account keeps its tokens - deactivating does not
        # revoke them - so the check belongs here, on every request, not only
        # at login. Otherwise an account switched off this morning stays
        # signed in until its holder happens to sign out.
        if user.status != UserStatus.ACTIVE:
            return None

        tokens.touch(token)
        audit.set_actor(user)

        return (user, token)

    def authenticate_header(self, request) -> str:
        """Present so DRF answers 401 rather than 403 for an anonymous call.

        Without an authenticate_header, DRF treats a missing credential as a
        permission failure and returns 403 - and a client that gets 403 does
        not know to send the user back to sign in.
        """
        return self.keyword
