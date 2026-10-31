# Search engine optimisation (SEO)

How school365ai.com gets found on Google and Bing by schools looking for
software. This plan was written on 2026-10-30 after reviewing the live site.
Nothing in it is built yet.

## Where the site stands today

The whole public website is the Flutter app. A crawler that fetches
https://school365ai.com/ receives a 4.6 KB HTML shell. That shell holds a
loading animation, the title "School365ai", a single sentence of description,
and a script tag. Everything a visitor reads (the headline "Run Your School
Smarter, Together.", the ten features, the mobile and web sections, the
footer) is painted onto a canvas by Flutter after about 1.5 MB of compressed
JavaScript and the CanvasKit renderer have downloaded.

| Check | Today | Why it matters |
|---|---|---|
| Readable text in the HTML | none: canvas only | Google can run JavaScript, but text painted on a canvas is not text to it. As far as search engines can tell, the homepage has no content. |
| Page addresses | `/#/pages/about`, `/#/?section=features` | Everything after `#` is ignored by search engines, so the whole site is one URL. |
| `/about`, `/terms`, `/privacy` | 302 redirect to a `#` address | The plain addresses redirect away instead of being pages, so they cannot rank. |
| robots.txt | 404 | Nothing tells crawlers what to skip or where the sitemap is. |
| sitemap.xml | 404 | Crawlers have no list of the pages. |
| `<title>` | "School365ai" on every page | Says nothing about what the product is. |
| Meta description | one generic sentence | It is the snippet shown under the link in results. |
| `<html lang>` | missing | Language and accessibility signal. |
| Open Graph / social cards | none | A link shared on WhatsApp, LinkedIn or X shows no image or summary. |
| Structured data (schema.org) | none | Rich results and brand knowledge panel. |
| Canonical URL | none | Duplicate addresses (http, www, `/index.html`) can split ranking. http and www already 301 to https, which helps. |
| Footer links | Blog, Help Center, Careers and Terms lead to "page not available" | Dead links on every page; a crawler counts them as broken. |
| Unknown address | 302 then a 200 "not available" page | A "soft 404", which Google flags in Search Console. |
| API host | no robots.txt and no `X-Robots-Tag` | API JSON could be indexed. |
| Speed of the first page view | about 1.5 MB of compressed JS before any text shows | Core Web Vitals is a ranking signal, and it weighs most on mobile. |

**In short, the site cannot rank for anything except, eventually, its own
name.** None of the gaps above is about wording. The problem is the
architecture: a canvas-rendered single-page app cannot be the public
website.

## The approach: two sites, one domain

Keep the Flutter app exactly as it is for signed-in people, and give the
public pages real, server-rendered HTML.

```
school365ai.com/                 static HTML  (homepage)
school365ai.com/features/...     static HTML  (one page per module)
school365ai.com/about, /privacy, /terms, /careers, /blog/...
                                 static HTML  (Website Pages)
school365ai.com/app/             the Flutter app (login and everything after it)
api.school365ai.com              the API, never indexed
```

**The Super Admin keeps editing exactly as today.** Homepage Content and
Website Pages stay the source of truth. When either is published, the server
renders those pages to plain HTML files in `public_html` and rewrites
`sitemap.xml`. Visitors and crawlers then get static files: fast, cacheable,
no Python on the request path, and no change to how editing works. If
writing the files ever fails, publishing still succeeds and the error is
shown, so a broken render can never block an edit.

The static pages use the same brand: colours, the Poppins font, the logo,
and the same copy, because they read the same homepage document. Buttons such
as "Request a Demo" and "Join Early Access" become small HTML forms that post
to the existing API endpoints, so those two forms keep working without the
app.

### Keeping every existing link working

Links already sent out point at `https://school365ai.com/#/...`: set-password
and reset emails (`jobs.py` builds `/#/reset-password?...`), the Play Store
listing, and bookmarks. A server never sees the part after `#`, so once `/`
is a static page those links would land on the homepage.

The fix is one line of script at the top of every static page: if the
address has a `#/` route, go to `/app/` with the same route. Every old link
keeps working. New emails will link to `/app/#/...` directly.

### Why not the alternatives

- **Pre-rendering the Flutter app.** Pre-rendering captures a canvas, so
  there is still no text.
- **Flutter's HTML renderer.** It has been removed from Flutter, and it was
  never meant for SEO.
- **A separate CMS (WordPress, Webflow).** A second system to host, secure
  and keep in step, and the Super Admin would edit in two places.

## The phases

| | Phase | What it does |
|---|---|---|
| S1 | Quick fixes (**built 2026-10-30**) | See "S1 as built" below. |
| S2 | Static public site (**built 2026-10-30**) | See "S2 as built" below. This is the change that makes ranking possible. |
| S3 | Pages that match searches | One page per module, written for how schools search: school attendance software (with SMS alerts to parents), school fee management (receipts, reminders, per-currency), school bus tracking (live GPS, boarding alerts), timetable, staff payroll, biometric attendance, teaching reports and syllabus tracking, the staff and driver apps. Each page has a real description of what the module does, screenshots, and a demo button. The homepage feature cards link to them. |
| S4 | Structured data and FAQs | schema.org `Organization`, `WebSite`, `SoftwareApplication` (category EducationalApplication; Web and Android), `BreadcrumbList`, and `FAQPage` on pages that carry real FAQs. No made-up ratings or reviews: Google penalises them, and they would be false. |
| S5 | Blog and help centre | Website Pages gain a "Blog post" kind (date, author, summary, cover image) and a `/blog` index; help articles at `/help/...`. Written content is what earns links and long-tail searches ("how to track school bus attendance", "school fee receipt format"). |
| S6 | Measure | Google Search Console and Bing Webmaster Tools verified (a DNS or meta-tag step), the sitemap submitted, indexing and search terms watched. Visitor analytics is a separate decision (see below). |

## S1 as built (2026-10-30)

- **`robots.txt`** on school365ai.com allows everything (`frontend/web/robots.txt`). The sitemap line comes with S2, once there are real pages to list.
- **The API host** answers `/robots.txt` with `Disallow: /`, and every response carries `X-Robots-Tag: noindex, nofollow` (`school/security.py`).
- **`index.html`** now has `lang="en"`, the title "School365ai - School Management Software for Attendance, Fees and Transport", a real description, a canonical URL, `theme-color`, and Open Graph and Twitter tags pointing at `og-image.png` (1200 x 630, drawn by `scripts/og_image.py`).
- **A `<noscript>` version of the homepage**: a heading, what the product does (only what is really built), and links to About, Privacy and Sign in. It also hides the loading screen, which would otherwise cover it for ever.
- **Footer links to unpublished website pages are hidden.** The homepage API now sends `pages`, the slugs visitors can read (cached, and cleared whenever a page is created, published, renamed or deleted). The footer drops any link to a school365ai.com page that is not among them, and the link comes back the moment the page is published. Today that hides Careers, Blog, Help Center, Pricing, Security and Terms. Homepage sections, app screens and other sites are never hidden.
- **Moved to S2: a real 404 for unknown addresses.** A plain address still redirects into the app, which shows "not available". Answering 404 needs the server to know which pages exist, and that is exactly what the static pages of S2 give it. The alternatives were a hand-kept list in `.htaccess`, which would break plain addresses for new pages, or a PHP lookup on every hit.

## S2 as built (2026-10-30)

- **`school/public_site.py`** writes the public pages as plain HTML into
  `PUBLIC_SITE_DIR` (the web root): `index.html` (the homepage), one
  `site/pages/<slug>.html` per published Website Page (served at
  `/<slug>`), `404.html`, `sitemap.xml`, `robots.txt` (crawl everything but
  `/app/`; points at the sitemap), `site/site.css`, `site/site.js`,
  `favicon.png` and `og-image.png`. Django templates in
  `school/templates/public_site/`, so everything typed is escaped.
- **When**: publishing the homepage, publishing, renaming or deleting a
  Website Page, and every deploy (`manage.py build_public_site`, which also
  writes the web root's `.htaccess`). A failure to write is logged and
  returned as `website_problem`; the editors show "Published, but the
  website copy was not updated", and the publish itself stands.
- **The words**: the published document over the same defaults as the app.
  The server keeps its own copy (`school/marketing_copy.py`); a test reads
  `marketing_defaults.dart` and fails if the two differ.
- **Website Page text** is converted by `school/site_markup.py`: the same
  small Markdown subset, escaped first, with every link checked again.
- **Links**: app screens (`/login`) go to `/app/#/login`; homepage sections
  (`/features`) to anchors; published pages to their plain address; footer
  links to unpublished pages are left out, as in S1.
- **The two forms** (changed 2026-10-31, at the user's request: sending
  visitors into the app looked wrong): "Request a Demo" and "Join Early
  Access" open as dialogs on whichever public page the visitor is on
  (`templates/public_site/forms.html`), and `site.js` sends them to the same
  API endpoints the app's forms use (`PUBLIC_API_URL`). Each field is
  checked first; what the server refuses shows beside its field; a
  throttled or failed send says so; success shows the server's thank-you.
  The web root's CSP allows `connect-src` to the API for this. The app's
  `?open=demo` / `?open=join` still work for links into the app.
- **`www.`** redirects to the bare domain, so the pages are never seen
  twice (the app under `/app/` is left alone).
- **The apps** (2026-10-31): the homepage names the two that exist -
  School365ai for staff, School365ai Driver for bus crews - with a card for
  each; the app's own phone mockups show those two, not a parent app.
- **Left out on purpose**: the footer's newsletter box (it stored nothing
  and only said "You're on the list") and the hero's "Watch Video" button
  (there is no video; it opened Early Access). The app's own homepage still
  shows both; deciding their fate is the Super Admin's.
- **The app** moved to `/app/` (`flutter build web --base-href /app/`). Its
  `index.html` says `noindex`. Every public page loads `site/site.js` first,
  which sends an old `/#/...` link on to `/app/#/...`, so emailed
  set-password and reset links, bookmarks and the Play listing keep working.
- **Real 404s**: an address that is neither a file nor a published page
  gets `404.html` with a 404 status (it carries `noindex`).
- **Not yet**: the homepage's live figures are refreshed on publish and
  deploy only; there is no nightly rebuild, because every figure on it is
  typed today. Leftover root files of the old app build (`main.dart.js`,
  `canvaskit/` and so on) are harmless and can be cleared once `/app/` has
  run for a while; `flutter_service_worker.js` must stay, so any browser
  still holding the old worker can fetch it and unregister.

## Content notes

- **Hero figures.** The live homepage shows "500+ Schools (Target)" and
  "Students (Target)". Targets presented as figures weaken trust with a
  reader and with Google's quality raters. Show real live figures (the
  homepage can already show counts of live and trial schools), or remove
  the figures.
- **One clear phrase per page.** The homepage targets "school management
  software". Each module page targets its own phrase, and two pages never
  compete for the same one.
- **Countries.** The product serves several countries (per-school currency
  and timezone). A page per country ("school management software in Nigeria")
  is worth it only with real local substance: currency, SMS rules such as
  India's DLT, payment modes. Otherwise it is a thin "doorway page" and hurts
  more than it helps. English only for now; no `hreflang` until there is a
  second language.
- **Images.** Real screenshots with descriptive `alt` text, served as WebP at
  the size shown.
- **Brand consistency.** "School365ai" everywhere (title, logo alt text,
  schema, social profiles, Play Store listing) so Google links them as one
  brand.

## Decisions needed

1. **Where the app lives.** `school365ai.com/app/` (recommended: one
   domain, no new certificate or CORS origin) or `app.school365ai.com` (a
   new subdomain; the CSP and the API's CORS list change too).
2. **Visitor analytics.** None beyond Search Console (recommended to start;
   no cookie banner needed), or a privacy-friendly counter, or Google
   Analytics 4 (needs a cookie notice).
3. **The hero figures.** Live figures, or none.
4. **Blog and help centre (S5).** Whether to start one, and who writes:
   the product can carry it, but it only pays off with regular posts.
5. **Countries to target first** (S3), if any beyond the generic pages.
