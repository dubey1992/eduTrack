"""Crawl a site as a search engine does and report everything that can keep
a page out of the index: status codes, redirects, canonical tags, noindex,
one H1, titles, descriptions, image alt text, thin pages, sitemap coverage,
orphans and duplicates (docs/seo.md). Run it with scripts/seo_audit.py,
which checks what a crawl cannot see.

    python scripts/seo_crawl.py https://school365ai.com
    python scripts/seo_crawl.py http://127.0.0.1:5078    # a local build
"""

import collections
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

BASE = sys.argv[1].rstrip("/")
HOST = urllib.parse.urlparse(BASE).netloc
UA = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


opener = urllib.request.build_opener(NoRedirect)


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        response = opener.open(request, timeout=30)
        return response.status, dict(response.headers), response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", "replace") if error.fp else ""
        return error.code, dict(error.headers), body
    except Exception as error:  # noqa: BLE001 - report, don't stop the crawl
        return 0, {}, str(error)


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links, self.canonical, self.robots, self.title, self.description = [], None, None, "", None
        self.h1, self.images_without_alt, self._in = [], 0, None
        self.og_image = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "a" and a.get("href"):
            self.links.append(a["href"])
        elif tag == "link" and a.get("rel") == "canonical":
            self.canonical = a.get("href")
        elif tag == "meta" and a.get("name") == "robots":
            self.robots = a.get("content")
        elif tag == "meta" and a.get("name") == "description":
            self.description = a.get("content")
        elif tag == "meta" and a.get("property") == "og:image":
            self.og_image = a.get("content")
        elif tag == "img" and not a.get("alt"):
            self.images_without_alt += 1
        if tag in ("title", "h1"):
            self._in = tag
            if tag == "h1":
                self.h1.append("")

    def handle_endtag(self, tag):
        if tag == self._in:
            self._in = None

    def handle_data(self, data):
        if self._in == "title":
            self.title += data
        elif self._in == "h1":
            self.h1[-1] += data


def normal(href, page_url):
    url = urllib.parse.urljoin(page_url, href)
    parsed = urllib.parse.urlparse(url)
    if parsed.netloc != HOST or parsed.scheme not in ("http", "https"):
        return None
    if parsed.path.startswith("/app/") or parsed.path.startswith("/site/") and parsed.path.endswith((".css", ".js")):
        return None
    if re.search(r"\.(png|jpe?g|ico|svg|webp|css|js|pdf|xml|txt)$", parsed.path):
        return None
    return urllib.parse.urlunparse((parsed.scheme, parsed.netloc, parsed.path or "/", "", parsed.query, ""))


status, _, sitemap = fetch(BASE + "/sitemap.xml")
in_sitemap = [loc for loc in re.findall(r"<loc>([^<]+)</loc>", sitemap)]
_, _, robots = fetch(BASE + "/robots.txt")

queue = collections.deque([BASE + "/"] + in_sitemap)
seen, results, linked_from = set(), {}, collections.defaultdict(set)

while queue:
    url = queue.popleft()
    if url in seen:
        continue
    seen.add(url)
    code, headers, body = fetch(url)
    entry = {"code": code, "location": headers.get("Location"), "xrobots": headers.get("X-Robots-Tag")}
    if code == 200 and "text/html" in headers.get("Content-Type", ""):
        parser = Page()
        parser.feed(body)
        entry.update(canonical=parser.canonical, robots=parser.robots, title=parser.title.strip(),
                     description=parser.description, h1=[h.strip() for h in parser.h1],
                     no_alt=parser.images_without_alt, words=len(re.sub(r"<[^>]+>", " ", body).split()),
                     og_image=parser.og_image)
        for href in parser.links:
            target = normal(href, url)
            if target:
                linked_from[target].add(url)
                queue.append(target)
    results[url] = entry

problems = collections.defaultdict(list)
titles, descriptions = collections.defaultdict(list), collections.defaultdict(list)
for url, e in sorted(results.items()):
    path = url.replace(BASE, "") or "/"
    if e["code"] in (301, 302, 307, 308):
        problems["redirect (linked internally or in the sitemap)"].append(
            f"{path} -> {e['location']}  linked from: {', '.join(sorted(p.replace(BASE, '') or '/' for p in linked_from[url]))[:150] or 'sitemap'}")
        continue
    if e["code"] != 200:
        problems[f"status {e['code']}"].append(
            f"{path}  linked from: {', '.join(sorted(p.replace(BASE, '') or '/' for p in linked_from[url]))[:150] or 'sitemap'}")
        continue
    if "title" not in e:
        continue
    if e["canonical"] != url:
        problems["canonical is not the page itself"].append(f"{path} canonical={e['canonical']}")
    if e["robots"] and "noindex" in e["robots"].lower() or (e["xrobots"] or "").lower().find("noindex") >= 0:
        problems["noindex"].append(path)
    if len(e["h1"]) != 1:
        problems["not exactly one h1"].append(f"{path} h1s={e['h1']}")
    if not e["description"]:
        problems["no meta description"].append(path)
    elif not 50 <= len(e["description"]) <= 300:
        # Whole sentences, up to the editor's 300-character summary
        # (public_site.snippet); Google shortens a long one on screen.
        problems["description length outside 50-300"].append(f"{path} ({len(e['description'])})")
    if not 15 <= len(e["title"]) <= 70:
        problems["title length outside 15-70"].append(f"{path} ({len(e['title'])}: {e['title']})")
    if e["no_alt"]:
        problems["images without alt"].append(f"{path} ({e['no_alt']})")
    if e["words"] < 250:
        problems["thin page (<250 words)"].append(f"{path} ({e['words']} words)")
    if url not in in_sitemap:
        problems["indexable page missing from sitemap"].append(path)
    if len(linked_from[url] - {url}) == 0 and path != "/":
        problems["no internal links to it"].append(path)
    elif len(linked_from[url] - {url}) <= 1 and path != "/":
        problems["only one page links to it"].append(f"{path} from {list(linked_from[url])[0].replace(BASE, '') or '/'}")
    titles[e["title"]].append(path)
    descriptions[e["description"]].append(path)

for title, paths in titles.items():
    if len(paths) > 1:
        problems["duplicate title"].append(f"{title!r}: {paths}")
for description, paths in descriptions.items():
    if description and len(paths) > 1:
        problems["duplicate description"].append(f"{paths}")
for loc in in_sitemap:
    if results.get(loc, {}).get("code") != 200:
        problems["sitemap lists a URL that is not 200"].append(f"{loc} ({results.get(loc, {}).get('code')})")

pages = [u for u, e in results.items() if e.get("code") == 200 and "title" in e]
print(f"Crawled {len(results)} URLs; {len(pages)} pages answer 200 with HTML; sitemap lists {len(in_sitemap)}.")
print(f"robots.txt: {robots.strip().splitlines()[-3:] if robots else 'none'}")
for kind, items in problems.items():
    print(f"\n## {kind} ({len(items)})")
    for item in items:
        print("  -", item)
