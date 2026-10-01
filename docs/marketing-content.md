# The marketing page, managed from the Super Admin panel

**Status (2026-10-01): planned.** Decided with the user on 2026-10-01. The
public homepage at `/` is a Flutter recreation of the marketing prototype
with every word written into the widgets as a `const`. Changing the
headline currently means a code change, a build and a deploy. This puts the
words behind the Super Admin panel.

```
FEATURE:   Editable marketing content
OBJECTIVE: The Super Admin edits the public homepage's words and lists,
           previews them, and publishes when they are ready.
DATABASE:  marketing_content (one row: a draft document, a published
           document, and who published it when)
API:       GET /api/v1/marketing-content (public, cached),
           GET/PUT /api/v1/marketing-content/draft, POST .../publish
FLUTTER:   A Marketing Content screen under the Super Admin panel; the
           marketing page reads its words from the API
```

## What is on the page today

Six sections, about eighty strings, roughly thirty of them inside
repeating lists:

| Section | Content |
|---|---|
| Nav bar | wordmark, tagline, six nav labels, two button labels |
| Hero | eyebrow, headline, body, two buttons, trust line, **five stats** |
| Features | eyebrow, title, body, **ten cards** (icon, title, description) |
| Mobile app | eyebrow, headline, body, two store badges, mockup copy |
| Web app | eyebrow, headline, body, **four bullets**, mockup KPIs |
| CTA | headline, body, button label |
| Footer | wordmark, blurb, **three link columns (twelve links)**, newsletter copy, copyright |

## The decisions

Taken with the user on 2026-10-01.

**The words and the lists, not the layout.** Every headline, body and
label is editable, and the repeating items can be added, removed, reordered
and edited. The order of the sections and the design of the page are not
editable: this is a designed page whose shape is part of the product, and a
block-builder would put that shape in the hands of whoever is typing.

**Draft, preview, publish.** The public page keeps showing the last
published document until somebody publishes a new one. This is the face
the product shows the world, and a typo saved at speed should not be live
to it. Publishing is one explicit act with a preview before it.

**No images yet.** The wordmark stays a styled text string and the
dashboard and phone mockups stay drawn in Flutter. Uploading a logo needs
*public* file serving, and the only file path the product has today - the
profile photo - is deliberately authenticated-only. That is new ground and
it can wait.

**The hero stats may show real platform figures.** Each stat is either a
fixed value the Super Admin types, or a live figure - the number of schools
on the platform, or of students. Chosen per stat rather than by one
switch, so a platform with three schools can keep "500+ (Target)" on the
board until the real number is worth showing, and swap it over without a
deploy.

The dashboard mockup's KPIs - "Students 1,248", "Attendance 93%" - stay
fixed text. They sit inside a drawing of *one school's* dashboard, and
platform-wide totals in that frame would be describing something the
picture is not showing. Raised with the user; change it if that reading is
wrong.

## What holds the whole thing up

**The current copy is the default, in code.** Not seed data, not a
migration that inserts rows: the defaults live beside the declaration, so
an empty table, a failed request and a backend that is down all render
exactly the page that ships today. A marketing homepage that shows an
empty hero because an API call failed is worse than one that cannot be
edited.

**The document is declared once.** Sections and their fields are a
declaration in code, the way `school/modules.py` declares module settings -
so the API shape, the defaults and the editor's form all come from one
place and a new field is one line rather than four.

**The public read is cached.** Every visitor to the homepage hits it, and
it must not become a database query per visit. The same cache the module
settings use, cleared on publish.

**Who may do what.** Reading the published document is public - that is the
point of it. Everything else is the Super Admin's. One path serving both,
checking who is asking, the way `early_access` already serves a public
signup and a private queue.

## The slices

### Slice 1 - The words come from the server

The declaration, the defaults, the table, and the public cached GET. The
marketing page reads its words from the API and falls back to the defaults
when it cannot.

**Demo:** the page looks exactly as it does today. That is the whole test.

Edge cases: no row at all; a row with a section missing; a field added to
the declaration after a document was saved; the API refusing; a slow API
(the page must not flash empty); the cache serving a stale document after
a publish.

### Slice 2 - Editing, and publishing

The Super Admin screen for the fixed text fields, built from the
declaration, with the draft/preview/publish cycle. Publishing clears the
public cache.

Edge cases: a field left empty (the default, or a refusal); a very long
headline; markup typed into a field; two admins editing at once;
publishing with nothing changed; previewing a draft that is not published.

### Slice 3 - The lists

Features, hero stats, footer links and the web-app bullets: add, remove,
reorder, edit. Icons for feature cards come from a fixed set rather than
free text, so a card cannot be given a glyph the font has no room for.

Edge cases: emptying a list entirely; one item; many more than the design
expects; reordering then cancelling; a removed item that was published.

### Slice 4 - The live figures

A hero stat may be a live platform figure instead of typed text. Counted
cheaply and cached with the document.

Edge cases: a platform with no schools; counting only active schools and
students; the figure while the cache is cold; a stat switched from live
back to fixed.
