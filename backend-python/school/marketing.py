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
class Choice:
    """One of a fixed set of values a field may take."""

    value: str
    label: str


@dataclass(frozen=True)
class ItemField(Field):
    """A field inside a repeating item.

    `choices` turns the box into a picker. The feature cards use it for
    their icon: the page draws the icon as a character, so free text lets
    somebody type one the font has no glyph for and the card shows a box.
    """

    choices: tuple[Choice, ...] = ()

    # A blank required box is a hole in the page - a card with no title.
    # An optional one is a real choice: a footer line with no address is
    # the plain text it has always been.
    required: bool = True

    # Checked as a web address rather than as words.
    is_url: bool = False


@dataclass(frozen=True)
class ListField:
    """A repeating list - the feature cards, the hero stats, and so on.

    `min_items` and `max_items` are the layout again, not storage. The hero
    stats sit in a five-column rule across the width of the hero; a sixth
    wraps onto a row of its own at a fifth of the width, with the divider
    logic still expecting it to be last. The grid of features has room for
    three rows of five.

    A list absent from the document is the one the page ships with, exactly
    as a cleared box is. The editor says so and offers a way back to it.
    """

    key: str
    label: str
    item_label: str
    help: str
    fields: tuple[ItemField, ...]
    min_items: int = 1
    max_items: int = 10


@dataclass(frozen=True)
class Section:
    key: str
    label: str
    description: str
    fields: tuple[Field, ...]
    lists: tuple[ListField, ...] = ()


# The characters the feature cards already draw. A picker rather than free
# text, so a card cannot be given a glyph the font has no room for - the
# page would show an empty box where an icon belongs.
FEATURE_ICONS: tuple[Choice, ...] = (
    Choice("☺", "Face"),
    Choice("✓", "Tick"),
    Choice("¤", "Sun"),
    Choice("⌣", "Smile"),
    Choice("🚌", "Bus"),
    Choice("✉", "Envelope"),
    Choice("⚭", "Rings"),
    Choice("▥", "Chart"),
    Choice("☰", "Lines"),
)


# Where a hero figure's number comes from. TYPED is first because it is
# what a newly added figure gets, and because a platform with three schools
# would rather keep "500+ (Target)" on the board than say "3".
TYPED = "typed"
SCHOOLS = "schools"
STUDENTS = "students"

STAT_SOURCES: tuple[Choice, ...] = (
    Choice(TYPED, "What I type below"),
    Choice(SCHOOLS, "Schools using the product"),
    Choice(STUDENTS, "Students on the platform"),
)

STATS = "hero.stats"


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
        lists=(
            ListField(
                "hero.stats", "The figures under the hero", "Figure",
                "Five across the width of the hero; a sixth wraps onto a row of its own and looks wrong.",
                (
                    ItemField("source", "Where it comes from", max_length=16, choices=STAT_SOURCES,
                              help="A live count replaces the figure below once there is one to show."),
                    ItemField("value", "Figure", max_length=16),
                    ItemField("label", "What it is", max_length=24),
                ),
                min_items=1, max_items=5,
            ),
        ),
    ),
    Section(
        "features", "What it does", "The heading above the grid of features.",
        (
            Field("eyebrow", "Eyebrow", max_length=60),
            Field("title", "Heading", max_length=90),
            Field("body", "Paragraph", multiline=True, max_length=240),
        ),
        lists=(
            ListField(
                "features.items", "The feature cards", "Card",
                "Five to a row on a desktop, two on a phone. Three rows is as many as the section holds.",
                (
                    ItemField("icon", "Icon", max_length=4, choices=FEATURE_ICONS),
                    ItemField("title", "Title", max_length=28),
                    ItemField("body", "Description", max_length=70,
                              help="Wraps to three lines at the narrowest; longer than that is cut off."),
                ),
                min_items=1, max_items=15,
            ),
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
            Field("button", "Button", max_length=32),
        ),
        lists=(
            ListField(
                "web.bullets", "The ticked list", "Line",
                "Stacked under the button, each with a tick. Six is as many as fit beside the mockup.",
                (ItemField("text", "Line", max_length=40),),
                min_items=1, max_items=6,
            ),
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
            Field("productTitle", "First column heading", max_length=24),
            Field("companyTitle", "Second column heading", max_length=24),
            Field("resourceTitle", "Third column heading", max_length=24),
        ),
        lists=(
            ListField(
                "footer.productLinks", "First column", "Line",
                "A line with an address becomes a link; one without stays plain text.",
                (
                    ItemField("label", "Line", max_length=28),
                    ItemField("url", "Address", max_length=200, required=False, is_url=True,
                              help="Leave empty and the line stays plain text, as it is today."),
                ),
                min_items=1, max_items=6,
            ),
            ListField(
                "footer.companyLinks", "Second column", "Line",
                "A line with an address becomes a link; one without stays plain text.",
                (
                    ItemField("label", "Line", max_length=28),
                    ItemField("url", "Address", max_length=200, required=False, is_url=True,
                              help="Leave empty and the line stays plain text, as it is today."),
                ),
                min_items=1, max_items=6,
            ),
            ListField(
                "footer.resourceLinks", "Third column", "Line",
                "A line with an address becomes a link; one without stays plain text.",
                (
                    ItemField("label", "Line", max_length=28),
                    ItemField("url", "Address", max_length=200, required=False, is_url=True,
                              help="Leave empty and the line stays plain text, as it is today."),
                ),
                min_items=1, max_items=6,
            ),
        ),
    ),
)


def fields() -> dict[str, Field]:
    """Every editable field, by its `section.field` key."""
    return {f"{section.key}.{field.key}": field for section in SECTIONS for field in section.fields}


def keys() -> set[str]:
    return set(fields())


def lists() -> dict[str, ListField]:
    """Every repeating list, by its `section.field` key."""
    return {declared.key: declared for section in SECTIONS for declared in section.lists}


def list_keys() -> set[str]:
    return set(lists())


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
            "lists": [
                {
                    "key": declared.key,
                    "label": declared.label,
                    "item_label": declared.item_label,
                    "help": declared.help,
                    "min_items": declared.min_items,
                    "max_items": declared.max_items,
                    "fields": [
                        {
                            "key": field.key,
                            "label": field.label,
                            "multiline": field.multiline,
                            "max_length": field.max_length,
                            "help": field.help,
                            "required": field.required,
                            "is_url": field.is_url,
                            "choices": [
                                {"value": choice.value, "label": choice.label} for choice in field.choices
                            ],
                        }
                        for field in declared.fields
                    ],
                }
                for declared in section.lists
            ],
        }
        for section in SECTIONS
    ]


def resolve(document: dict, figures: dict[str, int]) -> dict:
    """Puts today's counts into the hero figures that asked for them.

    The page is never told which figures are live: it is handed numbers
    and draws them. Keeping the substitution here means the public page,
    the preview and the editor's hint all follow one rule, and a visitor's
    browser never counts anything.

    **A count of nothing falls back to the typed figure.** A platform with
    no schools yet saying "0 Schools" on its own front page helps nobody,
    and the typed value is already there, usually saying something like
    "500+ (Target)".
    """
    stats = document.get(STATS)

    if not isinstance(stats, list):
        return document

    resolved = []

    for item in stats:
        if not isinstance(item, dict):
            resolved.append(item)
            continue

        count = figures.get(item.get("source", TYPED), 0)
        resolved.append({**item, "value": f"{count:,}"} if count > 0 else item)

    return {**document, STATS: resolved}


# Where a footer line may point.
#
# `javascript:` is the reason this is a list of what is allowed rather than
# a list of what is not. The page is served to the open web, and a link
# whose address is script would run that script in the visitor's browser,
# with the Super Admin's typing as the source. Anything not named here is
# refused, so a scheme nobody thought about cannot slip through.
WEB_SCHEMES = ("https://", "http://")
HANDOFF_SCHEMES = ("mailto:", "tel:")


def url_problem(url: str) -> str | None:
    """Why this address may not be used, or None if it may.

    Four shapes, each doing something a visitor would expect:

    - `https://` or `http://` - somewhere else on the web, opened in a new
      tab so the homepage is not lost.
    - `/something` - a page of this app, such as `/login`.
    - `mailto:` or `tel:` - handed to whatever the device uses for those.
    """
    if url.startswith(WEB_SCHEMES):
        return None if len(url.split("://", 1)[1]) > 0 else "that address has nothing after the ://."

    if url.startswith(HANDOFF_SCHEMES):
        return None if len(url.split(":", 1)[1]) > 0 else "that address has nothing after the colon."

    if url.startswith("/"):
        return None if " " not in url else "a page of this site cannot have a space in it."

    return (
        "an address has to start with https://, http://, a / for a page of this site, "
        "or mailto: or tel:."
    )
