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
// Deletion: highlight a bookmark and press Delete (see
//   Launcher.qml deleteCurrentBookmark — the row vanishes in
//   place, menu stays open). The provider side is removeAt(),
//   the same splice+save+re-search the key path calls.
//   `%delete <needle>` still lists one `Delete "<title>"` row
//   per match (data.action "delete", detail shows the url) for
//   deleting by name without highlighting; Enter removes it.
//   The open path (xdg-open) is untouched and neither delete
//   path ever opens a browser.
// Renaming (same shape): `%rename <needle> to <new name>` lists one
//   `Rename "<title>"` row per match (data.action "rename"); Enter
//   rewrites that bookmark's title and saves. The needle is everything
//   before the FIRST " to ", so a needle may not itself contain " to "
//   (a rare enough title that spelling it out is the documented cost).
//   With no " to " the rows still list the matches but Enter is a no-op
//   and the detail line says how to finish the command, so a half-typed
//   rename never destroys a title. Rename never touches the URL and
//   never opens a browser.
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
//   rename rows (rename mode, q is "rename" or starts with "rename "):
//     one per match, {name:'Rename "'+title+'"',
//     detail: '"<new name>"' when a " to " was given, else a
//     "type: %rename ... to <new name>" hint,
//     data:{action:"rename",index,name}}. No create row in rename
//     mode. Activate rewrites only the title; url, icon and folder
//     are preserved. A name of "" is a no-op.
// URL heuristic: leading http(s)://, leading www., or a bare
// domain-like token (no spaces, one dot, TLD >= 2 chars) counts as a
// URL; normalization keeps an http(s) scheme or prepends https://.
// Otherwise the entry stores {title:q, url:""}.
// Icons: rows carry bookmarkIcon ("bookmark.svg"), resolved
//   against Theme.iconDir by Launcher.iconSourceFor; an
//   imported bookmark may carry an absolute favicon path
//   instead, which wins. No network fetching, no colour deps.
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

    // Every bookmark row draws this instead of falling through to logo.svg.
    // "bookmark.svg" is a bare basename with a dot, so Launcher.iconSourceFor
    // resolves it against Theme.iconDir (the GENERATED, palette-substituted
    // copy) rather than treating it as a desktop-theme name. The set has no
    // off/on pair here -- a bookmark row is not a state -- so the normal icon
    // weight is correct and no `dim`-authored twin is needed.
    //
    // Lowercase on purpose: a QML property name may not begin with an upper
    // case letter, and the provider fails to load entirely when it does
    // (Type BookmarksProvider unavailable -> the whole launcher goes).
    readonly property string bookmarkIcon: "bookmark.svg"

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

    // Turn a raw URL into a name worth reading in a list.
    //
    // Browsers very often store a bookmark's TITLE as the URL itself — Brave
    // writes "https://chat.deepseek.com/" when you never renamed it — so the
    // launcher showed a bare link where a word should be. This is the fix, and
    // it runs on LOAD as well as on import, because the entries already in
    // bookmarks.json were written before this existed: sanitising only at
    // import time would leave the old ones ugly forever.
    //
    // THE PATH USUALLY KNOWS MORE THAN THE HOST. github.com/anthropics is
    // about anthropics, en.wikipedia.org/wiki/Niri_(compositor) is about niri,
    // not about wikipedia. So the first meaningful path segment wins and the
    // host is the fallback for the many sites that live at the root
    // (chat.deepseek.com/, youtube.com).
    //
    // "Meaningful" has to be defined, because most path segments are plumbing
    // — /search, /index.html, /en/, /item, an id, a uuid. Those are skipped;
    // with nothing left the host name is used. Returns "" when even that
    // fails, so the caller can fall back rather than print nothing.
    function titleFromUrl(u: string): string {
        let rest = (u ?? "").trim();
        if (rest === "")
            return "";
        rest = rest.replace(/^[a-z][a-z0-9+.-]*:\/\//i, "");
        rest = rest.replace(/^www\./i, "");
        rest = rest.split("#")[0].split("?")[0];
        rest = rest.split("@").pop();
        const segs = rest.split("/").filter(s => s !== "");
        // Strip the port from the HOST SEGMENT, not from the whole string:
        // "localhost:3000/app" ends in "app", so an anchored /:\d+$/ on the
        // whole string never fires and the name came out "localhost:3000".
        const host = segs.length > 0 ? segs[0].replace(/:\d+$/, "").toLowerCase() : "";
        if (host === "")
            return "";
        // A bare address is the name: 192.168.1.5/admin is a router page and
        // "admin" (the path) says nothing the address does not. Same for a
        // dotless intranet host, whose path is a route rather than a subject.
        if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.indexOf(".") === -1)
            return host;
        // Skip plumbing segments on the way to the real one (/blob/main/,
        // /wiki/, /r/). The FIRST meaningful segment is the subject; the LAST
        // is often a file or a qualifier (…/README.md).
        for (let i = 1; i < segs.length; ++i) {
            const name = cleanSegment(segs[i]);
            if (name !== "")
                return name;
        }
        const parts = host.split(".");
        if (parts.length <= 2)
            return parts[0] || host;
        const tld = parts[parts.length - 1];
        const second = parts[parts.length - 2];
        // Keep a country-code second level: example.co.uk -> example, not co.
        const keep = (tld.length === 2 && /^[a-z]{2}$/i.test(tld) &&
                      second.length <= 3 && /^[a-z]{2}$/i.test(second)) ? 3 : 2;
        return parts[parts.length - keep] || host;
    }

    // Path segments that describe the site's plumbing rather than its subject.
    // Routers emit these constantly; treating them as the name made every
    // Google link read "search" and every Hacker News link read "item".
    readonly property var noiseSegments: [
        "index", "default", "home", "main", "page", "pages", "search", "results",
        "find", "view", "list", "lists", "item", "items", "post", "posts", "entry",
        "browse", "category", "categories", "tag", "tags", "topic", "topics",
        "feed", "rss", "atom", "login", "signin", "sign-in", "signup", "sign-up",
        "register", "account", "accounts", "profile", "user", "users", "settings",
        "dashboard", "app", "apps", "application", "applications", "en", "us", "uk",
        "de", "fr", "es", "it", "nl", "jp", "cn", "ru", "br", "in", "www", "web",
        "site", "html", "htm", "php", "aspx", "jsp", "do", "cgi", "about",
        "help", "support", "contact", "privacy", "terms", "legal", "cookies",
        "download", "downloads", "docs", "documentation", "wiki", "new", "old",
        "cid", "id", "uid", "ref", "share", "amp"
    ];

    // One path segment into a name, or "" when it carries no signal.
    function cleanSegment(seg: string): string {
        let s = (seg ?? "").trim();
        if (s === "")
            return "";
        // A file extension says nothing about the subject: index.html, post.aspx.
        s = s.replace(/\.(html?|php|aspx?|jsp|cfm|do|md|txt|json)$/i, "");
        // A parenthetical is a gloss, not the name: "Niri_(compositor)" -> "niri".
        s = s.replace(/\(.*?\)/g, "");
        s = s.replace(/\.(?!$)/g, " ");      // remaining dots -> spaces
        s = s.replace(/[-_+]+/g, " ");        // slug separators -> spaces
        s = s.replace(/\s+/g, " ").trim();
        if (s === "")
            return "";
        const low = s.toLowerCase();
        if (low.length < 3 || root.noiseSegments.indexOf(low) !== -1)
            return "";
        // An all-digit segment, a long hex run, or a uuid is an identifier.
        if (/^\d+$/.test(s) || /^[0-9a-f]{8,}$/i.test(low) ||
            /^[0-9a-f]{8}-[0-9a-f]{4}-/i.test(low))
            return "";
        return s.length > 32 ? s.slice(0, 32).trim() : s;
    }

    // The display name for a stored entry. A title that is ONLY a URL is
    // replaced by the host; a real title the user typed is left alone, even if
    // it happens to mention a site.
    function displayTitle(title: string, url: string): string {
        const t = (title ?? "").trim();
        if (t !== "" && !isUrl(t))
            return t;
        const fromUrl = titleFromUrl(url);
        if (fromUrl !== "")
            return fromUrl;
        return t;
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
                // Sanitised on LOAD, not only at import: entries saved before
                // displayTitle existed still carry a bare URL as their title,
                // and they are the majority. Rewriting `title` here means the
                // list reads well immediately, and the next save (any add or
                // delete) persists the tidied name. `name` is left untouched so
                // this stays a display concern and not a data migration.
                const entry = { "title": root.displayTitle(title, url), "url": url };
                if (typeof b.icon === "string" && b.icon !== "")
                    entry["icon"] = b.icon;
                if (typeof b.folder === "string" && b.folder !== "")
                    entry["folder"] = b.folder;
                clean.push(entry);
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
            "detail": b.url !== "" ? (b.folder !== undefined && b.folder !== ""
                    ? "Enter to open in browser · " + b.folder
                    : "Enter to open in browser")
                : "No URL stored — Enter does nothing",
            // An imported bookmark carries an absolute path to a PNG lifted out
            // of the browser's own favicon cache (scripts/import-browser-bookmarks.py).
            // iconSourceFor sees the "/" and loads it as file://, so it beats the
            // bookmark.svg default. A hand-made bookmark has no icon key and
            // falls back to bookmarkIcon.
            "icon": b.icon !== undefined && b.icon !== "" ? b.icon : bookmarkIcon,
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
                        "icon": bookmarksProvIcon,
                        "score": 100,
                        "section": "Bookmarks",
                        "data": { "action": "delete", "index": i }
                    });
                }
            }
            latestRows = dout;
            return dout;
        }
        // Rename mode: "%rename <needle> to <new name>". Enter rewrites
        // the title and saves; the URL is untouched and no browser
        // opens. The needle is matched case-insensitively, but the
        // NEW NAME is taken from the RAW query — slicing it off the
        // lowercased needle would rewrite "GitHub Hub" as "github hub".
        // Split on the FIRST " to " so a new name may itself contain
        // " to ". No " to " yet → rows list the matches but
        // data.name is "", which activate treats as a no-op, and the
        // detail line teaches the rest of the command.
        if (needle === "rename" || needle.startsWith("rename ")) {
            const rraw = raw.length > 6 ? raw.slice(6).trim() : "";
            const sep = rraw.indexOf(" to ");
            const rneedle = (sep === -1 ? rraw : rraw.slice(0, sep)).trim().toLowerCase();
            const newname = (sep === -1 ? "" : rraw.slice(sep + 4)).trim();
            let rout = [];
            for (let i = 0; i < marks.length && rout.length < cap; ++i) {
                if (rneedle === "" || marks[i].title.toLowerCase().indexOf(rneedle) !== -1 || marks[i].url.toLowerCase().indexOf(rneedle) !== -1) {
                    const b = marks[i];
                    const nm = b.title !== "" ? b.title : b.url;
                    rout.push({
                        "kind": "bookmark",
                        "name": 'Rename "' + nm + '"',
                        "detail": newname !== ""
                            ? 'to "' + newname + '"'
                            : 'type: %rename "' + nm + '" to <new name>',
                        "icon": bookmarksProvIcon,
                        "score": 100,
                        "section": "Bookmarks",
                        "data": { "action": "rename", "index": i, "name": newname }
                    });
                }
            }
            latestRows = rout;
            return rout;
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
                "icon": bookmarksProvIcon,
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
            // No icon/folder on a hand-made bookmark: it has no browser cache
            // behind it, so it keeps bookmark.svg. Marks already carrying an
            // imported favicon are copied wholesale by concat, so saving after
            // an add or a delete does not strip their icons.
            marks = marks.concat([{ "title": t, "url": u }]);
        } else if (a === "delete") {
            root.removeAt(row.data.index);
            return;
        } else if (a === "rename") {
            const i = row.data.index;
            const nn = (typeof row.data.name === "string") ? row.data.name.trim() : "";
            // A no-op until the command is finished (no " to <name>"),
            // so a half-typed rename cannot blank a title.
            if (typeof i !== "number" || i < 0 || i >= marks.length || nn === "")
                return;
            // URL and any imported icon/folder are preserved: only
            // the title is rewritten. The old mark is read BEFORE
            // the replacement object is built, or the icon/folder
            // keys it carried would be dropped by the new literal.
            const old = marks[i];
            let next = marks.slice();
            next[i] = { "title": nn, "url": old.url };
            if (old.icon !== undefined)
                next[i]["icon"] = old.icon;
            if (old.folder !== undefined)
                next[i]["folder"] = old.folder;
            marks = next;
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
