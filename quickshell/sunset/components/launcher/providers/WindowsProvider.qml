// WindowsProvider.qml — launcher "Windows" provider (kind "window", section "Windows").
//
// Sync fast path only: search() filters NiriService.windows by
// title/app_id substring (case-insensitive; empty q returns all), caps at
// `limit`, returns the rows directly and mirrors them into latestRows for
// interface uniformity. resultsChanged is never emitted (nothing completes
// asynchronously) — same convention as RunnerProvider.qml/WebProvider.qml.
// activate() focuses via NiriService.focusWindow(id) (verified to exist at
// services/NiriService.qml; fire-and-forget `niri msg action`).
//
// Contract:
//   function search(q: string, limit: int): var -> JS array of row objects
//   signal resultsChanged()
//   property var latestRows: []
//   function activate(row: var): void  (Launcher closes BEFORE calling
//     activate, so this only acts — it never closes anything.)
//
// Row shape: {kind, name, detail, icon, score, section, data}.
//   icon is null per contract (no window glyph is claimed from
//   quickshell/sunset/assets/icons/).

import QtQuick
import qs.services

QtObject {
    id: root

    signal resultsChanged()
    property var latestRows: []

    function search(q: string, limit: int): var {
        const needle = q ? q.trim().toLowerCase() : "";
        const cap = (limit > 0) ? limit : 10;
        const wins = NiriService.windows ?? [];
        let rows = [];
        for (let i = 0; i < wins.length; ++i) {
            const w = wins[i];
            const title = w.title ?? "";
            const appId = w.app_id ?? "";
            if (needle !== "") {
                const hay = (title + "\n" + appId).toLowerCase();
                if (hay.indexOf(needle) === -1)
                    continue;
            }
            // name/detail are REQUIRED non-empty: "window <id>" covers the
            // (rare) both-empty case; detail is non-empty by construction.
            const name = title !== "" ? title : (appId !== "" ? appId : "window " + w.id);
            rows.push({
                "kind": "window",
                "name": name,
                "detail": (appId !== "" ? appId : (title !== "" ? title : "window " + w.id)) + " — Enter to focus",
                "icon": null,
                "score": 100,
                "section": "Windows",
                "data": { "id": w.id }
            });
            if (rows.length >= cap)
                break;
        }
        latestRows = rows;
        return rows;
    }

    function activate(row: var): void {
        if (!row || !row.data || row.data.id === undefined || row.data.id === null)
            return;
        NiriService.focusWindow(row.data.id);
    }
}
