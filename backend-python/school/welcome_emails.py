"""The welcome a new school gets (docs/onboarding.md, slice O3).

Two emails, written here and sent from the queue (`jobs.py`):

- **The School Admin's welcome** - always, whether or not a password was
  typed for them. It names their school, the address they sign in with, the
  way in (a set-password button when nobody chose one, a sign-in button when
  someone did), and the six first steps. A password is never in it.
- **A note to the school's own address**, when that is not the admin's: the
  school is set up, and who its School Admin is.

Each builder returns (subject, text, html) and touches no database, so the
wording is tested on its own.
"""

from __future__ import annotations

import html

from django.conf import settings

# The order the setup guide on the dashboard follows (docs/onboarding.md).
FIRST_STEPS = (
    ("Academic year", "the year's start and end dates."),
    ("Departments", "for example Science, Languages, Primary."),
    ("Classes & sections", "Quick setup adds Nursery to Class 10, with their sections, in one step."),
    ("Subjects", "and which classes each is taught in."),
    ("Teachers & staff", "one by one or from a spreadsheet."),
    ("Students", "one by one or with Bulk Upload; roll numbers are given automatically."),
)

BLUE = "#2563eb"


def school_admin(
    *, first_name: str, email: str, school_name: str, sub_admin: bool, set_password_link: str | None, year: int
) -> tuple[str, str, str]:
    """The School Admin's welcome. `set_password_link` is None when a
    password was chosen for them: then the button signs them in instead."""
    name = settings.APP_NAME
    role = "a Sub Admin" if sub_admin else "the School Admin"
    sign_in = sign_in_url()

    subject = f"Welcome to {name} - {school_name} is ready"
    opening = f"An account has been created for you as {role} of {school_name} on {name}."

    if set_password_link:
        action, url = "Set your password", set_password_link
        way_in = (
            f"Choose a password with the button below, then sign in with it and this email address. "
            f"The link works for {settings.PASSWORD_RESET_EXPIRE_MINUTES} minutes; after that, use "
            '"Forgot password" on the sign-in page to be sent a new one.'
        )
    else:
        action, url = "Sign in", sign_in
        way_in = (
            "Sign in with this email address and the password you were given. "
            "You can change it any time from My Profile."
        )

    steps_text = "\n".join(f"{n}. {title} - {detail}" for n, (title, detail) in enumerate(FIRST_STEPS, start=1))
    text = (
        f"{name}\n\n"
        f"Hello {first_name},\n\n"
        f"{opening}\n\n"
        f"Sign-in email: {email}\n"
        f"Sign-in page: {sign_in}\n\n"
        f"{way_in}\n\n"
        f"{action}: {url}\n\n"
        "Your first steps, in this order - the setup guide on your dashboard takes you through them:\n"
        f"{steps_text}\n\n"
        f"Help articles: {help_url()}\n"
        f"Questions? Write to {support_email()}.\n\n"
        f"Regards,\n{name}\n\n"
        f"{footer_text(year)}"
    )

    steps_html = "".join(
        f"<li style=\"margin-bottom:6px\"><strong>{html.escape(title)}</strong> - {html.escape(detail)}</li>"
        for title, detail in FIRST_STEPS
    )
    body = layout(
        year,
        f"<p>Hello {html.escape(first_name)},</p>"
        f"<p>{html.escape(opening)}</p>"
        '<table role="presentation" style="border-collapse:collapse;margin:12px 0;font-size:14px">'
        f"{row('Sign-in email', email)}{row('Sign-in page', sign_in, link=True)}</table>"
        f"<p>{html.escape(way_in)}</p>"
        f"{button(action, url)}"
        "<p style=\"margin-top:24px\"><strong>Your first steps, in this order</strong> - "
        "the setup guide on your dashboard takes you through them:</p>"
        f"<ol style=\"padding-left:20px\">{steps_html}</ol>"
        f"<p>Help articles: <a href=\"{html.escape(help_url())}\" style=\"color:{BLUE}\">"
        f"{html.escape(help_url())}</a><br>"
        f"Questions? Write to <a href=\"mailto:{html.escape(support_email())}\" style=\"color:{BLUE}\">"
        f"{html.escape(support_email())}</a>.</p>"
        f"<p>Regards,<br>{html.escape(name)}</p>"
        + fallback(action, url),
    )

    return subject, text, body


def school_note(
    *, school_name: str, admin_name: str | None, admin_email: str | None, year: int
) -> tuple[str, str, str]:
    """To the school's own address: it is set up, and who runs it."""
    name = settings.APP_NAME
    subject = f"{school_name} is set up on {name}"
    opening = f"Your school's account on {name} has been created."

    if admin_email:
        who = f"Your School Admin is {admin_name} ({admin_email}). They have been emailed how to sign in."
    else:
        who = "A School Admin will be added for you; they will be emailed how to sign in."

    text = (
        f"{name}\n\n"
        "Hello,\n\n"
        f"{opening}\n\n"
        f"{who}\n\n"
        f"Sign-in page: {sign_in_url()}\n"
        f"Help articles: {help_url()}\n"
        f"Questions? Write to {support_email()}.\n\n"
        f"Regards,\n{name}\n\n"
        f"{footer_text(year)}"
    )
    body = layout(
        year,
        "<p>Hello,</p>"
        f"<p>{html.escape(opening)}</p>"
        f"<p>{html.escape(who)}</p>"
        f"{button('Open the sign-in page', sign_in_url())}"
        f"<p>Help articles: <a href=\"{html.escape(help_url())}\" style=\"color:{BLUE}\">"
        f"{html.escape(help_url())}</a><br>"
        f"Questions? Write to <a href=\"mailto:{html.escape(support_email())}\" style=\"color:{BLUE}\">"
        f"{html.escape(support_email())}</a>.</p>"
        f"<p>Regards,<br>{html.escape(name)}</p>",
    )

    return subject, text, body


# -- pieces ---------------------------------------------------------------------


def sign_in_url() -> str:
    # The web app routes on the fragment, so every link is FRONTEND_URL/#/...
    return f"{settings.FRONTEND_URL.rstrip('/')}/#/login"


def help_url() -> str:
    from .public_site import site_url

    return f"{site_url()}/help"


def support_email() -> str:
    from .site_pages import SUPPORT_EMAIL

    return SUPPORT_EMAIL


def footer_text(year: int) -> str:
    return f"Smarter Schools. Brighter Futures.\n© {year} {settings.APP_NAME}. All rights reserved."


def layout(year: int, inner: str) -> str:
    name = html.escape(settings.APP_NAME)

    return (
        '<div style="font-family:Arial,sans-serif;color:#1f2937;max-width:570px;margin:0 auto;line-height:1.5">'
        f'<p style="font-size:19px;font-weight:bold">\U0001f393 {name}</p>'
        f"{inner}"
        '<p style="font-size:12px;color:#6b7280;text-align:center;margin-top:28px">'
        f"Smarter Schools. Brighter Futures.<br>© {year} {name}. All rights reserved.</p>"
        "</div>"
    )


def button(label: str, url: str) -> str:
    return (
        f'<p><a href="{html.escape(url)}" style="background-color:{BLUE};border:8px solid {BLUE};'
        "border-left-width:18px;border-right-width:18px;color:#ffffff;text-decoration:none;"
        f'border-radius:4px;display:inline-block">{html.escape(label)}</a></p>'
    )


def row(label: str, value: str, link: bool = False) -> str:
    shown = (
        f'<a href="{html.escape(value)}" style="color:{BLUE}">{html.escape(value)}</a>' if link else html.escape(value)
    )

    return (
        f'<tr><td style="padding:2px 12px 2px 0;color:#6b7280">{html.escape(label)}</td>'
        f"<td style=\"padding:2px 0\"><strong>{shown}</strong></td></tr>"
    )


def fallback(action: str, url: str) -> str:
    safe = html.escape(url)

    return (
        f'<p style="font-size:12px;color:#6b7280">If the "{html.escape(action)}" button does not work, copy this '
        f'address into your browser: <a href="{safe}" style="color:{BLUE}">{safe}</a></p>'
    )
