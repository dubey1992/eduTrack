"""A thin HTTP client for the contract suite.

Deliberately built on the standard library alone. This suite has to outlive
the backend it was written against: it runs against Laravel today and against
Django tomorrow, in CI, on a developer's machine and potentially on the
production host itself. A dependency it could fail to install is a dependency
it should not have, and `urllib` is always there.

It speaks HTTP and nothing else. No database access, no framework imports, no
knowledge of how the answer was produced - which is the entire point. If this
suite could import anything from the backend it would stop being able to test
the replacement.
"""

from __future__ import annotations

import json
import os
import urllib.error
import uuid
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Any

import coverage

DEFAULT_BASE_URL = "http://127.0.0.1:8000/api/v1"


def base_url() -> str:
    """The backend under test. Every assertion in this suite is about this one."""
    return os.environ.get("CONTRACT_BASE_URL", DEFAULT_BASE_URL).rstrip("/")


def setup_url() -> str:
    """The backend the world is *built* through, which is normally the same one.

    It can be a different one, and that is what makes this suite usable during
    the port rather than only at the end of it. The Python backend grows one
    module at a time, so for most of the migration it can serve the endpoints
    under test while being unable to create the school they are about. Pointing
    setup at Laravel and the tests at Django asks the honest question - does
    the new backend answer the same way about the same rows? - months before
    the new backend can build a school of its own.

    Both must be on the same database for this to mean anything. They are:
    that is the whole point of moving to PostgreSQL first, and of the two
    backends staying runnable side by side.
    """
    return os.environ.get("CONTRACT_SETUP_BASE_URL", base_url()).rstrip("/")


@dataclass
class Response:
    """What came back, in the three terms the contract is written in."""

    status: int
    body: Any
    headers: dict[str, str] = field(default_factory=dict)

    @property
    def data(self) -> Any:
        """The `data` envelope of a paginated list, or the body itself."""
        if isinstance(self.body, dict) and "data" in self.body:
            return self.body["data"]
        return self.body

    def __repr__(self) -> str:  # pragma: no cover - diagnostics only
        rendered = json.dumps(self.body, indent=2, default=str)
        if len(rendered) > 800:
            rendered = rendered[:800] + "\n  ... truncated"
        return f"<{self.status}>\n{rendered}"


class Client:
    """One caller, optionally holding a token.

    `base` names which backend it speaks to. Left alone it is the one under
    test; world.py binds its setup calls to the other one. Coverage is only
    recorded for the backend under test, so building a school somewhere else
    cannot flatter the figure.
    """

    def __init__(self, token: str | None = None, timeout: int = 30, base: str | None = None) -> None:
        self.token = token
        self.timeout = timeout
        self.base = base

    # -- verbs -------------------------------------------------------------

    def get(self, path: str, **query: Any) -> Response:
        return self._send("GET", self._with_query(path, query))

    def post(self, path: str, payload: dict | None = None) -> Response:
        return self._send("POST", path, payload)

    def patch(self, path: str, payload: dict | None = None) -> Response:
        return self._send("PATCH", path, payload)

    def put(self, path: str, payload: dict | None = None) -> Response:
        return self._send("PUT", path, payload)

    def delete(self, path: str) -> Response:
        return self._send("DELETE", path)

    def upload(self, path: str, field: str, filename: str, data: bytes, content_type: str) -> Response:
        """A multipart POST carrying one file - the profile photo."""
        boundary = "contract" + uuid.uuid4().hex
        head = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{field}"; filename="{filename}"\r\n'
            f"Content-Type: {content_type}\r\n\r\n"
        )
        body = head.encode() + data + f"\r\n--{boundary}--\r\n".encode()

        return self._send("POST", path, raw=(body, f"multipart/form-data; boundary={boundary}"))

    def get_bytes(self, path: str) -> tuple[int, bytes, str]:
        """A GET whose answer is not JSON - an image. (status, body, type)."""
        return self._send("GET", path, want_bytes=True)

    # -- plumbing ----------------------------------------------------------

    def _with_query(self, path: str, query: dict[str, Any]) -> str:
        pairs = {k: v for k, v in query.items() if v is not None}
        if not pairs:
            return path

        encoded = urllib.parse.urlencode(pairs)
        joiner = "&" if "?" in path else "?"

        return f"{path}{joiner}{encoded}"

    def _send(self, method: str, path: str, payload: dict | None = None, raw=None, want_bytes: bool = False):
        base = self.base or base_url()

        # Recorded here because this is the only place a request is made, so
        # the coverage figure cannot disagree with what the suite actually did
        # - and only for the backend under test, so calls made to build the
        # world elsewhere do not count as endpoints this backend answered.
        if base == base_url():
            coverage.record(method, path)

        url = f"{base}/{path.lstrip('/')}"
        body = None if payload is None else json.dumps(payload).encode()
        content_type = "application/json"

        if raw is not None:
            body, content_type = raw

        request = urllib.request.Request(url, data=body, method=method)
        request.add_header("Accept", "application/json")
        if body is not None:
            request.add_header("Content-Type", content_type)
        if self.token:
            request.add_header("Authorization", f"Bearer {self.token}")

        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as answer:
                if want_bytes:
                    return answer.status, answer.read(), answer.headers.get("Content-Type", "")
                return self._read(answer)
        except urllib.error.HTTPError as failure:
            # A 4xx is an answer, not an accident - most of this suite is about
            # what the errors look like, so they must come back as responses.
            if want_bytes:
                return failure.code, failure.read(), failure.headers.get("Content-Type", "")
            return self._read(failure)
        except urllib.error.URLError as unreachable:
            raise AssertionError(
                f"Could not reach {url}: {unreachable.reason}. "
                "Is the backend running, and is CONTRACT_BASE_URL pointing at it?"
            ) from unreachable

    def _read(self, raw: Any) -> Response:
        text = raw.read().decode("utf-8", errors="replace")
        headers = {k.lower(): v for k, v in raw.headers.items()}

        try:
            body = json.loads(text) if text else None
        except json.JSONDecodeError:
            # Worth failing loudly rather than returning a string: an endpoint
            # answering HTML is usually a stack trace or a login redirect, and
            # either is a contract violation in its own right.
            body = {"__not_json__": text[:400]}

        return Response(status=raw.status, body=body, headers=headers)


def sign_in(email: str, password: str, base: str | None = None) -> Client:
    """A client holding a token for this account.

    Signing in happens on whichever backend the client will be used against.
    That is not a detail: it means a run pointed at Django proves Django can
    issue a token for a password Laravel hashed, which is the single riskiest
    assumption in the whole migration.
    """
    response = Client(base=base).post("/auth/login", {"email": email, "password": password})

    if response.status != 200:
        raise AssertionError(f"Could not sign in as {email}: HTTP {response.status} {response.body}")

    token = response.body.get("token")
    if not token:
        raise AssertionError(f"Login for {email} returned no token: {response.body}")

    return Client(token=token, base=base)
