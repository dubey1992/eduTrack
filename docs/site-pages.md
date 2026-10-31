# Website pages, managed from the Super Admin panel

**Status (2026-10-27): backend built.** The public website's own pages -
About Us, the Privacy Policy, the Terms of Use, and anything else the Super
Admin adds (a Help Center, Careers) - are written, previewed and published
from the Super Admin panel instead of being written into the app as code.

```
FEATURE:   Website pages
OBJECTIVE: The Super Admin writes any number of public pages, previews
           them, and publishes when they are ready.
DATABASE:  site_pages (one row per page: a draft title and body, the
           published title and body, and who published it when)
API:       GET /api/v1/pages/{slug} (public, cached),
           GET/POST /api/v1/site-pages, GET/PUT/DELETE /api/v1/site-pages/{slug},
           POST /api/v1/site-pages/{slug}/publish (Super Admin only)
FLUTTER:   A Website Pages screen under the Super Admin panel; the public
           site reads each page from the API
```

## The decisions

Taken with the user on 2026-10-27.

**Any page, not a fixed set.** The Super Admin can add pages as the
business needs them - up to 50 in all, which keeps the list unpaged and
the footer sane. Each has its own address: school365ai.com/help-center.

**A text box with format buttons, and a live preview.** Not a
block-builder and not a rich-text editor. The page is plain text in a small
format (below); buttons insert the marks for a heading, a list, bold or a
link, and the preview beside the box draws the page as visitors will see
it. Plain text is something anybody can read, diff and paste from a
lawyer's email.

**Draft, preview, publish.** Exactly as the homepage works: saving changes
the draft, and visitors keep reading the last published version until
somebody publishes. A privacy policy half rewritten over a morning is not
something the world should read. Publishing an empty page is refused.

**Three built-in pages that always exist.** About Us (`about`), the Privacy
Policy (`privacy`) and the Terms of Use (`terms`). Their text ships in
code (`school/site_pages.py`), so an empty table still serves a privacy
policy - Google Play requires one. They can be edited and published but
never deleted, and their addresses never change, because the footer and
the app stores link to them.

- **About Us** and the **Privacy Policy** are live by default. The privacy
  policy carries its own date (2026-10-26) until somebody publishes their
  own version.
- **The Terms of Use** are *not* live by default. The shipped text has
  blanks - `[COMPANY LEGAL NAME]`, `[COUNTRY / STATE]` - that only the
  operator can fill in, and a page that says them is worse than none.

The first save or publish of a built-in creates its row, seeded with what
visitors already read, so saving a draft never changes the public page.

**Renaming a custom page is immediate.** The old address stops answering
and the new one starts at once; a renamed page is not a draft change.
Deleting a custom page takes it off the site at once too.

## The page-text format

Line by line, a deliberately small subset of Markdown:

| Typed | Drawn as |
|---|---|
| `# `, `## `, `### ` at the start of a line | a heading |
| `- ` or `* ` at the start of a line | a bullet |
| `1. ` (any number) at the start of a line | a numbered item |
| `---` alone on a line | a divider |
| a blank line | a new paragraph (a single newline is kept as a line break) |
| `**bold**` | bold |
| `[text](address)` | a link |

The client never renders it as HTML, so there is nothing to sanitise. The
one thing checked is where links point: every address must pass the
homepage footer's own rule (`marketing.url_problem`) - `https://`,
`http://`, `/a-page-of-this-site`, `mailto:` or `tel:`. A `javascript:`
address is refused, naming the link. The text is capped at 100,000
characters.

## Addresses

Lowercase letters, numbers and single hyphens, 2 to 60 characters
(`help-center`). Unique, and never a built-in's.

**Some addresses are reserved.** A page is served at
school365ai.com/<slug>, and the web `.htaccess` already turns plain
addresses like `/privacy` into the app's own routes. So a page may not take
an address that is already something: a screen of the app (`login`,
`dashboard`, `students`, ...), a part of the public site (`contact`,
`features`, `pages`), or a path the server answers itself (`api`, `assets`,
`canvaskit`, `404`). The list is `RESERVED_SLUGS` in `school/site_pages.py`.

## What holds it up

**The public read is cached** per address for an hour, a missing page
included, so a script asking for made-up addresses is answered from the
cache. Creating, publishing, renaming and deleting clear the addresses they
touch, so a visitor sees the change on the next request. An address that
could never be a page is refused before the cache or the database.

**Every change visitors could see is audited** - created, renamed,
published (with the text before and after) and deleted - under the
`settings` module, with no school.

## Blog posts and help articles (2026-10-31)

A Website Page is now one of three kinds: a page (`/<slug>`), a blog post
(`/blog/<slug>`) or a help article (`/help/<slug>`). The kind is chosen when
it is created and never changes. Posts carry a summary, an author and a
cover image; help articles a summary and a topic. Like the title and text,
each is a draft until published. See docs/seo.md, "S5 as built".

