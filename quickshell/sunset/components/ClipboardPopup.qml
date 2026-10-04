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
import qs.services

Scope {
    id: root

    // ---- theme (taste.md tokens; alphas are the fuzzel clipboard.ini parity) ----
    // Same treatment as Launcher.qml: the fuzzel hexes are alphas, the colours
    // are Theme tokens, so a palette switch repaints this popup too.
    readonly property color bg: Theme.withAlpha(Theme.bg, 0.95) // fuzzel background alpha f2
    readonly property color textCol: Theme.text // fuzzel text #f7c7a1ff
    readonly property color accent: Theme.accent // fuzzel selection #e85d2fff
    readonly property color accentHover: Theme.accentHover // fuzzel match #ff8b4aff
    readonly property color muted: Theme.withAlpha(Theme.muted, 0.67) // fuzzel placeholder alpha aa
    readonly property color selText: Theme.onAccent // fuzzel selection-text, measured not assumed
    readonly property color rowCol: Theme.row
    readonly property color borderStrong: Theme.borderStrong
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int menuWidth: 980
    readonly property int maxRows: 12 // fuzzel lines=12
    readonly property int rowHeight: 32 // fuzzel line-height=32

    readonly property string repoHome: "/home/me/niri-setup"
    readonly property string pickScript: repoHome + "/waybar/scripts/clipboard-pick.py"
    readonly property string clearScript: repoHome + "/scripts/clear-clipboard.sh"
    readonly property string saveImageScript: repoHome + "/scripts/clipboard-save-image.sh"
    readonly property string deleteLastScript: repoHome + "/scripts/clipboard-delete-last.sh"

    property bool isOpen: false
    property string query: ""
    // Mouse must not vote until the user actually moves it (Launcher
    // hoverArmed parity): on open the highlight stays on row 0 even if
    // the cursor rests lower over the list.
    property bool hoverArmed: false
    // All entries: { cid, preview, kind: "img"|"txt" } (newest first).
    property var entries: []
    // Filtered view over entries.
    property var view: []

    function open(): void {
        query = "";
        clipInput.text = "";
        hoverArmed = false;
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
        root.updatePreview();
    }

    // ---- preview pane state ----
    property string previewText: ""
    property string previewImage: "" // "file://...?g=N" or ""
    property int previewGen: 0
    property bool previewSawMarker: false
    property bool previewIsImg: false

    function updatePreview(): void {
        previewText = "";
        previewImage = "";
        previewSawMarker = false;
        previewIsImg = false;
        if (clipList.currentIndex < 0 || clipList.currentIndex >= view.length)
            return;
        const row = view[clipList.currentIndex];
        previewGen++;
        previewProc.exec([root.repoHome + "/scripts/clipboard-preview.sh", row.cid, row.kind]);
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
        hoverArmed = true;
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

    function goFirst(): void {
        hoverArmed = true;
        if (view.length === 0)
            return;
        clipList.currentIndex = 0;
        clipList.positionViewAtIndex(0, ListView.Contain);
    }

    function goLast(): void {
        hoverArmed = true;
        if (view.length === 0)
            return;
        const i = view.length - 1;
        clipList.currentIndex = i;
        clipList.positionViewAtIndex(i, ListView.Contain);
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

    Process {
        id: previewProc
        stdout: SplitParser {
            onRead: (data) => {
                if (!root.previewSawMarker) {
                    root.previewSawMarker = true;
                    if (data.indexOf("IMG ") === 0) {
                        root.previewIsImg = true;
                        root.previewImage = "file://" + data.slice(4) + "?g=" + root.previewGen;
                    }
                } else if (!root.previewIsImg) {
                    root.previewText += (root.previewText === "" ? "" : "\n") + data;
                }
            }
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
            // Content-driven: input + pane row + empty-state + buttons.
            // All terms are intrinsic (no parent-height cycle).
            height: inputRow.height + paneRow.height + emptyLabel.height + buttonRow.height + 56
            radius: 12 // fuzzel [border] radius (intentional taste.md exception)
            color: root.bg
            border.width: 2
            border.color: root.accent
            // Micro-animation: subtle entrance (opacity 150ms OutCubic +
            // scale 0.96->1 180ms OutBack overshoot 1.2 + y -6->0).
            // Close stays instant (visible flips with isOpen, <200ms).
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

            // Swallow clicks on the card background so the window-level
            // MouseArea below doesn't close the popup; also re-focus the
            // search input so arrow keys keep navigating after such a click.
            MouseArea {
                anchors.fill: parent
                onPressed: clipInput.forceActiveFocus()
                onClicked: clipInput.forceActiveFocus()
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
                                const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                                if (event.key === Qt.Key_Escape) {
                                    event.accepted = true;
                                    root.close();
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
                                    event.accepted = true;
                                    root.restoreCurrent();
                                } else if (event.key === Qt.Key_Delete) {
                                    event.accepted = true;
                                    root.deleteCurrent();
                                }
                            }
                            // Tab cycles input <-> list (focus trap); plain
                            // j/k still type (Ctrl+J/K navigate, above).
                            Keys.onTabPressed: (event) => {
                                event.accepted = true;
                                clipList.forceActiveFocus();
                            }
                            Keys.onBacktabPressed: (event) => {
                                event.accepted = true;
                                clipList.forceActiveFocus();
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

                Row {
                    id: paneRow
                    width: parent.width
                    spacing: 8
                    height: root.view.length > 0 ? Math.min(root.view.length, root.maxRows) * root.rowHeight : 0

                    ListView {
                        id: clipList
                        width: parent.width * 0.58 - 4
                        height: parent.height
                        clip: true
                        model: root.view
                        keyNavigationWraps: true
                        onCurrentIndexChanged: root.updatePreview()
                        Keys.onPressed: (event) => {
                            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                            if (event.key === Qt.Key_Escape) {
                                event.accepted = true;
                                root.close();
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
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                                event.accepted = true;
                                root.restoreCurrent();
                            } else if (event.key === Qt.Key_Delete) {
                                event.accepted = true;
                                root.deleteCurrent();
                            }
                        }
                        Keys.onTabPressed: (event) => {
                            event.accepted = true;
                            clipInput.forceActiveFocus();
                        }
                        Keys.onBacktabPressed: (event) => {
                            event.accepted = true;
                            clipInput.forceActiveFocus();
                        }

                        delegate: Rectangle {
                            id: row
                            property var rowData: modelData
                            width: clipList.width
                            height: root.rowHeight
                            radius: 6
                            color: clipList.currentIndex === index ? root.accent : "transparent"
                            transformOrigin: Item.Center
                            scale: clipMouse.pressed ? 0.98 : 1.0
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 100
                                    easing.type: Easing.OutQuad
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
                                id: clipMouse
                                anchors.fill: parent
                                // middle-click deletes the entry (middle-clear).
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                hoverEnabled: true
                                onEntered: if (root.hoverArmed) clipList.currentIndex = index
                                onPositionChanged: root.hoverArmed = true
                                onPressed: root.hoverArmed = true
                            onClicked: (mouse) => {
                                root.hoverArmed = true;
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

                    Rectangle {
                        id: previewPane
                        width: parent.width * 0.42 - 4
                        height: parent.height
                        radius: 6
                        color: root.rowCol
                        border.width: 1
                        border.color: root.borderStrong

                        Text {
                            anchors.centerIn: parent
                            visible: root.previewImage === "" && root.previewText === ""
                            text: "Preview"
                            font.family: root.fontFamily
                            font.pointSize: 11
                            color: root.muted
                        }

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 8
                            visible: root.previewImage === "" && root.previewText !== ""
                            clip: true
                            contentHeight: previewTextItem.height

                            Text {
                                id: previewTextItem
                                width: parent.width
                                text: root.previewText
                                font.family: root.fontFamily
                                font.pointSize: 10
                                color: root.textCol
                                wrapMode: Text.Wrap
                            }
                        }

                        Image {
                            anchors.fill: parent
                            anchors.margins: 8
                            visible: root.previewImage !== ""
                            source: root.previewImage
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                        }

                        // Clicking the preview pastes/restores the entry.
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.restoreCurrent()
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
                            color: btnArea.containsMouse ? root.accent : root.rowCol // taste --row
                            border.width: 1
                            border.color: root.borderStrong // taste --border-strong
                            transformOrigin: Item.Center
                            scale: btnArea.pressed ? 0.98 : 1.0
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 100
                                    easing.type: Easing.OutQuad
                                }
                            }
                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }

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
