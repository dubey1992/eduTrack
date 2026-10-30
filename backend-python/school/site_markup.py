"""A website page's text as HTML, for the plain-HTML website (docs/seo.md, S2).

Website Pages are typed in a small subset of Markdown (docs/site-pages.md):

    # / ## / ###      a heading
    - or *            a bullet
    1.                a numbered item
    ---               a divider
    a blank line      a new paragraph; a single newline is a line break
    **bold**          bold
    [text](address)   a link

Everything typed is escaped before any of it becomes markup, so a page can
say "<script>" and it reads as those characters. Links are checked again
here with the rule they were saved under (`marketing.url_problem`): a link
that would not pass now is left as its words, never as a link.

The page's title is its `<h1>`, so `#` in the text is an `<h2>`.
"""

from __future__ import annotations

import html
import re

from . import marketing

HEADING = re.compile(r"^(#{1,3}) +(.*)$")
BULLET = re.compile(r"^[-*] +(.*)$")
NUMBERED = re.compile(r"^\d+\. +(.*)$")
DIVIDER = re.compile(r"^-{3,}$")
BOLD = re.compile(r"\*\*(.+?)\*\*")
# Over escaped text: neither brackets nor parentheses are touched by escaping.
LINK = re.compile(r"\[([^\]]+)\]\(([^)\s]*)\)")


def to_html(body: str) -> str:
    blocks: list[str] = []
    paragraph: list[str] = []
    items: list[str] = []
    list_tag: str | None = None

    def close_paragraph():
        if paragraph:
            blocks.append("<p>" + "<br>\n".join(inline(line) for line in paragraph) + "</p>")
            paragraph.clear()

    def close_list():
        nonlocal list_tag
        if items:
            blocks.append(f"<{list_tag}>" + "".join(f"<li>{inline(item)}</li>" for item in items) + f"</{list_tag}>")
            items.clear()
        list_tag = None

    def open_list(tag: str):
        nonlocal list_tag
        if list_tag != tag:
            close_list()
            list_tag = tag

    for raw in (body or "").replace("\r\n", "\n").split("\n"):
        line = raw.strip()

        if not line:
            close_paragraph()
            close_list()
            continue

        if DIVIDER.match(line):
            close_paragraph()
            close_list()
            blocks.append("<hr>")
            continue

        heading = HEADING.match(line)
        if heading:
            close_paragraph()
            close_list()
            level = len(heading.group(1)) + 1
            blocks.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
            continue

        bullet = BULLET.match(line)
        numbered = None if bullet else NUMBERED.match(line)
        if bullet or numbered:
            close_paragraph()
            open_list("ul" if bullet else "ol")
            items.append((bullet or numbered).group(1))
            continue

        close_list()
        paragraph.append(line)

    close_paragraph()
    close_list()

    return "\n".join(blocks)


def inline(text: str) -> str:
    """One line's words: escaped, then bold and links."""
    escaped = html.escape(text, quote=True)
    escaped = BOLD.sub(r"<strong>\1</strong>", escaped)

    return LINK.sub(_link, escaped)


def _link(match: re.Match) -> str:
    words, address = match.group(1), html.unescape(match.group(2))

    if marketing.url_problem(address) is not None:
        return words

    href = html.escape(address, quote=True)

    if address.startswith(("https://", "http://")) and not _ours(address):
        return f'<a href="{href}" rel="noopener" target="_blank">{words}</a>'

    return f'<a href="{href}">{words}</a>'


def _ours(address: str) -> bool:
    return re.match(r"^https?://(www\.)?school365ai\.com(/|$)", address) is not None
