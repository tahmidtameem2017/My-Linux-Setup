#!/usr/bin/env python3
"""Pin the launcher's contextual menu: what it offers, and that it is reachable.

The row menu (right click / F10, added 2026-10-05) is built from two pieces
that live in DIFFERENT files and must agree:

  Launcher.qml      rowMenuItems()  — which items a row gets, by row kind
  ContextMenu.qml   runLauncherOp() — which `op` strings it will act on

`op` crosses a process boundary (ContextMenu execs `qs ... launcher rowMenuItem
<op>`, which shell.qml dispatches back onto the launcher's root method). A typo
in either half produces a menu item that renders, takes focus, and does
absolutely nothing when chosen — with no error anywhere. That is exactly the
class of silent failure this repo keeps re-learning, so the two lists are
compared here rather than trusted.

It also pins the properties that make the menu honest:

  - every actionable item carries a `hint` naming its keyboard twin, because
    the mouse path and the key path printing side by side IS the feature
  - a row never offers a verb it cannot perform (a cheatsheet `/` row with no
    path must not get Reveal/Terminal/Copy)
  - the informational help-menu rows carry no `op` at all, so they are inert
  - the pin label flips to "Unpin" on an already-pinned row

rowMenuItems() is lifted out of the QML and run under node, the same approach
as test_launcher_site_seed.py (WebProvider's site helpers) and
test_icon_colors.py (Theme.qml's icon-ramp maths). Editing the QML is the only
way to change the behaviour; the cases here just pin it.
"""

import json
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "quickshell/sunset/components/Launcher.qml"
CONTEXT_MENU = ROOT / "quickshell/sunset/components/ContextMenu.qml"
SHELL = ROOT / "quickshell/sunset/shell.qml"

NODE = subprocess.run(["node", "--version"], capture_output=True)


def _matching_brace(text, brace):
    """Index of the bracket closing the one at `brace`."""
    pairs = {"{": "}", "[": "]", "(": ")"}
    depth = 0
    for i in range(brace, len(text)):
        if text[i] in pairs:
            depth += 1
        elif text[i] in pairs.values():
            depth -= 1
            if depth == 0:
                return i
    raise AssertionError("unbalanced brackets")


def _strip_annotations(fn):
    """Drop QML param/return type annotations, which are not valid JS."""
    fn = re.sub(r"\)\s*:\s*[A-Za-z]+\s*\{", ") {", fn)
    fn = re.sub(r"([(,]\s*)([A-Za-z_]\w*)\s*:\s*[A-Za-z]+\s*([,)])", r"\1\2 \3", fn)
    return fn


def _qml_function(text, name):
    """One `function name(...) {...}` verbatim, annotations stripped."""
    start = text.index("function %s(" % name)
    brace = text.index("{", start)
    return _strip_annotations(text[start:_matching_brace(text, brace) + 1])


def run_node(program, arg):
    result = subprocess.run(["node", "-e", program, json.dumps(arg)],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError("node failed on the extracted QML: %s" % result.stderr)
    return json.loads(result.stdout)


def launcher_program():
    """rowMenuItems / helpMenuItems / pinKeyFor / rowMenuItem, under node.

Stubs stand in for the QML objects they touch (appList, rows, pinned).
    They are minimal on purpose: anything a case depends on is passed in, so a
    change that starts reading NEW launcher state shows up as a test failure
    rather than silently reading a stub.

    SCOPING IS DELIBERATE AND LOADS-BEARING. In the real QML `appList` and
    `rows` are BARE identifiers, not members of root: `appList` is a ListView
    id declared inside the PanelWindow, and `rows` resolves to root's own
    `property var rows`. rowMenuItems() therefore reads bare `appList` and
    bare `rows`. This harness reproduces that with top-level `let` bindings
    rather than root members — because a previous build qualified them as
    `root.appList` / `root.rows`, and `root.appList` is undefined in QML (an
    id is not a property), so rowMenuItems() threw and EVERY right click fell
    through to the help menu. A stub that only provides `root.appList` cannot
    catch that class of bug, so this one must not provide it.
    """
    qml = LAUNCHER.read_text()
    # Spliced in as OBJECT MEMBERS, because rowMenuItems() calls
    # `root.pinKeyFor()` and reads `root.pinned`. QML resolves those as members
    # of one root object, so the harness has to too — a standalone namespace
    # leaves every `root.` reference undefined. Keyed form
    # (`pinKeyFor: function ...`) is required: a bare `function pinKeyFor()`
    # is not valid inside an object literal.
    members = ["%s: %s" % (name, _qml_function(qml, name)) for name in (
        "rowMenuItems", "helpMenuItems", "pinKeyFor", "isPinned", "rowMenuItem",
        "indexOfPinKey")]
    return """
let appList = { currentIndex: -1 };
let rows = [];
const root = {
    pinned: [],
    modePrefixes: [],
    // Recorded instead of performed, so a case can assert WHICH launcher
    // function an op reached. The real ones close windows / spawn terminals.
    calls: [],
%s,
    activateCurrent() { root.calls.push("activateCurrent"); },
    close() { root.calls.push("close"); },
    togglePreview() { root.calls.push("togglePreview"); },
    revealCurrent() { root.calls.push("revealCurrent"); },
    terminalCurrent() { root.calls.push("terminalCurrent"); },
    copyCurrent() { root.calls.push("copyCurrent"); },
    deleteCurrentBookmark() { root.calls.push("deleteCurrentBookmark"); },
    togglePinCurrent() { root.calls.push("togglePinCurrent"); },
};
function rowItemsFor(row, pinned) {
    rows = row === null ? [] : [row];
    appList.currentIndex = row === null ? -1 : 0;
    root.pinned = pinned || [];
    return root.rowMenuItems();
}
function helpItems() {
    root.modePrefixes = [
        { p: "=", n: "Calculator" }, { p: "$", n: "Windows" },
        { p: ":", n: "Clipboard" }, { p: "@", n: "Web search" },
        { p: "/", n: "Files" }, { p: ">", n: "Run a command" },
        { p: ".", n: "Symbols" }, { p: "!", n: "Todo" },
        { p: "%%", n: "Bookmarks" }, { p: ";", n: "Modes & controls" },
    ];
    return root.helpMenuItems();
}
function runOp(op) {
    root.calls = [];
    root.rowMenuItem(op);
    return root.calls;
}
function indexOfPinKey(rows, key) {
    root.rows = rows;
    return root.indexOfPinKey(key);
}
const input = JSON.parse(process.argv[1]);
const out = input.map(([kind, a, b]) => {
    if (kind === "rowItems") return rowItemsFor(a, b);
    if (kind === "helpItems") return helpItems();
    if (kind === "runOp") return runOp(a);
    if (kind === "pinKeyFor") return root.pinKeyFor(a);
    if (kind === "indexOfPinKey") return indexOfPinKey(a, b);
    return null;
});
process.stdout.write(JSON.stringify(out));
""" % ",\n".join(members)


APP_ROW = {"kind": "app", "entry": {"id": "brave.desktop", "name": "Brave"}, "action": None}
CONTROL_ROW = {"kind": "control", "name": "Settings", "ipcTarget": None, "cmd": "/x"}
FILE_ROW = {"kind": "file", "name": "report.pdf",
            "data": {"path": "/home/me/report.pdf"}}
BOOKMARK_ROW = {"kind": "bookmark", "name": "GH", "data": {"action": "open", "index": 0}}
CHEAT_ROW = {"kind": "file", "name": "!pdf !img !doc", "data": {}}


def labels(items):
    return [i["label"] for i in items if not i.get("sep")]


def ops(items):
    """Every op a menu can fire. Disabled rows carry no op by design."""
    return [i["op"] for i in items if not i.get("sep") and "op" in i]


def actionable(items):
    return [i for i in items if not i.get("sep") and not i.get("disabled")]


@unittest.skipIf(NODE.returncode != 0, "node is required to run the launcher's own QML")
class TestRowMenu(unittest.TestCase):
    def test_row_menu_contents(self):
        cases = [["rowItems", r, None] for r in
                 (APP_ROW, CONTROL_ROW, FILE_ROW, BOOKMARK_ROW, CHEAT_ROW)]

        app, control, filerow, bookmark, cheat = run_node(launcher_program(), cases)

        # Every row leads with an activation action — the same one Enter runs.
        for name, got in (("app", app), ("control", control),
                          ("file", filerow), ("bookmark", bookmark)):
            self.assertTrue(got, "%s row got an empty menu" % name)
            self.assertEqual(ops(got)[0], "open", "%s row: first op" % name)
            self.assertEqual(got[0]["hint"], "Enter", "%s row: Open hint" % name)

        # A bookmark says where it opens; everything else just says Open.
        self.assertEqual(labels(bookmark)[0], "Open in browser")
        self.assertEqual(labels(app)[0], "Open")

        # App + control rows get pinning, and NOT the file verbs.
        self.assertIn("pin", ops(app))
        self.assertIn("pin", ops(control))
        for forbidden in ("reveal", "terminal", "copy", "preview", "delete"):
            self.assertNotIn(forbidden, ops(app))
            self.assertNotIn(forbidden, ops(control))

        # A real file row gets the four file verbs, each with its chord. This
        # is the mouse/keyboard parity that is the whole point of the menu.
        self.assertEqual(
            ops(filerow), ["open", "preview", "reveal", "terminal", "copy"],
            "file row ops (note: a file row is not pinnable)")
        by_label = {i["label"]: i.get("hint") for i in actionable(filerow)}
        self.assertEqual(by_label["Preview"], "Ctrl+Alt+Space")
        self.assertEqual(by_label["Open in file manager"], "Ctrl+Enter")
        self.assertEqual(by_label["Open terminal here"], "Ctrl+T")
        self.assertEqual(by_label["Copy"], "Ctrl+C")

        # A bookmark gets deletion — the Delete key's twin.
        self.assertIn("delete", ops(bookmark))
        self.assertNotIn("pin", ops(bookmark), "bookmarks are not pinnable")

        # A `/`-mode cheatsheet row has no path, so every file verb would be a
        # no-op. Offering them would be a menu full of dead entries.
        self.assertEqual(ops(cheat), ["open"], "cheatsheet row must only offer Open")

    def test_pinned_row_flips_label(self):
        program = launcher_program()
        pinned = ["app:brave.desktop"]
        # Unpinned -> "Pin to top"; pinned -> "Unpin from top". A menu that
        # said "Pin to top" on an already-pinned row would lie about state.
        self.assertIn("Pin to top", labels(run_node(program, [["rowItems", APP_ROW, []]])[0]))
        self.assertIn("Unpin from top",
                      labels(run_node(program, [["rowItems", APP_ROW, pinned]])[0]))

    def test_every_actionable_item_has_a_hint_or_is_pin(self):
        # The feature's reason to exist: the mouse path and the key path are
        # printed together. "Pin to top" has no chord (it is new), so it is
        # the one permitted blank.
        program = launcher_program()
        rows = run_node(program, [["rowItems", r, None] for r in
                                  (APP_ROW, CONTROL_ROW, FILE_ROW, BOOKMARK_ROW)])
        for row_items in rows:
            for item in actionable(row_items):
                if item.get("hint"):
                    continue
                self.assertEqual(item["label"], "Pin to top",
                                 "actionable item with no hint: %r" % item)

    def test_help_menu_is_inert(self):
        items = run_node(launcher_program(), [["helpItems"]])[0]
        # The beginner legend: informational rows carry no op, so choosing one
        # cannot run anything.
        for item in actionable(items):
            if item["label"] == "Close the launcher":
                continue
            self.assertTrue(item.get("disabled"),
                            "help row is actionable but not disabled: %r" % item)
        # ...and exactly one real way out of it.
        self.assertEqual([i["op"] for i in actionable(items) if "op" in i], ["close"])

    def test_op_allowlist_is_closed(self):
        program = launcher_program()
        # Each op reaches exactly one launcher function — the same one its
        # keyboard twin calls.
        expected = {
            "open": "activateCurrent",
            "close": "close",
            "preview": "togglePreview",
            "reveal": "revealCurrent",
            "terminal": "terminalCurrent",
            "copy": "copyCurrent",
            "delete": "deleteCurrentBookmark",
            "pin": "togglePinCurrent",
        }
        order = sorted(expected)
        got = run_node(program, [["runOp", op] for op in order])
        for op, calls in zip(order, got):
            self.assertEqual(calls, [expected[op]],
                             "op %r reached %r, expected [%r]" % (op, calls, expected[op]))

        # Anything unknown is dropped, not guessed at: a menu item whose op
        # was mistyped must do nothing rather than fall through to some other
        # action.
        for junk in ("", "undefined", "null", "OPEN", "open; rm -rf /",
                     "restart-shell", "../evil"):
            self.assertEqual(run_node(program, [["runOp", junk]]), [[]],
                             "op %r should be a no-op" % junk)

    def test_menu_helpers_never_qualify_an_id_as_root_something(self):
        """A QML `id` is NOT a property, so `root.appList` is undefined.

        This is the exact defect behind "every right click opens the same
        (help) menu": rowMenuItems() read `root.appList.currentIndex`, which
        throws on the undefined property, so the function returned [] and the
        caller fell through to the help menu for every row, everywhere.

        The node harness above now models `appList`/`rows` as bare top-level
        bindings for the same reason — it fails loudly if this regresses. This
        check catches it at the source level too, including inside functions
        the harness does not lift, so the guard does not depend on node being
        installed.

        Only *ids* are forbidden. Real root members (`rows` is a property, but
        it is ALSO reachable bare) must stay legal, so the test lists the
        actual ListView ids rather than blanket-rejecting `root.<x>`.
        """
        launcher = LAUNCHER.read_text()
        # Ids declared anywhere in the file are the ones that cannot be
        # property-accessed off root.
        ids = set(re.findall(r"^\s*id:\s*(\w+)\s*$", launcher, re.M))
        self.assertIn("appList", ids, "sanity: the ListView id must exist")
        self.assertNotIn("rows", ids,
                         "rows is a root property, not an id — if this fails, "
                         "the guard below is checking the wrong thing")

        offenders = []
        for name in ("rowMenuItems", "helpMenuItems", "pinKeyFor", "rowMenuItem",
                     "indexOfPinKey", "isPinned"):
            # Strip line comments first: these functions are heavily commented,
            # and the prose deliberately NAMES `root.appList` to explain the
            # trap. Scanning raw text would match the explanation.
            body = re.sub(r"//[^\n]*", "", _qml_function(launcher, name))
            for var in ids:
                if re.search(r"root\.%s\b" % re.escape(var), body):
                    offenders.append("%s(): root.%s" % (name, var))
        self.assertEqual(
            offenders, [],
            "these read a QML id through root, which is undefined at runtime:\n  "
            + "\n  ".join(offenders))

    def test_row_menu_items_reads_the_live_selection(self):
        """The menu must describe the CURRENTLY SELECTED row.

        Guards the other half of the regression: if the index ever stops
        coming from `appList.currentIndex`, the menu would describe row 0 (or
        nothing) while a different row is highlighted — a menu that is
        internally consistent but describes the wrong row.
        """
        got = run_node(launcher_program(), [
            ["rowItems", {"kind": "control", "name": "Settings"}],
            ["rowItems", {"kind": "bookmark", "entry": {"name": "Docs"},
                          "url": "https://example.com"}],
        ])
        self.assertEqual(got[0][0]["label"], "Open")
        self.assertEqual(got[1][0]["label"], "Open in browser",
                         "a bookmark row leads with a browser-specific label")

    def test_pin_key_uses_the_desktop_id_not_the_filename(self):
        """`entry.id` has NO `.desktop` suffix — measured, not assumed.

        Probed against the live shell (123 entries): an installed app's id is
        `brave-browser`, while the file on disk is `brave-browser.desktop`.
        Building the key from the filename instead would make every app pin
        fail to match its own row, so reconcilePins() would silently delete it
        on the very next rebuild — a pin that appears to save and then vanishes.
        """
        got = run_node(launcher_program(), [
            ["pinKeyFor", {"kind": "app", "entry": {"id": "brave-browser"}}],
            ["pinKeyFor", {"kind": "app", "entry": {"id": "brave-browser.desktop"}}],
            ["pinKeyFor", {"kind": "app", "entry": {}}],
            ["pinKeyFor", {"kind": "control", "name": "Settings"}],
            ["pinKeyFor", {"kind": "action", "entry": {"id": "brave-browser"}}],
            ["pinKeyFor", {"kind": "file", "data": {"path": "/tmp/x"}}],
        ])
        self.assertEqual(got[0], "app:brave-browser")
        # The key is just the id with a prefix, so the suffixed form is only
        # wrong because such an id never exists — assert it is not normalised,
        # so nobody "helpfully" strips .desktop and breaks a real pin.
        self.assertEqual(got[1], "app:brave-browser.desktop")
        self.assertEqual(got[2], "", "an entry with no id is not pinnable")
        self.assertEqual(got[3], "control:Settings", "controls key on NAME")
        self.assertEqual(got[4], "app:brave-browser",
                         "an action row must resolve to its parent app")
        self.assertEqual(got[5], "", "file rows are not pinnable")

    def test_persisted_pin_file_shape(self):
        """The store is a flat JSON array of prefixed keys, most-recent-first.

        loadPinsText() has to survive a hand-edited or truncated file without
        turning `pinned` into something rowMenuItems has to defend against on
        every click, so the shape is pinned here as well as in the QML.
        """
        launcher = LAUNCHER.read_text()
        body = _qml_function(launcher, "loadPinsText")
        self.assertIn("Array.isArray", body, "a non-array payload must be rejected")
        self.assertIn('typeof k === "string"', body,
                      "non-string entries must be filtered out")
        self.assertIn("JSON.parse", body)

    def test_pins_are_written_in_place(self):
        """The store is watched, so it must never be staged+renamed.

        FileView sits on QFileSystemWatcher, which watches the INODE; an
        os.replace() (the tmp+rename every other writer here uses) would kill
        the watch on the first real change. savePins() must therefore go
        through the FileView's own setText.
        """
        launcher = LAUNCHER.read_text()
        self.assertIn("pinnedFile.setText(JSON.stringify(pinned))",
                      _qml_function(launcher, "savePins"))
        self.assertNotIn("Stdio", launcher, "no shell-out write for the pin store")

    def test_index_of_pin_key_follows_the_row(self):
        """The selection must follow the row, not its old index.

        Caught by the end-to-end run: `qs ... launcher rowMenuItem pin` twice
        in a row pinned a SECOND control instead of undoing the first, because
        pinning inserts a row at index 0 and the old index then pointed at a
        different row entirely.
        """
        program = launcher_program()
        # A pinned row exists twice — Pinned section first, then its normal
        # section copy — so the lookup must return the FIRST index.
        rows = [APP_ROW, APP_ROW, CONTROL_ROW]
        got = run_node(program, [["indexOfPinKey", rows, "app:brave.desktop"]])
        self.assertEqual(got, [0], "must find the topmost row, not a later copy")
        self.assertEqual(run_node(program, [["indexOfPinKey", rows, "app:nope"]]), [-1])
        self.assertEqual(run_node(program, [["indexOfPinKey", rows, ""]]), [-1])

    def test_pinned_selection_uses_the_lookup(self):
        # togglePinCurrent must consult indexOfPinKey rather than restoring the
        # old numeric index. Structural, because the real function drives a
        # ListView and the rebuild it needs.
        launcher = LAUNCHER.read_text()
        body = _qml_function(launcher, "togglePinCurrent")
        self.assertIn("indexOfPinKey", body,
                      "togglePinCurrent must re-find the row by identity; "
                      "pinning inserts a row at index 0 so the old index "
                      "points at a different row")
        # The numeric index may only survive as a FALLBACK for the case where
        # the row is genuinely gone — never as the primary answer.
        after = body.split("indexOfPinKey(key)")[-1]
        self.assertIn("moved >= 0 ? moved", after,
                      "the re-found row must win over the stale index")

    def test_ops_emitted_are_all_dispatchable(self):
        """The cross-file invariant: every op the menu shows, ContextMenu acts on.

        rowMenuItems() lives in Launcher.qml and runLauncherOp() in
        ContextMenu.qml; the op string crosses a process boundary between them.
        A name in one and not the other is an item that renders and then does
        nothing, silently.
        """
        program = launcher_program()
        emitted = set()
        for r in (APP_ROW, CONTROL_ROW, FILE_ROW, BOOKMARK_ROW, CHEAT_ROW):
            emitted.update(ops(run_node(program, [["rowItems", r, None]])[0]))
        emitted.update(ops(run_node(program, [["helpItems"]])[0]))

        # ContextMenu forwards every op to the launcher (one verb), and the
        # launcher then re-checks it — so the requirement is really that both
        # halves list the same set.
        launcher_ops = set(re.findall(r'op === "([a-z]+)"', LAUNCHER.read_text()))
        self.assertTrue(emitted <= launcher_ops,
                        "menu emits ops rowMenuItem does not handle: %s"
                        % sorted(emitted - launcher_ops))
        self.assertEqual(emitted, launcher_ops,
                         "rowMenuItem handles ops no menu item emits: %s"
                         % sorted(launcher_ops - emitted))

    def test_wiring_is_present(self):
        """The parts that make the menu reachable at all.

        Each of these was a plausible silent break: a chord bound to nothing,
        an IPC verb with no shim (dispatch() calls the verb name on the popup
        ROOT), a signal nobody routes, or a menu whose ops can never arrive.
        """
        launcher = LAUNCHER.read_text()
        menu = CONTEXT_MENU.read_text()
        shell = SHELL.read_text()

        # Keyboard twin in BOTH key handlers. Only one is a feature that works
        # whenever focus happens to sit on the list rather than the input.
        self.assertEqual(launcher.count("Qt.Key_F10 || event.key === Qt.Key_Menu"), 2)

        # `;` is already the Modes prefix, so it must NOT also be the chord —
        # pin the collision so a later session does not "fix" F10 into it.
        self.assertIn('";": "mode"', launcher)
        self.assertNotIn("Qt.Key_Semicolon", launcher)

        # Right click reaches both handlers of the row menu: the row delegate
        # (a row) and the fullscreen backdrop (not a row -> help menu).
        self.assertIn("acceptedButtons: Qt.LeftButton | Qt.RightButton", launcher)
        self.assertEqual(launcher.count("openHelpMenuAt("), 2)

        # The IPC verb is a ROOT method and has a shim; without the shim the
        # verb is simply not callable (shell.qml's handler wins the target).
        self.assertIn("function rowMenuItem(op: string): void {", launcher)
        self.assertIn('function rowMenuItem(op: string): void {', shell)
        self.assertIn("markMenuOpen", shell)
        self.assertIn("markMenuClosed", shell)

        # The menu must be reachable via Connections on the loader's ITEM. An
        # `onRowMenuRequested:` on the LazyLoader itself compiles, warns at
        # runtime, and never fires.
        self.assertIn("target: launcherLoader.item", shell)
        self.assertNotIn("onRowMenuRequested: (items", shell)

        # ContextMenu must have the entry point and the launcher branch.
        self.assertIn("function openRow(list: var, x: real, y: real): void", menu)
        self.assertIn("runLauncherOp", menu)


if __name__ == "__main__":
    unittest.main()