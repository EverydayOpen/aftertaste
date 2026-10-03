"""Build the product website: site/src + site/static + CHANGELOG.md -> site/_dist.

Stdlib only. Pages are site/src/pages/**/*.html: a first line `<!--meta {json}-->` (title, description, optional
"noindex": true), then the body, which site/src/layout.html wraps.
{{key}} is replaced by site.json values and the computed values in values(); an unknown key fails the build.
Sources link root-relative (href="/support/"); the build prefixes those with baseURL's path, so the site works as a
GitHub Pages project site (https://everydayopen.github.io/aftertaste) and on a custom domain (https://example.com).
Canonicals, og:image, the sitemap, the feed, robots.txt and llms.txt use the full baseURL.

  python tools/build_site.py           writes site/_dist
  python tools/build_site.py --check   builds into temp dirs for baseURL, its bare origin and a /<releases repo>
                                       project path, then checks internal links (inside the path prefix), anchors,
                                       assets, meta tags, headings, alt text, XML, sitemap/feed/llms.txt URLs,
                                       placeholders, text contrast, exactly two root-selector CSS blocks, theme
                                       switches, the CSP (no inline script, style or handler), rel=noopener on
                                       external links, the not-affiliated line on every page, no webfont, size
                                       budgets, every <img> sized, tools/banned_phrases.txt over everything built
                                       (a line marked no-claim-ok is exempt) and the word "safe" only in the one guide
                                       title that is a search phrase (docs/DESIGN.md §1 decision 8); exit 1 on any problem
"""
import datetime
import html
import json
import re
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET
from email.utils import format_datetime
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
import changelog  # noqa: E402  tools/changelog.py: parse(path), to_html(md)

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
PLACEHOLDER = re.compile("REPLACE_ME|OWNER")
# layout.html's Content-Security-Policy allows only same-origin files, so no page may use inline code.
CSP = "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'"
# Bytes, for each built file matching the pattern (docs/DESIGN.md §8).
BUDGET = {"styles.css": 40_000, "motion.js": 6_000, "index.html": 36_000, "shots/*": 110_000}
AFFILIATION = "not affiliated with or endorsed by any app it detects"
SAFE = re.compile(r"\bsafe(?:ly|r|st)?\b", re.I)
SAFE_OK = ("Is it safe to delete ~/Library leftovers?", "is-it-safe-to-delete-library-leftovers-mac")   # guide G2: its title is the question people type, its URL says so (DESIGN §5)


class Raw(str):
    """Already HTML: inserted without escaping."""


def banned():
    """tools/banned_phrases.txt as one case-insensitive regex (the same list tools/safety_greps.sh check 17 uses)."""
    f = ROOT / "tools" / "banned_phrases.txt"
    pats = [l.strip() for l in f.read_text(encoding="utf-8").splitlines() if l.strip() and not l.lstrip().startswith("#")] if f.exists() else []
    return re.compile("|".join(pats), re.I) if pats else None


def fill(template, values, where, esc=html.escape):
    def sub(m):
        if m.group(1) not in values:
            sys.exit(f"{where}: unknown {{{{{m.group(1)}}}}}")
        v = values[m.group(1)]
        return v if isinstance(v, Raw) else esc(str(v))
    return re.sub(r"\{\{(\w+)\}\}", sub, template)


def pretty(iso):
    d = datetime.date.fromisoformat(str(iso))
    return f"{d.day} {d:%B %Y}"


def fmt_bytes(n):
    """Sizes as the app shows them (Format.bytes in Sources/AftertasteCore/Text/Format.swift): decimal, one decimal below 100."""
    if n < 1000: return f"{n} bytes"
    units, value, unit = ["KB", "MB", "GB", "TB"], n / 1000, 0
    while True:
        tenths = int(value * 10 + 0.5)
        one = unit > 0 and tenths < 1000
        if int(value + 0.5) >= 1000 and unit < len(units) - 1:
            value, unit = value / 1000, unit + 1
            continue
        if one and tenths % 10: return f"{tenths // 10}.{tenths % 10} {units[unit]}"
        return f"{tenths // 10 if one else int(value + 0.5)} {units[unit]}"


def orbit_sample():
    """The sample app of the home page, how-it-decides and the guide, read from the Core demo (DemoScenarios.orbit) so the site
    cannot drift from what the app shows. Orphan caps (APP4 §3.2): only a stale exact-ID cache or log is High, the rest is Medium."""
    src = (ROOT / "Sources/AftertasteCore/Demo/DemoScenarios.swift").read_text(encoding="utf-8")
    m = re.search(r"static func orbit\(.*?\n    \}\n", src, re.S)
    if not m: sys.exit("build_site: DemoScenarios.swift has no orbit() to read the sample numbers from")
    size, days, launch, helpers, files, rows, total = {}, {}, 0, 0, 0, 0, 0
    for kind, root, nbytes, count, age in re.findall(r"^\s*\.(dir|file)\(\.(\w+), .+?, ([\d_]+), (?:(\d+), )?(\d+)\)", m[0], re.M):
        rows, total = rows + 1, total + int(nbytes.replace("_", ""))
        files += int(count) if kind == "dir" else 1
        if root == "launchAgents": launch += 1
        elif root == "systemPrivilegedHelperTools": helpers += 1
        else: size[root], days[root] = int(nbytes.replace("_", "")), int(age)
    need = ("caches", "logs", "savedState", "webKit", "httpStorages", "preferences", "applicationSupport")
    if launch != 2 or helpers != 1 or any(r not in size for r in need): sys.exit("build_site: orbit() no longer matches the sample (2 launch agents, 1 helper, 7 folders)")
    if days["caches"] < 30 or days["logs"] < 30:
        sys.exit("build_site: the demo's Orbit Meet cache or log is under 30 days old, so it would not be High (README, orphan rule)")
    who = re.search(r'app\(id, "([^"]+)", "[^"]*", team: "[^"]*", version: "([^"]+)"', m[0])
    osv = re.search(r'static let osVersion = "([^"]+)"', src)
    if not who or not osv: sys.exit("build_site: DemoScenarios.swift no longer has the app name, version or osVersion the card reads")
    segs = [("Caches", size["caches"], True), ("Logs", size["logs"], True),
            ("Saved state, WebKit", size["savedState"] + size["webKit"], False),
            ("Web storage, settings", size["httpStorages"] + size["preferences"], False),
            ("Your data", size["applicationSupport"], False)]
    high, other = segs[0][1] + segs[1][1], sum(b for _, b, h in segs if not h)
    li = {True: '<li class="hi">', False: "<li>"}
    key = "".join(f"{li[h]}{n} {fmt_bytes(b)}</li>" for n, b, h in segs) + f"<li>Launch agents {launch}</li>"
    low = lambda n: n[0].lower() + n[1:]
    label = (f"Sample data: one bar for Orbit Meet 6.2. High, selected: {low(segs[0][0])} {fmt_bytes(segs[0][1])}, {low(segs[1][0])} {fmt_bytes(segs[1][1])}. "
             "Medium, not selected: " + "; ".join(f"{low(n)} {fmt_bytes(b)}" for n, b, _ in segs[2:]) + f". {launch} launch agents, listed only.")
    bar = ('<div class="rbar" role="img" aria-label="' + html.escape(label) + '">' + '<i class="hi"></i>' * 2 + "<i></i>" * 4 + "</div>\n    "
           f'<ul class="rbar-key" aria-hidden="true">{key}</ul>\n    '
           f'<p class="rbar-sum">{fmt_bytes(high)} selected (rebuilds itself) · {fmt_bytes(other)} not selected · {launch} launch agents listed</p>')
    return {"orbitCaches": fmt_bytes(size["caches"]), "orbitLogs": fmt_bytes(size["logs"]), "orbitState": fmt_bytes(segs[2][1]),
            "orbitData": fmt_bytes(size["applicationSupport"]), "orbitBar": Raw(bar),
            # The sidebar row of the app: "10 items · 1.3 GB", chips "2 High" and "5 Medium" (the rest is listed only).
            "orbitItems": rows, "orbitFiles": files, "orbitTotal": fmt_bytes(total), "orbitHigh": fmt_bytes(high),
            "orbitHighN": 2, "orbitMediumN": rows - launch - helpers - 2, "orbitListedN": launch + helpers,
            "orbitName": f"{who[1]} {who[2]}", "orbitOS": osv[1], "orbitLaunch": launch, "orbitHelpers": helpers,
            # styles.css sizes the bar's segments by MB (.rbar i:nth-child(n)); check() compares them with these.
            "orbitGrow": [round(b / 1e6) if b >= 1e7 else round(b / 1e6, 1) for _, b, _ in segs] + [.1]}


def coverage_sample():
    """The coverage line of the `leftovers` demo scan, worded as PlanText.coverageLine does: each LibraryRoot case is one place
    and the scenario protects the roots it lists. Read from Core so the site cannot show totals the engine never produces."""
    paths = (ROOT / "Sources/AftertasteCore/Model/Paths.swift").read_text(encoding="utf-8")
    body = re.search(r"enum LibraryRoot\b.*?\n    /// Under", paths, re.S)
    demo = (ROOT / "Sources/AftertasteCore/Demo/DemoScenarios.swift").read_text(encoding="utf-8")
    prot = re.search(r"scenario == \.blocked \? \[[^\]]*\] : \[([^\]]*)\]", demo)
    if not body or not prot: sys.exit("build_site: Paths.swift or DemoScenarios.swift no longer has the shape coverage_sample() reads")
    places = sum(len(l.split(",")) for l in re.findall(r"^    case ([\w, ]+)$", body[0], re.M))
    blocked = len([r for r in prot[1].split(",") if r.strip()])
    return f"Looked in {places - blocked} of {places} places." + (f" {blocked} protected by macOS." if blocked else "")


def card_sample(v):
    """The Trace Report card of the sample app, worded as TraceReportText does (APP4 §2.4): the home page's hero card and the two
    static faces under "A receipt" are built from this one place. Counts come from the Core demo (orbit_sample), so a zero count is
    left out and the "listed, not removed" note names only what the card counts."""
    plural = lambda n, w: f"{n} {w}" + ("" if n == 1 else "s")
    num, unit = v["orbitTotal"].split()
    figs = [f"<b>{v['orbitFiles']}</b> files", f"<b>{num}</b> {unit}", f"<b>{v['orbitLaunch']}</b> launch agent" + ("" if v["orbitLaunch"] == 1 else "s"),
            f"<b>{v['orbitHelpers']}</b> privileged helper" + ("" if v["orbitHelpers"] == 1 else "s")]
    plain = [f"{v['orbitFiles']} files", v["orbitTotal"], plural(v["orbitLaunch"], "launch agent"), plural(v["orbitHelpers"], "privileged helper")]
    note = "Launch agents and helpers are listed, not removed."
    when, how = f"macOS {v['orbitOS']} · scanned 2026-10-03", "measured on this Mac, nothing sent anywhere"   # one line on the 1200 px card, two here
    prov = f"{when} · {how}"
    site = urlsplit(v["baseURL"]); where = site.netloc + site.path
    footer = "This is a list of what was found in the places listed above. It is not proof that anything was erased."
    src = (ROOT / "Sources/AftertasteCore/Text/PlanText.swift").read_text(encoding="utf-8")
    nc = re.search(r"func notCovered\(\) -> \[String\] \{\s*\[(.*?)\]\s*\}", src, re.S)
    if not nc or "/private/var" not in nc[1]: sys.exit("build_site: PlanText.notCovered() no longer has the shape card_sample() reads")
    not_covered = " · ".join(re.findall(r'"([^"]+)"', nc[1]))
    front = ('<p class="card-brand"><svg aria-hidden="true"><use href="#i-mark"/></svg>Aftertaste<span class="tag violet">Sample data</span></p>\n'
             f'<p class="card-h"><b>{html.escape(v["orbitName"])}</b> left behind</p>\n'
             f'<p class="card-figs">{" · ".join(figs)}</p>\n'
             f'<p class="card-cov">{v["coverageSample"]}<br>{note}</p>\n'
             f'<p class="card-prov"><span>{when}</span><span>{how}</span><span>{where}</span></p>')
    back = (f'<p class="card-foot">{footer}</p>\n'
            f'<p class="card-nc"><span class="label">Not covered</span>{html.escape(not_covered)}</p>')
    aria = (f"Illustration with sample data: the Aftertaste Trace Report card. {v['orbitName']} left behind: {', '.join(plain)}. "
            f"{v['coverageSample']} {note} {prov.replace(' · ', ', ')}. On the back: {footer[0].lower() + footer[1:-1]}; "
            f"not covered: {not_covered.lower()}.")
    return {"cardFront": Raw(front), "cardBack": Raw(back), "cardAria": aria, "cardPlain": ", ".join(plain)}


def values(site):
    v = dict(site)
    base = site["baseURL"]
    v["year"] = datetime.date.today().year
    v["downloadURL"] = f"https://github.com/{site['releasesRepo']}/releases/latest/download/{site['dmgName']}"
    v["issuesURL"] = f"https://github.com/{site['releasesRepo']}/issues"
    v["wrongMatchURL"] = v["issuesURL"] + "/new?template=wrong-match.yml"
    v["falsePositiveURL"] = v["wrongMatchURL"]   # alias for pages copied from a sibling app
    v["releasesURL"] = f"https://github.com/{site['releasesRepo']}/releases"
    ld = {"@context": "https://schema.org", "@type": "SoftwareApplication", "name": site["name"],
          "operatingSystem": f"macOS {site['minMacOS']} or later", "applicationCategory": "UtilitiesApplication",
          "description": site["tagline"], "url": base + "/", "image": base + "/og.png",
          "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"}}
    v.update(orbit_sample())
    v["coverageSample"] = coverage_sample()
    v.update(card_sample(v))
    v["softwareJSON"] = Raw(json.dumps(ld, ensure_ascii=False).replace("</", "<\\/"))
    return v


def pages():
    """(output path, url, meta, body) for every page source."""
    src = SITE / "src" / "pages"
    for f in sorted(src.rglob("*.html"), key=lambda f: f.relative_to(src).as_posix().removesuffix("index.html")):
        rel = f.relative_to(src).as_posix()
        text = f.read_text(encoding="utf-8")
        m = re.match(r"<!--meta (\{.*?\})-->\n", text, re.S)
        if not m:
            sys.exit(f"{rel}: first line must be <!--meta {{...}}-->")
        yield rel, "/" + rel.removesuffix("index.html"), json.loads(m.group(1)), text[m.end():]


def changelog_html(entries, name):
    if not entries:
        return Raw(f'<p class="muted">No releases yet. {html.escape(name)} 1.0 is on its way.</p>')
    out = []
    for e in entries:
        ver = html.escape(e["version"])
        out.append(f'<section class="release" id="v{ver}"><h2>{ver} <time datetime="{e["date"]}">{pretty(e["date"])}</time></h2>'
                   f'{changelog.to_html(e["body_md"])}</section>')
    return Raw("\n".join(out))


def feed(v, entries):
    # Root-relative links in the notes get the full baseURL, like the pages' href/src rewrite in build().
    notes = lambda md: re.sub(r'\b(href|src)="/(?!/)', rf'\1="{v["baseURL"]}/', changelog.to_html(md))
    items = "".join(
        f"<item><title>{html.escape(v['name'])} {html.escape(e['version'])}</title>"
        f"<link>{v['baseURL']}/changelog/#v{html.escape(e['version'])}</link>"
        f"<guid isPermaLink=\"false\">{html.escape(v['name'])}-{html.escape(e['version'])}</guid>"
        f"<pubDate>{format_datetime(datetime.datetime.fromisoformat(str(e['date'])).replace(tzinfo=datetime.timezone.utc))}</pubDate>"
        f"<description>{html.escape(notes(e['body_md']))}</description></item>"
        for e in entries)
    return ('<?xml version="1.0" encoding="utf-8"?>\n<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel>'
            f"<title>{html.escape(v['name'])} changelog</title><link>{v['baseURL']}/changelog/</link>"
            f'<atom:link href="{v["baseURL"]}/feed.xml" rel="self" type="application/rss+xml"/>'
            f"<description>New versions of {html.escape(v['name'])}</description><language>en</language>{items}"
            "</channel></rss>\n")


def build(out, site):
    if out.name != "_dist": sys.exit(f"refusing to build into {out}: the output folder must be named _dist")   # rmtree below; not an assert, python -O strips those
    log = ROOT / "CHANGELOG.md"
    entries = changelog.parse(str(log)) if log.exists() else []
    v = values(site)
    v["changelog"] = changelog_html(entries, site["name"])
    v["version"] = f"Version {entries[0]['version']}" if entries else "1.0 coming soon"
    v["status"] = Raw(f'The latest release is {html.escape(entries[0]["version"])}.' if entries else
                      "There is no public release yet. A first tester beta comes after the code has compiled in CI on macOS and "
                      'real Macs have tried it. The <a href="/changelog/">changelog</a> and its <a href="/feed.xml">RSS feed</a> will say when it is out.')
    v["statusFaq"] = (f"Version {entries[0]['version']} is out. The changelog says what testers have tried. What an ordinary app can read inside protected folders differs between macOS versions, so the report names any folder it could not read."
                      if entries else "Not yet. Nothing has run on a real Mac with a real Library. The first tester beta is how that gets checked, and the changelog will say what was tried.")
    v["statusShort"] = f"Version {entries[0]['version']} is out." if entries else "In development. No public release yet."
    v["statusNote"] = ("The changelog says what testers have tried on real Macs." if entries else
                       "Nothing has run on a real Mac with a real Library yet, so read everything described here as the design, not as proof that it works. The changelog will say what testers have tried.")
    v["statusTag"] = f"Version {entries[0]['version']}" if entries else "In development"
    layout = (SITE / "src" / "layout.html").read_text(encoding="utf-8")
    prefix = urlsplit(site["baseURL"]).path   # "/aftertaste" on a project site, "" on a custom domain

    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(SITE / "static", out)
    (out / ".nojekyll").write_text("")   # serve files as-is on GitHub Pages
    css = out / "styles.css"   # the shipped sheet carries no comments (they are for people, and count against the budget)
    css.write_text(re.sub(r"/\*.*?\*/\s*", "", css.read_text(encoding="utf-8"), flags=re.S), encoding="utf-8", newline="\n")
    listed = []
    for rel, url, meta, body in pages():
        meta = {k: fill(x, v, rel, str) if isinstance(x, str) else x for k, x in meta.items()}
        head = ['<meta name="robots" content="noindex">'] if meta.get("noindex") else []
        listed += [] if meta.get("noindex") else [(url, meta)]
        page = dict(v, title=meta["title"], description=meta["description"], canonical=v["baseURL"] + url,
                    head=Raw("\n".join(head)), body=Raw(fill(body, v, rel)))
        dest = out / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        text = re.sub(r'\b(href|src)="/(?!/)', rf'\1="{prefix}/', fill(layout, page, "layout.html"))
        text = re.sub(r'<a\b[^>]*?\bhref="(https?://[^"]+)"[^>]*>',   # an external link gets rel=noopener
                      lambda m: m[0] if urlsplit(m[1]).netloc == urlsplit(site["baseURL"]).netloc or " rel=" in m[0] else m[0][:-1] + ' rel="noopener">', text)
        # srcset="/a.jpg 1x, /b.jpg 2x": every candidate gets the prefix too.
        text = re.sub(r'\bsrcset="([^"]*)"',
                      lambda m: 'srcset="' + re.sub(r'(^|,\s*)/(?!/)', rf'\1{prefix}/', m[1]) + '"', text)
        dest.write_text(text, encoding="utf-8", newline="\n")

    (out / "feed.xml").write_text(feed(v, entries), encoding="utf-8", newline="\n")
    (out / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        + "".join(f"<url><loc>{v['baseURL']}{u}</loc></url>\n" for u, _ in listed) + "</urlset>\n",
        encoding="utf-8", newline="\n")
    # Crawlers read robots.txt only at a host's root, so on a project site this file does nothing (harmless).
    (out / "robots.txt").write_text(f"User-agent: *\nAllow: /\n\nSitemap: {v['baseURL']}/sitemap.xml\n",
                                    encoding="utf-8", newline="\n")
    v["pageList"] = Raw("\n".join(f"- [{m['title']}]({v['baseURL']}{u}): {m['description']}" for u, m in listed))
    llms = fill((SITE / "src" / "llms.txt").read_text(encoding="utf-8"), v, "llms.txt", str)
    (out / "llms.txt").write_text(llms, encoding="utf-8", newline="\n")
    return v


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links, self.ids, self.meta, self.title, self.h1, self.noalt, self.nosize = [], set(), {}, "", 0, 0, 0
        self._title, self.csp, self.inline, self.anchors, self.text = False, None, [], [], []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "meta" and (a.get("http-equiv") or "").lower() == "content-security-policy":
            self.csp = a.get("content")
        # What the CSP blocks: inline scripts (JSON-LD is data, not script), <style>, style="" and on* handlers.
        if tag == "script" and not a.get("src") and a.get("type") != "application/ld+json" or tag == "style":
            self.inline.append(f"inline <{tag}> (blocked by the CSP)")
        self.inline += [f"<{tag} {k}> (blocked by the CSP)" for k in a if k == "style" or k.startswith("on")]
        if a.get("target") == "_blank" and "noopener" not in (a.get("rel") or ""):   # a new tab gets no opener
            self.inline.append(f"<{tag} target=_blank> without rel=noopener")
        if tag == "a" and (a.get("href") or "").startswith(("http://", "https://")):
            self.anchors.append((a["href"], a.get("rel") or ""))
        if "id" in a:
            self.ids.add(a["id"])
        self.links += [a[k] for k in ("href", "src") if a.get(k)]
        self.links += [c.split()[0] for c in (a.get("srcset") or "").split(",") if c.strip()]
        if tag == "meta" and (a.get("name") or a.get("property")):
            self.meta[a.get("name") or a.get("property")] = a.get("content") or ""
        if tag == "link" and a.get("rel") == "canonical":
            self.meta["canonical"] = a.get("href") or ""
        self._title |= tag == "title"
        self.h1 += tag == "h1"
        self.noalt += tag == "img" and "alt" not in a
        self.nosize += tag == "img" and not (a.get("width") and a.get("height"))

    def handle_endtag(self, tag):
        self._title &= tag != "title"

    def handle_data(self, data):
        self.text.append(data)
        if self._title:
            self.title += data


def contrast(css):
    """WCAG AA (4.5:1) for the text colors on the page backgrounds, in the light block and in the dark one (which
    overrides the light tokens it names)."""
    # ponytail: only 6-digit hex tokens are measured (not rgb() ones like --header), and not illustrations with fixed
    # colours.
    # Add pairs here when a color lands on a new background.
    def lum(c):
        c = [int(c[i:i + 2], 16) / 255 for i in (1, 3, 5)]
        c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    blocks = re.findall(r":root\s*\{([^}]*)\}", css)   # light, then prefers-color-scheme: dark
    if len(blocks) != 2:
        return [f"styles.css: {len(blocks)} root-selector blocks, want exactly two (light, then dark)"]
    light, dark = (dict(re.findall(r"--([\w-]+):\s*(#[0-9a-fA-F]{6})\b", b)) for b in blocks)
    pairs = [(f, b) for f in ("text", "text-2", "accent") for b in ("bg", "bg-alt", "card")]
    on = "on-button" if "on-button" in light else "#ffffff"   # the .button and .skip label
    pairs += [(on, "button"), (on, "button-hover")]
    errors = []
    for scheme, t in (("light", light), ("dark", {**light, **dark})):
        for fg, bg in pairs:
            hi, lo = sorted((lum(t.get(fg, fg)), lum(t[bg])), reverse=True)
            if (hi + 0.05) / (lo + 0.05) < 4.5:
                errors.append(f"styles.css: {fg} on --{bg} is {(hi + 0.05) / (lo + 0.05):.2f}:1 in {scheme}, want 4.5:1")
    return errors


def check(out, site, v):
    errors = []
    base = v["baseURL"]
    host, prefix = urlsplit(base).netloc, urlsplit(base).path
    parsed = {}
    for f in sorted(out.rglob("*.html")):
        p = Page()
        p.feed(f.read_text(encoding="utf-8"))
        parsed[f] = p

    def resolve(rel, page, link):
        u = urlsplit(urljoin(page, link))
        if u.scheme not in ("http", "https") or u.netloc != host:
            return   # mailto:, external
        if not u.path.startswith(prefix + "/"):
            errors.append(f"{rel}: link {link} is outside {base}/")
            return
        target = out / u.path[len(prefix) + 1:]
        if u.path.endswith("/"):
            target /= "index.html"
        if not target.is_file():
            errors.append(f"{rel}: broken link {link}")
        elif u.fragment and target in parsed and u.fragment not in parsed[target].ids:
            errors.append(f"{rel}: missing anchor {link}")

    for f, p in parsed.items():
        rel = f.relative_to(out).as_posix()
        url = "/" + rel.removesuffix("index.html")
        for key in ("description", "canonical", "og:title", "og:description", "og:image", "og:url"):
            if not p.meta.get(key):
                errors.append(f"{rel}: missing {key}")
        if not p.title.strip():
            errors.append(f"{rel}: missing <title>")
        if p.meta.get("canonical") != base + url:
            errors.append(f"{rel}: canonical {p.meta.get('canonical')} != {base + url}")
        if p.h1 != 1:
            errors.append(f"{rel}: {p.h1} <h1> elements, want 1")
        if p.noalt:
            errors.append(f"{rel}: {p.noalt} <img> without alt")
        if p.nosize:
            errors.append(f"{rel}: {p.nosize} <img> without width and height (layout shift)")
        if AFFILIATION not in re.sub(r"\s+", " ", "".join(p.text)):
            errors.append(f"{rel}: missing the line \"... {AFFILIATION}\"")
        errors += [f"{rel}: external link {h} without rel=noopener" for h, r in p.anchors if urlsplit(h).netloc != host and "noopener" not in r]
        if p.csp != CSP:
            errors.append(f"{rel}: Content-Security-Policy meta is {p.csp!r}, want {CSP!r}")
        errors += [f"{rel}: {what}" for what in p.inline]
        for link in p.links + [p.meta.get("og:image", "")]:
            resolve(rel, base + url, link)
    bp = banned()
    for f in sorted(out.rglob("*")):
        rel = f.relative_to(out).as_posix()
        if f.suffix in (".html", ".xml", ".txt", ".css", ".js"):
            for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
                if bp and (hit := bp.search(line)) and "no-claim-ok" not in line:
                    errors.append(f"{rel}:{n}: banned phrase {hit[0]!r} (tools/banned_phrases.txt); mark an intentional mention no-claim-ok")
        if f.suffix in (".html", ".txt") and (hit := SAFE.search(re.sub("|".join(map(re.escape, SAFE_OK)), "", f.read_text(encoding="utf-8")))):
            errors.append(f"{rel}: the word {hit[0]!r} (docs/DESIGN.md §1: say what happens instead)")
        if f.suffix in (".html", ".xml", ".txt"):
            text = f.read_text(encoding="utf-8")
            if f.suffix != ".html":   # sitemap, feed, robots.txt, llms.txt
                for link in re.findall(re.escape(base) + r'[^\s"<>)&]*', text):
                    resolve(rel, base, link)
            for key in site.get("placeholders", []):
                text = text.replace(html.escape(str(site[key])), "").replace(str(site[key]), "")
            if PLACEHOLDER.search(text):
                errors.append(f"{rel}: {PLACEHOLDER.search(text)[0]} not from a site.json placeholder")
        if f.suffix in (".html", ".css") and re.search(r"data-theme|localStorage", f.read_text(encoding="utf-8")):
            errors.append(f"{rel}: data-theme/localStorage (use prefers-color-scheme only)")
        if f.suffix == ".xml":
            try:
                ET.parse(f)
            except ET.ParseError as e:
                errors.append(f"{f.name}: {e}")
    for key, val in site.items():
        if PLACEHOLDER.search(str(val)) and key not in site.get("placeholders", []):
            errors.append(f"site.json: {key} is a placeholder but not listed in \"placeholders\"")
    errors += [f"{f.relative_to(out).as_posix()}: a webfont (the family ships none, docs/DESIGN.md §2.2)" for f in out.rglob("*") if f.suffix in (".woff", ".woff2", ".ttf", ".otf")]
    errors += contrast((out / "styles.css").read_text(encoding="utf-8"))
    if re.search(r"url\(\s*['\"]?data:", (out / "styles.css").read_text(encoding="utf-8")):
        errors.append("styles.css: a data: URL is blocked by the CSP's img-src 'self'; ship the image as a static file")
    # Every "Looked in N of M places" in prose must be the number the demo prints (or a prefix of the sample line).
    for f in [ROOT / "README.md", ROOT / "CHANGELOG.md", ROOT / "tools" / "make_og.py", out / "llms.txt", *out.rglob("*.html")]:
        for m in re.finditer(r"Looked in \d+ of \d+ places(?:\. \d+ protected by macOS)?", f.read_text(encoding="utf-8")):
            if not v["coverageSample"].startswith(m[0]):
                errors.append(f"{f.name}: {m[0]!r} is not the demo's {v['coverageSample']!r}")
    # The sample bar's segments are sized in CSS (CSP: no style attribute), so a changed demo scenario must change them too.
    css = (out / "styles.css").read_text(encoding="utf-8")
    grow = [float(g) for _, g in sorted(re.findall(r"\.rbar i:nth-child\((\d)\) \{ flex-grow: ([\d.]+); \}", css))]
    if grow != v["orbitGrow"]:
        errors.append(f"styles.css: .rbar flex-grow {grow} must match the demo scenario's sizes in MB {v['orbitGrow']}")
    for pattern, cap in BUDGET.items():
        for f in out.glob(pattern):
            if f.stat().st_size > cap:
                errors.append(f"{f.relative_to(out).as_posix()}: {f.stat().st_size} bytes, over its {cap} byte budget")
    return errors, len(parsed)


def main():
    site = json.loads((SITE / "site.json").read_text(encoding="utf-8"))
    site["baseURL"] = site["baseURL"].rstrip("/")
    if "--check" not in sys.argv[1:]:
        build(SITE / "_dist", site)
        print(f"built {SITE / '_dist'} for {site['baseURL']}")
        return
    # baseURL, plus the other shape it can take: a bare origin (custom domain) or a GitHub Pages project path.
    u = urlsplit(site["baseURL"])
    origin = f"{u.scheme}://{u.netloc}"
    failed = False
    for base in dict.fromkeys([site["baseURL"], origin, f"{origin}/{site['releasesRepo'].split('/')[-1]}"]):
        s = dict(site, baseURL=base)
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "_dist"
            errors, n = check(out, s, build(out, s))
        for e in errors:
            print("error:", e)
        print(f"checked {n} pages for {base}: {len(errors)} errors")
        failed |= bool(errors)
    todo = [k for k in site.get("placeholders", []) if PLACEHOLDER.search(str(site[k]))]
    if todo: print("placeholders still to fill: " + ", ".join(todo))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
