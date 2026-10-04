// ModesProvider.qml — launcher "Modes" provider (kind "mode",
// section "Modes"): one row per launcher mode + control popup.
//
// Contract:
//   root is QtObject; function search(q: string, limit: int): var -> JS
//     array of row objects; signal resultsChanged(); property var
//     latestRows: []; function activate(row: var): void (Launcher closes
//     BEFORE calling activate, so this only acts).
// Rows: {kind:"mode", name, detail, icon, score:100, section:"Modes",
//   data:{prefix} | data:{ipcTarget,ipcVerb} | data:{cmd}}.
//   Prefix modes carry data {prefix}; control popups carry
//   data {ipcTarget, ipcVerb}; spot actions (fixed bind-parity scripts)
//   carry data {cmd} (a shell command run via `sh -c`, RunnerProvider
//   precedent — Launcher falls through to activate() for these since they
//   are neither prefix nor ipcTarget rows).
//   Icons reuse Launcher.qml controlEntries basenames where one exists
//   (settings/wallpaper/power/volume/clipboard/logo.svg for Calendar —
//   all verified in quickshell/sunset/assets/icons/); provider modes
//   without a matching glyph use null (all spot-action rows are null).
// Prefix assignments (ASSUMPTION — confirm with sibling provider owners;
// $ : @ / are walker-parity per Launcher.qml header: windows `$`,
// clipboard `:`, websearch `@`, files `/`; the rest follow the contract's
// prefix set in mode-listing order):
//   Applications "" (default list: empty query), Calculator "=", Windows
//   "$", Clipboard ":", Web "@", Files "/" (!type/@scope bangs, see
//   FilesProvider.qml header), Runner ">", Symbols ".",
//
// INTEGRATOR DEPENDENCY (explicit): this provider has no reference to the
//   launcher's search input, so it CANNOT switch modes itself.
//   - Prefix row (data has "prefix" key — NOTE: use key presence, NOT
//     truthiness: Applications' prefix is ""): the integrator MUST set
//     the launcher query to data.prefix and refocus the input.
//   - IPC row (data has ipcTarget/ipcVerb): activate() below already
//     performs `qs -c sunset ipc call <target> <verb>` (Launcher.qml
//     close-then-qs precedent). Exactly-once rule: if the integrator
//     intercepts IPC rows itself it MUST NOT also call activate() (that
//     would toggle twice).
//   - Spot-action row (data has cmd): activate() runs it via
//     `sh -c` (RunnerProvider precedent). The integrator falls through
//     here (no prefix key, no ipcTarget) after closing the menu.
// Sync static list only: latestRows mirrored, resultsChanged never
// emitted (nothing async — sibling convention).
// No colors/fonts, no UI.
//
// Bind parity (Dev Menu audit, 2026-09-13): every keyboard bind in
//   niri/binds.kdl + niri/binds-quickshell.kdl maps to a menu path —
//   control row (Launcher.qml controlEntries, bare queries), ";" row
//   here, DesktopEntry app, ">" runner, or documented NOTHING:
//   - Control rows: all 11 controlEntries rows are mirrored here as ";"
//     rows (names match the controls except "Clipboard History", which
//     disambiguates from the ":" Clipboard prefix mode in this same
//     section). Launcher.qml control activation is untouched. "Settings"
//     and "Help & Guide" are `cmd` rows (GNOME Settings + the HTML guide
//     opened by scripts/*.sh), since the old native Settings Center /
//     Help Center popups are gone as of 2026-10-02.
//   - Spot actions (fixed scripts): Lock Screen (Mod+L, swaylock.sh),
//     Screenshot (Mod+Ctrl+S, scripts/screenshot.sh region; covers the Print
//     family by action family), Dropdown Terminal (Mod+Grave).
//     NEVER auto-activate Lock in QA — list only.
//   - Deliberately NOT rows (documented, never forced into this schema):
//     LocalSend (Mod+S) IS a DesktopEntry (Keywords=Sharing;...) so bare
//     `share`/`localsend` already surfaces it — no alias needed;
//     destructive clipboard scripts (Mod+Shift+C/V/D), updater
//     (Mod+U), niri reload (Mod+Ctrl+R), quickshell restart (Mod+Shift+Q)
//     stay ">"-runner reachable (session/destructive ops, not menu rows);
//     the wallpaper process knobs stay on scripts/wallpaper-process.sh
//     (their QML editor went away with SettingsCenter);
//     toggle-waybar (Mod+W) REMOVED (binary uninstalled 2026-09-15, configs kept on disk); window/
//     column/workspace ops (Mod+Q/T/M/F/arrows/HJKL/1-0/A/etc.) are
//     window-scoped niri actions with no menu meaning.
//   - Shortcut tokens (e.g. "mod+alt+s") ride in keys here so typing the
//     bind surfaces the row; Launcher.qml control keywords keep the
//     existing plain-word convention (no shortcut tokens there).

import QtQuick
import Quickshell

QtObject {
    id: root

    signal resultsChanged()
    property var latestRows: []

    readonly property var modes: [
        { "name": "Applications", "keys": "applications apps programs default all", "prefix": "" },
        { "name": "Calculator", "keys": "calculator calc math compute expression", "prefix": "=" },
        { "name": "Windows", "keys": "windows niri focus switch", "prefix": "$" },
        { "name": "Clipboard", "keys": "clipboard history copy paste cliphist", "prefix": ":", "icon": "clipboard.svg" },
        { "name": "Web", "keys": "web search browser google duckduckgo youtube wikipedia github stackoverflow reddit maps miruro anime dd yt wiki gh so bookmark save site", "prefix": "@" },
        { "name": "Files", "keys": "files file manager browse folders", "prefix": "/" },
        { "name": "Runner", "keys": "runner run shell command exec", "prefix": ">" },
        { "name": "Symbols", "keys": "symbols emoji characters glyphs", "prefix": "." },
        { "name": "Todo", "keys": "todo tasks list", "prefix": "!" },
        { "name": "Bookmarks", "keys": "bookmarks favorites sites urls", "prefix": "%" },
        { "name": "Quick Settings", "keys": "quick settings bluetooth brightness dnd idle power profile", "ipcTarget": "settings", "ipcVerb": "toggle", "icon": "settings.svg" },
        { "name": "Capture", "keys": "capture bar pin camera screenshot bar options menu mod+shift+5 mod+alt+shift+s", "ipcTarget": "capture", "ipcVerb": "toggle", "icon": "camera.svg" },
        { "name": "Wi-Fi", "keys": "wifi wi-fi wireless network ssid connect disconnect forget rescan internet ethernet mod+alt+f", "ipcTarget": "wifi", "ipcVerb": "toggle", "icon": "wifi.svg" },
        { "name": "Wallpaper", "keys": "wallpaper background gallery theme", "ipcTarget": "wallpaper-menu", "ipcVerb": "toggle", "icon": "wallpaper.svg" },
        { "name": "Power", "keys": "power lock suspend logout reboot shutdown quit", "ipcTarget": "power", "ipcVerb": "toggle", "icon": "power.svg" },
        { "name": "Volume", "keys": "volume mixer audio sound mute", "ipcTarget": "volume", "ipcVerb": "toggle", "icon": "volume.svg" },
        { "name": "Calendar", "keys": "calendar clock pomodoro timer date", "ipcTarget": "calendar", "ipcVerb": "toggle", "icon": "logo.svg" },
        { "name": "Settings", "keys": "settings center preferences system config network sound display accounts power gnome mod+alt+s", "cmd": "/home/me/niri-setup/scripts/gnome-settings.sh", "icon": "settings.svg", "detail": "Open GNOME Settings (Enter)" },
        { "name": "Clipboard History", "keys": "clipboard history copy paste cliphist manager popup mod+c", "ipcTarget": "clipboard", "ipcVerb": "toggle", "icon": "clipboard.svg" },
        { "name": "Crack the Whip", "keys": "whip crack lash fun mod+alt+l", "ipcTarget": "whip", "ipcVerb": "toggle", "icon": "whip.svg" },
        { "name": "Do Not Disturb", "keys": "dnd disturb silent mute notifications mod+alt+n", "ipcTarget": "notifications", "ipcVerb": "toggleSilent", "icon": "empty.svg" },
        { "name": "Themes", "keys": "themes style colors rice omarchy switcher mod+alt+t", "ipcTarget": "themes", "ipcVerb": "toggle", "icon": "palette.svg" },
        { "name": "Help & Guide", "keys": "help setup guide manual docs keybindings bangs file search mod+alt+h", "cmd": "/home/me/niri-setup/scripts/open-help.sh", "icon": "logo.svg", "detail": "Open this guide in a browser window (Enter)" },
        { "name": "Lock Screen", "keys": "lock screen secure swaylock mod+l", "cmd": "/home/me/niri-setup/scripts/swaylock.sh" },
        // Runs scripts/screenshot.sh, NOT a bare `flameshot gui`. The bare form
        // skips the two things that make a capture useful — it never copies the
        // image to the clipboard and never pops the OCR/Copy/Open/Delete pill —
        // so this row used to disagree with the Mod+Ctrl+S bind. One script,
        // one behaviour, whichever way you ask for it.
        { "name": "Screenshot", "keys": "screenshot capture region print clip annotate edit flameshot redact pixelate draw shapes mod+ctrl+s", "cmd": "/home/me/niri-setup/scripts/screenshot.sh region", "detail": "Pick, annotate & redact (Enter)" },
        { "name": "Scrolling Screenshot", "keys": "screenshot scrolling long page stitch capture mod+shift+s", "cmd": "/home/me/niri-setup/scripts/scroll-screenshot.sh", "detail": "Auto-scroll & stitch; run again to stop (Enter)" },
        { "name": "Screen Recording", "keys": "screen recording video capture record mod+shift+r", "cmd": "/home/me/niri-setup/scripts/record-screen.sh", "detail": "Toggle MP4 recording of the screen (Enter)" },
        { "name": "Dropdown Terminal", "keys": "dropdown terminal scratchpad console alacritty mod+grave", "cmd": "/home/me/niri-setup/scripts/dropdown-terminal.sh" }
    ]

    function makeRow(m): var {
        if (m.prefix !== undefined) {
            return {
                "kind": "mode",
                "name": m.name,
                "detail": m.prefix === "" ? "Default mode — clear the query (Enter)" : "Switch to " + m.name + " mode — type '" + m.prefix + "' (Enter)",
                "icon": m.icon !== undefined ? m.icon : null,
                "score": 100,
                "section": "Modes",
                "data": { "prefix": m.prefix }
            };
        }
        if (m.cmd !== undefined) {
            return {
                "kind": "mode",
                "name": m.name,
                "detail": m.detail !== undefined ? m.detail : "Run " + m.name + " (Enter)",
                "icon": m.icon !== undefined ? m.icon : null,
                "score": 100,
                "section": "Modes",
                "data": { "cmd": m.cmd }
            };
        }
        return {
            "kind": "mode",
            "name": m.name,
            "detail": "Open " + m.name + " (Enter)",
            "icon": m.icon !== undefined ? m.icon : null,
            "score": 100,
            "section": "Modes",
            "data": { "ipcTarget": m.ipcTarget, "ipcVerb": m.ipcVerb }
        };
    }

    function search(q: string, limit: int): var {
        const cap = (limit > 0) ? limit : 50;
        const needle = (q ? String(q) : "").trim().toLowerCase();
        let out = [];
        for (let i = 0; i < modes.length; ++i) {
            const m = modes[i];
            if (needle !== "" && m.name.toLowerCase().indexOf(needle) === -1 && String(m.keys).toLowerCase().indexOf(needle) === -1)
                continue;
            out.push(makeRow(m));
            if (out.length >= cap)
                break;
        }
        latestRows = out;
        return out;
    }

    function activate(row: var): void {
        if (!row || !row.data)
            return;
        // Control popup: perform the qs IPC here (close-then-qs precedent
        // from Launcher.qml launchRow). See exactly-once rule above.
        if (row.data.ipcTarget) {
            Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", row.data.ipcTarget, row.data.ipcVerb || "toggle"]);
            return;
        }
        // Spot action: run the fixed bind-parity script via sh -c
        // (RunnerProvider.activate precedent). Launcher closes BEFORE
        // calling activate, so this only acts.
        if (row.data.cmd) {
            Quickshell.execDetached(["sh", "-c", row.data.cmd]);
            return;
        }
        // Prefix mode: no access to the search input from here — the
        // integrator owns setting query = data.prefix + refocus.
        if (row.data.prefix !== undefined)
            console.warn("ModesProvider: integrator must set launcher query to '" + row.data.prefix + "' and refocus");
    }
}
