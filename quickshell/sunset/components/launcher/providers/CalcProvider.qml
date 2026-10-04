// CalcProvider.qml — launcher "Calculator" provider (kind "calc", section "Calculator").
//
// Async qalc backend (Process + StdioCollector precedent from
// services/WallpaperService.qml):
//   search() returns [] immediately (pending) and starts `qalc -t <expr>`
//   when q looks like a math expression (digits/operators/parens/functions/
//   spaces only, at least one digit and one operator, max 200 chars).
//   Non-expressions clear latestRows and return [] with no process spawned.
//   On process exit the trimmed result (truncated to 80 chars) becomes the
//   single row, written to latestRows with resultsChanged() emitted.
//   Stale completions are dropped by comparing the in-flight runQuery
//   against lastQuery (newest search wins); when a newer expression arrived
//   while a run was in flight, the finished run is dropped and a new run
//   for lastExpr is chained (debounce: in-flight runs are never killed,
//   per contract — they finish and their result is dropped on mismatch).
// /usr/bin/qalc verified present, so no bc fallback is wired.
// activate() copies row.data.result via `wl-copy` (verified present),
// fed through `printf | wl-copy` with single-quote escaping (same
// printf-pipe technique as ClipboardPopup.qml's restore path).
//
// Contract:
//   function search(q: string, limit: int): var (sync fast path: [] pending)
//   signal resultsChanged()
//   property var latestRows: []
//   function activate(row: var): void  (Launcher closes BEFORE calling
//     activate, so this only acts — it never closes anything.)
//
// Row shape: {kind, name, detail, icon, score, section, data}.
//   icon is null: no calculator glyph exists in
//   quickshell/sunset/assets/icons/ (verified listing), so no basename is
//   claimed.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    signal resultsChanged()
    property var latestRows: []

    // Newest query seen; in-flight run's query/expr for stale-drop guard.
    property string lastQuery: ""
    property string lastExpr: ""
    property string runQuery: ""
    property string runExpr: ""
    property string outText: ""

    // True when s looks like a math expression: allowed charset only plus
    // at least one digit and one operator.
    function isExpression(s: string): bool {
        const t = (s ?? "").trim();
        if (t === "" || t.length > 200)
            return false;
        if (!/^[0-9a-zA-Z+\-*/%^!.,()\s]+$/.test(t))
            return false;
        if (!/[0-9]/.test(t))
            return false;
        if (!/[+\-*/%^!]/.test(t))
            return false;
        return true;
    }

    function search(q: string, limit: int): var {
        lastQuery = q ? q : "";
        const expr = lastQuery.trim();
        if (!root.isExpression(expr)) {
            lastExpr = "";
            latestRows = [];
            return [];
        }
        lastExpr = expr;
        // Debounce: a run is already in flight — let it finish; finishRun
        // drops its result on mismatch and chains a run for lastExpr.
        if (calcProc.running)
            return [];
        runQuery = lastQuery;
        runExpr = expr;
        outText = "";
        calcProc.exec(["qalc", "-t", expr]);
        return [];
    }

    function finishRun(exitCode: int): void {
        // Stale guard: a newer search superseded this run — drop its output.
        if (runQuery !== lastQuery) {
            // Chain: the newest query is still an expression — run it now.
            if (lastExpr !== "" && lastExpr !== runExpr) {
                runQuery = lastQuery;
                runExpr = lastExpr;
                outText = "";
                calcProc.exec(["qalc", "-t", lastExpr]);
            }
            return;
        }
        let out = (outText ?? "").trim();
        if (out.indexOf("\n") !== -1)
            out = out.split("\n")[0].trim();
        if (out.length > 80)
            out = out.slice(0, 80);
        if (exitCode !== 0 || out === "") {
            latestRows = [];
            resultsChanged();
            return;
        }
        latestRows = [{
            "kind": "calc",
            "name": out,
            "detail": runExpr + " = … — Enter to copy",
            "icon": null,
            "score": 100,
            "section": "Calculator",
            "data": { "expr": runExpr, "result": out }
        }];
        resultsChanged();
    }

    function activate(row: var): void {
        if (!row || !row.data || !row.data.result)
            return;
        // Shell-safe single-quote escaping for arbitrary result text.
        const safe = String(row.data.result).replace(/'/g, "'\\''");
        Quickshell.execDetached(["sh", "-c", "printf '%s' '" + safe + "' | wl-copy"]);
    }

    Process {
        id: calcProc
        stdout: StdioCollector {
            onStreamFinished: root.outText = text
        }
        onExited: (exitCode) => root.finishRun(exitCode)
    }
}
