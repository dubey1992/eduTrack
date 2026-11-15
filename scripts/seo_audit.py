"""The deeper SEO audit (docs/seo.md, 2026-11-15): the signals behind
Search Console's "Crawled - currently not indexed" that a link crawl
(scripts/seo_crawl.py) cannot see.

- every sitemap entry carries a last-changed date;
- no description is cut off with "...";
- each blog post and help article is linked from the text of at least two
  other pages, not only from menus and footers;
- no two pages share much of their own wording;
- blog posts are long enough to be worth indexing, and have a picture;
- posts' structured data carries dateModified and, ideally, their own image;
- http://, www., a trailing slash and /index.html all reach the one address
  in a single permanent redirect;
- pages are served with a UTF-8 charset.

    python scripts/seo_audit.py https://school365ai.com
"""

import html
import re
import sys
import urllib.error
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor

BASE = sys.argv[1].rstrip("/")
UA = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def get(url, follow=True):
    opener = urllib.request.build_opener() if follow else urllib.request.build_opener(NoRedirect)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        r = opener.open(req, timeout=90)
        return r.status, r.headers, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.headers, ""
    except Exception as e:  # noqa: BLE001 - report, never stop the audit
        return 0, {}, str(e)


def main_html(page):
    m = re.search(r"(?s)<main[^>]*>(.*?)</main>", page)
    return m.group(1) if m else page


def strip_chrome(fragment):
    """The page's own words: no forms, CTA band, related-posts lists."""
    fragment = re.sub(r"(?s)<(script|style|form|dialog)[^>]*>.*?</\1>", " ", fragment)
    fragment = re.sub(r'(?s)<section class="[^"]*(cta|related|more-posts)[^"]*".*?</section>', " ", fragment)
    return fragment


def words(fragment):
    text = html.unescape(re.sub(r"<[^>]+>", " ", fragment))
    return re.findall(r"[a-z0-9']+", text.lower())


def shingles(ws, n=6):
    return {" ".join(ws[i : i + n]) for i in range(max(0, len(ws) - n + 1))}


status, _, sitemap = get(BASE + "/sitemap.xml")
entries = re.findall(r"<url>(.*?)</url>", sitemap, re.S)
urls, lastmods = [], {}
for e in entries:
    loc = re.search(r"<loc>(.*?)</loc>", e).group(1)
    urls.append(loc)
    lm = re.search(r"<lastmod>(.*?)</lastmod>", e)
    lastmods[loc] = lm.group(1) if lm else None

pages = dict(zip(urls, ThreadPoolExecutor(8).map(lambda u: get(u)[2], urls)))
problems = defaultdict(list)

# 1. Sitemap dates.
for u in urls:
    if not lastmods[u]:
        problems["sitemap entry without lastmod"].append(u.replace(BASE, ""))

# 2. Descriptions cut off mid-sentence.
for u, p in pages.items():
    d = re.search(r'<meta name="description" content="([^"]*)"', p)
    if d and (d.group(1).endswith("...") or d.group(1).endswith("…")):
        problems["meta description cut off with an ellipsis"].append(u.replace(BASE, ""))

# 3. Links from the body of other pages (not the menu, footer or related lists).
inbound = defaultdict(set)
for u, p in pages.items():
    body = strip_chrome(main_html(p))
    for href in set(re.findall(r'href="(/[^"#?]*)"', body)):
        target = BASE + (href.rstrip("/") or "/")
        if target != u:
            inbound[target].add(u)
for u in urls:
    path = u.replace(BASE, "") or "/"
    if path.startswith(("/blog/", "/help/")) and len(inbound[u]) < 2:
        problems["post/article linked from fewer than 2 pages' own text"].append(
            f"{path} <- {sorted(x.replace(BASE, '') or '/' for x in inbound[u])}"
        )

# 4. Near-duplicate text between pages: each page's own article (its
# "prose" block), not the cards and call-to-action bands every page shares.
def own_text(page):
    """The page's article: the block whose class list holds the word
    "prose" (class="prose" or "prose-card prose"), up to where it closes."""
    match = re.search(r'(?s)<div class="(?:[^"]* )?prose(?: [^"]*)?">(.*?)</div>\s*</div>', page)
    return match.group(1) if match else ""


sh = {u: shingles(words(own_text(p))) for u, p in pages.items()}
items = list(sh.items())
for i in range(len(items)):
    for j in range(i + 1, len(items)):
        (a, sa), (b, sb) = items[i], items[j]
        if not sa or not sb:
            continue
        overlap = len(sa & sb) / min(len(sa), len(sb))
        if overlap > 0.15:
            problems["pages sharing >15% of their own wording"].append(
                f"{overlap:.0%} {a.replace(BASE, '') or '/'} ~ {b.replace(BASE, '') or '/'}"
            )

# 5. Body length of posts.
for u, p in pages.items():
    path = u.replace(BASE, "")
    n = len(words(own_text(p)))
    if path.startswith("/blog/") and n < 800:
        problems["blog post under 800 words of its own text"].append(f"{path} ({n})")

# 6. Pictures in posts.
for u, p in pages.items():
    path = u.replace(BASE, "")
    if path.startswith("/blog/") and "<img" not in main_html(p):
        problems["blog post with no picture"].append(path)

# 7. Structured data for posts.
for u, p in pages.items():
    path = u.replace(BASE, "")
    if path.startswith("/blog/"):
        if '"dateModified"' not in p:
            problems["BlogPosting without dateModified"].append(path)
        if "og-image.png" in (re.search(r'"image": "([^"]*)"', p) or [None, ""])[1]:
            problems["BlogPosting image is the site-wide card, not the post's own"].append(path)

# 8. Address variants all lead to the one canonical address in one hop.
host = re.sub(r"^https?://", "", BASE)
probe = urls[1] if len(urls) > 1 else BASE + "/"
variants = {
    "http://" + host + "/": BASE + "/",
    "https://www." + host + "/": BASE + "/",
    probe + "/": probe,
    probe.upper().replace(BASE.upper(), BASE): probe,
    BASE + "/index.html": BASE + "/",
}
for v, want in variants.items():
    code, headers, _ = get(v, follow=False)
    loc = headers.get("Location") if headers else None
    if code == 200 and v != want:
        problems["address variant answers 200 instead of redirecting"].append(v)
    elif code in (301, 308) and loc and loc.rstrip("/") != want.rstrip("/"):
        problems["address variant redirects somewhere else"].append(f"{v} -> {loc}")
    elif code in (302, 307):
        problems["address variant uses a temporary redirect"].append(f"{v} ({code})")
    elif code == 0:
        problems["address variant unreachable"].append(v)

# 9. Headers.
code, headers, _ = get(BASE + "/blog")
ctype = headers.get("Content-Type", "") if headers else ""
if "charset" not in ctype.lower():
    problems["HTML served without a charset in Content-Type"].append(ctype)
if headers and headers.get("X-Robots-Tag"):
    problems["X-Robots-Tag header present"].append(headers.get("X-Robots-Tag"))

print(f"Audited {len(urls)} sitemap URLs on {BASE}")
for k, v in problems.items():
    print(f"\n## {k} ({len(v)})")
    for x in v:
        print("  -", x)
if not problems:
    print("No problems found.")
