"""Calls the WSGI application directly, without a web server.

    python scripts/check_wsgi.py [path]

Run from cPanel's "Execute python script" box. It answers the one question
that matters when a Python app 404s on a host you cannot shell into: **is
the application broken, or is the web server never calling it?**

If this prints a status line, the application works and anything the browser
sees is the server's doing - which is a support ticket, not a code change.
If it raises, the traceback is the real problem and it is ours.

Nothing here touches the network. It builds a WSGI environ by hand and calls
the same `application` object Passenger would.
"""

import io
import sys
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent / "backend-python"


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "/api/v1/marketing-content"

    sys.path.insert(0, str(APP_ROOT))
    print(f"app root : {APP_ROOT}")
    print(f"python   : {sys.executable}")
    print(f"path     : {path}")

    try:
        import passenger_wsgi
    except Exception as error:  # noqa: BLE001 - the whole point is to report it
        import traceback

        print("\nFAIL: passenger_wsgi.py could not be imported.")
        print("This is the application's fault, not the server's.\n")
        traceback.print_exc()
        return 1

    application = getattr(passenger_wsgi, "application", None)
    if application is None:
        print("\nFAIL: passenger_wsgi.py has no `application` - Passenger needs that name.")
        return 1

    environ = {
        "REQUEST_METHOD": "GET",
        "PATH_INFO": path,
        "QUERY_STRING": "",
        "SERVER_NAME": "api.school365ai.com",
        "SERVER_PORT": "443",
        "SERVER_PROTOCOL": "HTTP/1.1",
        "HTTP_HOST": "api.school365ai.com",
        "wsgi.version": (1, 0),
        "wsgi.url_scheme": "https",
        "wsgi.input": io.BytesIO(b""),
        "wsgi.errors": sys.stderr,
        "wsgi.multithread": False,
        "wsgi.multiprocess": True,
        "wsgi.run_once": False,
    }

    captured = {}

    def start_response(status, headers, exc_info=None):
        captured["status"] = status
        captured["headers"] = headers

    try:
        body = b"".join(application(environ, start_response))
    except Exception:  # noqa: BLE001
        import traceback

        print("\nFAIL: the application raised while handling the request.\n")
        traceback.print_exc()
        return 1

    print(f"\nstatus   : {captured.get('status')}")
    content_type = dict(captured.get("headers") or {}).get("Content-Type", "?")
    print(f"type     : {content_type}")
    print(f"body     : {body[:300]!r}")

    print(
        "\nOK: the application answered. If a browser still gets 404 from this\n"
        "host, the web server is not calling the application at all - that is\n"
        "a server configuration problem, not a problem with this code."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
