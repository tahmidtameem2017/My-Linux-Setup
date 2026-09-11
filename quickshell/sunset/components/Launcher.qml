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
//
// Quickshell mapping:
//   fuzzel #RRGGBBAA -> Qt #AARRGGBB (e.g. #000000f2 -> "#f2000000")
//   width=45 (~45 text cols) -> 700px centered card
//   lines=12 x line-height=32 -> list capped at 12 rows of 32px
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
// Walker note: this covers app launching only. Walker power-user providers
//   (calc, files `/`, windows `$`, websearch `@`, clipboard `:`) are NOT
//   replicated; walker binary + ~/.config/walker/config.toml stay installed
//   as fallback (config untouched).
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

Scope {
    id: root

    // ---- theme (taste.md Sunset Orange AMOLED + fuzzel.ini) ----
    readonly property color bg: "#f2000000" // fuzzel background #000000f2
    readonly property color textCol: "#fff7c7a1" // fuzzel text #f7c7a1ff
    readonly property color accent: "#ffe85d2f" // fuzzel selection #e85d2fff
    readonly property color accentHover: "#ffff8b4a" // fuzzel match #ff8b4aff
    readonly property color muted: "#aa7c8a6a" // fuzzel placeholder #7c8a6aaa
    readonly property color selText: "#ff000000" // fuzzel selection-text
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int menuWidth: 700 // fuzzel width=45
    readonly property int maxRows: 12 // fuzzel lines=12
    readonly property int rowHeight: 32 // fuzzel line-height=32
    readonly property string terminal: "alacritty"

    property bool isOpen: false
    property string query: ""
    // Bumped on every open so the row list rebuilds even for same query.
    property int generation: 0
    // Plain JS rows: { kind: "app"|"action", entry, action, score }.
    property var rows: []

    function open(): void {
        query = "";
        searchInput.text = "";
        generation++;
        rebuild();
        isOpen = true;
        focusTimer.restart();
    }

    function close(): void {
        isOpen = false;
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
        const kws = (e.keywords || []).join(" ");
        const kwm = root.fzfScore(q, kws) - 4;
        if (kwm > best)
            best = kwm;
        const cats = (e.categories || []).join(" ");
        const ctm = root.fzfScore(q, cats) - 8;
        if (ctm > best)
            best = ctm;
        return best;
    }

    function rebuild(): void {
        // Depend on generation so reopening refreshes the list.
        const gen = generation;
        const q = query.trim().toLowerCase();
        const apps = DesktopEntries.applications.values;
        let out = [];
        if (q === "") {
            const sorted = apps.slice().sort((a, b) => a.name.localeCompare(b.name));
            for (let i = 0; i < sorted.length; ++i)
                out.push({
                    "kind": "app",
                    "entry": sorted[i],
                    "action": null,
                    "score": 0
                });
        } else {
            let scored = [];
            for (let i = 0; i < apps.length; ++i) {
                const s = root.bestScore(q, apps[i]);
                if (s > -1e8)
                    scored.push({
                        "e": apps[i],
                        "s": s
                    });
            }
            scored.sort((a, b) => (b.s - a.s) || a.e.name.localeCompare(b.e.name));
            for (let k = 0; k < scored.length; ++k) {
                const e = scored[k].e;
                out.push({
                    "kind": "app",
                    "entry": e,
                    "action": null,
                    "score": scored[k].s
                });
                // show-actions=yes: action rows directly under their app.
                for (let a = 0; a < e.actions.length; ++a)
                    out.push({
                        "kind": "action",
                        "entry": e,
                        "action": e.actions[a],
                        "score": scored[k].s - 1
                    });
            }
            // filter-desktop=no: exact-id fallback (byId includes NoDisplay).
            const exact = DesktopEntries.byId(query.trim());
            if (exact) {
                let dup = false;
                for (let d = 0; d < out.length; ++d)
                    if (out[d].entry.id === exact.id)
                        dup = true;
                if (!dup)
                    out.unshift({
                        "kind": "app",
                        "entry": exact,
                        "action": null,
                        "score": 1e9
                    });
            }
        }
        if (gen !== generation)
            return;
        rows = out;
        appList.currentIndex = out.length > 0 ? 0 : -1;
    }

    function activateCurrent(): void {
        if (appList.currentIndex < 0 || appList.currentIndex >= rows.length)
            return;
        const row = rows[appList.currentIndex];
        launchRow(row);
    }

    function launchRow(row): void {
        if (!row || !row.entry)
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
        let idx = appList.currentIndex + delta;
        if (idx < 0)
            idx = 0;
        if (idx >= rows.length)
            idx = rows.length - 1;
        appList.currentIndex = idx;
        appList.positionViewAtIndex(idx, ListView.Contain);
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: searchInput.forceActiveFocus()
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

        // Click outside the card closes (fuzzel click-to-close parity).
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(root.menuWidth, parent.width - 48)
            // Content-driven: input + list + empty-state + margins/gaps.
            // All terms are intrinsic (no parent-height cycle).
            height: inputRow.height + appList.height + emptyLabel.height + 56
            radius: 12 // fuzzel [border] radius (intentional taste.md exception)
            color: root.bg
            border.width: 2 // fuzzel [border] width
            border.color: root.accent

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
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: root.fontFamily
                            font.pointSize: 13
                            font.bold: true
                            color: root.textCol
                            cursorVisible: true
                            onTextChanged: {
                                root.query = text;
                                root.rebuild();
                            }
                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Escape) {
                                    event.accepted = true;
                                    root.close();
                                } else if (event.key === Qt.Key_Up) {
                                    event.accepted = true;
                                    root.moveSelection(-1);
                                } else if (event.key === Qt.Key_Down) {
                                    event.accepted = true;
                                    root.moveSelection(1);
                                } else if (event.key === Qt.Key_PageUp) {
                                    event.accepted = true;
                                    root.moveSelection(-10);
                                } else if (event.key === Qt.Key_PageDown) {
                                    event.accepted = true;
                                    root.moveSelection(10);
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    event.accepted = true;
                                    root.activateCurrent();
                                }
                            }
                        }
                    }

                    Text {
                        id: counterText
                        // fuzzel counter parity (counter=#7c8a6a).
                        text: root.rows.length + "/" + DesktopEntries.applications.values.length
                        font.family: root.fontFamily
                        font.pointSize: 11
                        color: root.muted
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    id: appList
                    width: parent.width
                    height: Math.min(root.rows.length, root.maxRows) * root.rowHeight
                    clip: true
                    model: root.rows
                    keyNavigationWraps: true
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            event.accepted = true;
                            root.close();
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            event.accepted = true;
                            root.activateCurrent();
                        }
                    }

                    delegate: Rectangle {
                        id: row
                        property var rowData: modelData
                        property bool isAction: rowData && rowData.kind === "action"
                        width: appList.width
                        height: root.rowHeight
                        radius: 6
                        color: appList.currentIndex === index ? root.accent : "transparent"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            IconImage {
                                // icons-enabled=yes (icon-theme Colloid).
                                source: row.rowData && row.rowData.entry ? Quickshell.iconPath(row.rowData.entry.icon, true) : ""
                                implicitWidth: 22
                                implicitHeight: 22
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                width: parent.width - 40
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                Text {
                                    width: parent.width
                                    text: {
                                        if (!row.rowData || !row.rowData.entry)
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
                                    text: {
                                        if (!row.rowData || !row.rowData.entry)
                                            return "";
                                        if (row.isAction)
                                            return "";
                                        return row.rowData.entry.comment || row.rowData.entry.genericName || "";
                                    }
                                    font.family: root.fontFamily
                                    font.pointSize: 9
                                    color: appList.currentIndex === index ? root.selText : root.muted
                                    opacity: appList.currentIndex === index ? 0.85 : 1.0
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            hoverEnabled: true
                            onEntered: appList.currentIndex = index
                            onClicked: {
                                appList.currentIndex = index;
                                searchInput.forceActiveFocus();
                            }
                            onDoubleClicked: root.activateCurrent()
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
    }
}
