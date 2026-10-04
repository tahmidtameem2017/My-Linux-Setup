// TodoProvider.qml — launcher "Todo" provider (kind "todo", section "Todo").
//
// Contract:
//   root is Scope; function search(q: string, limit: int): var -> JS
//     array of row objects; signal resultsChanged(); property var
//     latestRows: []; function activate(row: var): void (Launcher closes
//     BEFORE calling activate, so this only acts).
// State: ~/.local/share/niri-setup/todo.json (JSON array of
//   {text:string, done:bool}). NIRI_SETUP_HOME is deliberately NOT used:
//   this is user state, not repo content. Parent dir is created with
//   `mkdir -p` via mkdirProc (CalendarPopup.qml precedent).
// Async pattern: FileView loads at startup (watchChanges: true, so
//   external edits reload live); search() filters the in-memory list
//   synchronously (sync fast path: latestRows mirrored, resultsChanged NOT
//   emitted — Runner/Windows/WebProvider convention). resultsChanged IS
//   emitted when the async file load completes, so the integrator can
//   re-search. Writes go through stateFile.setText + in-memory update
//   (no write-echo guard: what we write is exactly the memory content,
//   so a reload round-trip is idempotent — WallpaperPicker precedent).
// Rows:
//   todo row: {name: (done?"✓ ":"○ ")+text, detail:"Enter to toggle done",
//     icon:null, score:100, section:"Todo", data:{action:"toggle",index}}
//     (index = position in the full in-memory list, stable under filters).
//   create row (q non-empty only): {name:'Add "'+q+'"', detail:"Create
//     todo", data:{action:"create",text:q}}.
//   clear row (only when q contains "clear" and at least one todo is
//     done): {name:"Clear completed (N)",
//     detail:"Enter to delete all done todos", data:{action:"clearDone"}}.
//   Extras are appended after matches; matches are sliced to leave room
//   so the total never exceeds `limit`.
// No colors/fonts, no UI.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    signal resultsChanged()
    property var latestRows: []

    // In-memory state + last query (for post-mutation refresh).
    property var todos: []
    property string lastQuery: ""
    property int lastLimit: 20
    property bool mkdirDone: false

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string stateDir: homeDir + "/.local/share/niri-setup"
    readonly property string statePath: stateDir + "/todo.json"

    function loadText(t: string): void {
        try {
            const v = JSON.parse(t);
            if (!Array.isArray(v))
                return;
            let clean = [];
            for (let i = 0; i < v.length; ++i) {
                if (v[i] && typeof v[i].text === "string" && v[i].text !== "")
                    clean.push({ "text": v[i].text, "done": !!v[i].done });
            }
            todos = clean;
        } catch (e) {
            console.warn("TodoProvider: ignoring corrupt todo.json");
        }
    }

    function save(): void {
        if (!mkdirDone && !mkdirProc.running)
            mkdirProc.running = true;
        stateFile.setText(JSON.stringify(todos));
    }

    function todoRow(i: int): var {
        const t = todos[i];
        return {
            "kind": "todo",
            "name": (t.done ? "✓ " : "○ ") + t.text,
            "detail": "Enter to toggle done",
            "icon": null,
            "score": 100,
            "section": "Todo",
            "data": { "action": "toggle", "index": i }
        };
    }

    function search(q: string, limit: int): var {
        const cap = (limit > 0) ? limit : 50;
        const raw = (q ? String(q) : "").trim();
        const needle = raw.toLowerCase();
        lastQuery = q ? String(q) : "";
        lastLimit = cap;
        let doneCount = 0;
        for (let d = 0; d < todos.length; ++d) {
            if (todos[d].done)
                doneCount++;
        }
        const wantCreate = raw !== "";
        const wantClear = needle.indexOf("clear") !== -1 && doneCount > 0;
        let budget = cap;
        if (wantCreate)
            budget--;
        if (wantClear)
            budget--;
        if (budget < 0)
            budget = 0;
        let out = [];
        for (let i = 0; i < todos.length && out.length < budget; ++i) {
            if (needle === "" || todos[i].text.toLowerCase().indexOf(needle) !== -1)
                out.push(todoRow(i));
        }
        if (wantClear) {
            out.push({
                "kind": "todo",
                "name": "Clear completed (" + doneCount + ")",
                "detail": "Enter to delete all done todos",
                "icon": null,
                "score": 100,
                "section": "Todo",
                "data": { "action": "clearDone" }
            });
        }
        if (wantCreate) {
            out.push({
                "kind": "todo",
                "name": 'Add "' + raw + '"',
                "detail": "Create todo",
                "icon": null,
                "score": 100,
                "section": "Todo",
                "data": { "action": "create", "text": raw }
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
            todos = todos.concat([{ "text": t, "done": false }]);
        } else if (a === "toggle") {
            const i = row.data.index;
            if (typeof i !== "number" || i < 0 || i >= todos.length)
                return;
            let next = todos.slice();
            next[i] = { "text": next[i].text, "done": !next[i].done };
            todos = next;
        } else if (a === "clearDone") {
            todos = todos.filter(function (t) { return !t.done; });
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
            // Load once the directory exists (setText needs it too —
            // CalendarPopup.qml precedent).
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
        onLoadFailed: root.todos = []
        onFileChanged: reload()
    }

    Component.onCompleted: mkdirProc.running = true
}
