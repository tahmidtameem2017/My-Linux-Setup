// CaptureBar.qml — the screenshot utility: one menu holding every capture
// tool (Region / Window / Screen / Scroll / Record / OCR / Shots / Videos /
// Unpin). Opened by the camera pill in the bar's center cluster, Mod+Shift+5,
// Mod+Alt+Shift+S, the launcher "Screenshot" control row, the ";" Capture mode,
// or the Screenshot row in either right-click menu.
//
// Rebuilt 2026-10-04 from the horizontal strip it used to be. Two things
// forced the rebuild, both learned the hard way:
//
//   1. keyboardFocus was WlrKeyboardFocus.None, so the FocusScope never
//      received a key. Arrow keys, Enter and Esc were silently dead — the
//      panel was mouse-only by construction, not by choice. It is Exclusive
//      now, matching every other popup.
//   2. It must never end up inside its own screenshot. run() collapses the
//      card BEFORE starting the process (see below), and that stays true now
//      that the window is keyboard-mapped rather than click-through.
//
// Keyboard: Up/Down + j/k move, Left/Right alias Up/Down (single column),
// Home/End first/last, PageUp/PageDown ±3, digits jump to a row, Tab cycles,
// Enter/Space runs, Esc closes. Mouse hover only votes after the cursor has
// actually moved (hoverArmed) so a resting cursor cannot steal the selection.
// Closing keeps the pin: the camera icon stays in the bar until Unpin.
//
// IPC: `qs -c sunset ipc call capture <verb>` with verbs
//      toggle|show|hide|unpin.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    // ---- theme (Theme.qml tokens only, no hex) ----
    readonly property color cAccent: Theme.accent
    readonly property color cAccentHover: Theme.accentHover
    readonly property color cBorder: Theme.border
    readonly property color cBorderStrong: Theme.borderStrong
    readonly property color cDim: Theme.dim
    readonly property color cFont: Theme.fontFamily
    readonly property color cMuted: Theme.muted
    readonly property color cOnAccent: Theme.onAccent
    readonly property color cPanel: Theme.panel
    readonly property int cRadius: Theme.radius
    readonly property color cRow: Theme.row
    readonly property color cText: Theme.text

    property bool isOpen: false
    readonly property string setupHome: Quickshell.env("NIRI_SETUP_HOME") ?? (Quickshell.env("HOME") + "/niri-setup")

    // Keyboard/mouse selection: 0..actions.length-1, -1 = none.
    property int current: -1
    // Mouse must not vote until it actually moves (Launcher/PowerMenu
    // hoverArmed parity): on open current is the first row even if the cursor
    // rests over another one.
    property bool hoverArmed: false

    // Every capture tool, in menu order. `cmd` is an argv array handed to a
    // single Process (CaptureBar precedent, kept); `op: "unpin"` is the one
    // row that acts on the panel itself instead of spawning anything.
    readonly property var actions: [
        { "label": "Region", "tip": "Pick an area, then annotate or redact it", "cmd": [setupHome + "/scripts/screenshot.sh", "region"] },
        { "label": "Window", "tip": "The window you are looking at", "cmd": [setupHome + "/scripts/screenshot.sh", "window"] },
        { "label": "Screen", "tip": "Everything on this screen", "cmd": [setupHome + "/scripts/screenshot.sh", "screen"] },
        { "label": "Scroll", "tip": "Long page — auto-scrolls and stitches", "cmd": [setupHome + "/scripts/scroll-screenshot.sh"] },
        { "label": "Record", "tip": "Start or stop a screen recording", "cmd": [setupHome + "/scripts/record-screen.sh"] },
        { "label": "OCR", "tip": "Copy the text out of your last screenshot", "cmd": [setupHome + "/scripts/ocr-latest.sh"] },
        { "sep": true },
        { "label": "Screenshots", "tip": "Open the screenshots folder", "cmd": ["xdg-open", (Quickshell.env("HOME") ?? "/home") + "/Pictures/Screenshots"] },
        { "label": "Videos", "tip": "Open the videos folder", "cmd": ["xdg-open", (Quickshell.env("HOME") ?? "/home") + "/Videos"] },
        { "sep": true },
        { "label": "Unpin from bar", "tip": "Hide the camera icon until you open this again", "cmd": null, "op": "unpin" }
    ]

    // How many rows a digit can address. Derived from the model rather than
    // written as 8, so adding a row cannot silently leave it unreachable.
    readonly property int runnableCount: {
        let n = 0;
        for (let i = 0; i < actions.length; ++i) {
            if (actions[i].sep !== true)
                ++n;
        }
        return n;
    }

    function toggle(): void {
        CaptureService.pin();
        isOpen = !isOpen;
        if (isOpen) {
            current = firstIndex();
            hoverArmed = false;
            focusTimer.restart();
        }
    }
    function show(): void {
        CaptureService.pin();
        if (!isOpen) {
            current = firstIndex();
            hoverArmed = false;
        }
        isOpen = true;
        focusTimer.restart();
    }
    function hide(): void { isOpen = false; }
    function unpin(): void {
        CaptureService.unpin();
        isOpen = false;
    }

    function run(cmd): void {
        // Collapse first: the row must not be in the capture.
        root.isOpen = false;
        actProc.command = cmd;
        actProc.running = true;
    }

    // ---- selection (PowerMenu nav helpers + ContextMenu separator skip) ----
    function isActionable(i: int): bool {
        return i >= 0 && i < actions.length && actions[i].sep !== true;
    }
    function firstIndex(): int {
        for (let i = 0; i < actions.length; ++i)
            if (actions[i].sep !== true)
                return i;
        return -1;
    }
    function goIndex(n: int): void {
        hoverArmed = true;
        // The digits address the runnable rows in order; the two separators
        // are skipped so they map to actions, not to model positions.
        let seen = 0;
        for (let i = 0; i < actions.length; ++i) {
            if (actions[i].sep === true)
                continue;
            if (seen === n) {
                current = i;
                return;
            }
            ++seen;
        }
    }
    // Inverse of goIndex's mapping: 0-based position among the runnable rows,
    // or -1 for a separator. The row numbers and the digit keys must agree, so
    // both read the SAME function rather than counting separately.
    function actionNumberFor(i: int): int {
        if (i < 0 || i >= actions.length || actions[i].sep === true)
            return -1;
        let seen = 0;
        for (let k = 0; k < i; ++k) {
            if (actions[k].sep !== true)
                ++seen;
        }
        return seen;
    }
    function moveSelection(delta: int): void {
        hoverArmed = true;
        if (actions.length === 0)
            return;
        let idx = current;
        for (let step = 0; step < actions.length; ++step) {
            idx += delta;
            if (idx < 0 || idx >= actions.length) {
                idx = current;
                break;
            }
            if (actions[idx].sep !== true)
                break;
        }
        if (isActionable(idx))
            current = idx;
    }
    function goFirst(): void {
        hoverArmed = true;
        current = firstIndex();
    }
    function goLast(): void {
        hoverArmed = true;
        for (let i = actions.length - 1; i >= 0; --i)
            if (actions[i].sep !== true) {
                current = i;
                return;
            }
    }
    function activateCurrent(): void {
        if (!isActionable(current))
            return;
        const a = actions[current];
        if (a.op === "unpin")
            unpin();
        else if (a.cmd)
            run(a.cmd);
    }

    readonly property string tipText: {
        if (!isActionable(current))
            return "";
        const t = actions[current].tip;
        return t !== undefined ? t : "";
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: keys.forceActiveFocus()
    }

    Process {
        id: actProc
    }

    PanelWindow {
        id: win
        visible: root.isOpen
        color: "transparent"
        anchors { top: true; left: true; right: true; bottom: true }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusive (was None): the FocusScope below can only drive the menu if
        // the surface is keyboard-mapped. See the file header.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "sunset-capture"

        // Click anywhere outside the card collapses it.
        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            implicitWidth: Math.min(340, parent.width - 32)
            implicitHeight: Math.min(col.implicitHeight + 28, parent.height - 48)
            width: implicitWidth
            height: implicitHeight
            color: root.cPanel
            border.width: 1
            border.color: root.cBorderStrong
            radius: root.cRadius
            // Popup entrance (PowerMenu parity): opacity 150ms OutCubic +
            // scale 0.96->1 180ms OutBack overshoot 1.2 + y -6->0.
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

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.hide()
                // Full keyboard nav (PowerMenu parity). Left/Right alias Up/Down
                // because this is a single column. Digits jump straight to a
                // row; a typed digit must not start a capture by accident, so
                // they only MOVE the selection — Enter still runs it.
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Up || event.key === Qt.Key_Left || event.key === Qt.Key_K) {
                        event.accepted = true;
                        root.moveSelection(-1);
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right || event.key === Qt.Key_J) {
                        event.accepted = true;
                        root.moveSelection(1);
                    } else if (event.key === Qt.Key_Home) {
                        event.accepted = true;
                        root.goFirst();
                    } else if (event.key === Qt.Key_End) {
                        event.accepted = true;
                        root.goLast();
                    } else if (event.key === Qt.Key_PageUp) {
                        event.accepted = true;
                        root.moveSelection(-3);
                    } else if (event.key === Qt.Key_PageDown) {
                        event.accepted = true;
                        root.moveSelection(3);
                    } else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.runnableCount) {
                        event.accepted = true;
                        root.goIndex(event.key - Qt.Key_1);
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        event.accepted = true;
                        root.activateCurrent();
                    }
                }
                // Tab cycles the rows; kept out of onPressed so Qt focus
                // navigation never steals it.
                Keys.onTabPressed: event => {
                    event.accepted = true;
                    root.moveSelection(1);
                }
                Keys.onBacktabPressed: event => {
                    event.accepted = true;
                    root.moveSelection(-1);
                }

                Column {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 16
                    anchors.bottomMargin: 12
                    spacing: 6

                    Row {
                        width: parent.width
                        spacing: 10

                        Image {
                            width: 16
                            height: 16
                            anchors.verticalCenter: parent.verticalCenter
                            source: "file://" + Theme.iconDir + "camera.svg"
                            fillMode: Image.PreserveAspectFit
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Capture"
                            font.family: root.cFont
                            font.pixelSize: 13
                            font.bold: true
                            color: root.cAccent
                        }
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: " "
                        font.family: root.cFont
                        font.pixelSize: 4
                    }

                    Repeater {
                        model: root.actions
                        delegate: Rectangle {
                            id: row
                            readonly property bool isSep: modelData ? modelData.sep === true : false
                            readonly property bool isCurrent: root.current === index && !isSep
                            readonly property bool lit: isCurrent || (rHover.hovered && !isSep && root.hoverArmed)
                            // 0-based position among the RUNNABLE rows, or -1 for
                            // a separator — what the digit keys address.
                            readonly property int actionNumber: root.actionNumberFor(index)
                            width: col.width
                            height: isSep ? 6 : 34
                            color: root.cRow
                            border.width: 1
                            border.color: lit ? root.cAccent : root.cBorder
                            radius: root.cRadius
                            transformOrigin: Item.Center
                            scale: rMouse.pressed ? 0.98 : 1.0
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

                            // Separator (ContextMenu parity).
                            Rectangle {
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: parent.left
                                    right: parent.right
                                    leftMargin: 8
                                    rightMargin: 8
                                }
                                visible: row.isSep
                                height: 1
                                color: root.cBorder
                            }

                            // Accent-filled selected row: text must be the
                            // MEASURED on-accent token, not bg (see AGENTS.md —
                            // half of all palettes make bg unreadable).
                            Rectangle {
                                anchors.fill: parent
                                visible: row.lit
                                color: root.cAccent
                                radius: root.cRadius
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Text {
                                    width: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignLeft
                                    text: row.isSep ? "" : (row.actionNumber >= 0 ? String(row.actionNumber + 1) : "")
                                    font.family: root.cFont
                                    font.pixelSize: 11
                                    color: row.lit ? root.cOnAccent : root.cDim
                                }

                                Text {
                                    width: parent.width - 18 - 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.isSep ? "" : modelData.label
                                    font.family: root.cFont
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: row.lit ? root.cOnAccent : ((rHover.hovered || row.isCurrent) ? root.cAccentHover : root.cText)
                                    elide: Text.ElideRight
                                }
                            }

                            HoverHandler {
                                id: rHover
                            }
                            MouseArea {
                                id: rMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                visible: !row.isSep
                                onEntered: if (root.hoverArmed)
                                    root.current = index;
                                onPositionChanged: root.hoverArmed = true;
                                onPressed: root.hoverArmed = true;
                                onClicked: {
                                    root.current = index;
                                    root.activateCurrent();
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        height: 14
                        elide: Text.ElideRight
                        text: root.tipText
                        font.family: root.cFont
                        font.pixelSize: 10
                        color: root.cMuted
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "↑/↓ + Enter run \u00B7 1–" + root.runnableCount + " jump · Tab cycle · Esc closes"
                        font.family: root.cFont
                        font.pixelSize: 10
                        color: root.cMuted
                        topPadding: 2
                        bottomPadding: 4
                    }
                }
            }
        }

        onVisibleChanged: {
            if (visible)
                focusTimer.restart();
        }
    }

    IpcHandler {
        target: "capture"
        function toggle(): void { root.toggle(); }
        function show(): void { root.show(); }
        function hide(): void { root.hide(); }
        function unpin(): void { root.unpin(); }
    }
}