// FilesProvider.qml — launcher "Files" provider (kind "file", section "Files").
//
// Fast fd + fzf backend (measured on ~21.5k entries in $HOME):
//   `fd` builds one full-list index FILE per filter scope under
//   ~/.cache/niri-setup/file-index/ (TTL 60s, refreshed in the background);
//   `fzf --scheme=path --filter` ranks it per search (~25ms native — the
//   previous in-QML-JS scorer took ~580ms for the same query, which is why
//   typing felt laggy). Keystrokes never spawn `fd` (only one cheap `fzf`
//   per 300ms typing pause, via Launcher's debounce). The first keystroke
//   for a scope returns [] pending and fills in via resultsChanged once
//   the index lands (~50-200ms).
// At most one `fd` build is ever in flight (a newer scope chains from
// finishBuild); `fzf` runs are killed on a new search and guarded by
// generation + query checks, so stale output can never surface. A 3s Timer
// kills hung runs (completions after a kill are dropped).
// Bonus: fzf extended-search syntax works in the pattern
// (`^exact-start`, `foo$`, `!exclude`, `a | b`) — free with --filter.
// Requirements (like qalc/cliphist for sibling providers): `fd` + `fzf`
// on PATH; without fzf every search returns [] (degraded, never errors).
//
// File-search bangs (parsed out of the query, never scored):
//   !type  — file-type filter. Known words map to extension sets:
//     !img (jpg jpeg png webp gif bmp svg heic heif avif tif tiff ico)
//     !doc (pdf doc docx odt txt md rtf epub)
//     !pdf (pdf)
//     !vid (mp4 mkv webm avi mov m4v)
//     !aud (mp3 flac wav ogg opus m4a aac)
//     !code (py js ts qml rs go c h cpp java sh kdl json toml yaml css html xml lua sql)
//     !arc (zip tar gz xz 7z rar bz2)
//     !dir (directories only, no extension filter)
//     Any other !word is treated as a literal extension
//     (e.g. `!rs`, `!toml` -> `fd --extension rs`).
//     Multiple !bangs combine (extensions OR together).
//   @scope — directory scope. Known words (all under $HOME unless noted):
//     @home (~/)  @docs (~/Documents)  @pics (~/Pictures)
//     @dl (~/Downloads)  @vid (~/Videos)  @mus (~/Music)
//     @cfg (~/.config)  @repo (~/niri-setup)
//     @wall (~/Pictures/Wallpapers)  @tmp (/tmp)
//     @/abs/path and @~/path are used verbatim (~/ expanded).
//     First @bang wins; unknown @word is ignored. Default scope is $HOME.
//   Examples:
//     `/ quarterly report`            names matching in $HOME
//     `/ quarterly !pdf`              pdfs matching "quarterly"
//     `/ quarterly !pdf @docs`        pdfs matching "quarterly" in ~/Documents
//     `/ !img @pics`                  all images in ~/Pictures (no text needed)
//     `/ notes !md @repo`             markdown matching "notes" in ~/niri-setup
//   Bare `/` (no text, no bangs) returns a synchronous cheatsheet listing
//   the bangs above (info rows, Enter does nothing).
//
// Contract:
//   function search(q: string, limit: int): var (sync fast path: [] pending
//     while loading/filtering, cheatsheet rows directly)
//   signal resultsChanged()
//   property var latestRows: []
//   function activate(row: var): void  (Launcher closes BEFORE calling
//     activate, so this only acts — it never closes anything.)
//   function reveal(row: var): void  (Ctrl+Enter path: opens the parent
//     directory via xdg-open; same close-before-act contract.)
//   function copyFile(row: var): void  (Ctrl+C path: copies the file's
//     contents to the clipboard for text/image types via
//     scripts/copy-file.sh, the path string for anything else.)
//   function openTerminal(row: var): void  (Ctrl+T path: opens the
//     default terminal in the file's own directory — the directory
//     itself for a directory row, its parent folder for a file row,
//     resolved in sh like reveal().)
// Drag-and-drop: Launcher.qml makes every row with data.path draggable
//   (Wayland text/uri-list + text/plain, Copy/Move/Link). This provider
//   only supplies data.path — no drag code lives here.
//
// Row shape: {kind, name, detail, icon, score, section, data}.
//   icon is null: no folder/file glyph exists in
//   quickshell/sunset/assets/icons/ (verified listing), so no basename is
//   claimed.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    signal resultsChanged()
    property var latestRows: []

    // Newest query seen + its row cap + filter label
    // (e.g. "!pdf @docs", surfaced in row details).
    property string lastQuery: ""
    property int runLimit: 10
    property string runLabel: ""
    // Repo-relative script path (setupHome pattern from
    // Launcher.qml / ContextMenu.qml): copy-file.sh backs the
    // Ctrl+C "copy this file" verb.
    readonly property string setupHome: Quickshell.env("NIRI_SETUP_HOME") ?? ((Quickshell.env("HOME") || "") + "/niri-setup")
    readonly property string copyFileScript: setupHome + "/scripts/copy-file.sh"
    // Terminal for the Ctrl+T verb. Mirrors Launcher.qml's own
    // `terminal` property (both are plain literals — QML Scopes
    // cannot see each other's properties).
    readonly property string terminal: "alacritty"
    // Index freshness: key -> epochMs. At most one fd build in flight
    // (buildKey, "" = idle); fzf runs carry a generation + query guard.
    property var indexMs: ({})
    property string buildKey: ""
    property int buildGen: 0
    property string fzfRunQuery: ""
    property int fzfGen: 0
    property int runGen: 0
    property var fzfPending: []
    readonly property int indexTtlMs: 60000
    readonly property string cacheBase: (Quickshell.env("XDG_CACHE_HOME") || ((Quickshell.env("HOME") || "") + "/.cache")) + "/niri-setup/file-index"

    // Bang tables (documented in this file's header + help/index.html's
    // file-search section; keep all three in sync when adding entries).
    readonly property var typeExtensions: ({
        "img": ["jpg", "jpeg", "png", "webp", "gif", "bmp", "svg", "heic", "heif", "avif", "tif", "tiff", "ico"],
        "pic": ["jpg", "jpeg", "png", "webp", "gif", "bmp", "svg", "heic", "heif", "avif", "tif", "tiff", "ico"],
        "image": ["jpg", "jpeg", "png", "webp", "gif", "bmp", "svg", "heic", "heif", "avif", "tif", "tiff", "ico"],
        "doc": ["pdf", "doc", "docx", "odt", "txt", "md", "rtf", "epub"],
        "docs": ["pdf", "doc", "docx", "odt", "txt", "md", "rtf", "epub"],
        "pdf": ["pdf"],
        "vid": ["mp4", "mkv", "webm", "avi", "mov", "m4v"],
        "video": ["mp4", "mkv", "webm", "avi", "mov", "m4v"],
        "videos": ["mp4", "mkv", "webm", "avi", "mov", "m4v"],
        "aud": ["mp3", "flac", "wav", "ogg", "opus", "m4a", "aac"],
        "audio": ["mp3", "flac", "wav", "ogg", "opus", "m4a", "aac"],
        "mus": ["mp3", "flac", "wav", "ogg", "opus", "m4a", "aac"],
        "music": ["mp3", "flac", "wav", "ogg", "opus", "m4a", "aac"],
        "code": ["py", "js", "ts", "jsx", "tsx", "qml", "rs", "go", "c", "h", "hpp", "cpp", "cc", "java", "kt", "sh", "bash", "kdl", "json", "toml", "yaml", "yml", "css", "scss", "html", "xml", "lua", "vim", "sql"],
        "src": ["py", "js", "ts", "jsx", "tsx", "qml", "rs", "go", "c", "h", "hpp", "cpp", "cc", "java", "kt", "sh", "bash", "kdl", "json", "toml", "yaml", "yml", "css", "scss", "html", "xml", "lua", "vim", "sql"],
        "arc": ["zip", "tar", "gz", "tgz", "xz", "7z", "rar", "bz2"],
        "zip": ["zip", "tar", "gz", "tgz", "xz", "7z", "rar", "bz2"]
    })
    readonly property var scopeDirs: ({
        "home": "",
        "docs": "Documents",
        "documents": "Documents",
        "pics": "Pictures",
        "img": "Pictures",
        "pictures": "Pictures",
        "dl": "Downloads",
        "downloads": "Downloads",
        "vid": "Videos",
        "videos": "Videos",
        "mus": "Music",
        "music": "Music",
        "cfg": ".config",
        "config": ".config",
        "repo": "niri-setup",
        "setup": "niri-setup",
        "niri": "niri-setup",
        "wall": "Pictures/Wallpapers",
        "wallpapers": "Pictures/Wallpapers",
        "tmp": "/tmp"
    })

    // Split q into {pattern, exts, dirOnly, scope, scopeName, typeNames}.
    // pattern = non-bang tokens joined with a space (fzf needle).
    // exts = deduped extension list; dirOnly when !dir/!folder present.
    // scope = absolute search dir ("" = default $HOME); scopeName = bang text.
    function parseQuery(q: string): var {
        const home = Quickshell.env("HOME") || "";
        const raw = (q ?? "").trim();
        let patternParts = [];
        let exts = [];
        let dirOnly = false;
        let scope = "";
        let scopeName = "";
        let typeNames = [];
        if (raw === "")
            return { "pattern": "", "exts": [], "dirOnly": false, "scope": "", "scopeName": "", "typeNames": [] };
        const toks = raw.split(/\s+/);
        for (let i = 0; i < toks.length; ++i) {
            const t = toks[i];
            if (t.length > 1 && t[0] === "!") {
                const w = t.slice(1).toLowerCase().replace(/^\./, "");
                if (w === "dir" || w === "dirs" || w === "folder" || w === "folders" || w === "directory" || w === "directories") {
                    dirOnly = true;
                    if (typeNames.indexOf("dir") === -1)
                        typeNames.push("dir");
                    continue;
                }
                if (w === "")
                    continue;
                const known = root.typeExtensions[w];
                if (known !== undefined) {
                    if (typeNames.indexOf(w) === -1)
                        typeNames.push(w);
                    for (let e = 0; e < known.length; ++e)
                        if (exts.indexOf(known[e]) === -1)
                            exts.push(known[e]);
                } else if (/^[a-z0-9]{1,10}$/.test(w)) {
                    // Generic extension bang: `/ notes !md`, `/ main !rs`.
                    if (typeNames.indexOf(w) === -1)
                        typeNames.push(w);
                    if (exts.indexOf(w) === -1)
                        exts.push(w);
                }
                continue;
            }
            if (t.length > 1 && t[0] === "@") {
                if (scope !== "")
                    continue; // first @bang wins
                const w = t.slice(1);
                const wl = w.toLowerCase();
                if (w[0] === "/") {
                    scope = w;
                    scopeName = w;
                } else if (w[0] === "~" && (w.length === 1 || w[1] === "/")) {
                    scope = home + w.slice(1);
                    scopeName = w;
                } else if (root.scopeDirs[wl] !== undefined) {
                    const mapped = root.scopeDirs[wl];
                    if (mapped === "")
                        scope = home;
                    else if (mapped[0] === "/")
                        scope = mapped;
                    else
                        scope = home !== "" ? home + "/" + mapped : mapped;
                    scopeName = w;
                }
                // Unknown @word is ignored (stays out of the pattern).
                continue;
            }
            patternParts.push(t);
        }
        return {
            "pattern": patternParts.join(" "),
            "exts": exts,
            "dirOnly": dirOnly,
            "scope": scope,
            "scopeName": scopeName,
            "typeNames": typeNames
        };
    }

    // Index cache key for a parsed query (scope + type flags only —
    // the pattern is filtered by fzf, never part of the key).
    function cacheKeyFor(p): string {
        const scope = p.scope !== "" ? p.scope : "$HOME";
        let flags = "fd";
        if (p.dirOnly)
            flags = "d";
        else if (p.exts.length > 0)
            flags = "f:" + p.exts.slice().sort().join(",");
        return scope + "|" + flags;
    }

    function hashKey(s: string): string {
        let h = 5381;
        for (let i = 0; i < s.length; ++i)
            h = ((h * 33) + s.charCodeAt(i)) >>> 0;
        return ("0000000" + h.toString(16)).slice(-8);
    }

    function indexFileFor(key: string): string {
        const safe = key.replace(/[^a-zA-Z0-9]+/g, "_").slice(0, 40);
        return root.cacheBase + "/" + safe + "-" + root.hashKey(key) + ".list";
    }

    function indexFresh(key: string): bool {
        const ms = indexMs[key];
        if (ms === undefined)
            return false;
        return (Date.now() - ms) <= indexTtlMs;
    }

    function makeRow(path: string, base: string, label: string): var {
        const suffix = label !== "" ? " [" + label + "]" : "";
        return {
            "kind": "file",
            "name": base,
            "detail": path + " — Enter to open · Ctrl+Enter reveal · Ctrl+C copy · Ctrl+T terminal · drag to drop elsewhere" + suffix,
            "icon": null,
            "score": 100,
            "section": "Files",
            "data": { "path": path }
        };
    }

    function cheatRows(): var {
        const rows = [
            { "kind": "file", "name": "Type to search files in $HOME", "detail": "e.g. `/ quarterly report` — Enter to open", "icon": null, "score": 100, "section": "Files", "data": {} },
            { "kind": "file", "name": "!pdf !img !doc !vid !aud !code !arc !dir", "detail": "Type filter — e.g. `/ quarterly !pdf` (any !ext works)", "icon": null, "score": 99, "section": "Files", "data": {} },
            { "kind": "file", "name": "@docs @pics @dl @vid @mus @cfg @repo @wall @tmp", "detail": "Scope — e.g. `/ quarterly !pdf @docs` (@/path works too)", "icon": null, "score": 98, "section": "Files", "data": {} }
        ];
        latestRows = rows;
        return rows;
    }

    function search(q: string, limit: int): var {
        const trimmed = (q ?? "").trim();
        const parsed = root.parseQuery(trimmed);
        const hasFilter = parsed.exts.length > 0 || parsed.dirOnly || parsed.scope !== "";
        if (trimmed === "" || (parsed.pattern === "" && !hasFilter)) {
            lastQuery = q ? q : "";
            return root.cheatRows();
        }
        lastQuery = q;
        runLimit = (limit > 0) ? limit : 10;
        let labelParts = [];
        for (let t = 0; t < parsed.typeNames.length; ++t)
            labelParts.push("!" + parsed.typeNames[t]);
        if (parsed.scopeName !== "")
            labelParts.push("@" + parsed.scopeName);
        runLabel = labelParts.join(" ");
        const key = root.cacheKeyFor(parsed);
        if (root.indexFresh(key)) {
            root.fzfPass(parsed.pattern, root.indexFileFor(key));
            return [];
        }
        // No fresh index: build it unless a build is running (finishBuild
        // chains the newest query's key when done).
        if (buildKey === "")
            root.startBuild(key, parsed);
        return [];
    }

    // fd full-list index build for key. NOTE: fd syntax is
    // `fd [PATTERN] [PATH]` — a lone positional is the PATTERN (a path
    // there errors out with zero results), so the match-all "." pattern
    // is passed explicitly before the scope dir.
    function startBuild(key: string, parsed): void {
        runGen++;
        buildGen = runGen;
        buildKey = key;
        killTimer.restart();
        let fdArgs = [];
        if (parsed.dirOnly) {
            fdArgs.push("-t", "d");
        } else if (parsed.exts.length > 0) {
            fdArgs.push("-t", "f");
            for (let e = 0; e < parsed.exts.length; ++e)
                fdArgs.push("--extension", parsed.exts[e]);
        } else {
            fdArgs.push("-t", "f", "-t", "d");
        }
        fdArgs.push(".");
        const home = Quickshell.env("HOME");
        if (parsed.scope !== "")
            fdArgs.push(parsed.scope);
        else if (home)
            fdArgs.push(home);
        // mkdir -p first (cache dir may not exist on fresh installs);
        // fd args ride as "$@" so paths with spaces/quotes stay intact.
        fdProc.exec(["bash", "-c", 'mkdir -p "$1" && fd "${@:3}" > "$2"', "bash", root.cacheBase, root.indexFileFor(key)].concat(fdArgs));
    }

    // One fzf filter pass over a fresh index file (~25ms native).
    // Empty pattern lists the head of the index. Runs are killed on a
    // new search; generation + query guards drop stale completions.
    function fzfPass(pattern: string, file: string): void {
        runGen++;
        fzfGen = runGen;
        fzfRunQuery = lastQuery;
        fzfPending = [];
        if (fzfProc.running)
            fzfProc.kill();
        killTimer.restart();
        const cap = runLimit > 0 ? runLimit : 10;
        if (pattern === "") {
            fzfProc.exec(["head", "-n", String(cap), file]);
        } else {
            fzfProc.exec(["bash", "-c", 'fzf --scheme=path --filter="$1" < "$2" | head -n "$3"', "bash", pattern, file, String(cap)]);
        }
    }

    function appendFzfLine(line: string): void {
        const t = line.trim();
        if (t === "")
            return;
        fzfPending.push(t);
    }

    function finishBuild(exitCode: int): void {
        killTimer.stop();
        const key = buildKey;
        const gen = buildGen;
        buildKey = "";
        // Killed run or fd failure: never cache, retry on next keystroke.
        if (gen !== runGen || exitCode !== 0)
            return;
        indexMs[key] = Date.now();
        // Answer the NEWEST query, then chain a build if it moved to
        // another (uncached) key meanwhile.
        const parsed = root.parseQuery((lastQuery ?? "").trim());
        const hasFilter = parsed.exts.length > 0 || parsed.dirOnly || parsed.scope !== "";
        if (parsed.pattern === "" && !hasFilter)
            return;
        const need = root.cacheKeyFor(parsed);
        if (need === key) {
            root.fzfPass(parsed.pattern, root.indexFileFor(key));
        } else if (!root.indexFresh(need)) {
            root.startBuild(need, parsed);
        }
    }

    function finishFzf(): void {
        killTimer.stop();
        const gen = fzfGen;
        fzfGen = 0;
        if (gen !== runGen) {
            fzfPending = [];
            return;
        }
        if (fzfRunQuery !== lastQuery) {
            fzfPending = [];
            return;
        }
        const label = runLabel;
        const cap = runLimit > 0 ? runLimit : 10;
        let rows = [];
        const n = Math.min(fzfPending.length, cap);
        for (let i = 0; i < n; ++i) {
            const p = fzfPending[i];
            const slash = p.lastIndexOf("/");
            let base = slash >= 0 ? p.slice(slash + 1) : p;
            if (base === "")
                base = p;
            rows.push(root.makeRow(p, base, label));
        }
        fzfPending = [];
        latestRows = rows;
        resultsChanged();
    }

    function activate(row: var): void {
        if (!row || !row.data || !row.data.path)
            return;
        Quickshell.execDetached(["xdg-open", row.data.path]);
    }

    // Reveal in the default file manager (Launcher Ctrl+Enter): xdg-open,
    // so the manager choice doesn't matter and no per-manager flags are
    // needed (selection not requested). Directories open directly, files
    // open their containing folder (dir-vs-file resolved in sh so QML
    // needs no stat).
    function reveal(row: var): void {
        if (!row || !row.data || !row.data.path)
            return;
        const p = String(row.data.path);
        if (p === "")
            return;
        Quickshell.execDetached(["sh", "-c", 'p="$1"; if [ -d "$p" ]; then xdg-open "$p"; else xdg-open "$(dirname "$p")"; fi', "sunset-reveal", p]);
    }

    // Ctrl+T on a file row: open the default terminal sitting in the
    // file's own directory — a directory row starts a shell there, a
    // file row starts it in the parent folder, which is why this
    // resolves dir-vs-file in sh exactly like reveal() above rather
    // than handing the path straight to `workingDirectory` (a file
    // path is not a cwd, and the terminal would fail to spawn).
    // The path rides as "$1" and the terminal as "$2", so nothing is
    // ever interpolated into the command line (spaces, quotes, $ in a
    // filename are fine). `exec` in place of a trailing `&` means no
    // shell survives to leak, and the terminal inherits the cwd from
    // the exec rather than from a passing parent.
    function openTerminal(row: var): void {
        if (!row || !row.data || !row.data.path)
            return;
        const p = String(row.data.path);
        if (p === "" || p[0] !== "/")
            return;
        Quickshell.execDetached(["sh", "-c", 'p="$1"; if [ -d "$p" ]; then d="$p"; else d="${p%/*}"; fi; [ -d "$d" ] && cd -- "$d" && exec "$2"', "sunset-terminal", p, root.terminal]);
    }

    // Ctrl+C on a file row (Launcher.copyCurrent): copy the file's
    // contents to the clipboard for text and image types, the path
    // string for directories and unknown types (scripts/copy-file.sh
    // owns the type table). Detached like reveal/activate: the script
    // outlives the menu and no result is expected back.
    function copyFile(row: var): void {
        if (!row || !row.data || !row.data.path)
            return;
        const p = String(row.data.path);
        if (p === "")
            return;
        Quickshell.execDetached(["bash", copyFileScript, p]);
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root.cacheBase]);
    }

    Process {
        id: fdProc
        onExited: (exitCode) => root.finishBuild(exitCode)
    }

    Process {
        id: fzfProc
        stdout: SplitParser {
            onRead: (data) => root.appendFzfLine(data)
        }
        onExited: root.finishFzf()
    }

    Timer {
        id: killTimer
        interval: 3000
        repeat: false
        onTriggered: {
            // Backstop: bump the generation so late completions are
            // dropped; the next keystroke restarts whatever is needed.
            root.runGen++;
            root.buildKey = "";
            if (fdProc.running)
                fdProc.kill();
            if (fzfProc.running)
                fzfProc.kill();
        }
    }
}
