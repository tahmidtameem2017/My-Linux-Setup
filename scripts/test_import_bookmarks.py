#!/usr/bin/env python3
"""import-browser-bookmarks.py must read both store formats and never clobber.

The two things worth pinning here are not the happy path:

  * the MERGE contract. The launcher's bookmarks.json is the user's file. An
    importer that overwrites it would silently delete bookmarks they added by
    hand, so this asserts the three cases that define the contract: a URL
    already present is untouched, a URL the user DELETED is never re-added, and
    only genuinely new URLs are appended.

  * Firefox is untestable on a machine with no Firefox profile (this one has
    none), so places.sqlite / favicons.sqlite are built as fixtures here. A
    change to the Firefox SQL that only ever runs on someone else's laptop
    would otherwise ship unverified.

Chromium's real profile is also used when present, read-only, as a smoke test.
"""

import importlib.util
import json
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parent
REPO = SCRIPTS.parent
spec = importlib.util.spec_from_file_location(
    "import_browser_bookmarks", SCRIPTS / "import-browser-bookmarks.py")
imp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(imp)


def chromium_profile(root: Path, bar=("Docs", "https://docs.example.com/guide")):
    """A Chromium-shaped profile: Bookmarks JSON + a Favicons database."""
    profile = root / "Default"
    profile.mkdir(parents=True)
    title, url = bar
    (profile / "Bookmarks").write_text(json.dumps({
        "version": 1,
        "roots": {
            "bookmark_bar": {
                "type": "folder", "name": "Bookmarks bar",
                "children": [
                    {"type": "folder", "name": "Reading", "children": [
                        {"type": "url", "name": title, "url": url},
                        {"type": "url", "name": "Empty", "url": "javascript:void(0)"},
                    ]},
                ],
            },
            "other": {"type": "folder", "name": "Other Bookmarks", "children": []},
        },
    }), encoding="utf-8")

    con = sqlite3.connect(profile / "Favicons")
    con.executescript("""
        CREATE TABLE favicon_bitmaps(id INTEGER PRIMARY KEY, icon_id INTEGER,
            last_updated INTEGER, image_data BLOB, width INTEGER, height INTEGER,
            last_requested INTEGER);
        CREATE TABLE favicons(id INTEGER PRIMARY KEY, url TEXT, icon_type INTEGER);
        CREATE TABLE icon_mapping(id INTEGER PRIMARY KEY, page_url TEXT,
            icon_id INTEGER, page_url_type INTEGER);
    """)
    # A 16px decoy and the 32px we want: the larger one must win.
    for wid, blob in ((16, b"\x89PNG\r\n\x1a\n16"), (32, b"\x89PNG\r\n\x1a\n32")):
        con.execute("INSERT INTO favicons(id,url,icon_type) VALUES (1,?,1)",
                    ("https://docs.example.com/favicon.ico",))
        con.execute("INSERT INTO favicon_bitmaps(icon_id,image_data,width,height)"
                    " VALUES (1,?,?,?)", (blob, wid, wid))
        break
    con.execute("INSERT INTO favicon_bitmaps(icon_id,image_data,width,height)"
                " VALUES (1,?,32,32)", (b"\x89PNG\r\n\x1a\n-thirty-two",))
    con.execute("INSERT INTO icon_mapping(page_url,icon_id,page_url_type)"
                " VALUES (?,1,0)", (url,))
    con.commit()
    con.close()
    return profile


def firefox_profile(root: Path):
    """A Firefox-shaped profile: places.sqlite + favicons.sqlite."""
    profile = root / "abcd1234.default-release"
    profile.mkdir(parents=True)
    con = sqlite3.connect(profile / "places.sqlite")
    con.executescript("""
        CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url TEXT, title TEXT);
        CREATE TABLE moz_bookmarks(id INTEGER PRIMARY KEY, type INTEGER,
            fk INTEGER, parent INTEGER, position INTEGER, title TEXT);
    """)
    rows = [
        (1, "https://mozilla.org/firefox/", "Firefox"),
        (2, "https://addons.mozilla.org/", "Add-ons"),
        (3, "about:config", None),
        (4, "place:sort=8", None),
    ]
    for pid, url, title in rows:
        con.execute("INSERT INTO moz_places(id,url,title) VALUES (?,?,?)", (pid, url, title))
        if url.startswith("http"):
            con.execute("INSERT INTO moz_bookmarks(type,fk,title) VALUES (1,?,?)",
                        (pid, title))
    con.commit()
    con.close()

    con = sqlite3.connect(profile / "favicons.sqlite")
    con.executescript("""
        CREATE TABLE moz_favicons(id INTEGER PRIMARY KEY, page_url TEXT, origin TEXT);
        CREATE TABLE moz_favicon_bitmaps(id INTEGER PRIMARY KEY, icon_id INTEGER,
            image_data BLOB, width INTEGER, height INTEGER);
    """)
    con.execute("INSERT INTO moz_favicons(id,page_url,origin) VALUES (1,?,NULL)",
                ("https://mozilla.org/firefox/",))
    con.execute("INSERT INTO moz_favicon_bitmaps(icon_id,image_data,width,height)"
                " VALUES (1,?,32,32)", (b"\x89PNG\r\n\x1a\n-ff",))
    con.commit()
    con.close()
    return profile


class TempCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        # Point the module at the sandbox for the duration of the test.
        for attr, value in (("STATE_DIR", self.root / "state"),
                            ("BOOKMARKS", self.root / "state" / "bookmarks.json"),
                            ("LEDGER", self.root / "state" / "bookmarks-import.json"),
                            ("FAVICON_DIR", self.root / "favicons")):
            self.addCleanup(setattr, imp, attr, getattr(imp, attr))
            setattr(imp, attr, value)


class ChromiumTests(TempCase):
    def test_reads_nested_folder_and_drops_non_http(self):
        profile = chromium_profile(self.root)
        marks = imp.read_chromium_bookmarks(profile)
        self.assertEqual([m["url"] for m in marks], ["https://docs.example.com/guide"])
        self.assertEqual(marks[0]["title"], "Docs")
        self.assertEqual(marks[0]["folder"], "Bookmarks bar / Reading",
                         "the folder path is kept, not folded into the title")

    def test_favicon_prefers_the_larger_bitmap(self):
        profile = chromium_profile(self.root)
        favicons = imp.read_chromium_favicons(profile)
        blob, width = favicons["https://docs.example.com/guide"]
        self.assertEqual(width, 32)
        self.assertIn(b"thirty-two", blob)

    def test_host_match_finds_an_icon_for_a_deeper_url(self):
        """A bookmark saved as /page, cached as / — same site, one icon."""
        favicons = {"https://docs.example.com/": (b"\x89PNG\r\n\x1a\nx", 32)}
        self.assertIsNotNone(imp.pick_favicon("https://docs.example.com/page", favicons))


class FirefoxTests(TempCase):
    def test_reads_places_bookmarks_only(self):
        profile = firefox_profile(self.root)
        marks = imp.read_firefox_bookmarks(profile)
        self.assertEqual([m["title"] for m in marks], ["Firefox", "Add-ons"])

    def test_reads_firefox_favicon(self):
        profile = firefox_profile(self.root)
        favicons = imp.read_firefox_favicons(profile)
        self.assertIn(b"-ff", favicons["https://mozilla.org/firefox/"][0])

    def test_missing_database_degrades_to_no_icons(self):
        profile = firefox_profile(self.root)
        (profile / "favicons.sqlite").unlink()
        self.assertEqual(imp.read_firefox_favicons(profile), {})


class MergeTests(TempCase):
    """The contract: never clobber, never resurrect a deletion, append the rest."""

    def incoming(self):
        return [{"title": "New", "url": "https://new.example.com/", "folder": ""}]

    def test_existing_url_is_left_alone(self):
        entries = [{"title": "Mine", "url": "https://new.example.com/"}]
        added, _ = imp.merge(entries, {}, self.incoming(), "src", {}, False)
        self.assertEqual(added, [])
        self.assertEqual(entries, [{"title": "Mine", "url": "https://new.example.com/"}],
                         "the user's title was overwritten")

    def test_deleted_bookmark_is_not_re_added(self):
        entries = []
        ledger = {"src": [imp.norm_url("https://new.example.com/")]}
        added, _ = imp.merge(entries, ledger, self.incoming(), "src", {}, False)
        self.assertEqual(added, [], "a bookmark the user deleted came back")

    def test_genuinely_new_is_appended(self):
        entries = []
        added, _ = imp.merge(entries, {}, self.incoming(), "src", {}, False)
        self.assertEqual(len(added), 1)
        self.assertEqual(entries[0]["url"], "https://new.example.com/")

    def test_url_variants_are_one_bookmark(self):
        """www / trailing slash / host case must not import as duplicates.

        The SCHEME is deliberately not part of it: http:// and https:// are
        different pages to a browser, so they stay distinct bookmarks.
        """
        entries = [{"title": "Mine", "url": "https://example.com/page"}]
        variants = [{"title": "A", "url": "https://www.example.com/page/"},
                    {"title": "B", "url": "https://EXAMPLE.com/page"}]
        added, _ = imp.merge(entries, {}, variants, "src", {}, False)
        self.assertEqual(added, [], "url normalisation diverged: %r" % (added,))
        entries2 = [{"title": "Mine", "url": "https://example.com/page"}]
        added2, _ = imp.merge(entries2, {}, [{"title": "C",
                                              "url": "http://example.com/page"}],
                              "src", {}, False)
        self.assertEqual(len(added2), 1,
                         "http and https are different pages and must stay apart")

    def test_icon_is_attached_and_falls_back_to_none(self):
        entries = []
        favicons = {"https://new.example.com/": (b"\x89PNG\r\n\x1a\n-z", 32)}
        added, _ = imp.merge(entries, {}, self.incoming(), "src", favicons, True)
        self.assertTrue(added[0]["icon"].endswith(".png"))
        self.assertTrue(Path(added[0]["icon"]).is_file())
        entries2 = []
        added2, _ = imp.merge(entries2, {}, self.incoming(), "src", {}, True)
        self.assertNotIn("icon", added2[0],
                         "a bookmark with no favicon must keep the default icon")


class TitleTests(unittest.TestCase):
    """A browser stores the bare link as the name when never renamed."""

    def test_url_becomes_a_word(self):
        cases = {
            "https://chat.deepseek.com/": "deepseek",
            "https://youtube.com": "youtube",
            # /pricing is a real segment, so it beats the host. The
            # country-code rule is only reached when there is no path.
            "https://example.co.uk/pricing": "pricing",
            "https://example.co.uk": "example",
            "https://x.com": "x",
            "http://192.168.1.5/admin": "192.168.1.5",
            "http://localhost:3000/app": "localhost",
            "https://user:pw@internal.example.com:8443/x": "example",
        }
        for url, want in cases.items():
            with self.subTest(url=url):
                self.assertEqual(imp.title_from_url(url), want)

    def test_the_path_wins_over_the_host(self):
        """The path knows the subject; the host only knows the publisher."""
        cases = {
            "https://github.com/anthropics": "anthropics",
            "https://en.wikipedia.org/wiki/Niri_(compositor)": "Niri",
            "https://www.reddit.com/r/niri/": "niri",
            "https://almohri.io/cs223": "cs223",
            # The FIRST meaningful segment, not the last: the tail of a GitHub
            # file URL is blob/main/README.md, none of which is the subject.
            "https://github.com/anthropics/claude-code/blob/main/README.md": "anthropics",
        }
        for url, want in cases.items():
            with self.subTest(url=url):
                self.assertEqual(imp.title_from_url(url), want)

    def test_plumbing_segments_are_skipped(self):
        """/search and /item say nothing; the host is the better name."""
        self.assertEqual(imp.title_from_url("https://www.google.com/search?q=x"), "google")
        self.assertEqual(imp.title_from_url("https://news.ycombinator.com/item?id=1"),
                         "ycombinator")

    def test_country_code_second_level_is_kept(self):
        """example.co.uk must be "example" — the naive slice gave "co"."""
        self.assertEqual(imp.title_from_url("https://example.co.uk"), "example")

    def test_ip_and_port_survive_intact(self):
        """192.168.1.5 must not collapse to "1", and lose its port."""
        self.assertEqual(imp.title_from_url("http://192.168.1.5/admin"), "192.168.1.5")
        self.assertEqual(imp.title_from_url("http://localhost:3000/app"), "localhost")

    def test_empty_input_returns_empty(self):
        self.assertEqual(imp.title_from_url(""), "")

    def test_is_urlish_matches_the_providers_shape(self):
        for t in ("https://x.com", "http://x.com", "www.x.com", "x.com"):
            self.assertTrue(imp.is_urlish(t), t)
        for t in ("Docs", "My notes", "a b c", ""):
            self.assertFalse(imp.is_urlish(t), t)


@unittest.skipIf(shutil.which("node") is None, "node is required for the QML parity check")
class QmlParityTests(unittest.TestCase):
    """The shell derives the same name the importer wrote.

    Two implementations of one rule is a duplication risk, and the failure is
    quiet and ugly: an imported name that changes the first time quickshell
    reloads bookmarks.json looks like the launcher renaming your bookmarks at
    random. So this extracts the REAL functions out of BookmarksProvider.qml,
    runs them under node, and compares every URL. Change either side and this
    fails — the same approach test_icon_colors.py uses for the icon ramp.
    """

    URLS = [
        "https://chat.deepseek.com/", "https://github.com/anthropics",
        "https://en.wikipedia.org/wiki/Niri_(compositor)",
        "https://news.ycombinator.com/item?id=1", "https://www.google.com/search?q=x",
        "https://youtube.com", "https://example.co.uk/pricing",
        "http://192.168.1.5/admin", "http://localhost:3000/app",
        "https://user:pw@internal.example.com:8443/x", "https://almohri.io/cs223",
        "https://x.com", "https://github.com/anthropics/claude-code/blob/main/README.md",
        "https://www.reddit.com/r/niri/", "https://sub.domain.freellm.net/deep",
        "https://medium.com/@someone/some-long-article-title-here",
        "https://freellm.net/", "https://a.b.c.d.github.io",
        "https://en.m.wikipedia.org/wiki/Niri", "", "https://x.com/a/b/c/d/e",
    ]

    @classmethod
    def setUpClass(cls):
        qml = (REPO / "quickshell" / "sunset" / "components" / "launcher" /
               "providers" / "BookmarksProvider.qml").read_text()
        noise = qml[qml.index("readonly property var noiseSegments:"):
                    qml.index("];", qml.index("readonly property var noiseSegments:")) + 2]
        noise = noise.replace("readonly property var noiseSegments:", "const noise =")

        def grab(name, drop_types):
            start = qml.index("function %s(" % name)
            brace = qml.index("{", start)
            depth, i = 0, brace
            while i < len(qml):
                if qml[i] == "{":
                    depth += 1
                elif qml[i] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            body = qml[start:i + 1].replace(drop_types[0], drop_types[1])
            return body.replace("root.noiseSegments.indexOf(low)", "noise.indexOf(low)")

        program = "\n".join([
            noise,
            grab("cleanSegment", ("function cleanSegment(seg: string): string",
                                  "function cleanSegment(seg)")),
            grab("titleFromUrl", ("function titleFromUrl(u: string): string",
                                  "function titleFromUrl(u)")),
            "const out = {};",
            "for (const u of JSON.parse(process.argv[1])) out[u] = titleFromUrl(u);",
            "process.stdout.write(JSON.stringify(out));",
        ])
        result = subprocess.run(["node", "-e", program, json.dumps(cls.URLS)],
                                capture_output=True, text=True)
        if result.returncode != 0:
            raise AssertionError("node failed on the extracted QML: %s" % result.stderr)
        cls.qml = json.loads(result.stdout)

    def test_both_sides_derive_the_same_name(self):
        for url in self.URLS:
            with self.subTest(url=url):
                self.assertEqual(self.qml[url], imp.title_from_url(url),
                                 "BookmarksProvider.qml and import-browser-bookmarks.py "
                                 "disagree about the name for %s" % url)


class ProfileDiscoveryTests(TempCase):
    """Discovery scans the REAL roots, so point them at the sandbox.

    find_chromium()/find_firefox() read module-level root tables on purpose --
    they are the list of places a browser actually installs itself, which is
    the one thing worth not abstracting. A test therefore redirects the tables
    rather than the functions, and so still exercises the real _profile_dirs
    walk and the "does this profile hold a bookmarks file" test.
    """

    def redirect(self):
        for attr, value in (("CHROMIUM_ROOTS", [("FakeChrome", self.root / "chromium")]),
                            ("FIREFOX_ROOTS", [("FakeFirefox", self.root / "firefox")])):
            self.addCleanup(setattr, imp, attr, getattr(imp, attr))
            setattr(imp, attr, value)

    def test_finds_both_families(self):
        self.redirect()
        (self.root / "chromium").mkdir()
        (self.root / "firefox").mkdir()
        chromium_profile(self.root / "chromium")
        firefox_profile(self.root / "firefox")
        chromium = [str(p) for _, p in imp.find_chromium()]
        firefox = [str(p) for _, p in imp.find_firefox()]
        self.assertEqual(len(chromium), 1)
        self.assertEqual(len(firefox), 1)

    def test_collect_reads_every_profile_it_finds(self):
        self.redirect()
        (self.root / "chromium").mkdir()
        (self.root / "firefox").mkdir()
        chromium_profile(self.root / "chromium")
        firefox_profile(self.root / "firefox")
        found = imp.collect()
        self.assertEqual(len(found), 2)
        self.assertEqual(sum(len(marks) for _, _, marks, _ in found), 3)

    def test_selecting_one_browser_skips_the_other(self):
        self.redirect()
        (self.root / "chromium").mkdir()
        (self.root / "firefox").mkdir()
        chromium_profile(self.root / "chromium")
        firefox_profile(self.root / "firefox")
        found = imp.collect("firefox")
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0][1].startswith("FakeFirefox"))

    def test_a_corrupt_bookmarks_file_reports_instead_of_crashing(self):
        profile = chromium_profile(self.root)
        (profile / "Bookmarks").write_text("{not json", encoding="utf-8")
        self.assertEqual(imp.read_chromium_bookmarks(profile), [])


if __name__ == "__main__":
    unittest.main()