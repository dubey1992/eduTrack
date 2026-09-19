"""One HTTP POST, the way every provider adapter needs it.

The standard library's urllib rather than a client package: two adapters
making one call each is not a reason to add a dependency to shared hosting.
Tests replace `post` and never touch the network.

Nothing here logs a request body or a header. A body carries a message about
a named child; a header carries the school's account token.
"""

from __future__ import annotations

import base64
import json
import urllib.error
import urllib.parse
import urllib.request

TIMEOUT_SECONDS = 15


class ProviderError(Exception):
    """The provider could not be reached or refused the request. The message
    is safe to show an administrator and never contains a credential."""


def post(url: str, *, form: dict | None = None, body: dict | None = None, basic=None, bearer=None) -> dict:
    """POSTs a form or a JSON body and returns the decoded JSON answer.

    A 4xx or 5xx is still an answer - Twilio and Meta both explain a refusal
    in the body - so it is decoded and returned with `_status` set, and the
    adapter reads the explanation. Only a connection failure raises.
    """
    headers = {"Accept": "application/json"}

    if basic is not None:
        pair = f"{basic[0]}:{basic[1]}".encode()
        headers["Authorization"] = "Basic " + base64.b64encode(pair).decode()

    if bearer is not None:
        headers["Authorization"] = f"Bearer {bearer}"

    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    else:
        data = urllib.parse.urlencode(form or {}).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"

    request = urllib.request.Request(url, data=data, headers=headers, method="POST")

    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return decoded(response.read(), response.status)
    except urllib.error.HTTPError as error:
        return decoded(error.read(), error.code)
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise ProviderError(f"Could not reach the provider: {error.reason if hasattr(error, 'reason') else error}")


def decoded(raw: bytes, status: int) -> dict:
    try:
        answer = json.loads(raw.decode() or "{}")
    except ValueError:
        answer = {}

    if not isinstance(answer, dict):
        answer = {"data": answer}

    answer["_status"] = status

    return answer
