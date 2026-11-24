"""The link a WhatsApp message may carry into the app (docs/mobile-apps-review.md,
6.5, decided 2026-11-18).

`https://school365ai.com/f/<screen>` opens the School365ai Family app on that
screen where the app is installed (Android App Links, assetlinks.json on the
website), and a page saying how to get it where it is not. Staff are sent to
the web app instead, which they can open on any phone.

Only WhatsApp gets it, and only through a template that asks for `link`:
WhatsApp sends nothing but templates Meta or Twilio approved, so a link
appears only once the platform's own template has a place for it. SMS never
carries one (no SMS template re-registration).
"""

from __future__ import annotations

from django.conf import settings

from .enums import MessageCategory, MessageEvent

# A token only a WhatsApp template may fill - never an SMS or email body.
LINK_TOKEN = "link"

# The Family app screen each kind of message is about; Notices otherwise.
# The same screens a tapped push opens (push.FAMILY_ROUTES).
FAMILY_SCREENS = {
    MessageCategory.FEE: "fees",
    MessageCategory.TRANSPORT: "bus",
    MessageCategory.RESULT: "results",
    MessageCategory.ATTENDANCE: "attendance",
}


# A message whose screen is not its category's (M8, 8.1).
FAMILY_EVENT_SCREENS = {MessageEvent.HOMEWORK_FOR_FAMILY: "homework"}


def family_link(event: str) -> str:
    screen = FAMILY_EVENT_SCREENS.get(event) or FAMILY_SCREENS.get(MessageEvent.category(event), "notices")

    return f"{settings.PUBLIC_SITE_URL.rstrip('/')}/f/{screen}"


def link_for(event: str, recipient) -> str:
    """Staff, who sign in, get the web app; a guardian gets the Family app."""
    user = getattr(recipient, "user", None)
    if user is not None and getattr(user, "role", None) not in (None, "parent", "student"):
        return f"{settings.PUBLIC_SITE_URL.rstrip('/')}/app/"

    return family_link(event)
