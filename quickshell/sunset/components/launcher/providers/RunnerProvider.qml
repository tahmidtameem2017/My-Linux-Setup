// RunnerProvider.qml — launcher "Runner" provider (kind "run", section "Runner").
//
// Sync fast path only: search() returns the single command row directly and
// mirrors it into latestRows for interface uniformity. resultsChanged is
// never emitted (nothing completes asynchronously).
//
// Contract:
//   function search(q: string, limit: int): var -> JS array of row objects
//   signal resultsChanged()
//   property var latestRows: []
//   function activate(row: var, terminal: bool): void  (Launcher closes
//     BEFORE calling activate, so this only acts — it never closes
//     anything.)
// NOTE on the optional second arg: `terminal` is optional — callers that
//   pass only (row) run the command via sh; the Launcher passes
//   terminal=true on Shift+Enter to run it inside a terminal (walker
//   runner parity: runterminal -> `alacritty -e sh -c <cmd>`).
//
// Row shape: {kind, name, detail, icon, score, section, data}.
//   icon is null: no terminal glyph exists in
//   quickshell/sunset/assets/icons/ (verified listing), so no basename is
//   claimed.

import QtQuick
import Quickshell

QtObject {
    id: root

    signal resultsChanged()
    property var latestRows: []

    function search(q: string, limit: int): var {
        if (!q || q.length < 1) {
            latestRows = [];
            return [];
        }
        const rows = [{
            "kind": "run",
            "name": q,
            "detail": "Run command — Enter to run, Shift+Enter in terminal",
            "icon": null,
            "score": 100,
            "section": "Runner",
            "data": { "cmd": q }
        }];
        latestRows = rows;
        return rows;
    }

    function activate(row: var, terminal: bool): void {
        if (!row || !row.data || !row.data.cmd)
            return;
        const cmd = row.data.cmd;
        if (terminal)
            Quickshell.execDetached(["alacritty", "-e", "sh", "-c", cmd]);
        else
            Quickshell.execDetached(["sh", "-c", cmd]);
    }
}
