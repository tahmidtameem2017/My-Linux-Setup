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
//     Ctrl+Enter reveals a file row in the default file manager;
//     Ctrl+C copies a file row to the clipboard — contents for
//     text/image types, path string otherwise;
//     Ctrl+T opens a terminal in a file row's own directory — a
//     directory row starts the shell there, a file row in its parent
//     folder),
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
//   Bookmark add/open/delete/rename (keyboard-first, see
//     BookmarksProvider.qml header for the contract): type URL →
//     Enter to bookmark → later type part of title → Enter opens in
//     browser; `@ <site> -bookmark` bookmarks straight from web mode
//     (Enter saves, no % needed); `%` mode keeps the create-row for
//     any non-empty query; rename is `%rename <needle> to <new name>`
//     + Enter on a Rename row (rewrites the title only — url, icon
//     and folder survive).
//   Deleting a bookmark: highlight it and press Delete — the row
//     vanishes in place and the menu STAYS OPEN so several can be
//     removed in a row (deletion is not a dismissal, the Ctrl+C/copy
//     precedent). deleteCurrentBookmark() only ever removes a real
//     saved bookmark (kind "bookmark", data.action "open"); the
//     create/delete/rename rows are commands, not bookmarks, and no
//     other kind is touched, so Delete on an app/control/file row
//     keeps its default. In the search box the Delete key applies
//     only with the caret at the END of the query (mid-caret it
//     forward-deletes a character, so an in-progress filter is never
//     clobbered); in the list it applies at any caret. `%delete
//     <needle>` + Enter on a Delete row still works too (same
//     removeAt path) for deleting by name without highlighting.
//     Bookmark rows carry bookmark.svg; imported bookmarks carry
//     their browser favicon instead (no network fetching).
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
// Ctrl+Tab seeds a site search (2026-10-05): with a row highlighted in the
//   "@" site list, or a saved bookmark whose URL maps to a known site, the
//   query becomes "@<bang> " and the caret sits after the space, so you type
//   straight into a search of THAT site instead of opening its homepage and
//   hunting for its search box. It fires only when it can produce a real seed
//   and otherwise falls through to plain Tab — plain Tab is the
//   input<->list focus trap, so hijacking it unconditionally would break
//   keyboard navigation on every non-site row. Ctrl+Shift+Tab is a synonym.
//   The seed goes through applyPrefix() (the same path the ";" mode rows and
//   websearch take), so it rebuilds immediately and refocuses the input.
//   Seed text is owned by WebProvider.seedFor/bangForUrl, not here: the site
//   table is the only place that knows the canonical bang.
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
//      (also: open, close, websearch, seedSiteSearch)

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
    readonly property string configEditorScript: setupHome + "/scripts/config-editor.sh"
    readonly property string sushiScript: setupHome + "/scripts/sushi-preview.sh"
    readonly property string importBookmarksScript: setupHome + "/scripts/import-bookmarks.sh"

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

    // ---- pinned rows (2026-10-05) ---------------------------------------
    // Pinning is a launcher-row feature, so the store lives here and NOT in a
    // service: nothing outside the launcher reads it, and a service would add
    // a file for one array.
    //
    // Persisted so a pin survives a shell restart (the whole point of pinning
    // a favourite). FileView + setText, the BookmarksProvider precedent in
    // this same directory — NOT a tmp+rename: FileView sits on
    // QFileSystemWatcher, which watches the INODE, so os.replace() would
    // silently kill the watch and the list would only reload on a restart
    // (the write_watched() rule, see scripts/sync-external-theme.py).
    //
    // Same state dir as bookmarks.json (Theme.themeDir), which is what
    // BookmarksProvider spells out as its own stateDir — the two stores live
    // side by side and a third location for the same kind of data would be
    // one more thing to look for.
    readonly property string pinnedPath: Theme.themeDir + "/launcher-pins.json"
    // Pin identities, most-recent-first. See pinKeyFor() for the shapes:
    //   "app:<desktop-file-id>"      app + action rows share it, so pinning
    //                                 an app pins its action rows with it
    //   "control:<Control row name>" name is the key, not the index — the
    //                                 order of controlEntries is data and can
    //                                 move; an index would silently repoint
    // A pin whose app has been uninstalled is dropped on the next rebuild
    // (reconcilePins) rather than shown as a dead row.
    property var pinned: []
    property int pinsLoaded: 0
    property bool pinsDirReady: false

    // True while the contextual menu owns the keyboard. Set by shell.qml when
    // it routes rowMenuRequested to ContextMenu.openRow(), and cleared by the
    // shell again when the menu's own isOpen flips false. It gates the
    // focusTimer retry loop above, which would otherwise rip focus straight
    // back to the search input and leave the menu's own Up/Down/Enter dead.
    //
    // The shell owns both ends of this handshake because the launcher and
    // ContextMenu are sibling Scopes that cannot see each other — the same
    // reason rowMenuRequested is a signal. It is NOT a timeout on the
    // launcher side: a fixed delay would hand focus back while the menu was
    // still open (the user is reading it), which is the bug a timer
    // "fixes" into a different one.
    property bool menuOpen: false

    function markMenuOpen(): void {
        menuOpen = true;
    }

    // Menu went away: give the keyboard back, and restart the focus loop
    // markMenuOpen effectively suspended.
    function markMenuClosed(): void {
        if (!menuOpen)
            return;
        menuOpen = false;
        if (!isOpen)
            return; // launcher went with it; nothing to refocus
        focusTimer.attempts = 0;
        focusTimer.restart();
    }

    // Stable identity for a row, or "" when the row is not pinnable.
    //
    // Apps are keyed on the desktop-file id, not the name: the name is what
    // the user sees and therefore what they can change (a renamed .desktop
    // repoints the name), while the id is what actually identifies the
    // entry. An "action" row resolves to its parent app on purpose, so
    // pinning an app also keeps its action rows in the pinned block instead
    // of leaving orphans that filter back into the Applications section.
    //
    // Controls are keyed on the row NAME, not an index into controlEntries:
    // that array is data and its order changes (rows were reordered when
    // Instagram and Custom Editor were added), so an index would silently
    // repoint a pin at a different control.
    function pinKeyFor(row): string {
        if (!row)
            return "";
        if (row.kind === "app" || row.kind === "action") {
            if (row.entry && row.entry.id)
                return "app:" + row.entry.id;
            return "";
        }
        if (row.kind === "control" && row.name)
            return "control:" + row.name;
        return "";
    }

    function isPinned(row): bool {
        const k = root.pinKeyFor(row);
        if (k === "")
            return false;
        return root.pinned.indexOf(k) !== -1;
    }

    // Index of the first row with this pin key, or -1. Used after a rebuild to
    // put the selection back on the row the user actually acted on (see
    // togglePinCurrent). First match, because a pinned row exists twice — in
    // the Pinned section and in its normal section — and the top one is the
    // one that moved under the cursor.
    function indexOfPinKey(key: string): int {
        if (!key)
            return -1;
        for (let i = 0; i < root.rows.length; ++i)
            if (root.pinKeyFor(root.rows[i]) === key)
                return i;
        return -1;
    }

    function loadPinsText(txt: string): void {
        const t = (txt ?? "").trim();
        if (t === "") {
            root.pinned = [];
            pinsLoaded = 1;
            return;
        }
        try {
            const parsed = JSON.parse(t);
            // Defensive shape check: a hand-edited or truncated file must not
            // become a `pinned` array of arbitrary values that rowMenuItems
            // then has to defend against on every click.
            root.pinned = Array.isArray(parsed) ? parsed.filter(k => typeof k === "string") : [];
        } catch (e) {
            root.pinned = [];
        }
        pinsLoaded = 1;
    }

    function savePins(): void {
        if (!pinsDirReady)
            return;
        pinnedFile.setText(JSON.stringify(pinned));
    }

    // Toggle the highlighted row's pin. The launcher stays open (Ctrl+C/copy and
    // Delete precedent: an in-place edit is not a dismissal) so a second row
    // can be pinned without reopening.
    //
    // The selection must follow the ROW, not its old index. Pinning inserts a
    // new row at index 0 (the Pinned section) and unpinning removes one, so
    // restoring `idx` verbatim lands on a DIFFERENT row — pressing pin twice
    // in a row pinned a second control instead of undoing the first, which is
    // exactly what the end-to-end run caught.
    function togglePinCurrent(): void {
        const idx = appList.currentIndex;
        if (idx < 0 || idx >= rows.length)
            return;
        const key = root.pinKeyFor(rows[idx]);
        if (key === "")
            return;
        const next = root.pinned.slice();
        const at = next.indexOf(key);
        if (at !== -1)
            next.splice(at, 1);
        else
            // Most-recent-first, so re-pinning an app moves it back to the top
            // of the pinned block instead of leaving it where it was.
            next.unshift(key);
        root.pinned = next;
        root.savePins();
        root.rebuild();
        // Re-find the row by identity. When it is pinned there are now two
        // rows with this key (the Pinned one and the section copy), so take
        // the FIRST — the top of the list is where the user just acted.
        const moved = root.indexOfPinKey(key);
        const n = rows.length;
        appList.currentIndex = moved >= 0 ? moved : (n > 0 ? Math.min(idx, n - 1) : -1);
        root.updateCounter();
        searchInput.forceActiveFocus();
    }

    // Drop pins whose target no longer exists, so uninstalling an app cannot
    // leave a dead row at the top of the launcher forever. Runs on every
    // rebuild: it is O(pins) with no I/O (the app list is already loaded).
    function reconcilePins(): void {
        if (pinsLoaded !== 1 || root.pinned.length === 0)
            return;
        let dropped = false;
        const next = [];
        for (let i = 0; i < root.pinned.length; ++i) {
            const k = root.pinned[i];
            if (root.pinTargetExists(k)) {
                next.push(k);
            } else {
                dropped = true;
            }
        }
        if (dropped) {
            root.pinned = next;
            root.savePins();
        }
    }

    function pinTargetExists(key: string): bool {
        if (!key || key.indexOf("control:") === 0) {
            // A control pin is kept even when controlEntries changes: a
            // control is a shell feature, not an installed package, so a
            // missing one means the feature was renamed, and silently
            // deleting the pin would lose the user's intent.
            return true;
        }
        if (key.indexOf("app:") !== 0)
            return false;
        const id = key.slice(4);
        if (!id)
            return false;
        // Read the same source rebuild() does rather than a cached `apps`
        // local: that list is scoped to rebuild(), so a helper here cannot
        // see it, and a stale copy would keep a pin alive for an app that is
        // already uninstalled — the exact case reconcilePins exists for.
        const list = DesktopEntries.applications.values;
        for (let i = 0; i < list.length; ++i)
            if (list[i] && list[i].id === id)
                return true;
        return false;
    }

    // ---- contextual row menu (right click / F10, 2026-10-05) ------------
    //
    // One item set per highlighted row, chosen by the row's `kind` — so the
    // menu never offers an action the row cannot perform. Every item carries
    // its keyboard twin in the `hint`, which is the whole point for a
    // beginner: the mouse path and the key path are printed side by side, so
    // nobody has to learn one and discover the other later.
    //
    // Item shape consumed by ContextMenu.qml:
    //   { label, hint, op }         actionable; `op` is one of the closed
    //                                set in rowMenuItem() below
    //   { label, hint, disabled }   informational: rendered muted, skipped by
    //                                keyboard nav, inert on click
    //   { sep: true }               divider
    //
    // The menu is hosted by ContextMenu.qml, not a child of this card: it is
    // a top-level layer-shell surface, it positions in screen coordinates,
    // and it can take Exclusive keyboard focus without fighting the launcher's
    // own focusTimer. See ContextMenu.qml's header for the full reasoning.
    // This file reaches it by EMITTING rowMenuRequested, and shell.qml
    // routes it to contextMenu.openRow() — the same shape as
    // Bar.qml's contextMenuRequested, and mandatory rather than stylistic:
    // two sibling Scopes cannot read each other's properties, so a direct
    // `contextMenu.openRow(...)` call from here cannot resolve.
    function rowMenuItems(): var {
        // `appList` is a bare id (a ListView declared inside `win`), NOT a
        // property of root, so it MUST stay unqualified here: `root.appList`
        // is undefined and the whole function bails to [] — which is exactly
        // why an earlier build opened the help menu for every row.
        const idx = appList.currentIndex;
        if (idx < 0 || idx >= rows.length)
            return [];
        const row = rows[idx];
        if (!row || row.kind === "header")
            return [];
        const out = [];
        // Open is universal (every row kind has an activate() path — the same
        // Enter action launchRow runs) so it leads the menu in every case.
        const openLabel = row.kind === "bookmark" ? "Open in browser" : "Open";
        out.push({ "label": openLabel, "hint": "Enter", "op": "open" });

        // ---- file rows: the full set of file verbs, each with its chord ----
        // Guarded on a real absolute path, exactly like currentFilePath() and
        // the delegate's isFileRow: the `/`-mode cheatsheet rows carry data {}
        // and every one of these verbs is a no-op on them, so offering them
        // there would be a menu full of dead entries.
        if (row.kind === "file" && row.data && String(row.data.path || "")[0] === "/") {
            out.push({ "sep": true });
            out.push({ "label": "Preview", "hint": "Ctrl+Alt+Space", "op": "preview" });
            out.push({ "label": "Open in file manager", "hint": "Ctrl+Enter", "op": "reveal" });
            out.push({ "label": "Open terminal here", "hint": "Ctrl+T", "op": "terminal" });
            out.push({ "label": "Copy", "hint": "Ctrl+C", "op": "copy" });
        }

        // ---- app + action + control rows: pinning ----
        // Offered wherever pinKeyFor() can name the row, and the label flips
        // to Unpin once it is pinned — a menu that said "Pin to top" on an
        // already-pinned row would be a lie about its own state.
        if (root.pinKeyFor(row) !== "") {
            out.push({ "sep": true });
            out.push({
                "label": root.isPinned(row) ? "Unpin from top" : "Pin to top",
                "hint": "",
                "op": "pin"
            });
        }

        // ---- bookmarks: deletion (the Delete key's twin) ----
        // Only a real saved bookmark, not the create/rename/delete command
        // rows: deleteCurrentBookmark() guards on exactly this, and offering
        // "Delete bookmark" on the "Rename bookmark" row would be nonsense.
        if (row.kind === "bookmark" && row.data && row.data.action === "open") {
            out.push({ "sep": true });
            out.push({ "label": "Delete bookmark", "hint": "Delete", "op": "delete" });
        }
        return out;
    }

    // Right-click NOT on a row (the search box, or the space below the list):
    // the beginner menu. It is pure information plus one action, so every
    // legend row is `disabled` — nothing here pretends to be clickable.
    // The prefix list is derived from rebuild()'s prefixKind table rather
    // than retyped, so a new mode cannot be missing from the legend.
    readonly property var modePrefixes: [
        { "p": "=", "n": "Calculator" },
        { "p": "$", "n": "Windows" },
        { "p": ":", "n": "Clipboard" },
        { "p": "@", "n": "Web search" },
        { "p": "/", "n": "Files" },
        { "p": ">", "n": "Run a command" },
        { "p": ".", "n": "Symbols" },
        { "p": "!", "n": "Todo" },
        { "p": "%", "n": "Bookmarks" },
        { "p": ";", "n": "Modes & controls" }
    ]

    function helpMenuItems(): var {
        const out = [];
        out.push({ "label": "Type to search apps, files or the web", "hint": "", "disabled": true });
        out.push({ "sep": true });
        for (let i = 0; i < root.modePrefixes.length; ++i)
            out.push({
                "label": root.modePrefixes[i].p + "   " + root.modePrefixes[i].n,
                "hint": "",
                "disabled": true
            });
        out.push({ "sep": true });
        out.push({ "label": "Move between rows", "hint": "Up / Down", "disabled": true });
        out.push({ "label": "Open the highlighted row", "hint": "Enter", "disabled": true });
        // The two chords a beginner cannot guess, so they are printed here as
        // well as in the row menu.
        out.push({ "label": "Preview a file", "hint": "Ctrl+Alt+Space", "disabled": true });
        out.push({ "label": "This menu on any row", "hint": "F10", "disabled": true });
        out.push({ "sep": true });
        // The one real action: a way out of a launcher they are stuck in.
        out.push({ "label": "Close the launcher", "hint": "Esc", "op": "close" });
        return out;
    }

    // Execute one item of the contextual menu. Named after the IPC verb and
    // lives on the ROOT on purpose (2026-10-05): shell.qml's dispatch() calls
    // the verb name on the popup root, so a method that existed only inside
    // the IpcHandler is undefined there and the menu would silently do
    // nothing. The `op` allowlist is closed — an op the menu cannot produce
    // is dropped rather than guessed at.
    //
    // Everything here reuses the EXACT functions the matching key handler
    // calls (activateCurrent / togglePreview / revealCurrent /
    // copyCurrent / terminalCurrent / deleteCurrentBookmark / togglePinCurrent).
    // That is what keeps the mouse path and the keyboard path from ever
    // disagreeing: there is no second implementation of "reveal a file" here
    // to drift, only a second way to reach the one that already exists.
    function rowMenuItem(op: string): void {
        if (op === "open") {
            root.activateCurrent();
            return;
        }
        if (op === "close") {
            root.close();
            return;
        }
        if (op === "preview") {
            root.togglePreview();
            return;
        }
        if (op === "reveal") {
            root.revealCurrent();
            return;
        }
        if (op === "terminal") {
            root.terminalCurrent();
            return;
        }
        if (op === "copy") {
            // Copy deliberately keeps the menu's dismissal behaviour of the
            // chord it mirrors: copying is not a dismissal, so the launcher
            // stays open either way. Nothing to close here.
            root.copyCurrent();
            return;
        }
        if (op === "delete") {
            root.deleteCurrentBookmark();
            return;
        }
        if (op === "pin") {
            root.togglePinCurrent();
            return;
        }
    }

    // The help menu's own entry point (used by the `menu openRow` IPC verb
    // and by F10 when no row is highlighted). Named for the same reason as
    // rowMenuItem: the shim in shell.qml calls this exact name on the root.
    function helpMenu(): void {
        root.openContextMenu(root.helpMenuItems(), root.cardCentreX(), root.cardCentreY());
    }

    // ---- menu plumbing ---------------------------------------------------
    // Emitted, not called: shell.qml owns the eager ContextMenu (it has to be
    // eager — it owns the desktop input plane) and two sibling Scopes cannot
    // read each other's properties, so this is the only way across. Mirrors
    // Bar.qml's contextMenuRequested(x, y) exactly.
    signal rowMenuRequested(var items, real x, real y)

    // Centre of the card, in SCREEN coordinates (ContextMenu.openRow clamps in
    // screen space). `win` is anchored to all four edges of the output, so a
    // coordinate inside it IS a screen coordinate and no mapping call is
    // needed — the same assumption Bar.qml makes when it hands ContextMenu
    // `mouse.x` unscaled.
    //
    // It maps through the card rather than assuming the card is centred,
    // because the card moves LEFT when the Quick Look pane is open
    // (card.horizontalCenterOffset).
    readonly property int cardCentreX: card.x + Math.round(card.width / 2)
    readonly property int cardCentreY: card.y + Math.round(card.height / 2)

    function openContextMenu(list: var, sx: real, sy: real): void {
        if (!list || list.length === 0)
            return;
        root.rowMenuRequested(list, sx, sy);
    }

    // Right click on the highlighted row (F10 / Key_Menu). Anchored to the
    // card centre, not the mouse — see screenPointFor.
    function openRowMenu(): void {
        const list = root.rowMenuItems();
        // No actionable row (empty result list): fall back to the help menu
        // rather than opening nothing, so the chord is never a dead key.
        if (list.length === 0) {
            root.helpMenu();
            return;
        }
        root.openContextMenu(list, root.cardCentreX, root.cardCentreY);
    }

    // Right click anywhere in the launcher that is NOT a row: the search box
    // or the space below the list. Routed to the card backdrop's handler,
    // which is why the delegate consumes its own right click.
    function openHelpMenuAt(sx: real, sy: real): void {
        root.openContextMenu(root.helpMenuItems(), sx, sy);
    }
    // Browse-aware was the starting point, but the search field owns Space
    // (multi-word file queries like `/ quarterly report`), so the chord is a
    // modified Space and Space keeps typing. Two chords open it:
    //   Ctrl+Space      files mode only — routed through the `websearch`
    //                   IPC verb (websearch(): the bind is compositor-side,
    //                   so THIS handler never sees it), decided there
    //   Ctrl+Alt+Space  always, handled right here
    // The chord toggles:
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
        { "kind": "control", "name": "Config Editor", "keywords": "config editor niri settings gaps opacity corner radius focus ring column width animation duration input mouse touchpad acceleration tap scroll toggle tune adjust slider dropdown", "icon": "sliders.svg", "cmd": root.configEditorScript },
        { "kind": "control", "name": "Quick Settings", "keywords": "settings quick brightness volume dnd idle power profile", "icon": "settings.svg", "ipcTarget": "settings", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Wi-Fi", "keywords": "wifi wi-fi wireless network ssid connect disconnect forget rescan internet ethernet", "icon": "wifi.svg", "ipcTarget": "wifi", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Wallpaper", "keywords": "wallpaper background gallery random next theme", "icon": "wallpaper.svg", "ipcTarget": "wallpaper-menu", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Power", "keywords": "power lock suspend logout reboot shutdown quit", "icon": "power.svg", "ipcTarget": "power", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Volume", "keywords": "volume mixer audio sound sink mute", "icon": "volume.svg", "ipcTarget": "volume", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Now Playing", "keywords": "now playing media music track song mpris player spotify youtube mpv vlc", "icon": "media.svg", "ipcTarget": "now-playing", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Performance", "keywords": "performance monitor cpu gpu memory ram battery stats usage load perf island", "icon": "perf.svg", "ipcTarget": "perf", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Clipboard", "keywords": "clipboard history copy paste cliphist", "icon": "clipboard.svg", "ipcTarget": "clipboard", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Screenshot", "keywords": "screenshot capture region window screen scroll recording ocr redact annotate shot print camera", "icon": "camera.svg", "ipcTarget": "capture", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Calendar", "keywords": "calendar clock pomodoro timer date", "icon": "logo.svg", "ipcTarget": "calendar", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Crack the Whip", "keywords": "whip crack lash fun", "icon": "whip.svg", "ipcTarget": "whip", "ipcVerb": "toggle" },
        { "kind": "control", "name": "Do Not Disturb", "keywords": "dnd disturb silent mute notifications", "icon": "empty.svg", "ipcTarget": "notifications", "ipcVerb": "toggleSilent" },
        { "kind": "control", "name": "Import Bookmarks", "keywords": "import bookmarks browser brave chrome chromium firefox librewolf waterfox favicon icons sync pull in", "icon": "bookmark.svg", "cmd": root.importBookmarksScript }
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

    // Switch the launcher into one of its prefix modes (`@` web, `/` files,
    // `:` clipboard, …). Shared by the ";" mode rows and by websearch()
    // so the two cannot drift on the debounce handling below.
    //
    // Immediate (bypasses the typing debounce): a mode switch must show
    // now, not 300ms later. The text assignment fires onTextChanged
    // (restarting the timer); the lines below override it back to an
    // instant rebuild.
    function applyPrefix(p: string): void {
        searchInput.text = p;
        pendingQuery = p;
        query = p;
        debounceTimer.stop();
        rebuild();
        searchInput.forceActiveFocus();
    }

    // What Ctrl+Space does depends on where the query is pointing. PURE and
    // side-effect free on purpose: it is the one decision in this file that
    // decides between the user's two most-used launcher chords (browse a hit
    // vs search the web), it reads as one `if` in websearch(), and an untested
    // `if` on that shape is how the chord silently ended up bound to web search
    // in every mode. scripts/test_launcher_ctrl_space.py lifts this verbatim
    // out of the QML and runs it under node, the same way
    // test_launcher_site_seed.py does for WebProvider's site helpers.
    //
    // Returns "preview" or "search". `isOpen` is passed in rather than read:
    // the test has no panel. Closed means there is no query and nothing to
    // browse, so it is always a search (which also opens the launcher).
    function ctrlSpaceAction(isOpen: bool, q: string): string {
        const t = q.trim();
        // Files mode = the "/" entry of rebuild()'s prefixKind table, read off
        // the TRIMMED first character so a leading space cannot take you out.
        if (isOpen && t.length > 0 && t[0] === "/")
            return "preview";
        return "search";
    }

    // Ctrl+Space (niri/binds-quickshell.kdl -> `launcher websearch`).
    //
    // The action is chosen here rather than in a key handler, because niri binds
    // Ctrl+Space at the COMPOSITOR: the key event never reaches the QML
    // Keys.onPressed handlers at all, so a chord implemented only there is dead
    // code that reads correct. The IPC verb is the one path that bind actually
    // takes, so the decision has to live in this function.
    //
    //   files mode   -> Quick Look on the highlighted file row (the chord's
    //                   original job, kept because it is the fastest way to
    //                   eyeball a search hit; a no-op when no file row is
    //                   highlighted, e.g. one of the hint rows)
    //   anything else -> the launcher, opened already in web-search mode
    //                   (`open()` FIRST, because it resets query to "" — seeding
    //                   the prefix before that would be wiped)
    //
    // "@" is the web prefix (see rebuild()'s prefixKind table), so the search
    // path is the same WebProvider the typed "@" path uses, bangs included.
    //
    // Named `websearch`, not `openWebSearch`, because that is what makes the
    // IPC verb work: shell.qml's dispatch() calls the verb name on the popup
    // ROOT, and a function that exists only inside the IpcHandler is
    // undefined there (the same trap `themes set` -> runItem() has).
    function websearch(): void {
        if (root.ctrlSpaceAction(root.isOpen, root.query) === "preview") {
            root.togglePreview();
            return;
        }
        open();
        applyPrefix("@");
    }

    // Ctrl+Tab on a website row: drop a search on that site into the input,
    // so you go straight to typing instead of opening the homepage and
    // hunting for its search box. The text is "@<bang> " — bang plus a
    // trailing space, so the caret lands exactly where the words go.
    //
    // Works on the bare "@" site list AND on saved bookmarks ("%"), because
    // a bookmark is a website too — see WebProvider.bangForUrl, which maps
    // a bookmark's URL back to its site's canonical bang.
    //
    // Two rules make this safe rather than surprising:
    //   - It only fires when it can produce a real seed (site or matching
    //     bookmark). Otherwise it returns false and the key falls through to
    //     its plain meaning, because plain Tab is the input<->list focus trap
    //     (searchInput's onTabPressed) and hijacking that would break keyboard
    //     navigation for every row that is not a website.
    //   - The seed goes through applyPrefix(), the SAME path the ";" mode rows
    //     and Ctrl+Space's web search already use: immediate rebuild (a mode
    //     switch must show now, not 300ms later), pendingQuery kept in step,
    //     and the input refocused. Only the caret is added on top — placed
    //     after the trailing space so typing continues at the end.
    function seedSiteSearch(): bool {
        const idx = appList.currentIndex;
        if (idx < 0 || idx >= rows.length)
            return false;
        const row = rows[idx];
        if (!row)
            return false;
        let seed = "";
        // A site row from the "@" list carries its own canonical bang.
        if (row.kind === "web") {
            try {
                seed = webProv.seedFor(row);
            } catch (e) {
                seed = "";
            }
        } else if (row.kind === "bookmark" && row.data && row.data.action === "open") {
            // A saved bookmark: resolve its URL to a site. Guarded on
            // data.index because the create/delete/rename rows are commands,
            // not bookmarks, and must never seed.
            const mi = row.data.index;
            if (typeof mi === "number" && mi >= 0 && mi < bookmarksProv.marks.length) {
                try {
                    const bang = webProv.bangForUrl(bookmarksProv.marks[mi].url);
                    if (bang !== "")
                        seed = "@" + bang + " ";
                } catch (e) {}
            }
        }
        if (seed === "")
            return false;
        root.applyPrefix(seed);
        // Caret to the end, past the seeded space, so the first word the user
        // types lands in the query rather than before the bang.
        searchInput.cursorPosition = searchInput.text.length;
        return true;
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

    // Emit the pinned rows, in pin order, as their own section.
    //
    // Uses the SAME row objects the normal app/control sections build (one
    // factory each, below), so a pinned app is activated by exactly the same
    // launchRow() code path as an unpinned one — a pinned row is a position,
    // not a second kind of row, and it must never drift into its own
    // activation logic.
    //
    // A pinned app's action rows come with it (their pinKeyFor resolves to
    // the parent app, so `isPinned` is true for them too): pinning Brave
    // should not hide "New Window" behind a filter.
    function pushPinnedRows(out: var): void {
        if (pinsLoaded !== 1 || root.pinned.length === 0)
            return;
        const list = DesktopEntries.applications.values;
        for (let i = 0; i < root.pinned.length; ++i) {
            const key = root.pinned[i];
            if (!key)
                continue;
            if (key.indexOf("control:") === 0) {
                const want = key.slice(8);
                for (let c = 0; c < root.controlEntries.length; ++c) {
                    if (root.controlEntries[c].name !== want)
                        continue;
                    out.push(root.makeControlRow(root.controlEntries[c], "Pinned"));
                    break;
                }
                continue;
            }
            if (key.indexOf("app:") !== 0)
                continue;
            const id = key.slice(4);
            for (let a = 0; a < list.length; ++a) {
                const e = list[a];
                if (!e || e.id !== id)
                    continue;
                out.push(root.makeAppRow(e, "Pinned"));
                // show-actions=yes parity: the app's action rows ride along
                // under it, which is what the plain Applications section does.
                if (e.actions) {
                    for (let k = 0; k < e.actions.length; ++k)
                        out.push(root.makeActionRow(e, e.actions[k], "Pinned"));
                }
                break;
            }
        }
    }

    // One factory per row kind, shared by the pinned block and the normal
    // sections. Added with pinning because the row objects were previously
    // built inline in three places in rebuild(); two copies of a row shape
    // is how a pinned row ends up missing a field the delegate needs.
    function makeControlRow(ce: var, section: string, score: real): var {
        return {
            "kind": "control",
            "entry": null,
            "action": null,
            "name": ce.name,
            "keywords": ce.keywords,
            "icon": ce.icon,
            "ipcTarget": ce.ipcTarget,
            "ipcVerb": ce.ipcVerb,
            "cmd": ce.cmd,
            "score": score !== undefined ? score : 0,
            "section": section !== undefined ? section : "Controls"
        };
    }

    function makeAppRow(e: var, section: string, score: real): var {
        return {
            "kind": "app",
            "entry": e,
            "action": null,
            "score": score !== undefined ? score : 0,
            "section": section !== undefined ? section : "Applications"
        };
    }

    function makeActionRow(e: var, a: var, section: string, score: real): var {
        return {
            "kind": "action",
            "entry": e,
            "action": a,
            "score": score !== undefined ? score : -1,
            "section": section !== undefined ? section : "Applications"
        };
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
                                "icon": bookmarksProv.bookmarkIcon,
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
            // No typing. Pinned rows FIRST (their own section), then the
            // control rows, then alpha-sorted apps.
            //
            // reconcilePins runs here, not in open(): the app list is already
            // loaded by this point (DesktopEntries above), so a pin whose app
            // was uninstalled is dropped BEFORE it can be emitted as a dead
            // row, rather than after.
            root.reconcilePins();
            root.pushPinnedRows(out);
            for (let c = 0; c < root.controlEntries.length; ++c)
                out.push(root.makeControlRow(root.controlEntries[c]));
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
            // A pinned app is ALSO in `sorted` — pinned rows are a duplicate,
            // not a move — so it shows twice on an empty query: once under
            // Pinned, once here. Deliberate: Applications stays the complete
            // alphabetical list it has always been, so pinning never REMOVES
            // an app from it.
            //
            // Typing shows the normal scored results with no pinned block at
            // all (pushPinnedRows is only called on this branch), so a search
            // can never return the same app twice. Pinning is a shortcut for
            // the empty query, not a filter that survives into every search.
            for (let i = 0; i < sorted.length; ++i)
                out.push(root.makeAppRow(sorted[i]));
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
                    out.push(root.makeControlRow(scored[k].c, "Controls", scored[k].s));
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
                out.push(root.makeAppRow(e, "Applications", scored[k].s));
                // show-actions=yes: action rows directly under their app.
                for (let a = 0; e.actions && a < e.actions.length; ++a)
                    out.push(root.makeActionRow(e, e.actions[a], "Applications", scored[k].s - 1));
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

    // Ctrl+C on file rows: copy the file's contents to the
    // clipboard for text/image types (path string otherwise),
    // via FilesProvider.copyFile. Unlike reveal, the menu
    // STAYS OPEN — copying is not a dismissal, and several
    // files are often copied in a row. Returns true when a
    // file row was copied, so callers can accept the key only
    // then (plain Ctrl+C on other rows keeps its default).
    function copyCurrent(): bool {
        const p = root.currentFilePath();
        if (p === "")
            return false;
        const row = rows[appList.currentIndex];
        try {
            filesProv.copyFile(row);
        } catch (e) {}
        return true;
    }

    // Ctrl+T on a file row: open the default terminal in the file's own
    // directory (FilesProvider.openTerminal: the directory itself for a
    // directory row, its parent folder for a file row). Same
    // close-before-act contract as reveal.
    function terminalCurrent(): bool {
        if (appList.currentIndex < 0 || appList.currentIndex >= rows.length)
            return false;
        const row = rows[appList.currentIndex];
        if (!row || row.kind !== "file" || !row.data || !row.data.path)
            return false;
        close();
        try {
            filesProv.openTerminal(row);
        } catch (e) {}
        return true;
    }

    // Delete key on a highlighted bookmark: remove it in place.
    // The menu STAYS OPEN so several bookmarks can be deleted in
    // a row — deletion is not a dismissal (Ctrl+C/copy precedent).
    // Only a real saved bookmark qualifies: kind "bookmark" whose
    // data action is "open". The create/delete/rename rows are
    // commands, not bookmarks, and no other kind is ever removed,
    // so Delete on an app/control/file row keeps its default.
    // Returns true when a bookmark was deleted so the caller can
    // accept the key; false otherwise.
    function deleteCurrentBookmark(): bool {
        const idx = appList.currentIndex;
        if (idx < 0 || idx >= rows.length)
            return false;
        const row = rows[idx];
        if (!row || row.kind !== "bookmark" || !row.data || row.data.action !== "open")
            return false;
        const mi = row.data.index;
        if (typeof mi !== "number" || mi < 0 || mi >= bookmarksProv.marks.length)
            return false;
        // removeAt splices the provider's marks, saves, and
        // re-searches its own list; rebuild() then regenerates the
        // launcher rows (% mode via search(), bare mode via the
        // marks interleave) so every data.index stays correct.
        bookmarksProv.removeAt(mi);
        rebuild();
        // rebuild() resets the selection to the top; put it back
        // where the deleted row was so the row below slides up
        // into place (clamped for a now-shorter list).
        const n = rows.length;
        appList.currentIndex = n > 0 ? Math.min(idx, n - 1) : -1;
        root.updateCounter();
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

    // The chord toggles the preview for the selected file: Ctrl+Alt+Space
    // from anywhere (the QML handlers), or Ctrl+Space in files mode
    // (routed here from the bind's `websearch` verb — see websearch()).
    // A second press on the same file closes it (Finder Quick Look parity); a
    // press on a different file switches renderer as needed.
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
            if ("prefix" in d) {
                root.applyPrefix(d.prefix);
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
            // YIELD while the contextual menu is up. ContextMenu is a
            // top-level surface with Exclusive keyboard focus, so this retry
            // loop would rip focus straight back to the search input and the
            // menu's own Up/Down/Enter would go nowhere. The timer simply
            // stops; menuOpen going false restarts it (see its onChanged),
            // which is what puts the caret back for the next keystroke.
            if (root.menuOpen) {
                stop();
                return;
            }
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

    // ---- pinned rows: persistence (BookmarksProvider precedent) ----------
    Process {
        id: pinsMkdir
        command: ["mkdir", "-p", Theme.themeDir]
        running: false
        onExited: {
            root.pinsDirReady = true;
            pinnedFile.reload();
        }
    }

    FileView {
        id: pinnedFile
        path: root.pinnedPath
        watchChanges: true
        onLoaded: {
            root.loadPinsText(text());
            // The pin list can arrive after open() already built the rows, so
            // a first-load rebuild is the only way the Pinned section appears
            // without closing and reopening the launcher.
            if (root.isOpen)
                root.rebuild();
        }
        // No file yet (or a directory that is not there): empty list, and the
        // file is created lazily by the first pin.
        onLoadFailed: root.loadPinsText("")
        onFileChanged: reload()
    }

    Component.onCompleted: pinsMkdir.running = true

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
        //
        // RIGHT click is NOT a dismissal: it opens the help menu (the
        // beginner's "what can I do here"), which is the point of it —
        // reaching this area means the click was NOT on a row (the row
        // delegates claim their own right click), so there is nothing to
        // act on and closing the launcher would be the least helpful
        // possible answer. Left click outside still closes, unchanged.
        MouseArea {
            anchors.fill: parent
            onPressed: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    root.openHelpMenuAt(mouse.x, mouse.y);
                    return;
                }
            }
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton)
                    return; // handled in onPressed
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
                                const alt = (event.modifiers & Qt.AltModifier) !== 0;
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
                                } else if (event.key === Qt.Key_F10 || event.key === Qt.Key_Menu) {
                                    // The contextual menu, from the keyboard.
                                    // NOT the ContextMenu key alone: Qt.Key_Menu
                                    // is what most keyboards send for it and
                                    // F10 is the same action spelled as a
                                    // literal, because a right-click-only
                                    // feature would be unreachable without a
                                    // mouse. `;` was the obvious candidate and
                                    // is ALREADY the Modes prefix (rebuild()'s
                                    // prefixKind), so it cannot be both.
                                    event.accepted = true;
                                    root.openRowMenu();
                                } else if (ctrl && alt && event.key === Qt.Key_Space) {
                                    // Quick Look chord. Plain Space stays a
                                    // space: multi-word file queries need it.
                                    // Ctrl+Space never lands here — niri binds
                                    // it to the `websearch` verb, which decides
                                    // preview-vs-search by mode (websearch()).
                                    event.accepted = true;
                                    root.togglePreview();
                                } else if (ctrl && event.key === Qt.Key_C) {
                                    // Ctrl+C copies the selected file row
                                    // (contents for text/images, path
                                    // otherwise); the menu stays open.
                                    if (root.copyCurrent())
                                        event.accepted = true;
                                } else if (ctrl && event.key === Qt.Key_T) {
                                    // Ctrl+T opens a terminal in the
                                    // selected file row's directory. Menu
                                    // closes (terminal is a dismissal,
                                    // reveal precedent).
                                    if (root.terminalCurrent())
                                        event.accepted = true;
                                } else if (event.key === Qt.Key_Delete) {
                                    // Delete key: remove the highlighted
                                    // bookmark in place (menu stays open).
                                    // Only with the caret at the END of the
                                    // query — mid-caret, Delete keeps its
                                    // normal job of forward-deleting a
                                    // character, so an in-progress filter is
                                    // never clobbered. The list handler
                                    // below allows it at any caret since the
                                    // list never edits text.
                                    if (searchInput.cursorPosition === searchInput.text.length && root.deleteCurrentBookmark())
                                        event.accepted = true;
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
                            // Ctrl+Tab (and Ctrl+Shift+Tab as a synonym)
                            // seeds a site search instead — see
                            // seedSiteSearch. It is checked FIRST and only
                            // accepted when it actually produced a seed, so
                            // on every other row Ctrl+Tab still falls through
                            // to the focus trap below rather than being
                            // swallowed.
                            Keys.onTabPressed: (event) => {
                                if ((event.modifiers & Qt.ControlModifier) !== 0 && root.seedSiteSearch()) {
                                    event.accepted = true;
                                    return;
                                }
                                event.accepted = true;
                                appList.forceActiveFocus();
                            }
                            Keys.onBacktabPressed: (event) => {
                                if ((event.modifiers & Qt.ControlModifier) !== 0 && root.seedSiteSearch()) {
                                    event.accepted = true;
                                    return;
                                }
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
                        const alt = (event.modifiers & Qt.AltModifier) !== 0;
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
                        } else if (event.key === Qt.Key_F10 || event.key === Qt.Key_Menu) {
                            // Contextual menu (searchInput parity — both
                            // handlers must answer it, or the chord dies
                            // whenever focus happens to sit on the list).
                            event.accepted = true;
                            root.openRowMenu();
                        } else if (ctrl && alt && event.key === Qt.Key_Space) {
                            // Quick Look chord from the list too, where
                            // searchInput's handler cannot fire (Ctrl+Space
                            // itself is the bind, see websearch()).
                            event.accepted = true;
                            root.togglePreview();
                        } else if (ctrl && event.key === Qt.Key_C) {
                            // Ctrl+C copies the selected file row
                            // (contents for text/images, path
                            // otherwise); the menu stays open.
                            if (root.copyCurrent())
                                event.accepted = true;
                        } else if (ctrl && event.key === Qt.Key_T) {
                            // Ctrl+T opens a terminal in the selected
                            // file row's directory (searchInput parity).
                            if (root.terminalCurrent())
                                event.accepted = true;
                        } else if (event.key === Qt.Key_Delete) {
                            // Delete key: remove the highlighted
                            // bookmark in place (list-focus parity
                            // with the searchInput path). The list
                            // never edits text, so Delete is always
                            // free here — no caret guard needed.
                            if (root.deleteCurrentBookmark())
                                event.accepted = true;
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
                    // List-focus parity with the searchInput handlers above:
                    // plain Tab returns to the input, Ctrl+Tab seeds a site
                    // search on the highlighted row (and moves focus there,
                    // since applyPrefix refocuses the input — the key's whole
                    // job is to put the caret in the query). Checked before
                    // the focus trap so a seedable row never loses the key.
                    Keys.onTabPressed: (event) => {
                        if ((event.modifiers & Qt.ControlModifier) !== 0 && root.seedSiteSearch()) {
                            event.accepted = true;
                            return;
                        }
                        event.accepted = true;
                        searchInput.forceActiveFocus();
                    }
                    Keys.onBacktabPressed: (event) => {
                        if ((event.modifiers & Qt.ControlModifier) !== 0 && root.seedSiteSearch()) {
                            event.accepted = true;
                            return;
                        }
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
                            // Right click is claimed HERE so it cannot reach
                            // the fullscreen backdrop below, which would
                            // close the launcher instead of opening a menu.
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            hoverEnabled: true
                            // Gated: a resting cursor must not steal selection
                            // on open (delegate appears under it, firing
                            // onEntered with zero user input). Armed by first
                            // explicit mouse movement or keyboard nav.
                            onEntered: if (root.hoverArmed) appList.currentIndex = index
                            onPositionChanged: root.hoverArmed = true
                            // Right click: select THIS row (not the one the
                            // keyboard last left highlighted — the menu must
                            // describe the row under the cursor) and open the
                            // menu under the cursor. onClicked, not onReleased,
                            // so a press-drag-release does not fire it.
                            onPressed: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    root.hoverArmed = true;
                                    appList.currentIndex = index;
                                    return;
                                }
                                root.hoverArmed = true;
                                if (row.isFileRow) {
                                    row.grabToImage(function(result) {
                                        row.Drag.imageSource = result.url;
                                    });
                                }
                            }
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    // `mouse.x`/`mouse.y` are ITEM-LOCAL to this
                                    // MouseArea (it fills the delegate), NOT
                                    // screen coords — using them raw put the
                                    // menu ~175px up and left of the cursor.
                                    // `win` is a PanelWindow (QObject, not Item)
                                    // so win.mapToItem() does not exist; but the
                                    // surface is anchored to all four edges, so
                                    // win's origin IS the output/screen origin.
                                    // Therefore item-local -> screen is just
                                    // "where is this MouseArea within win".
                                    const p = rowMouse.mapToItem(win.contentItem, mouse.x, mouse.y);
                                    root.openContextMenu(root.rowMenuItems(), p.x, p.y);
                                    return;
                                }
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

        // Quick Look pane (Ctrl+Alt+Space), sibling of the card. It is part of
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

        // Quick Look parity for scripts/tests: toggles the preview for the
        // currently selected row (no-op unless it is a file row). The chord
        // itself moved to Ctrl+Alt+Space on 2026-10-05, but the verb keeps
        // its name — this is "preview a file", not a keybinding.
        function preview(): void {
            root.togglePreview();
        }

        // Ctrl+Space (niri/binds-quickshell.kdl -> `launcher websearch`):
        // files mode previews the highlighted file, anything else opens web
        // search. `qs -c sunset ipc call launcher websearch`
        function websearch(): void {
            root.websearch();
        }

        // Ctrl+Tab parity for scripts/tests: seed a site search from the
        // currently highlighted row (a site in the "@" list, or a saved
        // bookmark whose URL maps to a known site). No-op on every other
        // row, exactly like the key itself.
        // `qs -c sunset ipc call launcher seedSiteSearch`
        function seedSiteSearch(): void {
            root.seedSiteSearch();
        }

        // Execute one item of the contextual row menu (right click / F10).
        // shell.qml's dispatch() calls the verb name on the popup ROOT, which
        // is why rowMenuItem() lives out here and not inside this handler —
        // a method defined only in the IpcHandler is undefined to dispatch()
        // and the menu would silently do nothing.
        //   qs -c sunset ipc call launcher rowMenuItem <op>
        // `op` is typed string because an IPC verb cannot express an optional
        // argument (an untyped one is refused outright, and a default value is
        // refused too), so an omitted op arrives as the text "undefined" and
        // rowMenuItem's closed allowlist drops it — which is the correct
        // no-op, not a crash.
        function rowMenuItem(op: string): void {
            root.rowMenuItem(op);
        }

        // Open the help menu ("what can I do here") at a fixed point. Used by
        // the `menu openRow` verb so a keybind can reach it; the F10 chord
        // picks the row menu instead when a row is highlighted, and falls
        // back to this.
        function helpMenu(): void {
            root.helpMenu();
        }
    }
}
