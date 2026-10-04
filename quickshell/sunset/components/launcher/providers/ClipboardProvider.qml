// ClipboardProvider.qml — launcher "Clipboard" provider (kind "clip", section "Clipboard").
//
// Async cliphist backend (Process + SplitParser precedent from
// components/ClipboardPopup.qml, whose line parsing is mirrored here):
//   `cliphist list` lines are `<id>\t<preview>`; numeric-id validated,
//   image entries detected via "binary data" in the preview (same test as
//   ClipboardPopup.qml) and badged with a "[IMG] " name prefix (the popup
//   renders [IMG] as a separate badge; rows only carry name/detail strings).
//   Only the first 30 entries are considered, filtered by case-insensitive
//   substring; names truncate the preview to 80 chars ("(empty)" fallback
//   keeps name non-empty as required).
// The parsed list is cached for 5s to avoid re-running cliphist per
// keystroke: search() serves fresh cache synchronously (mirrored into
// latestRows, returned directly) and only spawns the process on a stale or
// missing cache, returning [] pending. On process exit the cache refreshes
// and rows are recomputed for the newest query, written to latestRows with
// resultsChanged() emitted. The payload is query-independent, so completion
// always derives rows from the current lastQuery — no stale rows can be
// published by construction (this subsumes the lastQuery/runQuery drop
// guard; runQuery is still tracked for interface uniformity).
// A 3s Timer kills a hung cliphist run (FilesProvider.qml parity).
// activate() restores via direct `cliphist decode <id> | wl-copy`
// (numeric-id validated, shell-safe) — the contract-preferred path rather
// than ClipboardPopup.qml's clipboard-pick.py pipeline, so image entries
// restore raw bytes without the clip-path-watcher sidecar pairing.
//
// Contract:
//   function search(q: string, limit: int): var (sync fast path: cache hit
//     rows, cache miss: [] pending)
//   signal resultsChanged()
//   property var latestRows: []
//   function activate(row: var): void  (Launcher closes BEFORE calling
//     activate, so this only acts — it never closes anything.)
//
// Row shape: {kind, name, detail, icon, score, section, data}.
//   icon "clipboard.svg" is a verified basename in
//   quickshell/sunset/assets/icons/ (same pick as the Launcher.qml
//   Clipboard control row).

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    signal resultsChanged()
    property var latestRows: []

    // Parsed cache: [{cid, preview, isImg}] (newest first) + fetch time.
    property var cache: []
    property double cacheMs: 0
    // Newest query seen; in-flight run's query for uniformity with the
    // sibling async provider (FilesProvider.qml).
    property string lastQuery: ""
    property string runQuery: ""
    property int runLimit: 10
    property var pending: []

    function search(q: string, limit: int): var {
        lastQuery = q ? q : "";
        runLimit = (limit > 0) ? limit : 10;
        const now = Date.now();
        if (!listProc.running && cacheMs !== 0 && (now - cacheMs) < 5000) {
            const rows = root.filterRows(lastQuery, runLimit);
            latestRows = rows;
            return rows;
        }
        runQuery = lastQuery;
        pending = [];
        if (listProc.running)
            listProc.kill();
        killTimer.restart();
        listProc.exec(["cliphist", "list"]);
        return [];
    }

    // ClipboardPopup.qml appendLine parity: tab split, numeric id, rest is
    // the preview; "binary data" marks image entries.
    function appendLine(line: string): void {
        if (line === "")
            return;
        const tab = line.indexOf("\t");
        if (tab === -1)
            return;
        const cid = line.slice(0, tab).trim();
        if (!/^[0-9]+$/.test(cid))
            return;
        const preview = line.slice(tab + 1);
        pending.push({
            "cid": cid,
            "preview": preview,
            "isImg": preview.indexOf("binary data") !== -1
        });
    }

    function filterRows(q: string, cap: int): var {
        const needle = q ? q.trim().toLowerCase() : "";
        const n = (cap > 0) ? cap : 10;
        let rows = [];
        const total = Math.min(cache.length, 30);
        for (let i = 0; i < total; ++i) {
            const e = cache[i];
            if (needle !== "" && e.preview.toLowerCase().indexOf(needle) === -1)
                continue;
            const pv = e.preview.slice(0, 80);
            rows.push({
                "kind": "clip",
                "name": (e.isImg ? "[IMG] " : "") + (pv !== "" ? pv : "(empty)"),
                "detail": "clipboard — Enter to copy",
                "icon": "clipboard.svg",
                "score": 100,
                "section": "Clipboard",
                "data": { "id": e.cid }
            });
            if (rows.length >= n)
                break;
        }
        return rows;
    }

    function finishRun(): void {
        killTimer.stop();
        cache = pending;
        pending = [];
        cacheMs = Date.now();
        // Query-independent payload: recompute for the newest query, so
        // published rows always match lastQuery (no stale mismatch possible).
        const rows = root.filterRows(lastQuery, runLimit);
        latestRows = rows;
        resultsChanged();
    }

    function activate(row: var): void {
        if (!row || !row.data || !/^[0-9]+$/.test(String(row.data.id)))
            return;
        const cid = String(row.data.id);
        restoreProc.exec(["sh", "-c", "cliphist decode " + cid + " | wl-copy"]);
    }

    Process {
        id: listProc
        stdout: SplitParser {
            onRead: (data) => root.appendLine(data)
        }
        onExited: root.finishRun()
    }

    Process {
        id: restoreProc
    }

    Timer {
        id: killTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (listProc.running)
                listProc.kill();
        }
    }
}
