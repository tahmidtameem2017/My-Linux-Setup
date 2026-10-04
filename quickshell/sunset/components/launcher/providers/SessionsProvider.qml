// SessionsProvider.qml — launcher "Sessions" provider (kind "session",
// section "Sessions"): one row per saved workspace session, Enter applies
// it via scripts/session.sh (profiles in ~/.local/share/niri-setup/
// sessions/*.json, edited in the Sessions popup or `session.sh edit`).
//
// Contract (Launcher.qml integrator):
//   root is QtObject; function search(q: string, limit: int): var -> JS
//     array of row objects; signal resultsChanged(); property var
//     latestRows: []; function activate(row: var): void (Launcher closes
//     BEFORE calling activate, so this only acts).
// Rows: {kind:"session", name, detail, icon:null, score, section:
//   "Sessions", data:{session}}.
// Listing is async (session.sh list proc); search() filters the last-known
// names synchronously and kicks a background refresh, resultsChanged ->
// onProvResults -> rebuild fills rows in (emitted only when the name list
// actually changes, so steady-state completions never rebuild). Launcher
// must call search() via cachedProvSearch (same-query guard), never bare
// per-rebuild, or the refresh completion re-triggers search forever.
// activate() runs
// `session.sh apply <name>` detached (overlapping runs are the user's
// explicit choice, same as RunnerProvider spot actions).
// No colors/fonts, no UI.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    signal resultsChanged()
    property var latestRows: []
    property var names: []
    property string lastQuery: ""

    readonly property string script: "/home/me/niri-setup/scripts/session.sh"

    function titleCase(s: string): string {
        if (!s)
            return s;
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    function refresh(): void {
        if (!listProc.running)
            listProc.running = true;
    }

    Process {
        id: listProc
        command: [root.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const lines = String(text).split("\n");
                for (let i = 0; i < lines.length; ++i) {
                    const n = lines[i].trim();
                    if (n !== "")
                        out.push(n);
                }
                // Emit only on actual change: an unconditional emit lets a
                // per-rebuild search() (pre-cachedProvSearch callers) reform
                // a respawn -> resultsChanged -> rebuild loop that pins the
                // launcher selection to row 0; identical names rebuild
                // nothing anyway.
                if (out.join("\n") !== root.names.join("\n")) {
                    root.names = out;
                    root.resultsChanged();
                }
            }
        }
    }

    function makeRow(name: string): var {
        return {
            "kind": "session",
            "name": root.titleCase(name) + " session",
            "detail": "Open the '" + name + "' workspace session (Enter)",
            "icon": null,
            "score": 100,
            "section": "Sessions",
            "data": { "session": name }
        };
    }

    function search(q: string, limit: int): var {
        root.lastQuery = (q === undefined || q === null) ? "" : String(q);
        const cap = (limit > 0) ? limit : 50;
        root.refresh();
        const needle = root.lastQuery.trim().toLowerCase();
        let out = [];
        for (let i = 0; i < names.length; ++i) {
            const n = names[i];
            if (needle !== "" && n.toLowerCase().indexOf(needle) === -1 && (root.titleCase(n) + " session").toLowerCase().indexOf(needle) === -1)
                continue;
            out.push(makeRow(n));
            if (out.length >= cap)
                break;
        }
        latestRows = out;
        return out;
    }

    function activate(row: var): void {
        if (!row || !row.data || !row.data.session)
            return;
        Quickshell.execDetached([root.script, "apply", String(row.data.session)]);
    }
}
