"""What may be changed on the public homepage (docs/marketing-content.md).

One declaration, the way `school/modules.py` declares module settings. The
validation that refuses a key nobody recognises, and the form the Super
Admin types into, both come from here - so adding a field to the page is
one entry rather than four edits that have to agree.

**What is not here is the copy itself.** The page's own words live in the
client (`marketing_defaults.dart`), because the homepage has to render
when this backend is down, when the table is empty, and before the first
byte arrives. This file knows the keys, not the English. A test reads both
and refuses to let them drift.

The lengths are about layout, not storage. A headline is set at 46px
against a drawn mockup; forty words would not wrap, it would wreck the
section. Refusing it at the form is kinder than letting somebody publish
it and find out.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Field:
    key: str
    label: str
    # A headline is one line; a paragraph is several. The editor draws a
    # taller box for the second, which is the only difference.
    multiline: bool = False
    max_length: int = 120
    help: str = ""


@dataclass(frozen=True)
class Section:
    key: str
    label: str
    description: str
    fields: tuple[Field, ...]


SECTIONS: tuple[Section, ...] = (
    Section(
        "nav", "The bar across the top", "The first thing a visitor sees, on every screen size.",
        (
            Field("wordmark", "Name", max_length=40,
                  help="Also sets how much room the brand takes; a long name leaves less for the links."),
            Field("tagline", "Tagline", max_length=60,
                  help="Hidden rather than cut when the bar is narrow, so keep it short."),
            Field("login", "Login button", max_length=24),
            Field("join", "Call to action", max_length=32),
            Field("joinShort", "Call to action, on a phone", max_length=16,
                  help="Shown under 480px, where the full wording does not fit."),
        ),
    ),
    Section(
        "hero", "The opening", "The headline and the first paragraph anybody reads.",
        (
            Field("eyebrow", "Eyebrow", max_length=60),
            Field("headline", "Headline", max_length=90,
                  help="Set large, beside the dashboard picture. Two short lines read better than one long one."),
            Field("body", "Opening paragraph", multiline=True, max_length=300),
            Field("primaryButton", "Main button", max_length=32),
            Field("secondaryButton", "Second button", max_length=32),
            Field("trustLine", "Line under the buttons", max_length=90),
        ),
    ),
    Section(
        "features", "What it does", "The heading above the grid of features.",
        (
            Field("eyebrow", "Eyebrow", max_length=60),
            Field("title", "Heading", max_length=90),
            Field("body", "Paragraph", multiline=True, max_length=240),
        ),
    ),
    Section(
        "mobile", "The phone section", "Beside the phone mockup.",
        (
            Field("eyebrow", "Eyebrow", max_length=40),
            Field("headline", "Heading", multiline=True, max_length=60,
                  help="Breaks across two lines in the design; a line break here is kept."),
            Field("body", "Paragraph", multiline=True, max_length=240),
        ),
    ),
    Section(
        "web", "The browser section", "Beside the dashboard mockup.",
        (
            Field("eyebrow", "Eyebrow", max_length=40),
            Field("headline", "Heading", multiline=True, max_length=60,
                  help="Breaks across two lines in the design; a line break here is kept."),
            Field("body", "Paragraph", multiline=True, max_length=240),
        ),
    ),
    Section(
        "cta", "The invitation", "The blue band near the bottom.",
        (
            Field("headline", "Heading", max_length=90),
            Field("body", "Paragraph", multiline=True, max_length=300),
            Field("button", "Button", max_length=32),
        ),
    ),
    Section(
        "footer", "The bottom", "The last thing on the page.",
        (
            Field("wordmark", "Name", max_length=40),
            Field("blurb", "Blurb", multiline=True, max_length=200),
            Field("newsletterTitle", "Newsletter heading", max_length=40),
            Field("newsletterBody", "Newsletter line", max_length=90),
            Field("copyright", "Copyright", max_length=90),
            Field("tagline", "Tagline", max_length=60),
        ),
    ),
)


def fields() -> dict[str, Field]:
    """Every editable field, by its `section.field` key."""
    return {f"{section.key}.{field.key}": field for section in SECTIONS for field in section.fields}


def keys() -> set[str]:
    return set(fields())


def resource() -> list[dict]:
    """The declaration as the editor reads it."""
    return [
        {
            "key": section.key,
            "label": section.label,
            "description": section.description,
            "fields": [
                {
                    "key": f"{section.key}.{field.key}",
                    "label": field.label,
                    "multiline": field.multiline,
                    "max_length": field.max_length,
                    "help": field.help,
                }
                for field in section.fields
            ],
        }
        for section in SECTIONS
    ]
