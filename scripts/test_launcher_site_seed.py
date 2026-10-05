#!/usr/bin/env python3
"""Run WebProvider.qml's own site-seed helpers, so Ctrl+Tab can never seed wrong.

Ctrl+Tab on a highlighted website row fills the launcher query with "@<bang> "
(Launcher.qml seedSiteSearch). The text is produced by WebProvider, not by the
launcher, because the site table is the only thing that knows the canonical
bang. That split is exactly what makes drift dangerous: a table edit that
renames a bang, or a host-matching rule that gets looser, would quietly hand the
user a search on the WRONG site -- and unlike a broken palette, there is no
screen that shows a user they got the wrong one.

So this lifts hostOf/bangForUrl/seedFor verbatim out of the QML and runs them
under node (same approach as test_icon_colors.py, which does the same for
Theme.qml's icon-ramp maths). Editing the QML is the only way to change the
behaviour; the expectations here just pin it.

It also pins the SHAPE that seedFor must keep, because the launcher relies on
"" meaning "this row is not a searchable site": plain Tab is the input<->list
focus trap, so returning a wrong-but-nonempty seed would break navigation and
wrong-but-empty would just do nothing.
"""

import json
import re
import subprocess
import unittest
from pathlib import Path

PROVIDER = Path(__file__).resolve().parents[1] / (
    "quickshell/sunset/components/launcher/providers/WebProvider.qml")

# hostOf/bangForUrl are used by seedFor's siblings; sites backs bangForUrl.
QML_FUNCTIONS = ["hostOf", "bangForUrl", "seedFor"]

NODE = subprocess.run(["node", "--version"], capture_output=True)


def _matching_brace(text, brace):
    """Index of the bracket closing the one at `brace`.

    Counts any bracket type, not just braces: the site table is a "[" ... "]"
    array, and a brace-only counter never closed it.
    """
    pairs = {"{": "}", "[": "]", "(": ")"}
    depth = 0
    for i in range(brace, len(text)):
        if text[i] in pairs:
            depth += 1
        elif text[i] in pairs.values():
            depth -= 1
            if depth == 0:
                return i
    raise AssertionError("unbalanced brackets in WebProvider.qml")


def _strip_annotations(fn):
    """Drop QML param/return type annotations, which are not valid JS.

    Return type first (it sits after the closing paren), then params. The param
    pattern allows an opening paren as well as a comma before it, so a
    single-parameter signature like `hostOf(url: string)` is caught too --
    requiring a comma there silently left the annotation in place and node
    then refused the whole program. Only a name immediately followed by a
    known QML type name and then a delimiter is rewritten, so a stray colon
    elsewhere in the body is never eaten.
    """
    fn = re.sub(r"\)\s*:\s*[A-Za-z]+\s*\{", ") {", fn)
    fn = re.sub(r"([(,]\s*)([A-Za-z_]\w*)\s*:\s*[A-Za-z]+\s*([,)])",
                r"\1\2 \3", fn)
    return fn


def qml_source():
    """A JS object literal exposing WebProvider's real site-seed functions.

    Lifted verbatim, not retyped. hostOf/bangForUrl call each other and read
    `sites`, so they all go into one namespace object plus the sites table --
    which is exactly how QML resolves them, being members of one root object.
    """
    qml = PROVIDER.read_text()
    members = []
    for name in QML_FUNCTIONS:
        start = qml.index("function %s(" % name)
        brace = qml.index("{", start)
        members.append("%s: %s" % (
            name, _strip_annotations(qml[start:_matching_brace(qml, brace) + 1])))
    # The site table, verbatim: these tests are about the REAL homes/bangs.
    # Slice to the matching bracket rather than to the first "];", which is a
    # plausible follower ("siteUrl()" right below the table) and over-captured.
    decl = qml.index("readonly property var sites:")
    brace = qml.index("[", decl)
    table = qml[brace:_matching_brace(qml, brace) + 1]
    # Kept as a full [...] array literal, brackets included: slicing off the
    # "[" left the elements as bare adjacent objects with nothing closing them.
    members.append("sites: %s" % table.strip())
    return "const Web = {%s};\n" % ",\n".join(members)


def run_node(cases):
    """Run WebProvider's own functions under node. Returns the JSON result list."""
    program = qml_source() + """
// The extracted functions call each other and read `sites` by bare name. That
// is how QML resolves them (members of one root object) but it is a global
// lookup in plain JS, so bind them into module scope -- same trick (and same
// reason) as test_icon_colors.py does for Theme.qml's own icon-ramp maths.
const {hostOf, bangForUrl, seedFor, sites} = Web;
const cases = JSON.parse(process.argv[1]);
const out = cases.map(([kind, arg]) => {
    if (kind === "hostOf") return hostOf(arg);
    if (kind === "bangForUrl") return bangForUrl(arg);
    if (kind === "seedRow") {
        // A homepage site row, exactly as siteRow() builds it.
        const site = Web.sites[arg];
        return seedFor({kind: "web", name: site.name,
                        data: {url: site.home, bang: site.bangs[0]}});
    }
    return seedFor(arg);
});
process.stdout.write(JSON.stringify(out));
"""
    result = subprocess.run(["node", "-e", program, json.dumps(cases)],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError("node failed on the extracted WebProvider.qml: %s"
                             % result.stderr)
    return json.loads(result.stdout)


@unittest.skipIf(NODE.returncode != 0, "node is required to run WebProvider.qml's own functions")
class TestSiteSeed(unittest.TestCase):
    def test(self):
        def bulk(cases):
            return run_node(cases)

        # hostOf: just has to isolate the hostname well enough to match a
        # bookmark against the site table. A near-miss means "no bang", never
        # a wrong bang, so the bar is "correct host for every real-world URL
        # shape" rather than a full RFC 3986 parse.
        self.assertEqual(bulk([["hostOf", u] for u in [
            "https://github.com/a/b",
            "https://github.com/",
            "github.com",
            "https://user:pw@github.com/x",
            "https://github.com:443/x",
            "https://github.com?tab=repos",
            "https://github.com#anchor",
            "HTTPS://GitHub.COM/x",
            "",
            "   ",
        ]]), ["github.com"] * 8 + ["", ""])

        # bangForUrl: a saved bookmark maps back to its site's canonical bang
        # (bangs[0]), so "@github" and "@gh" seed identically. Subdomain
        # tolerance both ways -- a bookmark to docs.github.com still finds
        # github.com, and github.com still finds a site hosted on www.*.
        self.assertEqual(bulk([["bangForUrl", u] for u in [
            "https://github.com/me",
            "https://www.github.com",
            "https://docs.github.com/x",
            "github.com",
            "https://www.google.com/search?q=x",
            "https://duckduckgo.com/?q=cats",
            "https://youtube.com/watch?v=1",
            "https://www.miruro.to",
            "https://www.google.com/maps/search/x",
            "https://example.org/x",
            "http://localhost:3000/",
            "",
        ]]), ["gh", "gh", "gh", "gh", "g", "dd", "yt", "miruro", "g", "", "", ""])

        # seedFor on a real homepage row: bang + ONE trailing space, so the
        # caret lands where the words go and nothing has to be deleted.
        for idx, want in [(0, "@dd "), (1, "@g "), (4, "@gh "), (8, "@miruro ")]:
            self.assertEqual(run_node([["seedRow", idx]]), [want])

        # seedFor must return "" -- never a guess -- for every row that is not
        # a searchable site. "" is the launcher's signal to leave Ctrl+Tab
        # alone and let plain Tab keep doing its focus-trap job.
        self.assertEqual(run_node([
            ["seed", {"kind": "web", "data": {"url": "https://x/search?q=1"}}],  # has terms
            ["seed", {"kind": "web", "data": {"url": "https://github.com"}}],     # bare URL
            ["seed", {"kind": "bookmark", "data": {"action": "open", "index": 0}}],
            ["seed", {"kind": "app", "entry": {"name": "GitHub"}}],
            ["seed", {"kind": "file", "data": {"path": "/tmp/x"}}],
            ["seed", {"kind": "control", "name": "Settings"}],
            ["seed", None],
            ["seed", {}],
        ]), [""] * 8)


if __name__ == "__main__":
    unittest.main()