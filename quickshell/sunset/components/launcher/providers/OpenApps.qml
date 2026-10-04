// OpenApps.qml — the launcher's pinned "Open" section: one row per RUNNING
// app, not per window and not per .desktop entry.
//
// Why this exists: the launcher only knew about apps you *could* launch. When
// you already have a terminal, a browser, an editor and a file manager open, the
// fastest thing to do is switch to one, and the only existing route was the "$"
// WindowsProvider, which lists every window with its raw app-id in the detail
// line and no icon at all.
//
// What it deliberately does NOT show: coordinates. No geometry, no workspace
// coordinates, no app-id strings, no window ids. Those are niri implementation
// detail and they made the old window rows read like a debug dump. Identity is
// the pretty app name ("Brave", "Files", "Code"), the glyph is a Nerd Font
// codepoint, and the detail line is the window count plus that app's most
// recent window title.
//
// Contract (the rows()+activate() shape of MediaActions.qml — this is a pinned
// section, not a search provider, so there is no search()/resultsChanged):
//   function rows(limit: int): var   -> JS array of row objects
//   function activate(row: var): void  (Launcher closes BEFORE calling
//     activate, so this only acts — it never closes anything.)
//
// Row shape: {kind:"open", name, detail, glyph, icon:null, score:0,
//              section:"Open", data:{ids:[…]}}.
//   `glyph` is a Nerd Font codepoint (NOT an assets/icons basename) — the
//   delegate renders it as Text instead of an IconImage when it is non-empty.
//   `icon` stays null so iconSourceFor() falls through to the row's own branch.
//
// Sync fast path: reads NiriService.windows, groups by app_id, and emits
// immediately — same convention as WindowsProvider.qml. Nothing completes
// asynchronously, so nothing is emitted asynchronously either.
//
// Dedupe rule: one row per app_id. Chromium PWAs (brave-<32 chars>-Default,
// per AGENTS.md) each get their own row rather than collapsing into "Brave",
// because they are separate apps the user installed separately and switches
// between on purpose — but they still match the browser table by substring, so
// every one of them gets the browser glyph. A window with no app_id is keyed by
// its title so it still appears (WindowsProvider.qml does the same).
//
// Focus rule: focus that app's window which currently has focus; otherwise the
// first one NiriService reports. Deterministic, no hidden per-app cursor.

import QtQuick
import qs.services

QtObject {
    id: root

    // Nerd Font codepoints, all verified present in JetBrainsMono-NF by
    // rendering them (a wrong guess here is a tofu box in the launcher).
    // Written as \uXXXX escapes and NOT as the literal glyphs: the private-use
    // area has no fallback font, and pasting the raw character put E755 in this
    // file where E795 was meant — invisible in a diff, and it just draws the
    // wrong icon. An escape is reviewable.
    //   E795 nf-dev-terminal   F0AC nf-fa-globe      F121 nf-fa-code
    //   F07B nf-fa-folder      F001 nf-fa-music-note F03D nf-fa-video-camera
    //   F03E nf-fa-picture     F1C1 nf-fa-file-pdf  F1EC nf-fa-calculator
    //   F0E0 nf-fa-envelope    F075 nf-fa-comment   F11B nf-fa-gamepad
    //   F013 nf-fa-cog         F0C9 nf-fa-bars      (bars = neutral fallback)
    readonly property string gTerminal: "\uE795"
    readonly property string gBrowser: "\uF0AC"
    readonly property string gCode: "\uF121"
    readonly property string gFiles: "\uF07B"
    readonly property string gMusic: "\uF001"
    readonly property string gVideo: "\uF03D"
    readonly property string gImage: "\uF03E"
    readonly property string gPdf: "\uF1C1"
    readonly property string gCalc: "\uF1EC"
    readonly property string gMail: "\uF0E0"
    readonly property string gChat: "\uF075"
    readonly property string gGame: "\uF11B"
    readonly property string gSettings: "\uF013"
    readonly property string gGeneric: "\uF0C9"

    // First match wins, so the order below is specificity order: the long
    // org.gnome.* / reverse-DNS forms come before the bare word, otherwise
    // "nautilus" would never be reached for "org.gnome.Nautilus".
    // Each entry: [matcher, pretty name, glyph]. The matcher is a
    // lowercased substring of the app_id.
    readonly property var table: [
        // terminals
        ["alacritty", "Alacritty", gTerminal],
        ["foot", "Foot", gTerminal],
        ["kitty", "Kitty", gTerminal],
        ["wezterm", "WezTerm", gTerminal],
        ["konsole", "Konsole", gTerminal],
        ["gnome-terminal", "Terminal", gTerminal],
        ["xterm", "XTerm", gTerminal],
        ["termux", "Termux", gTerminal],
        // browsers (a plain globe, deliberately: the chrome logo would be a lie
        // for firefox/brave, and a PWA row is still just a browser)
        ["brave", "Brave", gBrowser],
        ["chromium", "Chromium", gBrowser],
        ["chrome", "Chrome", gBrowser],
        ["firefox", "Firefox", gBrowser],
        ["vivaldi", "Vivaldi", gBrowser],
        ["opera", "Opera", gBrowser],
        ["microsoft-edge", "Edge", gBrowser],
        ["org.mozilla.firefox", "Firefox", gBrowser],
        // code / text editors
        ["visual studio code", "Code", gCode],
        ["vscodium", "VSCodium", gCode],
        ["codium", "VSCodium", gCode],
        ["sublime", "Sublime", gCode],
        ["jetbrains", "JetBrains", gCode],
        ["intellij", "IntelliJ", gCode],
        ["pycharm", "PyCharm", gCode],
        ["webstorm", "WebStorm", gCode],
        ["zed", "Zed", gCode],
        ["neovim", "Neovim", gCode],
        ["gvim", "GVim", gCode],
        ["vim", "Vim", gCode],
        ["emacs", "Emacs", gCode],
        ["org.gnome.texteditor", "Text Editor", gCode],
        ["text-editor", "Text Editor", gCode],
        ["kate", "Kate", gCode],
        ["geany", "Geany", gCode],
        ["code", "Code", gCode],
        // file managers
        ["org.gnome.nautilus", "Files", gFiles],
        ["nautilus", "Files", gFiles],
        ["dolphin", "Dolphin", gFiles],
        ["thunar", "Thunar", gFiles],
        ["nemo", "Nemo", gFiles],
        ["ranger", "Ranger", gFiles],
        ["pcmanfm", "PCManFM", gFiles],
        ["doublecmd", "Double Commander", gFiles],
        ["org.gnome.files", "Files", gFiles],
        // media
        ["spotify", "Spotify", gMusic],
        ["rhythmbox", "Rhythmbox", gMusic],
        ["audacious", "Audacious", gMusic],
        ["mpv", "mpv", gVideo],
        ["vlc", "VLC", gVideo],
        ["obs", "OBS", gVideo],
        // image / docs / misc
        ["gimp", "GIMP", gImage],
        ["inkscape", "Inkscape", gImage],
        ["shotwell", "Shotwell", gImage],
        ["imv", "Imv", gImage],
        ["eog", "Eye of GNOME", gImage],
        ["loupe", "Loupe", gImage],
        ["evince", "Evince", gPdf],
        ["zathura", "Zathura", gPdf],
        ["okular", "Okular", gPdf],
        ["mupdf", "MuPDF", gPdf],
        ["galculator", "Calculator", gCalc],
        ["calculator", "Calculator", gCalc],
        ["gnome-calculator", "Calculator", gCalc],
        ["qalculate", "Qalculate", gCalc],
        // communication
        ["thunderbird", "Thunderbird", gMail],
        ["evolution", "Evolution", gMail],
        ["discord", "Discord", gChat],
        ["slack", "Slack", gChat],
        ["telegram", "Telegram", gChat],
        ["signal", "Signal", gChat],
        ["element", "Element", gChat],
        // games / settings
        ["steam", "Steam", gGame],
        ["lutris", "Lutris", gGame],
        ["heroic", "Heroic", gGame],
        ["org.gnome.settings", "Settings", gSettings],
        ["pavucontrol", "Volume", gSettings]
    ]

    // [prettyName, glyph] for the first table entry whose matcher appears in
    // appId, else a name derived from the app_id plus the neutral glyph.
    function classify(appId) {
        const id = (appId || "").toLowerCase();
        for (let i = 0; i < table.length; ++i) {
            if (id.indexOf(table[i][0]) !== -1)
                return [table[i][1], table[i][2]];
        }
        return [deriveName(appId), gGeneric];
    }

    // Reverse-DNS trailing segments that describe the packaging rather than the
    // app. Skipped when picking which segment is the name — otherwise
    // "org.telegram.desktop" is called "Desktop" and "com.foo.Bar.app" is called
    // "App". Scanned from the END, so the real name wins over a generic word
    // earlier in the id.
    readonly property var genericSegments: [
        "desktop", "main", "application", "app", "client", "x11", "gtk2",
        "gtk3", "gtk4", "qt5", "qt6", "wayland", "shell", "gui", "program",
        "launcher", "bin", "service", "daemon", "agent"
    ]

    // Fallback name when the app is not in the table. Rules, in order:
    //   1. drop the launcher noise Chromium PWAs append ("-Default", "-bin");
    //   2. drop a VERSION suffix, but only in a version-shaped one ("-v2",
    //      ".v1.4", "-2.1") — never a bare digit run, because "v2" in
    //      "totally.unknown.app.v2" is the end of a name, not a version, and
    //      stripping it left the row called "V";
    //   3. for a reverse-DNS id, take the LAST non-generic segment;
    //   4. otherwise keep the whole id and title-case the first letter.
    // Never returns "".
    function deriveName(appId) {
        let s = (appId || "").trim();
        if (s === "")
            return "Window";
        s = s.replace(/-Default$/i, "");
        s = s.replace(/-bin$/i, "");
        s = s.replace(/[-.]v\d+(\.\d+)+$/i, "");
        s = s.replace(/[-.]v\d+$/i, "");
        s = s.trim();
        if (s === "")
            return "Window";
        if (s.indexOf(".") !== -1) {
            const segs = s.split(".").filter(function(part) {
                return part !== "";
            });
            let pick = null;
            for (let i = segs.length - 1; i >= 0; --i) {
                if (genericSegments.indexOf(segs[i].toLowerCase()) === -1) {
                    pick = segs[i];
                    break;
                }
            }
            s = (pick !== null) ? pick : segs.join(" ");
        }
        // A hyphen is a word separator here, not a discard: dropping everything
        // before the last one turned "brave-agimnkijc-Default" into a row
        // labelled with the random middle chunk.
        s = s.split("-").filter(function(part) {
            return part !== "";
        }).join(" ");
        s = s.trim();
        if (s === "")
            return "Window";
        // Title-case the first letter only. Names that are already mixed-case
        // are left alone — lower-casing "Nautilus" to "nautilus" reads worse
        // than leaving it.
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    function rows(limit) {
        const cap = (limit > 0) ? limit : 12;
        const wins = NiriService.windows ?? [];
        // Preserve first-seen order (NiriService's own order) but group by key.
        const order = [];
        const groups = {};
        for (let i = 0; i < wins.length; ++i) {
            const w = wins[i];
            const appId = w.app_id ?? "";
            const title = w.title ?? "";
            // No app_id -> key on the title so the window is still reachable.
            const key = appId !== "" ? appId : ("t:" + title);
            if (groups[key] === undefined) {
                groups[key] = { "appId": appId, "wins": [], "focused": -1 };
                order.push(key);
            }
            groups[key].wins.push(w);
            if (w.is_focused === true)
                groups[key].focused = groups[key].wins.length - 1;
        }

        const out = [];
        for (let k = 0; k < order.length && out.length < cap; ++k) {
            const g = groups[order[k]];
            const cls = classify(g.appId);
            const ids = [];
            for (let i = 0; i < g.wins.length; ++i)
                ids.push(g.wins[i].id);
            // Focused window first, so activate() can just take ids[0]. Ids are
            // only ever used to focus — never displayed.
            let focusId = null;
            if (g.focused >= 0)
                focusId = g.wins[g.focused].id;
            else
                focusId = g.wins[0].id;
            const ordered = [focusId];
            for (let i = 0; i < g.wins.length; ++i) {
                if (g.wins[i].id !== focusId)
                    ordered.push(g.wins[i].id);
            }

            // Detail: no coordinates, no app-id. Count when there is more than
            // one window (that is the case where the number is the useful
            // part), otherwise that window's title so you know what you will
            // land on.
            const title = g.wins[g.focused >= 0 ? g.focused : 0].title ?? "";
            let detail;
            if (g.wins.length > 1)
                detail = g.wins.length + " windows";
            else
                detail = title;

            out.push({
                "kind": "open",
                "name": cls[0],
                "detail": detail,
                "glyph": cls[1],
                "icon": null,
                "entry": null,
                "score": 0,
                "section": "Open",
                "data": { "ids": ordered }
            });
        }
        return out;
    }

    function activate(row) {
        if (!row || !row.data || !row.data.ids || row.data.ids.length === 0)
            return;
        NiriService.focusWindow(row.data.ids[0]);
    }
}