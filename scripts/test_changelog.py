#!/usr/bin/env python3
"""Pin scripts/changelog.py's contract, and the doc rules it exists to protect.

Three things are covered, all of them the kind of drift nobody notices:

  1. The section-count repair is the tool's whole reason for existing. help.html
     declares a row count per section in a hand-written <span class="n">, and it
     was already wrong in this repo (launcher said 59, held 62) before the tool
     existed. So the counting is tested against a synthetic document where the
     answer is known, NOT against the live file -- otherwise the test just
     asserts whatever the tool happens to do today.

  2. The doc rules that are silently breakable: the changelog heading shape, the
     key chords named in README must also appear in help/index.html, and the
     easter-egg site must stay out of every doc while remaining in code.

  3. That `verify` is clean on the committed tree, so a real regression fails
     the suite rather than waiting to be noticed by a reader.
"""

import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import changelog  # noqa: E402

README = ROOT / "README.md"
HELP = ROOT / "help" / "index.html"

# The launcher's site table is the code's business; the docs are not allowed to
# name it. An easter egg in a public README is just a spoiler.
EASTER_EGG = "miruro"


class TestCounting(unittest.TestCase):
    """help_sections() against a document whose answer is known by hand."""

    DOC = (
        '<details class="sec" id="one">'
        '  <summary><span class="sec-count"><span class="n">2</span></span></summary>'
        '  <div class="rows">'
        '    <div class="row">a</div>'
        '    <div class="row">b</div>'
        '  </div>'
        '  <details class="more"><summary>nested</summary>'
        '    <div class="row">c</div>'          # nested row: must be counted
        '  </details>'
        '</details>'
        '<details class="sec" id="two">'
        '  <summary><span class="sec-count"><span class="n">9</span></span></summary>'
        '  <div class="rows"><div class="row">d</div></div>'
        '</details>'
    )

    def test_counts_rows_and_reports_stale(self):
        rows = changelog.help_sections(self.DOC)
        self.assertEqual([r[0] for r in rows], ["one", "two"])
        # one: 2 declared, 3 actual (the nested <details> row counts) -> stale
        self.assertEqual(rows[0][1], 2)
        self.assertEqual(rows[0][2], 3)
        # two: 9 declared, 1 actual
        self.assertEqual(rows[1][1], 9)
        self.assertEqual(rows[1][2], 1)

    def test_section_slice_survives_nested_details(self):
        """A naive </details> slice would truncate `one` at the nested block.

        This is the bug the boundary-at-next-section comment describes: with a
        closing-tag slice the count would be 2 and look merely stale, while with
        no slice at all it would bleed `two`'s rows into `one`.
        """
        rows = dict((r[0], r[2]) for r in changelog.help_sections(self.DOC))
        self.assertEqual(rows["one"], 3)
        self.assertEqual(rows["two"], 1)

    def test_missing_count_is_reported_not_guessed(self):
        doc = ('<details class="sec" id="x"><div class="row">a</div>'
               '</details>')
        sid, declared, actual = changelog.help_sections(doc)[0]
        self.assertEqual((sid, declared), ("x", None))
        self.assertEqual(actual, 1)


class TestEntries(unittest.TestCase):
    def test_reads_date_and_headline(self):
        text = ("**2026-10-05 — Ctrl+Space is web search.**\nbody\n"
                "**2026-10-04 — Older thing.**\n")
        self.assertEqual(
            changelog.readme_entries(text),
            [("2026-10-05", "Ctrl+Space is web search."),
             ("2026-10-04", "Older thing.")])

    def test_repeated_dates_are_allowed(self):
        """The changelog legitimately has several entries per day.

        A version of this test asserted dates were unique, which would fail on
        a clean checkout -- four 2026-10-04 entries exist today.
        """
        text = "**2026-10-04 — A.**\n**2026-10-04 — B.**\n"
        self.assertEqual(len(changelog.readme_entries(text)), 2)

    def test_format_entry_names_every_file(self):
        out = changelog.format_entry(
            "2026-10-05", "A thing happened",
            [("a.qml", "touched"), ("b.kdl", "also touched")])
        self.assertIn("**2026-10-05 — A thing happened.**", out)
        self.assertIn("| `a.qml` | touched |", out)
        self.assertIn("| `b.kdl` | also touched |", out)


class TestDocRules(unittest.TestCase):
    """Rules about the committed docs themselves."""

    def test_easter_egg_is_absent_from_every_doc(self):
        for path in (README, HELP, ROOT / "AGENTS.md"):
            text = path.read_text().lower()
            self.assertNotIn(
                EASTER_EGG, text,
                "%s names the %s easter egg -- it belongs in code, not docs"
                % (path.name, EASTER_EGG))

    def test_easter_egg_still_works_in_code(self):
        """Removing it from docs must NOT have removed the feature."""
        provider = (ROOT / "quickshell/sunset/components/launcher/providers/"
                    "WebProvider.qml").read_text().lower()
        self.assertIn(EASTER_EGG, provider,
                      "the site was deleted from the launcher too -- the docs "
                      "and the feature are separate changes")

    def test_readme_changelog_headings_are_well_formed(self):
        text = README.read_text()
        entries = changelog.readme_entries(text)
        self.assertTrue(entries, "README has no changelog entries")
        for day, headline in entries:
            self.assertRegex(day, r"^\d{4}-\d{2}-\d{2}$")
            self.assertTrue(headline.strip(), "empty headline on %s" % day)
            # The period is INSIDE the bold in every existing entry
            # (**2026-10-05 — Thing.**), so it must be there. An earlier
            # version of this test asserted the opposite and failed on the
            # repo's own convention.
            self.assertTrue(headline.endswith("."),
                            "headline on %s has no trailing '.', which breaks "
                            "the **date — headline.** shape" % day)

    def test_new_chords_are_documented_in_both_places(self):
        """Every chord README advertises must exist in the in-app help too."""
        readme = README.read_text()
        help_text = HELP.read_text()
        # Strip tags so the chord and its surroundings are comparable.
        plain_help = re.sub(r"<[^>]+>", " ", help_text)
        plain_help = plain_help.replace("&amp;", "&").replace("&nbsp;", " ")

        for chord in ("F10", "Ctrl+Tab"):
            self.assertIn(chord, readme, "README dropped %s" % chord)
            self.assertIn(
                chord, plain_help,
                "README advertises %s but help/index.html does not mention it"
                % chord)

    def test_screenshot_checklist_present(self):
        text = README.read_text()
        found = re.findall(
            r'^\|\s*\d+\s*\|.*?\|\s*`([\w.-]+\.png)`\s*\|\s*[☐☑]', text,
            re.MULTILINE)
        self.assertGreaterEqual(len(found), 5,
                                "the 'Screenshots still to capture' checklist "
                                "disappeared from README.md")
        for name in found:
            self.assertNotIn(" ", name, "screenshot filename has a space")


class TestVerifyIsClean(unittest.TestCase):
    def test_verify_passes_on_the_committed_tree(self):
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "changelog.py"), "verify"],
            capture_output=True, text=True)
        self.assertEqual(
            result.returncode, 0,
            "changelog.py verify failed on the committed tree:\n%s"
            % result.stdout)

    def test_counts_write_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = (ROOT / "help" / "index.html").read_text()
            target = Path(tmp) / "index.html"
            target.write_text(src)
            original = changelog.HELP
            try:
                changelog.HELP = target
                args = changelog.argparse.Namespace(write=True)
                self.assertEqual(changelog.cmd_counts(args), 0)
                first = target.read_text()
                self.assertEqual(changelog.cmd_counts(args), 0)
                self.assertEqual(target.read_text(), first,
                                 "counts --write changed the file twice")
            finally:
                changelog.HELP = original


if __name__ == "__main__":
    unittest.main()