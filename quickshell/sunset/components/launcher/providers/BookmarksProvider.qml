// BookmarksProvider.qml — launcher "Bookmarks" provider
// (kind "bookmark", section "Bookmarks").
//
// Add/open/delete walkthrough (keyboard-first):
//   type URL → Enter to bookmark → later type part of title → Enter opens
//   in browser. Or bookmark straight from web mode:
//   `@ <site> -bookmark` + Enter saves (Launcher-side fast path, same
//   create-row shape; non-URL input stores the DuckDuckGo search URL).
//   Concretely: a bare launcher query that looks like a URL
//   gets an appended `Bookmark "<url>"` create-row (Launcher-side, cap 1,
//   via isUrl/normUrl below); Enter on it stores {title:url, url}. Later,
//   typing part of the title surfaces scored open rows (Launcher bare
//   interleave: bestScore on title+url, merged by score like media rows);
//   Enter on one xdg-opens the url. `%` mode keeps the same create-row
//   for any non-empty query, so `%<url>` + Enter also bookmarks.
// Deletion (minimal, Enter-driven): `%delete <needle>` lists one
//   `Delete "<title>"` row per matching bookmark (data.action "delete",
//   detail shows the url); Enter removes it + saves. The open path
//   (xdg-open) is untouched and the delete path never opens a browser.
//   NOTE: Shift+Delete was deliberately NOT used — Launcher's Keys/nav
//   blocks are frozen (see Launcher.qml header), so deletion is a row,
//   not a keybinding.
// Contract:
//   root is Scope; function search(q: string, limit: int): var -> JS
//     array of row objects; signal resultsChanged(); property var
//     latestRows: []; function activate(row: var): void (Launcher closes
//     BEFORE calling activate, so this only acts);
//     function removeAt(i: int): bool (the delete path: splice + save +
//     re-search; activate's "delete" branch delegates to it).
//   Launcher bare interleave reads marks/markRow/isUrl/normUrl directly
//   (no search call, so no create-row leaks into bare results); `%` mode
//   goes through search (rest = query minus the "%").
// State: ~/.local/share/niri-setup/bookmarks.json (JSON array of
//   {title:string, url:string}). Same state pattern as TodoProvider.qml:
//   FileView (watchChanges, external edits reload live), sync search over
//   the in-memory list (no resultsChanged on the sync path — sibling
//   convention; emitted when the async file load completes), writes via
//   setText + in-memory update (idempotent round-trip, no echo guard).
//   Parent dir via `mkdir -p` Process (CalendarPopup.qml precedent).
// Rows:
//   existing: {name: title (falls back to url), detail: url non-empty ?
//     "Enter to open in browser" : "No URL stored — Enter does nothing",
//     icon:null, score:100, section:"Bookmarks",
//     data:{action:"open",index}}.
//     Enter opens url via xdg-open; rows whose url is "" are no-ops on
//     activate (documented here and in detail). Bare-query interleave and
//     the empty-query section skip url-less rows (bare Enter must act);
//     they stay reachable (and deletable) in `%` mode.
//   create row (q non-empty, non-delete mode only): {name:'Bookmark "'+q+'"',
//     detail: URL-detected ? "Enter to bookmark this URL"
//                          : "Enter to bookmark (stores title only, no URL)",
//     data:{action:"create",text:q,url:normalized-or-""}}.
//     (text/url keys are additive plain-JSON alongside the contracted
//     action key; activate needs the payload.)
//   delete rows (delete mode only, i.e. q is "delete" or starts with
//     "delete "): one per matching bookmark, {name:'Delete "'+title+'"',
//     detail: url (or "No URL stored"), data:{action:"delete",index}}.
//     No create row in delete mode.
// URL heuristic: leading http(s)://, leading www., or a bare
// domain-like token (no spaces, one dot, TLD >= 2 chars) counts as a
// URL; normalization keeps an http(s) scheme or prepends https://.
// Otherwise the entry stores {title:q, url:""}.
// Icons: rows use icon:null → Launcher iconSourceFor falls back to
//   logo.svg by construction (no favicon fetching, no network deps).
// No colors/fonts, no UI.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    signal resultsChanged()
    property var latestRows: []

    property var marks: []
    property string lastQuery: ""
    property int lastLimit: 20
    property bool mkdirDone: false

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string stateDir: homeDir + "/.local/share/niri-setup"
    readonly property string statePath: stateDir + "/bookmarks.json"

    function isUrl(s: string): bool {
        const t = (s ?? "").trim();
        if (/^(https?:\/\/)/i.test(t))
            return true;
        if (/^www\.[^\s]+\.[^\s]+/i.test(t))
            return true;
        return /^[^\s]+\.[a-z]{2,}(\/\S*)?$/i.test(t);
    }

    function normUrl(s: string): string {
        const t = (s ?? "").trim();
        if (/^(https?:\/\/)/i.test(t))
            return t;
        return "https://" + t;
    }

    function loadText(t: string): void {
        try {
            const v = JSON.parse(t);
            if (!Array.isArray(v))
                return;
            let clean = [];
            for (let i = 0; i < v.length; ++i) {
                const b = v[i];
                if (!b || (typeof b.title !== "string" && typeof b.url !== "string"))
                    continue;
                const title = typeof b.title === "string" ? b.title : "";
                const url = typeof b.url === "string" ? b.url : "";
                if (title === "" && url === "")
                    continue;
                clean.push({ "title": title, "url": url });
            }
            marks = clean;
        } catch (e) {
            console.warn("BookmarksProvider: ignoring corrupt bookmarks.json");
        }
    }

    function save(): void {
        if (!mkdirDone && !mkdirProc.running)
            mkdirProc.running = true;
        stateFile.setText(JSON.stringify(marks));
    }

    function markRow(i: int): var {
        const b = marks[i];
        const nm = b.title !== "" ? b.title : b.url;
        return {
            "kind": "bookmark",
            "name": nm,
            "detail": b.url !== "" ? "Enter to open in browser" : "No URL stored — Enter does nothing",
            "icon": null,
            "score": 100,
            "section": "Bookmarks",
            "data": { "action": "open", "index": i }
        };
    }

    function removeAt(i: int): bool {
        if (typeof i !== "number" || i < 0 || i >= marks.length)
            return false;
        let next = marks.slice();
        next.splice(i, 1);
        marks = next;
        save();
        search(lastQuery, lastLimit);
        return true;
    }

    function search(q: string, limit: int): var {
        const cap = (limit > 0) ? limit : 50;
        const raw = (q ? String(q) : "").trim();
        const needle = raw.toLowerCase();
        lastQuery = q ? String(q) : "";
        lastLimit = cap;
        // Delete mode: "%delete <needle>" (Launcher strips the "%").
        // Enter on a Delete row removes that bookmark + saves; no browser
        // opens on this path. No create row here.
        if (needle === "delete" || needle.startsWith("delete ")) {
            const dneedle = needle.length > 6 ? needle.slice(6).trim() : "";
            let dout = [];
            for (let i = 0; i < marks.length && dout.length < cap; ++i) {
                if (dneedle === "" || marks[i].title.toLowerCase().indexOf(dneedle) !== -1 || marks[i].url.toLowerCase().indexOf(dneedle) !== -1) {
                    const b = marks[i];
                    const nm = b.title !== "" ? b.title : b.url;
                    dout.push({
                        "kind": "bookmark",
                        "name": 'Delete "' + nm + '"',
                        "detail": b.url !== "" ? b.url : "No URL stored",
                        "icon": null,
                        "score": 100,
                        "section": "Bookmarks",
                        "data": { "action": "delete", "index": i }
                    });
                }
            }
            latestRows = dout;
            return dout;
        }
        const wantCreate = raw !== "";
        let budget = wantCreate ? cap - 1 : cap;
        if (budget < 0)
            budget = 0;
        let out = [];
        for (let i = 0; i < marks.length && out.length < budget; ++i) {
            if (needle === "")
                out.push(markRow(i));
            else if (marks[i].title.toLowerCase().indexOf(needle) !== -1 || marks[i].url.toLowerCase().indexOf(needle) !== -1)
                out.push(markRow(i));
        }
        if (wantCreate) {
            const url = isUrl(raw) ? normUrl(raw) : "";
            out.push({
                "kind": "bookmark",
                "name": 'Bookmark "' + raw + '"',
                "detail": url !== "" ? "Enter to bookmark this URL" : "Enter to bookmark (stores title only, no URL)",
                "icon": null,
                "score": 100,
                "section": "Bookmarks",
                "data": { "action": "create", "text": raw, "url": url }
            });
        }
        latestRows = out;
        return out;
    }

    function activate(row: var): void {
        if (!row || !row.data || !row.data.action)
            return;
        const a = row.data.action;
        if (a === "create") {
            const t = (typeof row.data.text === "string") ? row.data.text.trim() : "";
            if (t === "")
                return;
            const u = (typeof row.data.url === "string") ? row.data.url : "";
            marks = marks.concat([{ "title": t, "url": u }]);
        } else if (a === "delete") {
            root.removeAt(row.data.index);
            return;
        } else if (a === "open") {
            const i = row.data.index;
            if (typeof i !== "number" || i < 0 || i >= marks.length)
                return;
            // Empty-url rows are no-ops (see header + row detail).
            if (marks[i].url === "")
                return;
            Quickshell.execDetached(["xdg-open", marks[i].url]);
            return;
        } else {
            return;
        }
        save();
        search(lastQuery, lastLimit);
    }

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.stateDir]
        running: false
        onExited: {
            root.mkdirDone = true;
            stateFile.reload();
        }
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        onLoaded: {
            root.loadText(text());
            root.resultsChanged();
        }
        // First run (or deleted file): start empty; the file is created
        // lazily on the first write.
        onLoadFailed: root.marks = []
        onFileChanged: reload()
    }

    Component.onCompleted: mkdirProc.running = true
}
