#!/usr/bin/env python3
"""Keep README.md and help/index.html in step with what the launcher actually does.

    changelog.py verify              # check both docs, exit 1 on any drift
    changelog.py counts [--write]    # help/index.html section row counts
    changelog.py insert --date D --headline H --file F [--file F ...]
    changelog.py screenshots [--write]

Four jobs, all mechanical, because the failure mode here is silent: help.html
carries a hand-written row count per section, so adding a shortcut row without
bumping it leaves the page quietly lying about how many it has. It already had
that bug (the launcher section claimed 59 while holding 62 rows) — nobody
noticed for a release.

`verify` is what a pre-commit hook or CI runs. `counts --write` is the fix.

READMEs are written by hand on purpose. This tool never rewrites prose; it only
reports drift, inserts a changelog entry above the previous one, and owns the
numbers that must not be typed by a human.
"""

import argparse
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
README = ROOT / "README.md"
HELP = ROOT / "help" / "index.html"

# `**2026-10-05 — some headline.**` optionally followed by prose. The em dash
# is U+2014; the repo's changelog has used it for every entry, so a plain
# hyphen means the author drifted and `verify` says so rather than guessing
# which of the two shapes is canonical.
ENTRY_RE = re.compile(
    r"^\*\*(?P<date>\d{4}-\d{2}-\d{2})\s*—\s*(?P<headline>.+?)\*\*",
    re.MULTILINE)

SECTION_RE = re.compile(r'<details class="sec" id="(?P<id>[\w-]+)">')

# A section ends at the next section's start (or EOF), NOT at its own
# `</details>`: several sections contain nested <details class="more"> blocks,
# so a regex that stops at the first closing tag undercounts everything after
# the first nested one. Measured wrong on three sections before this was fixed.
SECTION_COUNT_RE = re.compile(r'class="n">(\d+)</span>')


def readme_entries(text):
    """[(date, headline)] for every changelog entry, in file order."""
    return [(m.group("date"), m.group("headline")) for m in ENTRY_RE.finditer(text)]


def help_sections(text):
    """[(section_id, declared_count, actual_count)] in document order."""
    starts = [(m.start(), m.group("id")) for m in SECTION_RE.finditer(text)]
    out = []
    for i, (pos, sid) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else len(text)
        body = text[pos:end]
        declared = SECTION_COUNT_RE.search(body)
        actual = len(re.findall(r'class="row"', body))
        out.append((sid, int(declared.group(1)) if declared else None, actual))
    return out


def format_entry(day, headline, files):
    """One changelog entry in the repo's existing shape.

    The body is a bullet per changed file, because a changelog entry that
    names no file cannot be checked against `git show` later — and this repo's
    habit of writing prose that outlives the code is exactly why several of
    the numbers above had gone stale without anyone noticing.
    """
    lines = ["**%s — %s.**" % (day, headline), ""]
    lines.append("| File | What changed |")
    lines.append("| :-- | :-- |")
    for path, what in files:
        lines.append("| `%s` | %s |" % (path, what))
    lines.append("")
    return "\n".join(lines)


def cmd_counts(args):
    rows = help_sections(HELP.read_text())
    changed = []
    for sid, declared, actual in rows:
        state = "ok" if declared == actual else "STALE"
        print("%-10s declared=%-5s actual=%-5d %s"
              % (sid, "?" if declared is None else declared, actual, state))
        if declared != actual:
            changed.append((sid, actual))
    if args.write and changed:
        text = HELP.read_text()
        for sid, actual in changed:
            # Bound the replacement to this section's own header so a count of
            # 23 elsewhere cannot be rewritten when two sections happen to
            # share a number.
            pat = re.compile(
                r'(<details class="sec" id="%s">.*?class="n">)(\d+)(</span>)'
                % re.escape(sid), re.S)
            text, n = pat.subn(lambda m: m.group(1) + str(actual) + m.group(3),
                               text, count=1)
            if n != 1:
                print("could not rewrite count for %s" % sid, file=sys.stderr)
                return 1
        HELP.write_text(text)
        print("wrote %d section count(s)" % len(changed))
    elif changed:
        print("\n%d stale — rerun with --write" % len(changed))
    return 0


def cmd_insert(args):
    text = README.read_text()
    marker = "## 📝 Changelog"
    if marker not in text:
        print("no changelog section in README.md", file=sys.stderr)
        return 1
    entry = format_entry(args.date, args.headline, args.file)
    head = text[:text.index(marker) + len(marker)]
    tail = text[text.index(marker) + len(marker):]
    tail = re.sub(r"\A\s*\n", "\n\n" + entry, tail)
    README.write_text(head + tail)
    print("inserted %s entry above the previous one" % args.date)
    return 0


def cmd_screenshots(args):
    """Report which checklist images are on disk and which are still missing."""
    text = README.read_text()
    rows = re.findall(r'^\|\s*\d+\s*\|.*?\|\s*`([\w.-]+\.png)`\s*\|\s*([☑☐])',
                      text, re.MULTILINE)
    if not rows:
        print("no screenshot checklist found in README.md", file=sys.stderr)
        return 1
    missing = []
    for name, mark in rows:
        path = ROOT / ".github" / "assets" / "screenshots" / name
        ok = path.is_file()
        print("%-28s %-4s %s" % (name, "done" if ok else "MISSING",
                                  "on disk" if ok else "todo"))
        if not ok:
            missing.append(name)
    print("\n%d of %d captured" % (len(rows) - len(missing), len(rows)))
    return 0


def cmd_verify(args):
    problems = []

    entries = readme_entries(README.read_text())
    if not entries:
        problems.append("README.md has no changelog entries")
    for day, headline in entries:
        if not headline.strip():
            problems.append("empty headline on %s" % day)
    # Repeated dates are NOT a problem: the changelog already carries four
    # entries for 2026-10-04 and two for 2026-10-05, one per feature. An
    # earlier version flagged duplicates and would have failed on a clean
    # tree, which is the same cry-wolf failure the structural checks hit.
    for day in sorted({d for d, _ in entries}):
        same = [h for d, h in entries if d == day]
        if len(same) > 1:
            print("note %s has %d entries" % (day, len(same)))

    help_text = HELP.read_text()

    for sid, declared, actual in help_sections(help_text):
        if declared is None:
            problems.append("help/index.html: section %r has no row count" % sid)
        elif declared != actual:
            problems.append(
                "help/index.html: section %r says %d rows, has %d "
                "(changelog.py counts --write)" % (sid, declared, actual))

    # Structural validation is deliberately absent. Both obvious checks lie
    # here: help.html leaves two <details> without an end tag (present in
    # HEAD, browsers accept it), and a per-block <div> counter reports 25
    # "imbalances" on a tree byte-identical to HEAD. A verify command that
    # fails on a clean checkout gets ignored, so it checks the one thing
    # that is unambiguous — a number a human typed — and nothing else.
    for problem in problems:
        print("FAIL %s" % problem)
    if not problems:
        print("OK README changelog + help/index.html counts")
    return 1 if problems else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("verify", help="check both docs, exit 1 on drift")
    p.set_defaults(func=cmd_verify)

    p = sub.add_parser("counts", help="help/index.html section row counts")
    p.add_argument("--write", action="store_true")
    p.set_defaults(func=cmd_counts)

    p = sub.add_parser("insert", help="insert a README changelog entry")
    p.add_argument("--date", default=date.today().isoformat())
    p.add_argument("--headline", required=True)
    p.add_argument("--file", action="append", default=[],
                   metavar="PATH=WHAT", help="repeatable")
    p.set_defaults(func=cmd_insert)

    p = sub.add_parser("screenshots", help="which checklist images exist")
    p.add_argument("--write", action="store_true")
    p.set_defaults(func=cmd_screenshots)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())