// ClipboardPopup.qml — sunset clipboard history frontend over the KEPT
// cliphist backend. Replaces the fuzzel dmenu in
// waybar/scripts/clipboard.sh (frontend only).
//
// Backend parity (from waybar/scripts/clipboard.sh + clipboard-pick.py):
//   `cliphist list` -> pick line -> clipboard-pick.py restores it:
//   - plain entries: bytes restored verbatim via `wl-copy`
//   - image entry paired with its path sidecar (written by
//     scripts/clip-path-watcher.py into ~/.cache/cliphist/images/):
//     served as image/* + text/uri-list + text/plain via
//     scripts/clipboard-offer.py (so text fields get a copyable path).
//   This popup restores by piping the selected `cliphist list` line into
//   clipboard-pick.py — the pairing/verbatim logic is unchanged.
//
// Fuzzel parity (from fuzzel/clipboard.ini — KEPT as fallback):
//   match-mode=fzf, prompt="  ", placeholder="Search clipboard...",
//   lines=12, width=60, layer=overlay, anchor=center, same Sunset colors.
//
// Untouched (do NOT move into quickshell):
//   spawn daemons `wl-paste --watch cliphist store` and
//   `wl-paste --type image --watch .../clip-path-watcher.py save`
//   (see niri/spawn-at-startup.kdl + niri/spawn-quickshell.kdl),
//   scripts/clip-path-watcher.py, clipboard-offer.py, clipboard-pick.py,
//   clear-clipboard.sh, clipboard-delete-last.sh, clipboard-save-image.sh,
//   copyq (+ Mod+C `copyq toggle`).
//
// Mod+Shift+C/V/D semantics (binds.kdl unchanged; mirrored as buttons):
//   Mod+Shift+C -> scripts/clear-clipboard.sh (wipe live + history)
//   Mod+Shift+V -> scripts/clipboard-save-image.sh (save clipboard image)
//   Mod+Shift+D -> scripts/clipboard-delete-last.sh (delete newest entry)
// Buttons below dispatch to the same scripts; Delete-key/middle-click
//   delete uses `echo <id> | cliphist delete` with the same 3x retry loop
//   as clipboard-delete-last.sh (watcher holds the BoltDB write lock).
//
// Suggested trigger (for the binds/bar owner — do NOT edit here):
//   waybar clipboard module on-click today runs clipboard.sh; point it at:
//     `qs -c sunset ipc call clipboard toggle`
//   and/or add e.g. Mod+V { spawn-sh "qs -c sunset ipc call clipboard toggle"; }
//
// niri layer-rule doc (for the shell owner — do NOT edit rules.kdl here):
//   layer-rule { match namespace="sunset-clipboard" ... }
//   Verify while running: `niri msg layers`
//
// IPC: `qs -c sunset ipc call clipboard toggle`
//      (also: open, close, refresh)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // ---- theme (taste.md Sunset Orange AMOLED + fuzzel clipboard.ini) ----
    readonly property color bg: "#f2000000" // fuzzel background #000000f2
    readonly property color textCol: "#fff7c7a1" // fuzzel text #f7c7a1ff
    readonly property color accent: "#ffe85d2f" // fuzzel selection #e85d2fff
    readonly property color accentHover: "#ffff8b4a" // fuzzel match #ff8b4aff
    readonly property color muted: "#aa7c8a6a" // fuzzel placeholder #7c8a6aaa
    readonly property color selText: "#ff000000" // fuzzel selection-text
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int menuWidth: 860 // fuzzel clipboard width=60 (wider)
    readonly property int maxRows: 12 // fuzzel lines=12
    readonly property int rowHeight: 32 // fuzzel line-height=32

    readonly property string repoHome: "/home/me/niri-setup"
    readonly property string pickScript: repoHome + "/waybar/scripts/clipboard-pick.py"
    readonly property string clearScript: repoHome + "/scripts/clear-clipboard.sh"
    readonly property string saveImageScript: repoHome + "/scripts/clipboard-save-image.sh"
    readonly property string deleteLastScript: repoHome + "/scripts/clipboard-delete-last.sh"

    property bool isOpen: false
    property string query: ""
    // All entries: { cid, preview, kind: "img"|"txt" } (newest first).
    property var entries: []
    // Filtered view over entries.
    property var view: []

    function open(): void {
        query = "";
        clipInput.text = "";
        isOpen = true;
        refresh();
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

    function refresh(): void {
        // One-shot `cliphist list`; rows accumulate via SplitParser, the
        // filtered view rebuilds when the process exits.
        pending = [];
        listProc.exec({
            "command": ["cliphist", "list"]
        });
    }

    function appendLine(line: string): void {
        if (line === "")
            return;
        const tab = line.indexOf("\t");
        if (tab === -1)
            return;
        const cid = line.slice(0, tab).trim();
        if (!/^[0-9]+$/.test(cid))
            return;
        const preview = line.slice(tab + 1);
        pending.push({
            "cid": cid,
            "preview": preview,
            "kind": preview.indexOf("binary data") !== -1 ? "img" : "txt"
        });
    }

    property var pending: []

    function finishList(): void {
        entries = pending;
        pending = [];
        refilter();
    }

    // fzf-style subsequence score (match-mode=fzf parity). -1e9 = no match.
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
            score += (found === si) ? 5 : 1;
            score -= (found - si);
            si = found + 1;
        }
        score -= first;
        return score;
    }

    function refilter(): void {
        const q = query.trim().toLowerCase();
        if (q === "") {
            view = entries.slice();
        } else {
            let scored = [];
            for (let i = 0; i < entries.length; ++i) {
                const s = root.fzfScore(q, entries[i].preview);
                if (s > -1e8)
                    scored.push({
                        "e": entries[i],
                        "s": s
                    });
            }
            scored.sort((a, b) => b.s - a.s);
            let out = [];
            for (let k = 0; k < scored.length; ++k)
                out.push(scored[k].e);
            view = out;
        }
        clipList.currentIndex = view.length > 0 ? 0 : -1;
    }

    function validCid(cid: string): bool {
        return /^[0-9]+$/.test(cid);
    }

    function restoreCurrent(): void {
        if (clipList.currentIndex < 0 || clipList.currentIndex >= view.length)
            return;
        restoreEntry(view[clipList.currentIndex]);
    }

    function restoreEntry(row): void {
        if (!row || !validCid(row.cid))
            return;
        // Same pipeline as waybar/scripts/clipboard.sh:
        // selected `cliphist list` line -> clipboard-pick.py, which decodes
        // the id itself and preserves the image+path pairing from
        // clip-path-watcher.py (~/.cache/cliphist/images/).
        restoreProc.exec(["sh", "-c", "printf '%s\\t\\n' '" + row.cid + "' | '" + root.pickScript + "'"]);
        close();
    }

    function deleteEntry(row): void {
        if (!row || !validCid(row.cid))
            return;
        // Same retry loop as scripts/clipboard-delete-last.sh: the
        // `wl-paste --watch cliphist store` daemon can hold the BoltDB lock.
        deleteProc.exec(["sh", "-c", "for i in 1 2 3; do echo '" + row.cid + "' | cliphist delete 2>/dev/null && break; sleep 0.1; done"]);
    }

    function deleteCurrent(): void {
        if (clipList.currentIndex < 0 || clipList.currentIndex >= view.length)
            return;
        deleteEntry(view[clipList.currentIndex]);
    }

    function clearAll(): void {
        // Mod+Shift+C semantics: scripts/clear-clipboard.sh.
        Quickshell.execDetached([root.clearScript]);
        close();
    }

    function saveImage(): void {
        // Mod+Shift+V semantics: scripts/clipboard-save-image.sh.
        Quickshell.execDetached([root.saveImageScript]);
        close();
    }

    function deleteLast(): void {
        // Mod+Shift+D semantics: scripts/clipboard-delete-last.sh.
        Quickshell.execDetached([root.deleteLastScript]);
        close();
    }

    function moveSelection(delta: int): void {
        if (view.length === 0)
            return;
        let idx = clipList.currentIndex + delta;
        if (idx < 0)
            idx = 0;
        if (idx >= view.length)
            idx = view.length - 1;
        clipList.currentIndex = idx;
        clipList.positionViewAtIndex(idx, ListView.Contain);
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: clipInput.forceActiveFocus()
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: SplitParser {
            onRead: (data) => root.appendLine(data)
        }
        onExited: root.finishList()
    }

    // Fire-and-forget restore; pick script exits on its own after wl-copy /
    // clipboard-offer.py handoff.
    Process {
        id: restoreProc
    }

    Process {
        id: deleteProc
        onExited: {
            if (root.isOpen)
                root.refresh();
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
        WlrLayershell.namespace: "sunset-clipboard"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(root.menuWidth, parent.width - 48)
            // Content-driven: input + list + empty-state + buttons.
            // All terms are intrinsic (no parent-height cycle).
            height: inputRow.height + clipList.height + emptyLabel.height + buttonRow.height + 56
            radius: 12 // fuzzel [border] radius (intentional taste.md exception)
            color: root.bg
            border.width: 2
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
                        // fuzzel clipboard prompt="  "
                        text: "  "
                        font.family: root.fontFamily
                        font.pointSize: 13
                        font.bold: true
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
                            visible: clipInput.text === ""
                            text: "Search clipboard..."
                            font.family: root.fontFamily
                            font.pointSize: 13
                            color: root.muted
                            elide: Text.ElideRight
                        }

                        TextInput {
                            id: clipInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: root.fontFamily
                            font.pointSize: 13
                            font.bold: true
                            color: root.textCol
                            cursorVisible: true
                            onTextChanged: {
                                root.query = text;
                                root.refilter();
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
                                    root.restoreCurrent();
                                } else if (event.key === Qt.Key_Delete) {
                                    event.accepted = true;
                                    root.deleteCurrent();
                                }
                            }
                        }
                    }

                    Text {
                        id: counterText
                        text: root.view.length + "/" + root.entries.length
                        font.family: root.fontFamily
                        font.pointSize: 11
                        color: root.muted
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    id: clipList
                    width: parent.width
                    height: root.view.length > 0 ? Math.min(root.view.length, root.maxRows) * root.rowHeight : 0
                    clip: true
                    model: root.view
                    keyNavigationWraps: true
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            event.accepted = true;
                            root.close();
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            event.accepted = true;
                            root.restoreCurrent();
                        } else if (event.key === Qt.Key_Delete) {
                            event.accepted = true;
                            root.deleteCurrent();
                        }
                    }

                    delegate: Rectangle {
                        id: row
                        property var rowData: modelData
                        width: clipList.width
                        height: root.rowHeight
                        radius: 6
                        color: clipList.currentIndex === index ? root.accent : "transparent"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                // Image entries (binary sidecars from
                                // clip-path-watcher.py) get an accent badge.
                                visible: row.rowData && row.rowData.kind === "img"
                                text: "[IMG]"
                                font.family: root.fontFamily
                                font.pointSize: 10
                                font.bold: true
                                color: clipList.currentIndex === index ? root.selText : root.accentHover
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                width: parent.width - (row.rowData && row.rowData.kind === "img" ? 52 : 0)
                                text: row.rowData ? row.rowData.preview : ""
                                font.family: root.fontFamily
                                font.pointSize: 11
                                color: clipList.currentIndex === index ? root.selText : root.textCol
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            // middle-click deletes the entry (middle-clear).
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            hoverEnabled: true
                            onEntered: clipList.currentIndex = index
                            onClicked: (mouse) => {
                                clipList.currentIndex = index;
                                if (mouse.button === Qt.MiddleButton)
                                    root.deleteEntry(row.rowData);
                                else
                                    clipInput.forceActiveFocus();
                            }
                            onDoubleClicked: root.restoreCurrent()
                        }
                    }
                }

                Text {
                    id: emptyLabel
                    visible: root.view.length === 0
                    height: visible ? implicitHeight : 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.entries.length === 0 ? "Clipboard history empty" : "No match"
                    font.family: root.fontFamily
                    font.pointSize: 11
                    color: root.muted
                }

                Row {
                    id: buttonRow
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: [
                            {
                                "label": "Clear (Mod+Shift+C)",
                                "fn": "clear"
                            },
                            {
                                "label": "Save img (Mod+Shift+V)",
                                "fn": "save"
                            },
                            {
                                "label": "Del last (Mod+Shift+D)",
                                "fn": "last"
                            }
                        ]

                        Rectangle {
                            required property var modelData
                            width: (buttonRow.width - 16) / 3
                            height: 30
                            radius: 6
                            color: btnArea.containsMouse ? root.accent : "#141010" // taste --row
                            border.width: 1
                            border.color: "#3D2B24" // taste --border-strong

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                font.family: root.fontFamily
                                font.pointSize: 10
                                color: btnArea.containsMouse ? root.selText : root.textCol
                            }

                            MouseArea {
                                id: btnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (parent.modelData.fn === "clear")
                                        root.clearAll();
                                    else if (parent.modelData.fn === "save")
                                        root.saveImage();
                                    else
                                        root.deleteLast();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        function refresh(): void {
            root.refresh();
        }
    }
}
