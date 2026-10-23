"""Does this host's mail configuration actually work? (docs/deployment.md)

    python scripts/check_smtp.py            # connect and sign in
    python scripts/check_smtp.py --send     # and send one real email

Run from cPanel's "Execute python script" box, which takes a Python file and
nothing else - so this needs no shell, no database and no Django.

**Why it exists.** Shared hosts routinely block outbound SMTP to stop spam,
and the failure is silent in exactly the wrong way: the app queues a
password-reset email, reports success, and the person waiting for the link
never hears anything. Better to find out from a script than from a locked-out
headteacher.

**It never prints the password**, only whether the server accepted it.
"""

import argparse
import os
import smtplib
import ssl
import sys
from email.message import EmailMessage
from pathlib import Path

ENV_FILE = Path(__file__).resolve().parent.parent / "backend" / ".env"


def settings() -> dict:
    """The same .env Django and Laravel read, parsed without either."""
    if not ENV_FILE.is_file():
        sys.exit(f"No {ENV_FILE} - nothing to check.")

    values = {}
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")

    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--send", action="store_true", help="send a real email to MAIL_USERNAME")
    options = parser.parse_args()

    env = settings()
    host = env.get("MAIL_HOST", "")
    port = int(env.get("MAIL_PORT") or 0)
    user = env.get("MAIL_USERNAME", "")
    password = env.get("MAIL_PASSWORD", "")
    sender = env.get("MAIL_FROM_ADDRESS") or user

    print(f"host     : {host}:{port}")
    print(f"username : {user}")
    print(f"password : {'set, ' + str(len(password)) + ' chars' if password else 'MISSING'}")

    if not (host and port and user and password):
        print("\nFAIL: the mail settings are incomplete.")
        return 1

    # 587 is STARTTLS; 465 is TLS from the first byte. Getting this the wrong
    # way round looks exactly like a blocked port.
    try:
        if port == 465:
            server = smtplib.SMTP_SSL(host, port, timeout=20, context=ssl.create_default_context())
        else:
            server = smtplib.SMTP(host, port, timeout=20)
            server.starttls(context=ssl.create_default_context())
    except OSError as error:
        print(f"\nFAIL: could not reach {host}:{port} - {error}")
        print("On shared hosting this usually means outbound SMTP is blocked.")
        print("Ask the host to open it, or use their own SMTP relay instead.")
        return 1

    with server:
        try:
            server.login(user, password)
        except smtplib.SMTPAuthenticationError as error:
            print(f"\nFAIL: the server refused the credentials - {error.smtp_code}")
            print("For Gmail this means the app password is wrong or has been revoked.")
            return 1

        print("\nOK: connected, STARTTLS negotiated, credentials accepted.")

        if not options.send:
            print("Run again with --send to post a real message.")
            return 0

        message = EmailMessage()
        message["Subject"] = "School365ai: SMTP check"
        message["From"] = sender
        message["To"] = user
        message.set_content("If you are reading this, the server can send mail.")

        server.send_message(message)
        print(f"OK: sent one message to {user}.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
