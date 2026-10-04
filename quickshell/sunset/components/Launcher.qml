// Launcher.qml — unified sunset app launcher. Replaces BOTH fuzzel
// app-launcher (Mod+Ctrl+Return) AND walker (Alt+Space) frontends.
//
// Fuzzel parity (from fuzzel/fuzzel.ini — KEPT as fallback, do not delete):
//   match-mode=fzf, icons-enabled=yes (icon-theme Colloid),
//   show-actions=yes, filter-desktop=no, terminal="alacritty -e"
//   lines=12, width=45, line-height=32, layer=overlay, anchor=center
//   prompt="  ", placeholder="Search applications..."
//   font JetBrainsMono Nerd Font 13, use-bold=yes
//   background #000000f2, text/input #f7c7a1, prompt #e85d2f,
//   placeholder/counter #7c8a6a, match #ff8b4a,
//   selection #e85d2f + selection-text/match #000000
//   NOTE: those fuzzel hexes are ALPHAS, not colours. The launcher renders
//     Theme.bg/accent/accentHover/text/muted at the same alphas (see the
//     token block below), so it follows the dynamic palette like the bar.
//
// Quickshell mapping:
//   fuzzel #RRGGBBAA -> Qt #AARRGGBB (e.g. #000000f2 -> "#f2000000")
//   width=45 (~45 text cols) -> 700px centered card
//   lines=12 x line-height=32 -> list capped at 12 rows (32px single-line,
//     46px two-line when a detail is present so paths stay fully visible)
//   layer=overlay anchor=center -> full-screen transparent PanelWindow
//     (exclusiveZone 0) + centered card,
//     WlrLayershell.layer Overlay, Exclusive keyboard focus while open.
//   fzf match-mode -> JS subsequence scorer (consecutive + word-start
//     bonuses, gap + late-start penalties), sorted by score then name.
//     Searched fields: name, genericName, comment, keywords, categories, id.
//   show-actions=yes -> each matching entry's DesktopActions are flattened
//     into extra rows ("App → Action"); Enter runs the highlighted row.
//   filter-desktop=no -> exact-id fallback via DesktopEntries.byId()
//     (includes NoDisplay). The broad list still comes from
//     DesktopEntries.applications (toolkit hides NoDisplay there); for full
//     NoDisplay browsing keep fuzzel.ini fallback.
//   runInTerminal entries launch via `alacritty -e` (fuzzel terminal=);
//     DesktopEntry.execute() ignores runInTerminal so this is handled here.
//   NOTE: taste.md wants radius 0, but fuzzel parity keeps radius 12 here.
//
// Walker note: app launching + walker power-user providers are BOTH
//   covered here via components/launcher/providers/ (calc "=", windows
//   "$", clipboard ":", web "@" (site bangs @dd @g @yt @wiki @gh
//   @so @r @maps @miruro/@anime, else URL/DDG fallback — see
//   WebProvider.qml header),
//   files "/" (!type/@scope bangs — file rows are draggable:
//     press+move a file row out to drop its file:// URL anywhere;
//     text/uri-list + text/plain, Copy/Move/Link, drop closes the menu),
//   runner ">", symbols ".",
//   todo "!", bookmarks "%", modes ";", media actions).
//   The walker binary
//   + ~/.config/walker/config.toml stay installed as fallback (untouched).
//
// Control rows (Extend Launcher plan): 14 static {kind:"control"} rows
//   (Settings, Help & Guide, Themes, Custom Editor, Quick Settings, Wi-Fi, Wallpaper, Power,
//   Volume, Now Playing, Clipboard, Calendar, Crack the Whip, Do Not Disturb)
//   scored on name+keywords
//   with the same fzf scorer and
//   interleaved with apps when filtering; pinned BEFORE the alpha-sorted
//   app list when the query is empty (selection starts on first row
//   — Controls first, i.e. Settings — so the first list item is highlighted). Rows carry section
//     "Applications"|"Controls".
//   Fifteen rows are quickshell popups (ipcTarget+ipcVerb); THREE are external
//     and carry `cmd` instead: Settings -> GNOME Settings
//     (scripts/gnome-settings.sh, Mod+Alt+S), Help & Guide -> the HTML
//     guide (scripts/open-help.sh, Mod+Alt+H), and Custom Editor ->
//     help/custom-theme.html via its loopback server
//     (scripts/custom-theme.sh, Mod+Alt+Shift+T). All three self-toggle.
//   Bind parity (Dev Menu audit, 2026-09-13): all 15 control rows are covered
//     here AND mirrored as ";" ModesProvider rows (plus Lock/Screenshot/
//     Dropdown spot actions there); app binds resolve via DesktopEntries.
//     Control keywords keep the plain-word convention (no "mod+..." tokens;
//     shortcut tokens ride in ModesProvider keys instead).
//   UI: control rows render inline with icon (assets/icons/ basename resolved
//     against Theme.iconDir, the generated themed copy), name, and hint
//     "opens <ipcTarget>" ("opens the app" for the two `cmd` rows).
//     ListView section headers ("Applications" / "Controls", muted 9pt bold
//     per this file's hardcoded colors) sit above each section; they are
//     ListView section delegates, NOT model rows, so the position counter
//     (current+1/rows.length) counts data rows only and selection/
//     activation skip them by construction (defensive kind==="header"
//     guards in moveSelection/activateCurrent). Filtered queries interleave
//     by score, so headers may repeat at section boundaries there; empty
//     query is grouped (controls first, then apps). App/action delegate
//     pixels are unchanged. Provider rows reuse the same generic
//     name/detail delegate (row.name/row.detail) + iconSourceFor.
//   Activation: launchRow() control branch runs close() then either
//     Quickshell.execDetached(["qs","-c","sunset","ipc","call",
//     ipcTarget,ipcVerb]) per the WallpaperMenu.qml precedent, or
//     ["sh","-c",cmd] for the two external rows; app/action activation
//     is untouched.
//
// Provider dispatch (walker parity, dir contract pointer:
//   components/launcher/providers/*.qml — each header documents its
//   contract; all are QtObject with search(q,limit)/activate(row)/
//   resultsChanged/latestRows EXCEPT MediaActions which is rows()+
//   activate(row) only, no search):
//   Prefix modes (first char of trimmed query, rest = slice(1), limit
//   maxRows; prefix queries show ONLY that provider's rows):
//     "=" calc, "$" windows, ":" clipboard, "@" web (matching saved
//     bookmarks first, then web history recents/matches, then the live
//     row; trailing " -bookmark" saves the site instead of opening it,
//     e.g. "@ github.com -bookmark"), "/" files
//     (with !type/@scope bangs — see FilesProvider.qml header),
//     ">" runner (Shift+Enter runs in terminal via alacritty -e;
//     Ctrl+Enter reveals a file row in the default file manager),
//     "." symbols, "!" todo, "%" bookmarks, ";" modes.
//   Bare queries (no prefix char):
//     empty -> 13 controls FIRST, then up to 5 recent Bookmarks (most
//       recent first, url-having only), then alpha apps; currentIndex
//       starts on the first row (Controls first) so the first list item is highlighted (Settings). Placement
//       choice: Bookmarks sit BELOW controls / ABOVE apps (visible on
//       open without scrolling). Below-apps was rejected: the
//       app list is ~100 rows, bookmarks would need End-key discovery.
//     non-empty -> scored apps+controls interleaved (unchanged) PLUS
//       media (MediaActions.rows() filtered by bestScore on name,
//       interleaved by score) PLUS bookmarks (marks filtered by
//       bestScore on title+url — synthetic {name:title, comment:url},
//       interleaved by score like media; url-less rows excluded so bare
//       Enter always acts) PLUS calc prepend (cap 3) when
//       CalcProvider.isExpression(raw) PLUS web append (cap 1) when
//       len>=3 and contains space/dot PLUS bookmark create-row append
//       (cap 1) when BookmarksProvider.isUrl(raw) — type URL, pick the
//       `Bookmark "<url>"` row, Enter to bookmark, no % needed. Exact-id
//       fallback still unshifts on top. All provider.search calls are
//       try/catch (degrade to app search, never blank the menu).
//   Bookmark add/open/delete (keyboard-first, see BookmarksProvider.qml
//     header for the contract): type URL → Enter to bookmark → later
//     type part of title → Enter opens in browser; `@ <site> -bookmark`
//     bookmarks straight from web mode (Enter saves, no % needed);
//     `%` mode keeps the
//     create-row for any non-empty query; deletion is `%delete <needle>`
//     + Enter on a Delete row (Shift+Delete deliberately unused: Keys
//     blocks are frozen, deletion is a row not a keybinding). Bookmark
//     rows use icon:null → logo.svg fallback (no favicon fetching).
//   Async (calc/files/clipboard/sessions return [] while pending):
//     Launcher-side asyncCache keyed by provider+query merged in rebuild
//     via cachedProvSearch; each provider's resultsChanged caches
//     latestRows then calls rebuild(); same-query re-search is skipped
//     (lastProvQuery guard) so Calc doesn't respawn its qalc proc in a
//     loop — and sessions doesn't respawn `session.sh list` in a loop
//     (which pinned currentIndex to 0 and broke Up/Down). Sync providers
//     (windows/web/runner/symbols/todo/bookmarks/modes) return rows
//   directly, mirrored in latestRows, never emit (Todo/Bookmarks/Web
//   emit only on async file load -> rebuild to re-search current query).
//   Modes rows: "prefix" in row.data (key presence, NOT truthiness;
//     "" = Applications default) -> set search text to data.prefix +
//     refocus input, do NOT call activate; else if data.ipcTarget ->
//     close + qs IPC toggle exactly-once (do NOT call activate); else
//     modesProv.activate(row).
//   Counter is a position indicator "<current+1>/<rows.length>"
//     (Raycast-style "3 of 114"), updated via updateCounter() at the end
//     of rebuild() and on currentIndex change.
//
// Keybindings (for the binds owner — do NOT edit binds.kdl here):
//   Mod+Ctrl+Return { spawn-sh "qs -c sunset ipc call launcher toggle"; }
//   Alt+Space       { spawn-sh "qs -c sunset ipc call launcher toggle"; }
//   (A/B test binds currently live in niri/binds-quickshell.kdl.)
//
// niri layer-rule doc (for the shell owner — do NOT edit rules.kdl here):
//   layer-rule { match namespace="sunset-launcher" ... }
//   Verify while running: `niri msg layers`
//
// IPC: `qs -c sunset ipc call launcher toggle`
//      (also: open, close)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import qs.services
import "launcher/providers"
import "launcher"

Scope {
    id: root

    // ---- theme (taste.md tokens; alphas are the fuzzel.ini parity) ----
    // fuzzel carried the sunset hexes inline (background=#000000f2,
    // placeholder=#7c8a6aaa, selection-text=#000000). Those alphas are kept,
    // but the *colours* come from Theme so a wallpaper/curated palette switch
    // repaints the launcher like it repaints the bar. Theme.withAlpha is used
    // rather than a literal like "#f2000000": the latter is black-at-95%,
    // which silently froze the card to sunset black under every other theme.
    readonly property color bg: Theme.withAlpha(Theme.bg, 0.95) // fuzzel background alpha f2
    readonly property color textCol: Theme.text // fuzzel text #f7c7a1ff
    readonly property color accent: Theme.accent // fuzzel selection #e85d2fff
    readonly property color accentHover: Theme.accentHover // fuzzel match #ff8b4aff
    readonly property color muted: Theme.withAlpha(Theme.muted, 0.67) // fuzzel placeholder alpha aa
    readonly property color selText: Theme.onAccent // fuzzel selection-text, measured not assumed
    // The row glyph/icon column. Theme.icon is the same neutral, accent-tinted
    // grey that Theme.iconDir paints the stroke SVGs with, so a Nerd Font
    // glyph and an SVG in adjacent rows are the SAME colour -- they used to be
    // `text` here and `accent` there, i.e. two weights in one list. Not
    // `textCol`: an icon is chrome, and body-text weight made it louder than the
    // row name beside it.
    readonly property color iconCol: Theme.icon
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int menuWidth: 700 // fuzzel width=45
    readonly property int maxRows: 12 // fuzzel lines=12
    readonly property int rowHeight: 32 // fuzzel line-height=32
    // Two-line rows (name + detail): 11pt name + 9pt detail need more than
    // 32px, otherwise the detail line is clipped (file rows always carry
    // the path detail; control rows carry "opens <target>").
    readonly property int rowHeightTall: 46
    readonly property string terminal: "alacritty"

    // Repo-relative script paths (setupHome pattern from ContextMenu.qml).
    // Two control rows are NOT quickshell popups any more (2026-10-02):
    // settings = GNOME Settings, help = the standalone HTML guide.
    readonly property string setupHome: Quickshell.env("NIRI_SETUP_HOME") ?? (Quickshell.env("HOME") + "/niri-setup")
    readonly property string gnomeSettingsScript: setupHome + "/scripts/gnome-settings.sh"
    readonly property string openHelpScript: setupHome + "/scripts/open-help.sh"
    readonly property string instagramScript: setupHome + "/scripts/instagram.sh"
    readonly property string customThemeScript: setupHome + "/scripts/custom-theme.sh"
    readonly property string sushiScript: setupHome + "/scripts/sushi-preview.sh"

    property bool isOpen: false
    property string query: ""
    // Debounced typing: the input stays live per keystroke, but filtering
    // (rebuild) runs 300ms after the last keystroke so fast typing never
    // queues full scans behind every char. Enter flushes immediately;
    // async completions (resultsChanged) still rebuild at once.
    property string pendingQuery: ""
    // Mouse must not vote until the user actually moves it: on open,
    // currentIndex is set to the first row (Controls first), but the delegate under a
    // resting cursor would fire onEntered and steal selection. Disarmed on
    // open(); armed on first explicit mouse movement (delegate
    // onPositionChanged) or any keyboard navigation; click/press arms too.
    property bool hoverArmed: false
    // True while a file-row external drag (Wayland text/uri-list) is in
    // flight. Guards the click-outside-to-close MouseArea so the release
    // that ends a cancelled drag doesn't instantly close the menu.
    property bool dragActive: false
    // Bumped on every open so the row list rebuilds even for same query.
    property int generation: 0
    // Plain JS rows:
    //   app/action: { kind: "app"|"action", entry, action, score, section }
    //   control:    { kind: "control", entry: null, action: null, name,
    //                 keywords, icon, ipcTarget, ipcVerb, score, section }
    // `section` is "Applications" (apps/actions) or "Controls" (controls)
    // for the UI agent's section headers. `icon` is an assets/icons/ basename.
    // Provider rows add { kind: "calc"|"window"|"clip"|"web"|"file"|"run"|
    //   "symbol"|"todo"|"bookmark"|"mode"|"media", name, detail, icon,
    //   score, section, data } (no entry/action).
    property var rows: []
    // Position counter text ("<current+1>/<rows.length>"), maintained by
    // updateCounter() (rebuild + currentIndex change).
    property string counterStr: "0/0"
    // Async provider cache: key = providerName + "|" + query arg -> rows.
    // Covers Calc/Files/Clipboard which return [] while pending (their
    // latestRows is stale for a new query, and re-calling search() would
    // respawn the backend proc). Sync providers bypass this cache.
    property var asyncCache: ({})
    // Last query arg sent to each async provider (avoids respawning the
    // backend when rebuild() re-runs for the same query, e.g. on the
    // provider's own resultsChanged).
    property var lastProvQuery: ({})

    // ---- Ctrl+Space preview (Quick Look parity, hybrid surface) --------
    // Browse-aware was the starting point, but the search field owns Space
    // (multi-word file queries like `/ quarterly report`), so the chord is
    // Ctrl+Space and Space keeps typing. Ctrl+Space toggles:
    //   native pane      images, animated gifs, PDFs (paged), text, folders
    //   Sushi window     audio, video, office docs, fonts (hybrid fallback)
    // The launcher never loses keyboard focus: the native pane is part of
    // this PanelWindow, and the Sushi toplevel is pinned `open-focused false`
    // in niri/rules.kdl. Esc closes the preview first, the launcher second.
    property bool previewOpen: false
    // Path last handed to Sushi (used for the same-file toggle).
    property string sushiPath: ""
    property bool sushiAvailable: false
    // Sushi is a persistent D-Bus service: its window can close while the bus
    // name stays owned (verified), so window presence must come from niri's
    // live window list, not from `sushi-preview.sh status`.
    readonly property bool sushiWindowOpen: {
        const list = NiriService.windows;
        for (let i = 0; i < list.length; ++i)
            if (list[i] && list[i].app_id === "org.gnome.NautilusPreviewer")
                return true;
        return false;
    }
    // Pane geometry. The card keeps its fuzzel width when there is room; the
    // pane takes what is left, clamped so a 1280x800 laptop stays sane.
    readonly property int previewPaneWidth: root.previewOpen
        ? Math.max(280, Math.min(560, win.width - 48 - root.menuWidth - 12)) : 0
    readonly property int cardWidth: {
        const avail = win.width - 48;
        if (!root.previewOpen)
            return Math.min(root.menuWidth, avail);
        return Math.min(root.menuWidth, Math.max(360, avail - root.previewPaneWidth - 12));
    }

    // Filtering changes the rows under an open preview: follow or close it.
    onRowsChanged: root.syncPreview()

    // Static control rows (Alt+Space control menus). Icons are basenames in
    // assets/icons/ (no calendar/bell glyph exists: calendar falls back to
    // logo.svg, DND to empty.svg). Activation is owned by the UI agent.
    readonly property var controlEntries: [
        { "kind": "control", "name": "Settings", "keywords": "settings center preferences system config network sound display accounts power gnome", "icon": "settings.svg", "cmd": root.gnomeSettingsScript },
        { "kind": "control", "name": "Help & Guide", "keywords": "help guide manual docs setup keybindings bangs file search howto", "icon": "logo.svg", "cmd": root.openHelpScript },
        { "kind": "control", "name": "Instagram", "keywords": "instagram insta social photos reels stories dms feed", "icon": "camera.svg", "cmd": root.instagramScript },
        { "kind": "control", "name": "Themes", "keywords": "theme themes style colors rice omarchy catppuccin tokyo gruvbox nord kanagawa everforest dracula rose pine skillet", "icon": "palette.svg", "ipcTarget": "themes", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Custom Editor", "keywords": "custom theme edit colors palette hex contrast accessibility editor tweak rice", "icon": "palette.svg", "cmd": root.customThemeScript },
        { "kind": "control", "name": "Quick Settings", "keywords": "settings quick brightness volume dnd idle power profile", "icon": "settings.svg", "ipcTarget": "settings", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Wi-Fi", "keywords": "wifi wi-fi wireless network ssid connect disconnect forget rescan internet ethernet", "icon": "wifi.svg", "ipcTarget": "wifi", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Wallpaper", "keywords": "wallpaper background gallery random next theme", "icon": "wallpaper.svg", "ipcTarget": "wallpaper-menu", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Power", "keywords": "power lock suspend logout reboot shutdown quit", "icon": "power.svg", "ipcTarget": "power", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Volume", "keywords": "volume mixer audio sound sink mute", "icon": "volume.svg", "ipcTarget": "volume", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Now Playing", "keywords": "now playing media music track song mpris player spotify youtube mpv vlc", "icon": "media.svg", "ipcTarget": "now-playing", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Clipboard", "keywords": "clipboard history copy paste cliphist", "icon": "clipboard.svg", "ipcTarget": "clipboard", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Screenshot", "keywords": "screenshot capture region window screen scroll recording ocr redact annotate shot print camera", "icon": "camera.svg", "ipcTarget": "capture", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Calendar", "keywords": "calendar clock pomodoro timer date", "icon": "logo.svg", "ipcTarget": "calendar", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Crack the Whip", "keywords": "whip crack lash fun", "icon": "whip.svg", "ipcTarget": "whip", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Do Not Disturb", "keywords": "dnd disturb silent mute notifications", "icon": "empty.svg", "ipcTarget": "notifications", "ipcVerb": "toggleSilent" }
    ]

    // ---- provider instances (top-level; see dir contract in header) ----
    CalcProvider {
        id: calcProv
    }
    WindowsProvider {
        id: windowsProv
    }
    // Pinned "Open" section (rows()+activate(), MediaActions shape — not a
    // search provider). One row per running app, Nerd Font glyph, no
    // coordinates; see OpenApps.qml header.
    OpenApps {
        id: openApps
    }
    ClipboardProvider {
        id: clipProv
    }
    WebProvider {
        id: webProv
    }
    FilesProvider {
        id: filesProv
    }
    RunnerProvider {
        id: runnerProv
    }
    SymbolsProvider {
        id: symbolsProv
    }
    TodoProvider {
        id: todoProv
    }
    BookmarksProvider {
        id: bookmarksProv
    }
    ModesProvider {
        id: modesProv
    }
    SessionsProvider {
        id: sessionsProv
    }
    MediaActions {
        id: mediaActions
    }

    function open(): void {
        query = "";
        pendingQuery = "";
        debounceTimer.stop();
        searchInput.text = "";
        hoverArmed = false;
        dragActive = false;
        // A fresh open is a clean slate: no pane, no leftover Sushi window.
        previewOpen = false;
        previewPane.path = "";
        closeSushi();
        // Fresh backend state per open: dynamic providers (windows,
        // clipboard, files) must not serve the previous open's cache.
        asyncCache = ({});
        lastProvQuery = ({});
        generation++;
        rebuild();
        // Deterministic open state: highlight stays on the first row (Controls first)
        // while the view shows the top even if the cursor sits low over the list.
        appList.currentIndex = rows.length > 0 ? 0 : -1;
        appList.positionViewAtBeginning();
        isOpen = true;
        focusTimer.attempts = 0;
        focusTimer.restart();
    }

    function close(): void {
        debounceTimer.stop();
        dragActive = false;
        // Closing the launcher closes its preview too (the pane lives in
        // this surface; the Sushi window is part of the same interaction).
        dismissPreview();
        isOpen = false;
    }

    // Run the pending typed query now (Enter path): no-op when idle.
    function flushQuery(): void {
        if (!debounceTimer.running)
            return;
        debounceTimer.stop();
        query = pendingQuery;
        rebuild();
    }

    function toggle(): void {
        if (isOpen)
            close();
        else
            open();
    }

    // fzf-style subsequence score. -1e9 = no match.
    function fzfScore(q: string, s: string): real {
        if (q === "")
            return 0;
        const needle = q.toLowerCase();
        const hay = s.toLowerCase();
        let si = 0;
        let score = 0;
        let first = -1;
        for (let qi = 0; qi < needle.length; ++qi) {
            const c = needle[qi];
            let found = -1;
            for (let j = si; j < hay.length; ++j) {
                if (hay[j] === c) {
                    found = j;
                    break;
                }
            }
            if (found === -1)
                return -1e9;
            if (first === -1)
                first = found;
            const prev = found > 0 ? hay[found - 1] : " ";
            if (found === 0 || prev === " " || prev === "-" || prev === "_" || prev === "/" || prev === ".")
                score += 8;
            else if (found === si)
                score += 5;
            else
                score += 1;
            score -= (found - si);
            si = found + 1;
        }
        score -= first;
        return score;
    }

    function bestScore(q: string, e): real {
        let best = root.fzfScore(q, e.name || "");
        const gen = root.fzfScore(q, e.genericName || "") - 4;
        if (gen > best)
            best = gen;
        const com = root.fzfScore(q, e.comment || "") - 6;
        if (com > best)
            best = com;
        const idm = root.fzfScore(q, e.id || "") - 4;
        if (idm > best)
            best = idm;
        // keywords is an array (DesktopEntry) or a plain string (control row).
        const kwSrc = Array.isArray(e.keywords) ? e.keywords.join(" ") : (e.keywords || "");
        const kwm = root.fzfScore(q, kwSrc) - 4;
        if (kwm > best)
            best = kwm;
        const cats = (e.categories || []).join(" ");
        const ctm = root.fzfScore(q, cats) - 8;
        if (ctm > best)
            best = ctm;
        return best;
    }

    // Generic icon fallback chain (synchronous, never ""/checker).
    //   (a) control rows: assets/icons/ basename, resolved against Theme.iconDir.
    //   (b) provider rows with row.icon: contains "/" -> file://,
    //       bare basename with "." -> Theme.iconDir,
    //       else theme name via iconPath ("" falls to (d)).
    //   (c) app rows (row.entry): absolute -> file://, else theme ->
    //       iconPath-with-fallback -> logo.svg (pixmaps-only names land on
    //       the fallback/placeholder, no blank/checker).
    //   (d) final placeholder: logo.svg.
    function iconSourceFor(row): string {
        // assets/icons/theme/ is the GENERATED copy of the monochrome stroke set
        // (scripts/sync-external-theme.py substitutes the palette into every
        // stroke/fill). The hand-written originals in assets/icons/ are sunset
        // coloured and would stay orange under every other theme.
        const base = Theme.iconDir;
        const logo = "file://" + base + "logo.svg";
        if (!row)
            return logo;
        if (row.kind === "control" && row.icon)
            return "file://" + base + row.icon;
        if (row.icon) {
            const icon = row.icon;
            if (icon.indexOf("/") !== -1)
                return "file://" + icon;
            if (icon.indexOf(".") !== -1)
                return "file://" + base + icon;
            const themed = Quickshell.iconPath(icon, true);
            if (themed !== "")
                return themed;
            return logo;
        }
        if (row.entry) {
            const e = row.entry.icon;
            if (e) {
                if (e[0] === "/")
                    return "file://" + e;
                const themed = Quickshell.iconPath(e, true);
                if (themed !== "")
                    return themed;
                const fb = Quickshell.iconPath(e, "application-x-executable");
                if (fb !== "")
                    return fb;
            }
            return logo;
        }
        return logo;
    }

    // Detail line for a row (single source of truth for the delegate's
    // detail Text + hasDetail height switch). "" = single-line row.
    function detailFor(r): string {
        if (!r)
            return "";
        if (r.detail)
            return r.detail;
        if (r.kind === "control")
            return r.ipcTarget ? "opens " + r.ipcTarget : (r.cmd ? "opens the app" : "");
        if (!r.entry)
            return "";
        if (r.kind === "action")
            return "";
        return r.entry.comment || r.entry.genericName || "";
    }

    // Absolute path -> "file://" URL for Wayland text/uri-list drags.
    // Segments are encodeURIComponent'd individually so spaces, "#", "?"
    // etc. survive; the leading "/" yields the "file:///" triple slash.
    // Non-absolute input is returned "" (no drag) — fd always emits
    // absolute paths, so this only guards cheatsheet/info rows.
    function fileUrlFor(path: string): string {
        if (!path)
            return "";
        const p = String(path);
        if (p === "" || p[0] !== "/")
            return "";
        const segs = p.split("/");
        for (let i = 0; i < segs.length; ++i)
            segs[i] = encodeURIComponent(segs[i]);
        return "file://" + segs.join("/");
    }

    // List height from MODEL data (not contentHeight: binding the view's
    // height to its own contentHeight risks a collapse when no delegates
    // exist yet). Counts one 20px section header per distinct section
    // among the first maxRows items (InlineLabels parity) + per-row
    // single/tall heights (detailFor parity with the delegate).
    function estListHeight(): int {
        let h = 0;
        let seen = ({});
        const n = Math.min(rows.length, maxRows);
        for (let i = 0; i < n; ++i) {
            const r = rows[i];
            if (r && seen[r.section] === undefined) {
                seen[r.section] = true;
                h += 20;
            }
            h += (root.detailFor(r) !== "" ? rowHeightTall : rowHeight);
        }
        return h;
    }

    function updateCounter(): void {
        if (rows.length === 0) {
            counterStr = "0/0";
            return;
        }
        const idx = appList.currentIndex;
        const pos = (idx >= 0 && idx < rows.length) ? (idx + 1) : 0;
        counterStr = pos + "/" + rows.length;
    }

    // Sync provider search with try/catch: never throws, never blanks the
    // menu (falls back to []). Used for windows/web/runner/symbols/todo/
    // bookmarks/modes which return rows synchronously.
    function safeProvSearch(prov, arg: string, cap: int): var {
        try {
            const r = prov.search(arg, cap);
            return r ? r : [];
        } catch (e) {
            return [];
        }
    }

    // Pinned "Open" rows. Same degrade-to-empty rule as every other provider
    // call: a throw here would take the whole default view down, and a missing
    // section is a far better outcome than a launcher that will not open. Also
    // strips anything the provider failed to fill in (a row without a name
    // would render as a blank line with no way to activate it).
    function safeOpenRows(): var {
        try {
            const r = openApps.rows(12);
            if (!r)
                return [];
            const out = [];
            for (let i = 0; i < r.length; ++i) {
                const row = r[i];
                if (row && row.name !== undefined && row.name !== "")
                    out.push(row);
            }
            return out;
        } catch (e) {
            return [];
        }
    }

    // Async provider search (calc/clipboard/files return [] while pending).
    // Same-query re-search is skipped via lastProvQuery so backends aren't
    // respawned (Calc qalc loop guard, Files fd kill/restart guard,
    // Clipboard cliphist kill/restart guard). Pending queries return [] and
    // fill in via onProvResults -> asyncCache -> rebuild.
    function cachedProvSearch(prov, provName: string, arg: string, cap: int): var {
        const key = provName + "|" + arg;
        if (lastProvQuery[provName] === arg) {
            if (asyncCache[key] !== undefined)
                return asyncCache[key];
            try {
                const lr = prov.latestRows;
                if (lr && lr.length > 0) {
                    asyncCache[key] = lr;
                    return lr;
                }
            } catch (e) {}
            return [];
        }
        lastProvQuery[provName] = arg;
        let fresh = [];
        try {
            const r = prov.search(arg, cap);
            if (r)
                fresh = r;
        } catch (e) {
            fresh = [];
        }
        if (fresh.length > 0)
            asyncCache[key] = fresh;
        return fresh;
    }

    // resultsChanged fan-in: cache the provider's latest rows under its
    // last query, then rebuild() for the CURRENT query. rebuild() reuses
    // the cache for same-query async providers (no respawn) and re-searches
    // sync providers fresh (Todo/Bookmarks file loads, Windows list).
    function onProvResults(provName: string, prov): void {
        try {
            let keyQ = "";
            try {
                keyQ = (prov.lastQuery !== undefined && prov.lastQuery !== null) ? String(prov.lastQuery) : String(lastProvQuery[provName] ?? "");
            } catch (e2) {
                keyQ = String(lastProvQuery[provName] ?? "");
            }
            const lr = prov.latestRows || [];
            asyncCache[provName + "|" + keyQ] = lr;
        } catch (e) {}
        rebuild();
    }

    function rebuild(): void {
        // Depend on generation so reopening refreshes the list.
        const gen = generation;
        const rawTrim = query.trim();
        const q = rawTrim.toLowerCase();
        const apps = DesktopEntries.applications.values;
        let out = [];
        // ---- prefix dispatch (walker parity; rest = slice(1), limit maxRows) ----
        const prefixKind = {
            "=": "calc",
            "$": "window",
            ":": "clip",
            "@": "web",
            "/": "file",
            ">": "run",
            ".": "symbol",
            "!": "todo",
            "%": "bookmark",
            ";": "mode"
        };
        if (rawTrim.length > 0 && prefixKind[rawTrim[0]] !== undefined) {
            const kind = prefixKind[rawTrim[0]];
            const rest = rawTrim.slice(1);
            try {
                if (kind === "calc")
                    out = root.cachedProvSearch(calcProv, "calc", rest, maxRows);
                else if (kind === "window")
                    out = root.safeProvSearch(windowsProv, rest, maxRows);
                else if (kind === "clip")
                    out = root.cachedProvSearch(clipProv, "clip", rest, maxRows);
                else if (kind === "web") {
                    // `@ <site> -bookmark` fast path: save any site without
                    // leaving web mode. Trailing " -bookmark" (or
                    // " --bookmark", case-insensitive) is stripped; the rest
                    // is bookmarked via BookmarksProvider.activate on Enter
                    // (same {action:"create", text, url} shape as the `%`
                    // and bare-URL create rows, so launchRow needs no new
                    // branch). URL-like input is normalized via
                    // BookmarksProvider.normUrl (matches `%` storage);
                    // anything else bookmarks the DuckDuckGo search URL
                    // WebProvider would have opened (mirrors its
                    // isUrl/normalizeUrl fallback).
                    const wq = rest.trim();
                    const bmFlag = wq.match(/(^|\s)-{1,2}bookmark\s*$/i);
                    if (bmFlag) {
                        const site = wq.slice(0, wq.length - bmFlag[0].length).trim();
                        if (site === "") {
                            out = [{
                                "kind": "bookmark",
                                "name": "Bookmark: type a site first",
                                "detail": "Usage: @ github.com -bookmark",
                                "icon": null,
                                "score": 100,
                                "section": "Bookmarks",
                                "data": { "action": "create", "text": "", "url": "" }
                            }];
                        } else {
                            let burl = "";
                            let btitle = site;
                            try {
                                // Site bangs resolve first: `@dd cats
                                // -bookmark` bookmarks the DuckDuckGo search
                                // for "cats" (WebProvider.findSite parity
                                // with the live `@` row below).
                                const bsp = site.indexOf(" ");
                                const btok = (bsp === -1 ? site : site.slice(0, bsp)).toLowerCase();
                                const bterms = bsp === -1 ? "" : site.slice(bsp + 1).trim();
                                let bs = null;
                                try {
                                    bs = webProv.findSite(btok);
                                } catch (e5) {
                                    bs = null;
                                }
                                if (bs !== null) {
                                    burl = bterms === "" ? bs.home : bs.search + encodeURIComponent(bterms);
                                    btitle = bterms !== "" ? bterms : bs.name;
                                } else if (bookmarksProv.isUrl(site))
                                    burl = bookmarksProv.normUrl(site);
                                else if (webProv.isUrl(site))
                                    burl = webProv.normalizeUrl(site);
                                else
                                    burl = "https://duckduckgo.com/?q=" + encodeURIComponent(site);
                            } catch (e3) {
                                burl = "";
                            }
                            out = [{
                                "kind": "bookmark",
                                "name": 'Bookmark "' + btitle + '"',
                                "detail": burl !== "" ? "Enter to bookmark " + burl : "Enter to bookmark",
                                "icon": null,
                                "score": 100,
                                "section": "Bookmarks",
                                "data": { "action": "create", "text": btitle, "url": burl }
                            }];
                        }
                    } else {
                        // Web rows (history recents/matches + live row, via
                        // WebProvider) with matching saved bookmarks FIRST:
                        // `@` mode used to be web-only, so bookmarked sites
                        // never appeared here. Empty rest lists recent
                        // bookmarks (most-recent-first, url-having only).
                        const webRows = root.safeProvSearch(webProv, rest, maxRows);
                        let bpre = [];
                        try {
                            const bneedle = rest.trim().toLowerCase();
                            const bmarks = bookmarksProv.marks || [];
                            for (let bi = bmarks.length - 1; bi >= 0 && bpre.length < 5; --bi) {
                                const bb = bmarks[bi];
                                if (!bb || !bb.url)
                                    continue;
                                if (bneedle !== "" && bb.title.toLowerCase().indexOf(bneedle) === -1 && bb.url.toLowerCase().indexOf(bneedle) === -1)
                                    continue;
                                bpre.push(bookmarksProv.markRow(bi));
                            }
                        } catch (e4) {}
                        out = bpre.concat(webRows).slice(0, maxRows);
                    }
                }
                else if (kind === "file")
                    out = root.cachedProvSearch(filesProv, "file", rest, maxRows);
                else if (kind === "run")
                    out = root.safeProvSearch(runnerProv, rest, maxRows);
                else if (kind === "symbol")
                    out = root.safeProvSearch(symbolsProv, rest, maxRows);
                else if (kind === "todo")
                    out = root.safeProvSearch(todoProv, rest, maxRows);
                else if (kind === "bookmark")
                    out = root.safeProvSearch(bookmarksProv, rest, maxRows);
                else if (kind === "mode")
                    out = root.safeProvSearch(modesProv, rest, maxRows);
            } catch (e) {
                out = [];
            }
            if (!out)
                out = [];
            if (gen !== generation)
                return;
            rows = out;
            appList.currentIndex = out.length > 0 ? 0 : -1;
            root.updateCounter();
            return;
        }
        if (q === "") {
            // No typing: control rows FIRST, then alpha-sorted apps.
            for (let c = 0; c < root.controlEntries.length; ++c) {
                const ce = root.controlEntries[c];
                out.push({
                    "kind": "control",
                    "entry": null,
                    "action": null,
                    "name": ce.name,
                    "keywords": ce.keywords,
                    "icon": ce.icon,
                    "ipcTarget": ce.ipcTarget,
                    "ipcVerb": ce.ipcVerb,
                    "cmd": ce.cmd,
                    "score": 0,
                    "section": "Controls"
                });
            }
            // The "Open" section: what is ALREADY running, pinned below the
            // controls and above bookmarks. Controls stay first so the default
            // selection is still Settings (documented in this file's header);
            // Open goes second because "switch to my terminal" is the most
            // common reason to open the launcher when everything is already up.
            // Empty when nothing is open, and it is rebuilt on every empty-query
            // rebuild, so a window closed while the menu sat open disappears on
            // the next search/reopen.
            try {
                const openRows = root.safeOpenRows();
                for (let o = 0; o < openRows.length; ++o)
                    out.push(openRows[o]);
            } catch (e) {}
            // Bookmarks BELOW controls / ABOVE apps (header-documents the
            // choice): most recent first, cap 5, openable (url-having)
            // only so empty-query Enter always acts. Reads marks/markRow
            // directly (no search call → no create-row leaks in).
            try {
                const bmarks = bookmarksProv.marks || [];
                let bshown = 0;
                for (let bi = bmarks.length - 1; bi >= 0 && bshown < 5; --bi) {
                    const bb = bmarks[bi];
                    if (!bb || !bb.url)
                        continue;
                    const br = bookmarksProv.markRow(bi);
                    br.score = 0;
                    out.push(br);
                    bshown++;
                }
            } catch (e) {}
            const sorted = apps.slice().sort((a, b) => a.name.localeCompare(b.name));
            for (let i = 0; i < sorted.length; ++i)
                out.push({
                    "kind": "app",
                    "entry": sorted[i],
                    "action": null,
                    "score": 0,
                    "section": "Applications"
                });
            if (gen !== generation)
                return;
            rows = out;
            appList.currentIndex = out.length > 0 ? 0 : -1;
            root.updateCounter();
            return;
        } else {
            let scored = [];
            for (let i = 0; i < apps.length; ++i) {
                const s = root.bestScore(q, apps[i]);
                if (s > -1e8)
                    scored.push({
                        "t": "app",
                        "e": apps[i],
                        "s": s
                    });
            }
            // Same scorer over control name + keywords; interleaved by score.
            for (let c = 0; c < root.controlEntries.length; ++c) {
                const ce = root.controlEntries[c];
                const s = root.bestScore(q, ce);
                if (s > -1e8)
                    scored.push({
                        "t": "control",
                        "c": ce,
                        "s": s
                    });
            }
            // Media actions have no search(): filter by fzf on name.
            // bestScore tolerates the synthetic {name} object (all other
            // fields fall back to ""/[] per its guards).
            try {
                const mediaRows = mediaActions.rows() || [];
                for (let m = 0; m < mediaRows.length; ++m) {
                    const s = root.bestScore(q, { "name": mediaRows[m].name });
                    if (s > -1e8)
                        scored.push({
                            "t": "media",
                            "m": mediaRows[m],
                            "s": s
                        });
                }
            } catch (e) {}
            // Bookmarks interleaved by score like media: bestScore on
            // title+url (url rides as comment, -6, mirroring app-comment
            // scoring). Url-less rows stay %-mode only (bare Enter must
            // act). Reads marks directly; scores ride in `n` for the
            // sort tiebreak below.
            try {
                const bmarks = bookmarksProv.marks || [];
                for (let bi = 0; bi < bmarks.length; ++bi) {
                    const b = bmarks[bi];
                    if (!b || !b.url)
                        continue;
                    const bt = (b.title && b.title !== "") ? b.title : b.url;
                    const s = root.bestScore(q, { "name": bt, "comment": b.url });
                    if (s > -1e8)
                        scored.push({
                            "t": "bookmark",
                            "b": bi,
                            "n": bt,
                            "s": s
                        });
                }
            } catch (e) {}
            // Sessions interleaved by score like media/bookmarks: bestScore
            // on the display name; provider refreshes its list in the
            // background (resultsChanged -> rebuild fills rows in).
            // Async like calc/files/clipboard: cachedProvSearch so the
            // same-query rebuild does NOT re-call search() (which would
            // respawn `session.sh list`, whose completion emits
            // resultsChanged -> rebuild -> respawn... an infinite loop
            // that pinned currentIndex to 0 and made Up/Down look dead).
            try {
                const sessRows = root.cachedProvSearch(sessionsProv, "session", q, maxRows);
                for (let si = 0; si < sessRows.length; ++si) {
                    const s = root.bestScore(q, { "name": sessRows[si].name });
                    if (s > -1e8)
                        scored.push({
                            "t": "session",
                            "r": sessRows[si],
                            "n": sessRows[si].name,
                            "s": s
                        });
                }
            } catch (e) {}
            const rowName = (m) => {
                if (m.t === "control")
                    return m.c.name;
                if (m.t === "app")
                    return m.e.name;
                if (m.t === "bookmark")
                    return m.n;
                if (m.t === "session")
                    return m.n;
                return m.m.name;
            };
            scored.sort((a, b) => (b.s - a.s) || rowName(a).localeCompare(rowName(b)));
            for (let k = 0; k < scored.length; ++k) {
                if (scored[k].t === "control") {
                    const ce = scored[k].c;
                    out.push({
                        "kind": "control",
                        "entry": null,
                        "action": null,
                        "name": ce.name,
                        "keywords": ce.keywords,
                        "icon": ce.icon,
                        "ipcTarget": ce.ipcTarget,
                        "ipcVerb": ce.ipcVerb,
                        "cmd": ce.cmd,
                        "score": scored[k].s,
                        "section": "Controls"
                    });
                    continue;
                }
                if (scored[k].t === "media") {
                    const mr = scored[k].m;
                    out.push({
                        "kind": mr.kind,
                        "name": mr.name,
                        "detail": mr.detail,
                        "icon": mr.icon,
                        "score": scored[k].s,
                        "section": mr.section,
                        "data": mr.data
                    });
                    continue;
                }
                // Bookmark match: provider-built row (icon:null → logo
                // fallback), Launcher-computed score. Index `b` is valid:
                // marks is read synchronously in this same rebuild.
                if (scored[k].t === "bookmark") {
                    const br = bookmarksProv.markRow(scored[k].b);
                    br.score = scored[k].s;
                    out.push(br);
                    continue;
                }
                // Session match: provider-built row (icon:null → logo
                // fallback), Launcher-computed score.
                if (scored[k].t === "session") {
                    const sr = scored[k].r;
                    sr.score = scored[k].s;
                    out.push(sr);
                    continue;
                }
                const e = scored[k].e;
                out.push({
                    "kind": "app",
                    "entry": e,
                    "action": null,
                    "score": scored[k].s,
                    "section": "Applications"
                });
                // show-actions=yes: action rows directly under their app.
                for (let a = 0; e.actions && a < e.actions.length; ++a)
                    out.push({
                        "kind": "action",
                        "entry": e,
                        "action": e.actions[a],
                        "score": scored[k].s - 1,
                        "section": "Applications"
                    });
            }
            // Bare-query extra: math expression -> prepend calc rows (cap 3).
            try {
                let isExpr = false;
                try {
                    isExpr = calcProv.isExpression(rawTrim);
                } catch (e2) {
                    isExpr = false;
                }
                if (isExpr) {
                    const calcRows = root.cachedProvSearch(calcProv, "calc", rawTrim, 3);
                    if (calcRows && calcRows.length > 0)
                        out = calcRows.slice(0, 3).concat(out);
                }
            } catch (e) {}
            // Bare-query extra: len>=3 with space/dot -> append web row (cap 1).
            try {
                if (rawTrim.length >= 3 && (rawTrim.indexOf(" ") !== -1 || rawTrim.indexOf(".") !== -1)) {
                    const webRows = root.safeProvSearch(webProv, rawTrim, 1);
                    if (webRows && webRows.length > 0)
                        out = out.concat(webRows.slice(0, 1));
                }
            } catch (e) {}
            // Bare-query extra: URL-like query -> append Bookmark
            // create-row (cap 1) so typing a URL bookmarks it with Enter,
            // no % needed. Same shape as the provider's own create row;
            // activate stores {title:text, url} via bookmarksProv.
            try {
                if (bookmarksProv.isUrl(rawTrim)) {
                    out.push({
                        "kind": "bookmark",
                        "name": 'Bookmark "' + rawTrim + '"',
                        "detail": "Enter to bookmark this URL",
                        "icon": null,
                        "score": 100,
                        "section": "Bookmarks",
                        "data": { "action": "create", "text": rawTrim, "url": bookmarksProv.normUrl(rawTrim) }
                    });
                }
            } catch (e) {}
            // filter-desktop=no: exact-id fallback (byId includes NoDisplay).
            try {
                const exact = DesktopEntries.byId(query.trim());
                if (exact) {
                    let dup = false;
                    for (let d = 0; d < out.length; ++d)
                        if (out[d].entry && out[d].entry.id === exact.id)
                            dup = true;
                    if (!dup)
                        out.unshift({
                            "kind": "app",
                            "entry": exact,
                            "action": null,
                            "score": 1e9,
                            "section": "Applications"
                        });
                }
            } catch (e) {}
            if (gen !== generation)
                return;
            rows = out;
            appList.currentIndex = out.length > 0 ? 0 : -1;
            root.updateCounter();
            return;
        }
    }

    function activateCurrent(): void {
        if (appList.currentIndex < 0 || appList.currentIndex >= rows.length)
            return;
        const row = rows[appList.currentIndex];
        // Section headers are ListView section delegates (never model rows);
        // defensively ignore any inline header marker.
        if (row && row.kind === "header")
            return;
        launchRow(row);
    }

    // Ctrl+Enter on file rows: reveal in the default file manager
    // (FilesProvider.reveal: directories open directly, files open their
    // containing folder). Returns true when a reveal ran (menu closed);
    // false for non-file rows so callers can fall through to activation.
    function revealCurrent(): bool {
        if (appList.currentIndex < 0 || appList.currentIndex >= rows.length)
            return false;
        const row = rows[appList.currentIndex];
        if (!row || row.kind !== "file")
            return false;
        close();
        try {
            filesProv.reveal(row);
        } catch (e) {}
        return true;
    }

    // ---- preview plumbing ----------------------------------------------
    // Selected row's absolute path when it is a file row, else "".
    function currentFilePath(): string {
        const idx = appList.currentIndex;
        if (idx < 0 || idx >= rows.length)
            return "";
        const r = rows[idx];
        if (!r || r.kind !== "file" || !r.data || !r.data.path)
            return "";
        const p = String(r.data.path);
        return p[0] === "/" ? p : "";
    }

    // Ctrl+Space: toggle the preview for the selected file. A second press
    // on the same file closes it (Finder Quick Look parity); a press on a
    // different file switches renderer as needed.
    function togglePreview(): void {
        const p = root.currentFilePath();
        if (p === "")
            return;
        if (root.previewOpen) {
            root.previewOpen = false;
            return;
        }
        if (root.sushiWindowOpen && root.sushiPath === p) {
            root.closeSushi();
            return;
        }
        root.openPreviewFor(p);
    }

    // Esc layering: close the preview first, the launcher only when nothing
    // was open. Returns true when something was dismissed.
    function dismissPreview(): bool {
        let did = false;
        if (root.previewOpen) {
            root.previewOpen = false;
            did = true;
        }
        if (root.sushiWindowOpen) {
            root.closeSushi();
            did = true;
        }
        return did;
    }

    // Open the right surface for p and drop the other one.
    function openPreviewFor(p: string): void {
        const kind = previewPane.classifyPath(p);
        if (kind === "sushi" && root.sushiAvailable) {
            if (root.previewOpen)
                root.previewOpen = false;
            if (root.sushiPath !== p)
                root.showSushi(p);
            return;
        }
        if (root.sushiWindowOpen)
            root.closeSushi();
        previewPane.path = p;
        root.previewOpen = true;
    }

    // Selection moved while something is open: follow it (Finder Quick Look
    // walks the list with the panel up). Closes when the selection leaves the
    // file rows, e.g. after deleting the `/` prefix.
    function syncPreview(): void {
        if (!root.previewOpen && !root.sushiWindowOpen)
            return;
        const p = root.currentFilePath();
        if (p === "") {
            root.dismissPreview();
            return;
        }
        const kind = previewPane.classifyPath(p);
        if (kind === "sushi" && root.sushiAvailable) {
            if (root.previewOpen)
                root.previewOpen = false;
            if (root.sushiPath !== p)
                root.showSushi(p);
            return;
        }
        if (root.sushiWindowOpen)
            root.closeSushi();
        previewPane.path = p;
        root.previewOpen = true;
    }

    // Coalesced (80ms) so holding an arrow key does not fire one D-Bus
    // ShowFile per row.
    function showSushi(p: string): void {
        root.sushiPath = p;
        sushiDebounce.restart();
    }

    function closeSushi(): void {
        sushiDebounce.stop();
        const wasOpen = root.sushiWindowOpen || root.sushiPath !== "";
        root.sushiPath = "";
        if (wasOpen)
            Quickshell.execDetached([root.sushiScript, "close"]);
    }

    // ---- PDF paging keys (vim) ------------------------------------------
    // Routed from both key handlers below (search input and list), because
    // the pane never takes focus — Quick Look stays usable while the search
    // box keeps the caret, which is the whole point of it.
    //
    // Ctrl+F/Ctrl+D forward, Ctrl+B/Ctrl+U back, Ctrl+Home/Ctrl+End to the
    // ends. They are checked BEFORE the selection keys because Ctrl+F/Ctrl+D
    // are otherwise unbound here, but Ctrl+Home/End would otherwise be
    // swallowed by the plain Home/End "first/last row" branch below.
    // Returns true when the key was a page motion, so the caller can accept
    // it and stop.
    //
    // Everything still works with the preview closed (Ctrl+F types nothing),
    // because a plain Ctrl+F/Ctrl+D/Ctrl+B/Ctrl+U has no other meaning in
    // this launcher.
    function tryPdfPageKey(event): bool {
        if (!root.previewOpen)
            return false;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        if (!ctrl)
            return false;
        if (event.key === Qt.Key_F || event.key === Qt.Key_D) {
            event.accepted = true;
            previewPane.nextPage();
            return true;
        }
        if (event.key === Qt.Key_B || event.key === Qt.Key_U) {
            event.accepted = true;
            previewPane.prevPage();
            return true;
        }
        if (event.key === Qt.Key_Home) {
            event.accepted = true;
            previewPane.pdf && previewPane.pdf.firstPage();
            return true;
        }
        if (event.key === Qt.Key_End) {
            event.accepted = true;
            previewPane.pdf && previewPane.pdf.lastPage();
            return true;
        }
        return false;
    }

    function launchRow(row, terminal): void {
        if (!row)
            return;
        // Section headers are never activatable (see above).
        if (row.kind === "header")
            return;
        if (row.kind === "control") {
            const t = row.ipcTarget;
            const v = row.ipcVerb;
            close();
            if (t) {
                // Proven precedent: WallpaperMenu.qml pick branch
                // (close() then qs ipc call).
                Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", t, v]);
                return;
            }
            // External app/script row (GNOME Settings, HTML guide): run via
            // sh -c, RunnerProvider precedent. Both scripts self-toggl.
            if (row.cmd)
                Quickshell.execDetached(["sh", "-c", row.cmd]);
            return;
        }
        if (row.kind === "calc") {
            close();
            try {
                calcProv.activate(row);
            } catch (e) {}
            return;
        }
        if (row.kind === "window") {
            close();
            try {
                windowsProv.activate(row);
            } catch (e) {}
            return;
        }
        if (row.kind === "open") {
            // Pinned "Open" row: focus that app's focused window (or its first
            // one). data.ids already has the focused id at index 0.
            close();
            try {
                openApps.activate(row);
            } catch (e) {}
            return;
        }
        if (row.kind === "clip") {
            close();
            try {
                clipProv.activate(row);
            } catch (e) {}
            return;
        }
        if (row.kind === "web") {
            close();
            try {
                webProv.activate(row);
            } catch (e) {}
            return;
        }
        if (row.kind === "file") {
            close();
            try {
                filesProv.activate(row);
            } catch (e) {}
            return;
        }
        if (row.kind === "run") {
            close();
            try {
                runnerProv.activate(row, terminal === true);
            } catch (e) {}
            return;
        }
        if (row.kind === "symbol") {
            close();
            try {
                symbolsProv.activate(row);
            } catch (e) {}
            return;
        }
        if (row.kind === "todo") {
            close();
            try {
                todoProv.activate(row);
            } catch (e) {}
            return;
        }
        if (row.kind === "bookmark") {
            close();
            try {
                bookmarksProv.activate(row);
            } catch (e) {}
            return;
        }
        if (row.kind === "session") {
            close();
            try {
                sessionsProv.activate(row);
            } catch (e) {}
            return;
        }
        if (row.kind === "media") {
            close();
            try {
                mediaActions.activate(row);
            } catch (e) {}
            return;
        }
        if (row.kind === "mode") {
            const d = row.data || {};
            // Prefix mode (key presence, NOT truthiness: "" is Applications):
            // switch the query text + refocus, do NOT call activate.
            // Immediate (bypasses the typing debounce): a mode switch
            // must show now, not 300ms later. The text assignment fires
            // onTextChanged (restarting the timer); the lines below
            // override it back to an instant rebuild.
            if ("prefix" in d) {
                searchInput.text = d.prefix;
                pendingQuery = d.prefix;
                query = d.prefix;
                debounceTimer.stop();
                rebuild();
                searchInput.forceActiveFocus();
                return;
            }
            // IPC row: exactly-once — exec here, do NOT call activate
            // (activate would toggle a second time).
            if (d.ipcTarget) {
                const vt = d.ipcVerb || "toggle";
                close();
                Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", d.ipcTarget, vt]);
                return;
            }
            close();
            try {
                modesProv.activate(row);
            } catch (e) {}
            return;
        }
        if (!row.entry)
            return;
        if (row.kind === "action" && row.action) {
            row.action.execute();
        } else if (row.entry.runInTerminal) {
            // fuzzel terminal="alacritty -e"; execute() would skip the terminal.
            Quickshell.execDetached({
                "command": [root.terminal, "-e"].concat(row.entry.command),
                "workingDirectory": row.entry.workingDirectory
            });
        } else {
            row.entry.execute();
        }
        close();
    }

    function moveSelection(delta: int): void {
        if (rows.length === 0)
            return;
        // Keyboard navigation counts as intent: re-arm hover so subsequent
        // mouse movement takes selection again.
        hoverArmed = true;
        let idx = appList.currentIndex + delta;
        if (idx < 0)
            idx = 0;
        if (idx >= rows.length)
            idx = rows.length - 1;
        // Section headers are ListView section delegates, not model rows, so
        // they never occupy an index; defensively skip any inline header
        // marker so headers stay non-selectable.
        if (delta !== 0) {
            const step = delta > 0 ? 1 : -1;
            while (idx >= 0 && idx < rows.length && rows[idx] && rows[idx].kind === "header") {
                idx += step;
                if (idx < 0) {
                    idx = 0;
                    break;
                }
                if (idx >= rows.length) {
                    idx = rows.length - 1;
                    break;
                }
            }
        }
        appList.currentIndex = idx;
        appList.positionViewAtIndex(idx, ListView.Contain);
    }

    function goFirst(): void {
        if (rows.length === 0)
            return;
        // Keyboard navigation counts as intent (hoverArmed parity).
        hoverArmed = true;
        let idx = 0;
        // Section headers are delegates, not rows; defensively skip any
        // inline header marker so headers stay non-selectable.
        while (idx < rows.length && rows[idx] && rows[idx].kind === "header")
            idx++;
        if (idx >= rows.length)
            idx = 0;
        appList.currentIndex = idx;
        appList.positionViewAtIndex(idx, ListView.Contain);
    }

    function goLast(): void {
        if (rows.length === 0)
            return;
        hoverArmed = true;
        let idx = rows.length - 1;
        while (idx >= 0 && rows[idx] && rows[idx].kind === "header")
            idx--;
        if (idx < 0)
            idx = rows.length - 1;
        appList.currentIndex = idx;
        appList.positionViewAtIndex(idx, ListView.Contain);
    }

    // Async fan-in: cache latestRows then rebuild for the current query.
    // MediaActions has no resultsChanged (rows()+activate only) — no
    // connection by design.
    Connections {
        target: calcProv
        function onResultsChanged() {
            root.onProvResults("calc", calcProv);
        }
    }
    Connections {
        target: windowsProv
        function onResultsChanged() {
            root.onProvResults("window", windowsProv);
        }
    }
    Connections {
        target: clipProv
        function onResultsChanged() {
            root.onProvResults("clip", clipProv);
        }
    }
    Connections {
        target: webProv
        function onResultsChanged() {
            root.onProvResults("web", webProv);
        }
    }
    Connections {
        target: filesProv
        function onResultsChanged() {
            root.onProvResults("file", filesProv);
        }
    }
    Connections {
        target: runnerProv
        function onResultsChanged() {
            root.onProvResults("run", runnerProv);
        }
    }
    Connections {
        target: symbolsProv
        function onResultsChanged() {
            root.onProvResults("symbol", symbolsProv);
        }
    }
    Connections {
        target: todoProv
        function onResultsChanged() {
            root.onProvResults("todo", todoProv);
        }
    }
    Connections {
        target: bookmarksProv
        function onResultsChanged() {
            root.onProvResults("bookmark", bookmarksProv);
        }
    }
    Connections {
        target: modesProv
        function onResultsChanged() {
            root.onProvResults("mode", modesProv);
        }
    }
    Connections {
        target: sessionsProv
        function onResultsChanged() {
            root.onProvResults("session", sessionsProv);
        }
    }

    // Sushi bridge (hybrid preview). Availability is probed once per load;
    // the debounce coalesces selection-follow ShowFile calls.
    Timer {
        id: sushiDebounce
        interval: 80
        repeat: false
        onTriggered: {
            if (root.sushiPath === "")
                return;
            Quickshell.execDetached([root.sushiScript, "show", root.sushiPath]);
        }
    }

    Process {
        id: sushiCheck
        running: true
        command: ["sh", "-c", "command -v sushi >/dev/null 2>&1"]
        onExited: (exitCode) => root.sushiAvailable = (exitCode === 0)
    }

    // Focus acquisition: Exclusive gives the layer SURFACE keys, but the Qt
    // item tree still needs activeFocus on searchInput before typed text
    // lands in the field. A single 60ms shot can fire before the surface
    // maps (forceActiveFocus is then a silent no-op and every later key is
    // lost to whatever holds focus underneath — blinking cursor
    // notwithstanding, since cursorVisible is unconditional). Retry until
    // the input holds focus; stops itself. open()/onVisibleChanged restart.
    Timer {
        id: focusTimer
        interval: 60
        repeat: true
        property int attempts: 0
        onTriggered: {
            if (searchInput.activeFocus) {
                stop();
                return;
            }
            searchInput.forceActiveFocus();
            attempts++;
            if (attempts >= 20)
                stop();
        }
    }

    // Typing debounce (see pendingQuery): filtering runs 300ms after the
    // last keystroke; the input itself is never delayed.
    Timer {
        id: debounceTimer
        interval: 300
        repeat: false
        onTriggered: {
            root.query = root.pendingQuery;
            root.rebuild();
        }
    }

    PanelWindow {
        id: win
        visible: root.isOpen
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        // fuzzel layer=overlay; take no bar space.
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "sunset-launcher"
        // File-drag pass-through: the fullscreen input region that gives
        // click-outside-to-close ALSO swallows Wayland drag-motion, so the
        // app under the cursor never becomes the drop target. While a file
        // drag is in flight the input region shrinks to the card only —
        // everything outside passes through to the windows below and can
        // accept the drop. Restores to fullscreen (null) when idle.
        mask: root.dragActive ? cardMask : null
        Region {
            id: cardMask
            item: card
        }
        // Re-acquire input focus whenever the surface (re)maps: the IPC
        // open() runs before the compositor maps the layer, so the open()
        // focusTimer shot alone can land too early.
        onVisibleChanged: {
            if (visible) {
                focusTimer.attempts = 0;
                focusTimer.restart();
            }
        }

        // Click outside the card closes (fuzzel click-to-close parity).
        // Suppressed while a file drag is in flight so the release that
        // ends a cancelled drag doesn't instantly close the menu.
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (!root.dragActive)
                    root.close();
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            // With the pane open the card moves left by half the group
            // extension so card+pane stay centered as one unit.
            anchors.horizontalCenterOffset: root.previewOpen ? -(root.previewPaneWidth + 12) / 2 : 0
            width: root.cardWidth
            // Content-driven: input + list + empty-state + margins/gaps.
            // All terms are intrinsic (no parent-height cycle).
            height: inputRow.height + appList.height + emptyLabel.height + 56
            radius: 12 // fuzzel [border] radius (intentional taste.md exception)
            color: root.bg
            border.width: 2 // fuzzel [border] width
            border.color: root.accent
            // Micro-animation: subtle entrance (opacity 150ms OutCubic +
            // scale 0.96->1 180ms OutBack overshoot 1.2 + y -6->0).
            // Close stays instant (visible flips with isOpen, <200ms).
            // Pinned Controls IPC dispatch (launchRow control branch) untouched.
            transformOrigin: Item.Center
            scale: root.isOpen ? 1.0 : 0.96
            opacity: root.isOpen ? 1 : 0
            transform: Translate {
                y: root.isOpen ? 0 : -6
                Behavior on y {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                Row {
                    id: inputRow
                    width: parent.width
                    spacing: 8

                    Text {
                        // fuzzel prompt="  "
                        text: "  "
                        font.family: root.fontFamily
                        font.pointSize: 13
                        font.bold: true // fuzzel use-bold=yes
                        color: root.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Item {
                        width: parent.width - 32 - counterText.width - 16
                        height: 30
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: searchInput.text === ""
                            text: "Search applications..."
                            font.family: root.fontFamily
                            font.pointSize: 13
                            color: root.muted
                            elide: Text.ElideRight
                        }

                        TextInput {
                            id: searchInput
                            focus: true
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: root.fontFamily
                            font.pointSize: 13
                            font.bold: true
                            color: root.textCol
                            cursorVisible: true
                            onTextChanged: {
                                // Debounced (see pendingQuery): input stays
                                // live, filtering follows after 300ms idle.
                                root.pendingQuery = text;
                                debounceTimer.restart();
                            }
                            Keys.onPressed: (event) => {
                                const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                                // PDF paging wins over everything below
                                // (Ctrl+Home/End would otherwise hit the
                                // first/last row branch).
                                if (root.tryPdfPageKey(event))
                                    return;
                                if (event.key === Qt.Key_Escape) {
                                    event.accepted = true;
                                    // Esc peels the preview first; the
                                    // launcher only closes when nothing was
                                    // open (Finder Quick Look layering).
                                    if (!root.dismissPreview())
                                        root.close();
                                } else if (ctrl && event.key === Qt.Key_Space) {
                                    // Quick Look chord. Plain Space stays a
                                    // space: multi-word file queries need it.
                                    event.accepted = true;
                                    root.togglePreview();
                                } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P))) {
                                    event.accepted = true;
                                    root.moveSelection(-1);
                                } else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N))) {
                                    event.accepted = true;
                                    root.moveSelection(1);
                                } else if (event.key === Qt.Key_PageUp) {
                                    event.accepted = true;
                                    root.moveSelection(-10);
                                } else if (event.key === Qt.Key_PageDown) {
                                    event.accepted = true;
                                    root.moveSelection(10);
                                } else if (event.key === Qt.Key_Home) {
                                    event.accepted = true;
                                    root.goFirst();
                                } else if (event.key === Qt.Key_End) {
                                    event.accepted = true;
                                    root.goLast();
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    // Enter always acts on fresh rows: flush
                                    // any debounced (not yet filtered) typing.
                                    root.flushQuery();
                                    // Shift+Enter on runner rows runs in terminal.
                                    if ((event.modifiers & Qt.ShiftModifier) !== 0) {
                                        const idx = appList.currentIndex;
                                        if (idx >= 0 && idx < root.rows.length && root.rows[idx] && root.rows[idx].kind === "run") {
                                            event.accepted = true;
                                            root.launchRow(root.rows[idx], true);
                                            return;
                                        }
                                    }
                                    // Ctrl+Enter reveals the row's file in
                                    // the default file manager (file rows
                                    // only; other rows fall through to
                                    // normal activation). Checked after
                                    // Shift so Shift+Enter terminal-run keeps
                                    // priority on runner rows.
                                    if ((event.modifiers & Qt.ControlModifier) !== 0) {
                                        event.accepted = true;
                                        if (!root.revealCurrent())
                                            root.activateCurrent();
                                        return;
                                    }
                                    event.accepted = true;
                                    root.activateCurrent();
                                }
                            }
                            // Tab cycles input <-> list (focus trap); plain
                            // j/k still type (Ctrl+J/K navigate, above).
                            Keys.onTabPressed: (event) => {
                                event.accepted = true;
                                appList.forceActiveFocus();
                            }
                            Keys.onBacktabPressed: (event) => {
                                event.accepted = true;
                                appList.forceActiveFocus();
                            }
                        }
                    }

                    Text {
                        id: counterText
                        // Position indicator (Raycast-style "3 of 114"):
                        // "<current+1>/<rows.length>", via updateCounter().
                        text: root.counterStr
                        font.family: root.fontFamily
                        font.pointSize: 11
                        color: root.muted
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    id: appList
                    width: parent.width
                    height: root.estListHeight()
                    clip: true
                    model: root.rows
                    keyNavigationWraps: true
                    onCurrentIndexChanged: {
                        root.updateCounter();
                        root.syncPreview();
                    }
                    // Staggered list fade + highlight slide (micro-animation):
                    // delegates fade on add, displaced rows glide.
                    // Pinned Controls IPC dispatch (launchRow) untouched.
                    add: Transition {
                        NumberAnimation {
                            properties: "opacity"
                            from: 0
                            to: 1
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }
                    displaced: Transition {
                        NumberAnimation {
                            properties: "opacity,y"
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }
                    // Section headers: "Applications" above app/action rows,
                    // "Controls" above control rows (row.section; provider
                    // rows add their own sections). Section delegates are not
                    // model items: they never occupy currentIndex, so
                    // moveSelection/activateCurrent and the position counter
                    // skip them by construction. Filtered queries interleave
                    // by score, so headers may repeat at section boundaries
                    // there; the empty query is grouped (controls first,
                    // then apps alpha).
                    section.property: "section"
                    section.criteria: ViewSection.FullString
                    section.labelPositioning: ViewSection.InlineLabels
                    section.delegate: Item {
                        width: appList.width
                        height: 20
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: section
                            font.family: root.fontFamily
                            font.pointSize: 9
                            font.bold: true
                            color: root.muted
                        }
                    }
                    Keys.onPressed: (event) => {
                        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                        // PDF paging wins over everything below (list-focus
                        // parity; Ctrl+Home/End would otherwise hit the
                        // first/last row branch).
                        if (root.tryPdfPageKey(event))
                            return;
                        if (event.key === Qt.Key_Escape) {
                            event.accepted = true;
                            // Preview peels first (searchInput parity).
                            if (!root.dismissPreview())
                                root.close();
                        } else if (ctrl && event.key === Qt.Key_Space) {
                            event.accepted = true;
                            root.togglePreview();
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || (ctrl && event.key === Qt.Key_P)) {
                            event.accepted = true;
                            root.moveSelection(-1);
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J || (ctrl && event.key === Qt.Key_N)) {
                            event.accepted = true;
                            root.moveSelection(1);
                        } else if (event.key === Qt.Key_PageUp) {
                            event.accepted = true;
                            root.moveSelection(-10);
                        } else if (event.key === Qt.Key_PageDown) {
                            event.accepted = true;
                            root.moveSelection(10);
                        } else if (event.key === Qt.Key_Home) {
                            event.accepted = true;
                            root.goFirst();
                        } else if (event.key === Qt.Key_End) {
                            event.accepted = true;
                            root.goLast();
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            // Enter acts on fresh rows even mid-debounce.
                            root.flushQuery();
                            // Ctrl+Enter reveals the row's file in the
                            // default file manager (searchInput parity);
                            // non-file rows activate as normal.
                            if ((event.modifiers & Qt.ControlModifier) !== 0) {
                                event.accepted = true;
                                if (!root.revealCurrent())
                                    root.activateCurrent();
                            } else {
                                event.accepted = true;
                                root.activateCurrent();
                            }
                        } else if (event.key === Qt.Key_Space) {
                            event.accepted = true;
                            root.activateCurrent();
                        } else if (event.text !== "" && (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0) {
                            // Keyboard-first (list-focus parity):
                            // typing while the list holds focus (e.g. after
                            // Tab, or a focus fight with the input) resumes
                            // the query instead of dying silently. Plain j/k
                            // navigate above; Space activates above.
                            event.accepted = true;
                            searchInput.text += event.text;
                            searchInput.forceActiveFocus();
                        }
                    }
                    Keys.onTabPressed: (event) => {
                        event.accepted = true;
                        searchInput.forceActiveFocus();
                    }
                    Keys.onBacktabPressed: (event) => {
                        event.accepted = true;
                        searchInput.forceActiveFocus();
                    }

                    delegate: Rectangle {
                        id: row
                        property var rowData: modelData
                        property bool isAction: rowData && rowData.kind === "action"
                        property bool isControl: rowData && rowData.kind === "control"
                        // Draggable file row: kind "file" with a real absolute
                        // path in data.path (cheatsheet/info rows carry {}).
                        property bool isFileRow: rowData && rowData.kind === "file" && rowData.data && rowData.data.path && String(rowData.data.path)[0] === "/"
                        // External Wayland drag (file managers, browsers,
                        // chat drops, terminals): text/uri-list + text/plain
                        // fallback. Drag.Automatic + DragHandler(target:null)
                        // so the row itself never moves — the drag leaves the
                        // Overlay layer to whatever app accepts the drop.
                        // Successful drop closes the menu; a cancelled drag
                        // (IgnoreAction) keeps it open + refocuses the input.
                        Drag.dragType: Drag.Automatic
                        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
                        Drag.proposedAction: Qt.CopyAction
                        Drag.mimeData: isFileRow ? ({
                            "text/uri-list": root.fileUrlFor(rowData.data.path) + "\r\n",
                            "text/plain": String(rowData.data.path)
                        }) : ({})
                        Drag.active: fileDragHandler.active
                        Drag.onDragStarted: root.dragActive = true
                        Drag.onDragFinished: (dropAction) => {
                            root.dragActive = false;
                            if (dropAction !== Qt.IgnoreAction)
                                root.close();
                            else
                                searchInput.forceActiveFocus();
                        }
                        // Two-line rows (detail present) get the tall height
                        // so the detail line is never clipped. Single-line
                        // rows keep the fuzzel line-height=32 parity.
                        property bool hasDetail: root.detailFor(rowData) !== ""
                        width: appList.width
                        height: hasDetail ? root.rowHeightTall : root.rowHeight
                        radius: 6
                        color: appList.currentIndex === index ? root.accent : "transparent"
                        // Delegate fade only (no y/scale anims — perf: Smoothed +
                        // press-scale removed, ListView displaced covers glide).
                        opacity: 1
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 120
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            // Nerd Font glyph OR themed icon. Rows carry `glyph` when they want a
                            // codepoint instead of an asset (the pinned "Open"
                            // section), because the icon set here is stroke SVG
                            // and a Nerd Font glyph is what the rest of the shell
                            // already uses for these categories. Both are 22px
                            // cells in a 10px-gapped row, so they line up.
                            Item {
                                implicitWidth: 22
                                implicitHeight: 22
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    visible: !!(row.rowData && row.rowData.glyph)
                                    text: (row.rowData && row.rowData.glyph) ? row.rowData.glyph : ""
                                    font.family: root.fontFamily
                                    // 15pt lands the glyph on the same optical
                                    // size as a 22px SVG icon; the private-use
                                    // area has no fallback font, so a missing
                                    // codepoint would silently collapse to nothing.
                                    font.pointSize: 15
                                    font.bold: true
                                    // iconCol, not textCol: matches the stroke SVG
                                    // the IconImage below renders from Theme.iconDir.
                                    // Selected rows invert to onAccent, because there
                                    // the glyph sits ON an accent fill.
                                    color: appList.currentIndex === index ? root.selText : root.iconCol
                                }

                                IconImage {
                                    anchors.fill: parent
                                    // icons-enabled=yes (icon-theme Colloid) for apps;
                                    // controls use assets/icons/ basenames via Theme.iconDir.
                                    visible: !(row.rowData && row.rowData.glyph)
                                    source: root.iconSourceFor(row.rowData)
                                    onStatusChanged: if (status === Image.Error) source = "file://" + Theme.iconDir + "logo.svg"
                                }
                            }

                            Column {
                                width: parent.width - 40
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                Text {
                                    width: parent.width
                                    text: {
                                        if (!row.rowData)
                                            return "";
                                        if (row.rowData.name)
                                            return row.rowData.name;
                                        if (!row.rowData.entry)
                                            return "";
                                        if (row.isAction && row.rowData.action)
                                            return row.rowData.entry.name + " → " + row.rowData.action.name;
                                        return row.rowData.entry.name;
                                    }
                                    font.family: root.fontFamily
                                    font.pointSize: 11
                                    font.bold: true
                                    color: appList.currentIndex === index ? root.selText : root.textCol
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    visible: text !== ""
                                    // detailFor() parity with hasDetail above.
                                    text: root.detailFor(row.rowData)
                                    font.family: root.fontFamily
                                    font.pointSize: 9
                                    color: appList.currentIndex === index ? root.selText : root.muted
                                    opacity: appList.currentIndex === index ? 0.85 : 1.0
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            hoverEnabled: true
                            // Gated: a resting cursor must not steal selection
                            // on open (delegate appears under it, firing
                            // onEntered with zero user input). Armed by first
                            // explicit mouse movement or keyboard nav.
                            onEntered: if (root.hoverArmed) appList.currentIndex = index
                            onPositionChanged: root.hoverArmed = true
                            // Click implies intent: arm + select regardless of
                            // armed state; double-click activates as before.
                            // File rows also pre-snapshot the drag image here
                            // (press precedes the DragHandler threshold, so
                            // the image is ready before Drag.active flips —
                            // setting imageSource after the drag starts is a
                            // no-op per the Drag docs).
                            onPressed: {
                                root.hoverArmed = true;
                                if (row.isFileRow) {
                                    row.grabToImage(function(result) {
                                        row.Drag.imageSource = result.url;
                                    });
                                }
                            }
                            onClicked: {
                                appList.currentIndex = index;
                                searchInput.forceActiveFocus();
                            }
                            onDoubleClicked: root.activateCurrent()
                        }

                        // External-drag sensor for file rows only (target:null
                        // = detect, never move). Disabled for every other
                        // kind so clicks/double-clicks there are untouched.
                        // Coexists with rowMouse: a press+release without
                        // motion stays a click; press+move past the system
                        // threshold flips active -> Drag.active starts the
                        // Wayland drag. Selects the row on activation so
                        // keyboard and drag agree on what's being dragged.
                        DragHandler {
                            id: fileDragHandler
                            enabled: row.isFileRow
                            target: null
                            acceptedButtons: Qt.LeftButton
                            onActiveChanged: {
                                if (active) {
                                    root.hoverArmed = true;
                                    appList.currentIndex = index;
                                }
                            }
                        }
                    }
                }

                Text {
                    id: emptyLabel
                    visible: root.rows.length === 0
                    height: visible ? implicitHeight : 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "No match"
                    font.family: root.fontFamily
                    font.pointSize: 11
                    color: root.muted
                }
            }
        }

        // Quick Look pane (Ctrl+Space), sibling of the card. It is part of
        // this PanelWindow, so the surface keeps Exclusive keyboard focus and
        // the launcher stays fully interactive while the preview is up.
        // Placed right of the card, height-matched, click-swallowing (see the
        // component) so it never triggers click-outside-to-close.
        PreviewPane {
            id: previewPane
            anchors.left: card.right
            anchors.leftMargin: 12
            anchors.top: card.top
            width: root.previewPaneWidth
            height: card.height
            visible: root.previewOpen
            opacity: root.previewOpen ? 1 : 0
            sushiAvailable: root.sushiAvailable
            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on width {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        // Ctrl+Space parity for scripts/tests: toggles the preview for the
        // currently selected row (no-op unless it is a file row).
        function preview(): void {
            root.togglePreview();
        }
    }
}
