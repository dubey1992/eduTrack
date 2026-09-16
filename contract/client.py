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
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Any

import coverage

DEFAULT_BASE_URL = "http://127.0.0.1:8000/api/v1"


def base_url() -> str:
    return os.environ.get("CONTRACT_BASE_URL", DEFAULT_BASE_URL).rstrip("/")


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
    """One caller, optionally holding a token."""

    def __init__(self, token: str | None = None, timeout: int = 30) -> None:
        self.token = token
        self.timeout = timeout

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

    # -- plumbing ----------------------------------------------------------

    def _with_query(self, path: str, query: dict[str, Any]) -> str:
        pairs = {k: v for k, v in query.items() if v is not None}
        if not pairs:
            return path

        encoded = urllib.parse.urlencode(pairs)
        joiner = "&" if "?" in path else "?"

        return f"{path}{joiner}{encoded}"

    def _send(self, method: str, path: str, payload: dict | None = None) -> Response:
        # Recorded here because this is the only place a request is made, so
        # the coverage figure cannot disagree with what the suite actually did.
        coverage.record(method, path)

        url = f"{base_url()}/{path.lstrip('/')}"
        body = None if payload is None else json.dumps(payload).encode()

        request = urllib.request.Request(url, data=body, method=method)
        request.add_header("Accept", "application/json")
        if body is not None:
            request.add_header("Content-Type", "application/json")
        if self.token:
            request.add_header("Authorization", f"Bearer {self.token}")

        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as raw:
                return self._read(raw)
        except urllib.error.HTTPError as failure:
            # A 4xx is an answer, not an accident - most of this suite is about
            # what the errors look like, so they must come back as responses.
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


def sign_in(email: str, password: str) -> Client:
    """A client holding a token for this account."""
    response = Client().post("/auth/login", {"email": email, "password": password})

    if response.status != 200:
        raise AssertionError(f"Could not sign in as {email}: HTTP {response.status} {response.body}")

    token = response.body.get("token")
    if not token:
        raise AssertionError(f"Login for {email} returned no token: {response.body}")

    return Client(token=token)
