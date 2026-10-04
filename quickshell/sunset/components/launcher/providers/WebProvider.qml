// WebProvider.qml — launcher "Web" provider (kind "web", section "Web").
//
// Site bangs: the first token picks the site, the rest is the search text.
//   @dd <q> .... DuckDuckGo   @g <q> ..... Google
//   @yt <q> .... YouTube      @wiki <q> ... Wikipedia
//   @gh <q> .... GitHub       @so <q> ..... Stack Overflow
//   @r <q> ..... Reddit       @maps <q> ... Google Maps
//   @miruro/@anime <q> ....... Miruro (anime, popularity-sorted)
// A bang alone (no text) opens the site's homepage; unknown first tokens
// fall back to the old behavior on the whole query (URL opens directly,
// anything else searches DuckDuckGo), so `@ example.com` and
// `@ some question` keep working. Bare `@` lists every site (homepage
// rows) as a cheatsheet.
// Case-insensitive bangs; multi-word site names work (`@duckduckgo`,
// `@youtube`, `@wikipedia`, `@stackoverflow`, `@reddit`).
//
// Sync fast path only: no async work, so search() returns rows directly
// and mirrors them into latestRows for interface uniformity. resultsChanged is
// never emitted (nothing completes asynchronously).
//
// Contract:
//   function search(q: string, limit: int): var -> JS array of row objects
//   signal resultsChanged()
//   property var latestRows: []
//   function activate(row: var): void  (Launcher closes BEFORE calling
//     activate, so this only acts — it never closes anything.)
//
// Row shape: {kind, name, detail, icon, score, section, data}.
//   icon "wifi.svg" is a verified basename in quickshell/sunset/assets/icons/.

import QtQuick
import Quickshell

QtObject {
    id: root

    signal resultsChanged()
    property var latestRows: []

    // Site table (documented in this file's header + help/index.html's
    // search section; keep all three in sync when adding entries).
    // url() builds the action URL:
    // empty terms -> homepage, otherwise the site's search URL.
    readonly property var sites: [
        { "name": "DuckDuckGo", "bangs": ["dd", "duck", "duckduckgo"], "home": "https://duckduckgo.com", "search": "https://duckduckgo.com/?q=" },
        { "name": "Google", "bangs": ["g", "google"], "home": "https://www.google.com", "search": "https://www.google.com/search?q=" },
        { "name": "YouTube", "bangs": ["yt", "youtube"], "home": "https://www.youtube.com", "search": "https://www.youtube.com/results?search_query=" },
        { "name": "Wikipedia", "bangs": ["w", "wiki", "wikipedia"], "home": "https://en.wikipedia.org", "search": "https://en.wikipedia.org/wiki/Special:Search?search=" },
        { "name": "GitHub", "bangs": ["gh", "github"], "home": "https://github.com", "search": "https://github.com/search?q=" },
        { "name": "Stack Overflow", "bangs": ["so", "stackoverflow", "stack"], "home": "https://stackoverflow.com", "search": "https://stackoverflow.com/search?q=" },
        { "name": "Reddit", "bangs": ["r", "reddit"], "home": "https://www.reddit.com", "search": "https://www.reddit.com/search/?q=" },
        { "name": "Google Maps", "bangs": ["maps", "gmaps"], "home": "https://www.google.com/maps", "search": "https://www.google.com/maps/search/" },
        { "name": "Miruro", "bangs": ["miruro", "anime"], "home": "https://www.miruro.to", "search": "https://www.miruro.to/search?query=" },
    ]

    // Miruro needs trailing params after the query (type + sort), unlike
    // the prefix-search sites above: override URL building for it.
    function siteUrl(site, terms: string): string {
        if (site.name === "Miruro")
            return site.search + encodeURIComponent(terms) + "&type=ANIME&sort=POPULARITY_DESC";
        return site.search + encodeURIComponent(terms);
    }

    function findSite(bang: string): var {
        const b = (bang ?? "").toLowerCase();
        if (b === "")
            return null;
        for (let i = 0; i < sites.length; ++i) {
            const keys = sites[i].bangs;
            for (let k = 0; k < keys.length; ++k)
                if (keys[k] === b)
                    return sites[i];
        }
        return null;
    }

    function siteRow(site, terms: string): var {
        const t = (terms ?? "").trim();
        if (t === "") {
            return {
                "kind": "web",
                "name": site.name,
                "detail": "Open " + site.name + " — Enter to open",
                "icon": "wifi.svg",
                "score": 100,
                "section": "Web",
                "data": { "url": site.home }
            };
        }
        const shown = t.length > 80 ? t.slice(0, 80) : t;
        return {
            "kind": "web",
            "name": shown,
            "detail": "Search " + site.name + " — Enter to open",
            "icon": "wifi.svg",
            "score": 100,
            "section": "Web",
                "data": { "url": root.siteUrl(site, t) }
        };
    }

    // True when q should be treated as a URL: explicit scheme, or a
    // spaceless string containing a dot (e.g. "example.com", "foo/bar.baz").
    function isUrl(q: string): bool {
        if (q.startsWith("http://") || q.startsWith("https://"))
            return true;
        if (q.indexOf(" ") !== -1)
            return false;
        return q.indexOf(".") !== -1;
    }

    // Prepend https:// when no scheme is present.
    function normalizeUrl(q: string): string {
        if (q.startsWith("http://") || q.startsWith("https://"))
            return q;
        return "https://" + q;
    }

    function search(q: string, limit: int): var {
        const trimmed = (q ?? "").trim();
        if (trimmed === "") {
            // Bare `@`: every site as a homepage row (cheatsheet).
            let rows = [];
            for (let i = 0; i < sites.length; ++i)
                rows.push(root.siteRow(sites[i], ""));
            latestRows = rows;
            return rows;
        }
        const sp = trimmed.indexOf(" ");
        const first = sp === -1 ? trimmed : trimmed.slice(0, sp);
        const rest = sp === -1 ? "" : trimmed.slice(sp + 1).trim();
        const site = root.findSite(first);
        let rows;
        if (site !== null) {
            rows = [root.siteRow(site, rest)];
        } else if (root.isUrl(trimmed)) {
            const name = trimmed.length > 80 ? trimmed.slice(0, 80) : trimmed;
            rows = [{
                "kind": "web",
                "name": name,
                "detail": "Open URL — Enter to open",
                "icon": "wifi.svg",
                "score": 100,
                "section": "Web",
                "data": { "url": root.normalizeUrl(trimmed) }
            }];
        } else {
            const name = trimmed.length > 80 ? trimmed.slice(0, 80) : trimmed;
            rows = [{
                "kind": "web",
                "name": name,
                "detail": "Search the web — Enter to open",
                "icon": "wifi.svg",
                "score": 100,
                "section": "Web",
                "data": { "url": "https://duckduckgo.com/?q=" + encodeURIComponent(trimmed) }
            }];
        }
        latestRows = rows;
        return rows;
    }

    function activate(row: var): void {
        if (!row || !row.data || !row.data.url)
            return;
        Quickshell.execDetached(["xdg-open", row.data.url]);
    }
}
