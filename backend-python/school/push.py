"""Push notifications to the School365ai app (docs/teacher-app.md, T6).

A push is a second delivery of an in-app message, never a message of its own.
Whatever reaches a member of staff's inbox also buzzes the phones they are
signed in on. That one rule settles the hard questions:

- **A switched-off alert is never pushed**, because it is never recorded in
  the first place (school/notifications.py) - there is nothing to push.
- **Nothing is logged twice.** The inbox row is the record; a push that fails
  leaves the message read-able in the app, which is where it already is.
- **Only the person the message was written for.** Their tokens, by user id.

Firebase Cloud Messaging's HTTP v1 API, authorised with the service account
the business's Firebase project issues. Its key file lives outside git; the
path is `FIREBASE_CREDENTIALS_FILE` in the shared `.env`. Without it, push is
simply off: nothing is sent and nothing fails.

The access token is made here rather than with google-auth: a JWT signed with
the service account's RSA key, exchanged at Google's token endpoint. One
library already pinned (cryptography) does the signing; adding google-auth
for one call is not worth a dependency on shared hosting.

Nothing here logs a token, a key or a message body.
"""

from __future__ import annotations

import base64
import json
import logging
import time
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from django.conf import settings
from django.core.cache import cache

from .enums import MessageCategory, MessageEvent
from .gateways import http
from .models import DeviceToken, Message

logger = logging.getLogger(__name__)

TOKEN_URL = "https://oauth2.googleapis.com/token"
SEND_URL = "https://fcm.googleapis.com/v1/projects/{project}/messages:send"
SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

# Google's tokens last an hour; one is reused for most of it.
TOKEN_CACHE_KEY = "push.fcm_access_token"
TOKEN_LIFETIME_S = 3600
TOKEN_REUSE_S = 3000

# What a phone shows in the notification shade before it is opened.
BODY_LIMIT = 240

# Where a tap takes the person, by what the message is about. The app's own
# addresses (core/routing/teacher_router.dart).
ROUTES = {
    MessageCategory.LEAVE: "/leave",
    MessageCategory.TEACHING: "/teaching",
}
DEFAULT_ROUTE = "/inbox"


def credentials() -> dict | None:
    """The service account, or None when push is not set up."""
    path = getattr(settings, "FIREBASE_CREDENTIALS_FILE", "")
    if not path:
        return None

    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        logger.error("FIREBASE_CREDENTIALS_FILE is set but could not be read as a service account file.")
        return None

    if not all(data.get(key) for key in ("project_id", "client_email", "private_key")):
        logger.error("FIREBASE_CREDENTIALS_FILE is missing project_id, client_email or private_key.")
        return None

    return data


def configured() -> bool:
    return credentials() is not None


def _b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def signed_assertion(account: dict, now: int) -> str:
    """The JWT Google exchanges for an access token, signed RS256."""
    header = {"alg": "RS256", "typ": "JWT"}
    claims = {
        "iss": account["client_email"],
        "scope": SCOPE,
        "aud": TOKEN_URL,
        "iat": now,
        "exp": now + TOKEN_LIFETIME_S,
    }
    unsigned = f"{_b64(json.dumps(header).encode())}.{_b64(json.dumps(claims).encode())}"
    key = serialization.load_pem_private_key(account["private_key"].encode(), password=None)
    signature = key.sign(unsigned.encode(), padding.PKCS1v15(), hashes.SHA256())

    return f"{unsigned}.{_b64(signature)}"


def access_token(account: dict) -> str | None:
    cached = cache.get(TOKEN_CACHE_KEY)
    if cached:
        return cached

    try:
        answer = http.post(
            TOKEN_URL,
            form={
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": signed_assertion(account, int(time.time())),
            },
        )
    except http.ProviderError:
        logger.warning("Could not reach Google for a push access token.")
        return None

    token = answer.get("access_token")
    if answer.get("_status") != 200 or not token:
        logger.error("Google refused the push service account (status %s).", answer.get("_status"))
        return None

    cache.set(TOKEN_CACHE_KEY, token, TOKEN_REUSE_S)
    return token


def route_for(message: Message) -> str:
    return ROUTES.get(message.category, DEFAULT_ROUTE)


def title_for(message: Message) -> str:
    """An announcement's own title; otherwise what kind of message it is."""
    if message.subject:
        return message.subject

    if message.event in MessageEvent.values:
        return MessageEvent(message.event).label

    return "School365ai"


def notification_for(message: Message, token: str) -> dict:
    body = message.body if len(message.body) <= BODY_LIMIT else message.body[: BODY_LIMIT - 1] + "…"

    return {
        "message": {
            "token": token,
            "notification": {"title": title_for(message), "body": body},
            # Read by the app when the notification is tapped.
            "data": {"route": route_for(message), "message_id": str(message.id), "event": message.event},
            "android": {"priority": "high"},
        }
    }


def _gone(answer: dict) -> bool:
    """Firebase's way of saying the app was uninstalled or the token is dead."""
    if answer.get("_status") == 404:
        return True

    error = answer.get("error") or {}
    for detail in error.get("details") or []:
        if detail.get("errorCode") in ("UNREGISTERED", "INVALID_ARGUMENT") and answer.get("_status") in (400, 404):
            return True

    return False


def deliver(message: Message) -> int:
    """Pushes one in-app message to every phone its person is signed in on.
    Returns how many phones accepted it. Dead tokens are removed."""
    if not message.user_id:
        return 0

    account = credentials()
    if account is None:
        return 0

    devices = list(DeviceToken.objects.filter(user_id=message.user_id))
    if not devices:
        return 0

    bearer = access_token(account)
    if bearer is None:
        return 0

    url = SEND_URL.format(project=account["project_id"])
    accepted = 0

    for device in devices:
        try:
            answer = http.post(url, body=notification_for(message, device.token), bearer=bearer)
        except http.ProviderError:
            logger.warning("Could not reach Firebase to push message %s.", message.id)
            continue

        if answer.get("_status") == 200:
            accepted += 1
        elif _gone(answer):
            DeviceToken.objects.filter(pk=device.pk).delete()
        elif answer.get("_status") == 401:
            # The cached access token was revoked early; the next job makes a new one.
            cache.delete(TOKEN_CACHE_KEY)
            logger.error("Firebase refused the push access token for message %s.", message.id)
        else:
            logger.error("Firebase did not accept push for message %s (status %s).", message.id, answer.get("_status"))

    return accepted
