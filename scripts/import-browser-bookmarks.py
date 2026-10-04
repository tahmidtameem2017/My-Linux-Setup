#!/usr/bin/env python3
"""Import bookmarks from an installed browser into the launcher's list.

    import-browser-bookmarks.py [--list] [--browser NAME] [--dry-run] [--no-favicons]

Reads two store formats and nothing else, because there are only two:

  * Chromium family (Chrome, Chromium, Brave, Vivaldi, Edge, Opera, Arc) --
    a `Bookmarks` JSON file plus a `Favicons` SQLite database.
  * Firefox / LibreWolf / Waterfox -- `places.sqlite` plus `favicons.sqlite`.

Both are read READ-ONLY. Chromium keeps the live database open and its
`-journal`/WAL files beside it, so every database is COPIED to a temp dir
first and read from there; opening the live file directly risks reading a torn
page, and Firefox's `places.sqlite` in WAL mode needs `-wal` copied too.

MERGE CONTRACT -- this never clobbers. The launcher's list is the user's file,
and an import that overwrote it would silently delete bookmarks they added by
hand, renamed, or re-ordered. So:

  * a browser bookmark whose URL is ALREADY in bookmarks.json is left alone;
  * a URL present in the ledger (previously imported) but ABSENT from
    bookmarks.json was DELETED by the user -- it is never re-added;
  * everything else is appended.

That makes the script safely re-runnable: run it again after adding bookmarks
in the browser and only the genuinely new ones arrive. The one thing it will
refresh on a later run is each imported entry's favicon, because a favicon is
purely additive and a missing icon is the visible half of the feature.

FAVICONS are taken from the browser's OWN cache -- no network, no favicon
service, nothing fetched at runtime. Chrome stores PNG bytes in
`favicon_bitmaps.image_data`, Firefox in `moz_favicon_bitmaps.image_data`.
They are written to ~/.cache/niri-setup/bookmark-favicons/<sha1>.png, and a
row whose icon is an absolute path is loaded straight from there by
Launcher.iconSourceFor. A bookmark with no cached favicon keeps bookmark.svg.

Pure stdlib: sqlite3 + json + hashlib, nothing to install.

Contract with BookmarksProvider.qml: every entry is {title, url, icon?}, and
`icon` is either absent (the bookmark.svg default) or an absolute path to a
local PNG. `folder` is kept for the row's detail line only.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

STATE_DIR = Path.home() / ".local" / "share" / "niri-setup"
BOOKMARKS = STATE_DIR / "bookmarks.json"
LEDGER = STATE_DIR / "bookmarks-import.json"
FAVICON_DIR = Path.home() / ".cache" / "niri-setup" / "bookmark-favicons"

# Chromium profiles are directories holding a `Bookmarks` file. Ordered by how
# likely they are to be the real one: the literal default profile first, then
# anything else. Brave names its default "Default" too.
CHROMIUM_ROOTS = [
    ("Brave", Path.home() / ".config" / "BraveSoftware" / "Brave-Browser"),
    ("Chromium", Path.home() / ".config" / "chromium"),
    ("Chrome", Path.home() / ".config" / "google-chrome"),
    ("Chrome (beta)", Path.home() / ".config" / "google-chrome-beta"),
    ("Vivaldi", Path.home() / ".config" / "vivaldi"),
    ("Edge", Path.home() / ".config" / "microsoft-edge"),
    ("Opera", Path.home() / ".config" / "opera"),
    ("Arc", Path.home() / ".config" / "Arc"),
]
FIREFOX_ROOTS = [
    ("Firefox", Path.home() / ".mozilla" / "firefox"),
    ("Firefox (snap)", Path.home() / "snap" / "firefox" / "common" / ".mozilla" / "firefox"),
    ("LibreWolf", Path.home() / ".librewolf" / "profiles"),
    ("Waterfox", Path.home() / ".waterfox" / "profiles"),
]

# Firefox uses .default-release / .dev-edition etc.; Chromium uses Default,
# Profile 1... Match a directory that looks like a profile at all, then let the
# reader fail cleanly if the file is missing.
def _profile_dirs(root: Path):
    if not root.is_dir():
        return
    for child in sorted(root.iterdir()):
        if child.is_dir() and not child.name.startswith("."):
            yield child


def find_chromium():
    """Yield (browser, profile_dir) for every Chromium-family profile present."""
    for name, root in CHROMIUM_ROOTS:
        if not root.is_dir():
            continue
        for profile in _profile_dirs(root):
            if (profile / "Bookmarks").is_file():
                yield name, profile


def find_firefox():
    """Yield (browser, profile_dir) for every profile that has places.sqlite."""
    for name, root in FIREFOX_ROOTS:
        if not root.is_dir():
            continue
        for profile in _profile_dirs(root):
            if (profile / "places.sqlite").is_file():
                yield name, profile


# ---------------------------------------------------------------- canonical URL

TRACKING = {"si", "feature", "fbclid", "gclid", "igshid", "pp", "ref", "ved"}


def norm_url(url: str) -> str:
    """Same identity rule as BookmarksProvider.normUrl, plus scheme lowercasing.

    Kept byte-compatible with the provider on purpose: the importer dedupes
    against entries the provider wrote, so a mismatch here would import a
    duplicate of a bookmark the user already saved by hand.
    """
    raw = (url or "").strip()
    if not raw:
        return ""
    if not raw.lower().startswith(("http://", "https://")):
        if raw.startswith("ftp://") or "://" in raw:
            return ""
        raw = "https://" + raw.lstrip("/")
    parts = urlsplit(raw)
    if parts.scheme not in ("http", "https"):
        return ""
    if not parts.netloc or "." not in parts.netloc.split(":")[0]:
        return ""
    host = parts.netloc.split("@")[-1].lower()
    if host.startswith("www."):
        host = host[4:]
    path = parts.path or "/"
    if path != "/" and path.endswith("/"):
        path = path.rstrip("/")
    # Fragment is dropped: a bookmark's identity is host+path+meaningful query.
    query = "&".join(
        part for part in parts.query.split("&")
        if part and part.split("=")[0].lower() not in TRACKING
        and not part.split("=")[0].lower().startswith("utm_")
    )
    return urlunsplit((parts.scheme.lower(), host, path, query, ""))


def host_of(url: str) -> str:
    return urlsplit(url).netloc.split(":")[0].lower()


def is_urlish(text: str) -> bool:
    """True when a stored TITLE is really just a URL pasted into the name.

    Same three rules as BookmarksProvider.isUrl, so the importer and the shell
    agree on which names are "the browser never renamed this".
    """
    t = (text or "").strip()
    if re.match(r"^https?://", t, re.I):
        return True
    if re.match(r"^www\.[^\s]+\.[^\s]+", t, re.I):
        return True
    return bool(re.fullmatch(r"[^\s]+\.[a-z]{2,}(/\S*)?", t, re.I))


def title_from_url(url: str) -> str:
    """A readable name for a bookmark whose title IS its URL.

    Browsers store the bare link as the title whenever the bookmark was never
    renamed, which is most of them — the launcher then showed a URL where a
    word belongs. Mirrors BookmarksProvider.titleFromUrl exactly; the two have
    to agree or an imported name would change the first time the shell reloads
    the file.

    The PATH usually knows more than the host: github.com/anthropics is about
    anthropics, and en.wikipedia.org/wiki/Niri_(compositor) is about niri, not
    about wikipedia. So the last meaningful path segment wins, and the host is
    the fallback for the many sites that live at the root
    (chat.deepseek.com/, youtube.com).

    "Meaningful" has to be defined, because most path segments are noise —
    /search, /index.html, /en/, /item, an id, a uuid. Those are skipped, and
    with nothing left the host name is used.
    """
    rest = (url or "").strip()
    if not rest:
        return ""
    rest = re.sub(r"^[a-z][a-z0-9+.-]*://", "", rest, flags=re.I)
    rest = re.sub(r"^www\.", "", rest, flags=re.I)
    rest = rest.split("#")[0].split("?")[0]
    rest = rest.rsplit("@", 1)[-1]
    segs = [s for s in rest.split("/") if s]
    if not segs:
        return ""
    # Strip the port from the HOST SEGMENT, not from the whole string:
    # "localhost:3000/app" ends in "app", so an anchored /:\d+$/ on the whole
    # string never fires and the name came out as "localhost:3000".
    host = re.sub(r":\d+$", "", segs[0]).lower()
    if not host:
        return ""
    # A bare address is the name. 192.168.1.5/admin is a router page, and
    # calling it "admin" (from the path) tells you nothing you cannot get from
    # the address itself — so the address wins and the path is not consulted.
    if re.fullmatch(r"\d{1,3}(\.\d{1,3}){3}", host):
        return host
    # A bare host with no dot (localhost, an intranet name) likewise: its
    # "path" is usually a route, not a subject.
    if "." not in host:
        return host

    # Skip plumbing segments that sit on the way to the real one: /blob/main/,
    # /wiki/, /r/. The FIRST meaningful segment is usually the subject
    # (github.com/anthropics/claude-code -> anthropics), while the LAST is
    # often a file or a qualifier (…/README.md).
    for seg in segs[1:]:
        name = _clean_segment(seg)
        if name:
            return name

    parts = host.split(".")
    if len(parts) <= 2:
        return parts[0]
    tld, second = parts[-1], parts[-2]
    # Keep a country-code second level: example.co.uk -> example, not co.
    keep = 3 if (len(tld) == 2 and tld.isalpha() and
                 len(second) <= 3 and second.isalpha()) else 2
    return parts[len(parts) - keep] or host


# Path segments that describe the site's plumbing rather than its subject.
# Routers emit these constantly; treating them as the name produced
# "search" for every Google link and "item" for every Hacker News one.
NOISE_SEGMENTS = {
    "index", "default", "home", "main", "page", "pages", "search", "results",
    "find", "view", "list", "lists", "item", "items", "post", "posts", "entry",
    "browse", "category", "categories", "tag", "tags", "topic", "topics",
    "feed", "rss", "atom", "login", "signin", "sign-in", "signup", "sign-up",
    "register", "account", "accounts", "profile", "user", "users", "settings",
    "dashboard", "app", "apps", "application", "applications", "en", "us", "uk",
    "de", "fr", "es", "it", "nl", "jp", "cn", "ru", "br", "in", "www", "web",
    "site", "html", "htm", "php", "aspx", "jsp", "do", "cgi", "about",
    "help", "support", "contact", "privacy", "terms", "legal", "cookies",
    "download", "downloads", "docs", "documentation", "wiki", "new", "old",
    "cid", "id", "uid", "ref", "share", "share.php", "amp",
}

# A path segment that is mostly hex, or shaped like a uuid, is an identifier.
_IDISH = re.compile(r"^[0-9a-f]{8,}$|^[0-9a-f]{8}-[0-9a-f]{4}-", re.I)


def _clean_segment(seg: str) -> str:
    """Turn one path segment into a name, or "" when it carries no signal."""
    s = (seg or "").strip()
    if not s:
        return ""
    # A file extension says nothing about the subject: index.html, post.aspx.
    s = re.sub(r"\.(html?|php|aspx?|jsp|cfm|do|md|txt|json)$", "", s, flags=re.I)
    # A parenthetical qualifier is a gloss, not the name:
    # "Niri_(compositor)" -> "niri".
    s = re.sub(r"\(.*?\)", "", s)
    s = re.sub(r"\.(?!$)", " ", s)      # remaining dots -> spaces
    s = re.sub(r"[-_+]+", " ", s)        # slug separators -> spaces
    s = re.sub(r"\s+", " ", s).strip()
    if not s:
        return ""
    low = s.lower()
    if low in NOISE_SEGMENTS or len(low) < 3:
        return ""
    if s.isdigit() or _IDISH.match(low):
        return ""
    return s[:32].strip()


# ---------------------------------------------------------------- Chromium read

def read_chromium_bookmarks(profile: Path):
    """Flat list of {title, url, folder} from the Bookmarks JSON tree.

    The launcher shows a FLAT list with no folder column, so nesting has to go
    somewhere: each entry keeps its folder path for the row's detail line
    rather than being folded into the title, because mangling titles would make
    imported entries hard to find by search.
    """
    try:
        data = json.loads((profile / "Bookmarks").read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"  ! cannot read {profile / 'Bookmarks'}: {e}", file=sys.stderr)
        return []

    out = []

    def walk(node, path):
        kind = node.get("type")
        if kind == "folder":
            # Chromium's own bookkeeping roots are noise, not user folders.
            label = node.get("name", "") or ""
            nxt = path + [label] if label else path
            for child in node.get("children", []) or []:
                walk(child, nxt)
        elif kind == "url":
            url = node.get("url", "") or ""
            title = (node.get("name", "") or "").strip()
            if not url or not url.lower().startswith(("http://", "https://")):
                return
            # A browser stores the bare link as the name when the bookmark was
            # never renamed, which is most of them. Detect that shape (a name
            # that IS a url) rather than an empty one, or the list fills with
            # "https://…" instead of "deepseek".
            if not title or is_urlish(title):
                title = title_from_url(url) or host_of(url)
            out.append({"title": title, "url": url,
                        "folder": " / ".join(path) if path else ""})

    roots = data.get("roots", {})
    for key in ("bookmark_bar", "other", "synced"):
        if key in roots:
            walk(roots[key], [])
    return out


def read_chromium_favicons(profile: Path):
    """{page_url: (png_bytes, width)} from the Favicons database.

    Chromium stores one mapping per page it has seen, so matching is by the
    bookmark's own URL and then by host: a bookmark saved as
    `https://example.com/` and cached as `https://example.com/#/page` is the
    same site, and the favicon DB keys on the exact string.
    """
    src = profile / "Favicons"
    if not src.is_file():
        return {}
    icons = {}
    with _read_sqlite(src) as con:
        try:
            # Prefer the largest bitmap <=64px: 16px is blurry at the launcher's
            # 22px cell, and the 256px "download" size is wasted memory for a
            # row that is 22 CSS px.
            rows = con.execute(
                "SELECT m.page_url, b.image_data, b.width FROM icon_mapping m "
                "JOIN favicon_bitmaps b ON b.icon_id = m.icon_id "
                "WHERE b.width <= 64 AND b.image_data IS NOT NULL").fetchall()
        except sqlite3.Error as e:
            print(f"  ! favicon schema differs in {src}: {e}", file=sys.stderr)
            return {}
    best = {}
    for page_url, blob, width in rows:
        if not blob or not blob.startswith(b"\x89PNG\r\n\x1a\n"):
            continue  # only PNG: IconImage cannot decode the .ico/webp variants
        prev = best.get(page_url)
        if prev is None or width > prev[1]:
            best[page_url] = (blob, width)
        icons.setdefault(page_url, best[page_url])
    return {url: v for url, v in best.items()}


# ---------------------------------------------------------------- Firefox read

def read_firefox_bookmarks(profile: Path):
    """Flat list from places.sqlite via moz_bookmarks/moz_places.

    Firefox keeps the bookmark's name in moz_bookmarks.title and its address
    in moz_places.url, joined on fk = moz_places.id. Filtering on type = 1
    drops folder rows and moz_bookmarks' own placeholder entries, and
    `url LIKE 'http%'` drops the internal pseudo-URIs Firefox stores as
    bookmarks (place:, javascript:, about:). No root ids are hardcoded, so a
    bookmark filed anywhere -- toolbar, menu, or a folder -- all arrive.
    """
    rows = []
    with _read_sqlite(profile / "places.sqlite") as con:
        try:
            rows = con.execute(
                "SELECT b.title, p.url FROM moz_bookmarks b "
                "JOIN moz_places p ON p.id = b.fk "
                "WHERE b.type = 1 AND p.url LIKE 'http%'").fetchall()
        except sqlite3.Error as e:
            print(f"  ! places schema differs in {profile}: {e}", file=sys.stderr)
            return []

    out = []
    for title, url in rows:
        name = (title or "").strip()
        if not name or is_urlish(name):
            name = title_from_url(url) or host_of(url)
        out.append({"title": name, "url": url, "folder": ""})
    return out


def read_firefox_favicons(profile: Path):
    """{page_url: (png_bytes, width)} from favicons.sqlite.

    The join direction is the whole trap here, and it is the opposite of
    Chromium's: Firefox's `moz_favicons` has NO `icon_id` column -- it is
    (id, page_url, origin). The link to the bitmap is `moz_favicon_bitmaps.icon_id`
    -> moz_favicons.id, so the bitmap table is the one that carries the key.
    Querying `f.icon_id` fails outright with "no such column", and the whole
    store silently yields zero icons.
    """
    src = profile / "favicons.sqlite"
    if not src.is_file():
        return {}
    best = {}
    with _read_sqlite(src) as con:
        try:
            rows = con.execute(
                "SELECT f.page_url, b.image_data, b.width FROM moz_favicon_bitmaps b "
                "JOIN moz_favicons f ON f.id = b.icon_id "
                "WHERE b.image_data IS NOT NULL").fetchall()
        except sqlite3.Error as e:
            print(f"  ! favicon schema differs in {src}: {e}", file=sys.stderr)
            return {}
    for page_url, blob, width in rows:
        if not blob or not blob.startswith(b"\x89PNG\r\n\x1a\n"):
            continue
        width = width or 32
        if width > 64:
            continue
        prev = best.get(page_url)
        if prev is None or width > prev[1]:
            best[page_url] = (blob, width)
    return best


# ---------------------------------------------------------------- sqlite safety

class _read_sqlite:
    """Open a COPY of a live database, read-only, and always clean it up.

    Both browsers hold these files open and write to them as you read. SQLite
    would normally handle that, but Chrome's rollback journal and Firefox's WAL
    mean a naive read can see a half-written page or miss recent rows, and we
    are not the process holding the lock. Copying (with the journal sidecars)
    and reading the copy is what a backup tool does, and it never needs the
    browser to cooperate.
    """

    def __init__(self, path: Path):
        self.path = path
        self.tmpdir = None

    def __enter__(self):
        self.tmpdir = tempfile.mkdtemp(prefix="niri-bm-")
        copy = Path(self.tmpdir) / self.path.name
        shutil.copy2(self.path, copy)
        for suffix in ("-wal", "-shm", "-journal"):
            sidecar = self.path.with_name(self.path.name + suffix)
            if sidecar.is_file():
                shutil.copy2(sidecar, copy.with_name(copy.name + suffix))
        return sqlite3.connect(f"file:{copy}?mode=ro", uri=True)

    def __exit__(self, *exc):
        shutil.rmtree(self.tmpdir, ignore_errors=True)
        return False


# ---------------------------------------------------------------- favicon files

def favicon_path(url: str) -> Path:
    digest = hashlib.sha1(norm_url(url).encode()).hexdigest()[:16]
    return FAVICON_DIR / f"{digest}.png"


def write_favicon(url: str, blob: bytes) -> str:
    """Write the PNG and return its path, or "" when nothing was written."""
    target = favicon_path(url)
    try:
        FAVICON_DIR.mkdir(parents=True, exist_ok=True)
        if target.is_file() and target.read_bytes() == blob:
            return str(target)
        # Truncate+write in place: the shell resolves these by path, so a
        # rename would leave a decoded image cached against a dead inode.
        with open(target, "wb") as handle:
            handle.write(blob)
        return str(target)
    except OSError as e:
        print(f"  ! cannot write favicon for {url}: {e}", file=sys.stderr)
        return ""


def pick_favicon(url: str, favicons: dict):
    """Exact URL first, then host match, so a bookmark always gets an icon."""
    if not favicons:
        return None
    key = norm_url(url)
    if key in favicons:
        return favicons[key]
    if url in favicons:
        return favicons[url]
    host = host_of(key)
    if not host:
        return None
    for page_url, value in favicons.items():
        if host_of(norm_url(page_url)) == host:
            return value
    return None


# ---------------------------------------------------------------- state files

def load_state():
    try:
        data = json.loads(BOOKMARKS.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except (OSError, ValueError):
        return []


def load_ledger():
    try:
        data = json.loads(LEDGER.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(entries):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    # Write in place: BookmarksProvider watches this file by inode through
    # FileView, so a staged-then-renamed write would kill the watch and the
    # shell would show the old list until it restarted.
    with open(BOOKMARKS, "w") as handle:
        handle.write(json.dumps(entries, indent=2) + "\n")


def save_ledger(ledger):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with open(LEDGER, "w") as handle:
        handle.write(json.dumps(ledger, indent=2, sort_keys=True) + "\n")


# ---------------------------------------------------------------- merge

def merge(entries, ledger, incoming, source, favicons, want_favicons):
    """Append only what is new. Returns (added, refreshed_icons)."""
    have = {norm_url(e.get("url", "")) for e in entries}
    have.discard("")
    seen_from_source = set(ledger.get(source, []))
    added, refreshed = [], []

    for item in incoming:
        url = item["url"]
        key = norm_url(url)
        if not key or key in have or key in seen_from_source:
            continue
        entry = {"title": item["title"], "url": url}
        if item.get("folder"):
            entry["folder"] = item["folder"]
        if want_favicons:
            fav = pick_favicon(url, favicons)
            if fav:
                path = write_favicon(url, fav[0])
                if path:
                    entry["icon"] = path
        entries.append(entry)
        added.append(entry)
        have.add(key)
        seen_from_source.add(key)

    # A favicon can appear in the browser's cache after the bookmark was
    # imported, so refresh icons on every run: purely additive, never touches
    # a title or a url.
    if want_favicons and favicons:
        by_url = {norm_url(i["url"]): i["url"] for i in incoming}
        for entry in entries:
            if entry.get("icon"):
                continue
            real = by_url.get(norm_url(entry.get("url", "")))
            if not real:
                continue
            fav = pick_favicon(real, favicons)
            if not fav:
                continue
            path = write_favicon(real, fav[0])
            if path:
                entry["icon"] = path
                refreshed.append(entry)

    return added, refreshed


# ---------------------------------------------------------------- cli

def collect(selected=None):
    """Every (source_key, label, bookmarks, favicons) found on this machine."""
    found = []
    for name, profile in find_chromium():
        if selected and selected.lower() not in name.lower():
            continue
        found.append((f"chromium:{profile}", f"{name} ({profile.name})",
                      read_chromium_bookmarks(profile),
                      read_chromium_favicons(profile)))
    for name, profile in find_firefox():
        if selected and selected.lower() not in name.lower():
            continue
        found.append((f"firefox:{profile}", f"{name} ({profile.name})",
                      read_firefox_bookmarks(profile),
                      read_firefox_favicons(profile)))
    return found


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Import browser bookmarks into the launcher's % list.")
    parser.add_argument("--list", action="store_true",
                        help="show what would be read, import nothing")
    parser.add_argument("--browser", help="only this browser (brave, chrome, firefox…)")
    parser.add_argument("--dry-run", action="store_true",
                        help="report the changes without writing")
    parser.add_argument("--no-favicons", action="store_true",
                        help="import without icons")
    args = parser.parse_args(argv)

    found = collect(args.browser)
    if not found:
        print("No Chromium or Firefox profile with bookmarks was found.")
        print("Looked in:", ", ".join(str(r[1]) for _, r in CHROMIUM_ROOTS),
              "and", ", ".join(str(r[1]) for _, r in FIREFOX_ROOTS))
        return 0

    if args.list:
        for key, label, bookmarks, favicons in found:
            print(f"{label}: {len(bookmarks)} bookmarks, "
                  f"{len(favicons)} cached favicons")
            for item in bookmarks[:5]:
                print(f"    {item['title'][:44]:44} {item['url'][:60]}")
            if len(bookmarks) > 5:
                print(f"    … and {len(bookmarks) - 5} more")
        return 0

    entries = load_state()
    ledger = load_ledger()
    total = icons = 0
    for key, label, bookmarks, favicons in found:
        if not bookmarks:
            print(f"{label}: nothing to import")
            continue
        added, refreshed = merge(entries, ledger, bookmarks, key, favicons,
                                 not args.no_favicons)
        ledger[key] = sorted(set(ledger.get(key, [])) |
                             {norm_url(a["url"]) for a in added})
        with_icons = sum(1 for a in added if a.get("icon"))
        icons += with_icons
        total += len(added)
        print(f"{label}: {len(added)} new"
              + (f" ({with_icons} with a favicon)" if with_icons else "")
              + (f", {len(refreshed)} icon(s) refreshed" if refreshed else "")
              + f" — {len(bookmarks)} read")

    if not total:
        print("Nothing new — every browser bookmark is already in the list.")
    if not args.dry_run and total:
        save_state(entries)
        save_ledger(ledger)
        print(f"Wrote {total} bookmark(s) to {BOOKMARKS}")
    elif args.dry_run and total:
        print(f"(dry run — nothing written)")
    return 0


if __name__ == "__main__":
    sys.exit(main())