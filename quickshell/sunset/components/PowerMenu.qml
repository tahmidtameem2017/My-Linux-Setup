// PowerMenu.qml — power action popup (fixed allowlist, confirm-to-run).
//
// Replaces: waybar/power/power.html + waybar/power/power-server.py +
//           launcher waybar/scripts/power-menu.sh + Brave profile
//           ~/.cache/niri-power (old app-id brave-127.0.0.2__-Default,
//           window 360x440, backend on 127.0.0.2). Also replaces the wlogout
//           frontend (wlogout/ stays on disk untouched for now). The Brave
//           profile, the power-server.py daemon and the 127.0.0.2 backend are
//           all deleted by this migration; nothing else needs them.
//
// Backend parity (from power-server.py ACTIONS — the ONLY commands that can
// ever execute; the UI can never inject anything else):
//   shutdown -> systemctl poweroff
//   reboot   -> systemctl reboot
//   suspend  -> systemctl suspend
//   logout   -> pkill niri
//   lock     -> bash scripts/swaylock.sh (repo scripts dir)
// Actions run detached (server parity: Popen start_new_session, so the
// response/close is never killed by its own shutdown/reboot/logout).
// UX parity (from power.html): lock runs at once; the rest arm on first
// click ("Click again to confirm", danger styling) and fire on second
// click; arming expires after 5s; Esc/Close/outside-click disarms+closes.
//
// Shell contract (landed sunset pattern, cf. ClipboardPopup/Launcher):
//   - exclusiveKeyboardFocus == WlrLayershell.keyboardFocus Exclusive.
//   - Card width 360 (old 360x440 window); height is content-driven.
//   - niri layer-rule doc (shell owner adds, do NOT edit rules.kdl here):
//       layer-rule { match namespace="sunset-power" }
//     Verify: `niri msg layers`
// IPC: `qs -c sunset ipc call power toggle` (also: open, close)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root
    // Theme aliases (nested scopes cannot see file imports).
    readonly property color cAccent: Theme.accent
    readonly property color cDanger: Theme.danger
    readonly property color cAccentHover: Theme.accentHover
    readonly property color cBg: Theme.bg
    readonly property color cBorder: Theme.border
    readonly property color cBorderStrong: Theme.borderStrong
    readonly property color cDim: Theme.dim
    readonly property string cFontFamily: Theme.fontFamily
    readonly property color cMuted: Theme.muted
    readonly property color cPanel: Theme.panel
    readonly property int cRadius: Theme.radius
    readonly property color cRow: Theme.row
    readonly property color cText: Theme.text

    property bool isOpen: false
    // Task term "exclusiveKeyboardFocus" == the Exclusive layer-shell
    // keyboard focus set on the PanelWindow below.
    readonly property bool exclusiveKeyboardFocus: true

    // Armed (awaiting confirm) row index; -1 = none.
    property int armed: -1
    // Keyboard/mouse selection: 0..actions.length-1 = actions,
    // actions.length = Close row.
    property int current: 0
    // Mouse must not vote until the user actually moves it (Launcher
    // hoverArmed parity): on open current stays 0 even if the cursor
    // rests over another row. Armed on first mouse move/press or any
    // keyboard navigation; click arms too.
    property bool hoverArmed: false

    function open(): void {
        current = 0;
        hoverArmed = false;
        isOpen = true;
        focusTimer.restart();
    }
    function close(): void {
        armed = -1;
        isOpen = false;
    }
    function toggle(): void {
        if (isOpen)
            close();
        else
            open();
    }

    readonly property string swaylockScript: (Quickshell.env("NIRI_SETUP_HOME") ?? (Quickshell.env("HOME") + "/niri-setup")) + "/scripts/swaylock.sh"

    // Fixed allowlist. Order + labels mirror power.html.
    readonly property var actions: [
        {
            "op": "lock",
            "label": "Lock",
            "glyph": "󰌾"
        },
        {
            "op": "suspend",
            "label": "Suspend",
            "glyph": "󰒲"
        },
        {
            "op": "logout",
            "label": "Logout",
            "glyph": "󰗽"
        },
        {
            "op": "reboot",
            "label": "Reboot",
            "glyph": "󰜉"
        },
        {
            "op": "shutdown",
            "label": "Shutdown",
            "glyph": "󰐥"
        }
    ]

    function runOp(op: string): void {
        if (op === "shutdown")
            Quickshell.execDetached(["systemctl", "poweroff"]);
        else if (op === "reboot")
            Quickshell.execDetached(["systemctl", "reboot"]);
        else if (op === "suspend")
            Quickshell.execDetached(["systemctl", "suspend"]);
        else if (op === "logout")
            Quickshell.execDetached(["pkill", "niri"]);
        else if (op === "lock")
            Quickshell.execDetached(["bash", swaylockScript]);
        else
            return; // unknown op: never execute anything (allowlist parity)
    }

    function press(i: int): void {
        const op = actions[i].op;
        if (op === "lock") {
            runOp(op);
            close();
            return;
        }
        if (armed !== i) {
            armed = i;
            disarmTimer.restart();
            return;
        }
        disarmTimer.stop();
        armed = -1;
        runOp(op);
        close();
    }

    Timer {
        id: disarmTimer
        interval: 5000
        running: false
        repeat: false
        onTriggered: root.armed = -1
    }

    // Re-assert keyboard focus on open (Launcher/WallpaperMenu parity:
    // onVisibleChanged restarts this; visible mapping lags isOpen).
    Timer {
        id: focusTimer
        interval: 60
        running: false
        repeat: false
        onTriggered: keys.forceActiveFocus()
    }

    function moveSelection(delta: int): void {
        hoverArmed = true;
        const n = root.actions.length + 1; // actions + Close
        let idx = current + delta;
        if (idx < 0)
            idx = 0;
        if (idx >= n)
            idx = n - 1;
        current = idx;
    }

    function goFirst(): void {
        hoverArmed = true;
        current = 0;
    }

    function goLast(): void {
        hoverArmed = true;
        current = root.actions.length;
    }

    function activateCurrent(): void {
        if (current < 0 || current > root.actions.length)
            return;
        if (current === root.actions.length) {
            close();
            return;
        }
        press(current);
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
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "sunset-power"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            // Old Brave window was 360 wide; height is content-driven.
            implicitWidth: Math.min(360, parent.width - 32)
            implicitHeight: Math.min(col.implicitHeight + 28, parent.height - 48)
            width: implicitWidth
            height: implicitHeight
            color: root.cPanel
            border.width: 1
            border.color: root.cBorderStrong
            radius: root.cRadius
            // Micro-animation: subtle entrance (opacity 150ms OutCubic +
            // scale 0.96->1 180ms OutBack overshoot 1.2 + y -6->0).
            // Close stays instant (visible flips with isOpen, <200ms).
            // Destructive 2-click confirm (press/armed/disarmTimer) untouched.
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
                Keys.onEscapePressed: root.close()
                // Full keyboard nav (WallpaperMenu list parity): Up/Down +
                // Left/Right (single column, so Left=Up, Right=Down) + j/k,
                // Home/End first/last, PageUp/PageDown ±3, Enter/Space
                // activates (lock at once, rest arm-then-confirm via press).
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
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        event.accepted = true;
                        root.activateCurrent();
                    }
                }
                // Tab cycles the rows (Tab next, Shift+Tab prev); kept out
                // of onPressed so Qt focus navigation never steals it.
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
                    spacing: 8

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "POWER"
                        font.family: root.cFontFamily
                        font.pixelSize: 12
                        font.bold: true
                        color: root.cAccent
                    }
                    Item {
                        width: parent.width
                        height: 4
                    }

                    Repeater {
                        model: root.actions
                        delegate: Rectangle {
                            readonly property bool isArmed: root.armed === index
                            readonly property bool isCurrent: root.current === index
                            width: col.width
                            height: 50
                            color: root.cRow
                            border.width: 1
                            border.color: isArmed ? root.cDanger : ((pHover.hovered || isCurrent) ? root.cAccent : root.cBorder)
                            radius: root.cRadius
                            // Hover -> accentHover text (bindings below), press
                            // scale 0.98. Armed/danger confirm logic untouched.
                            transformOrigin: Item.Center
                            scale: pMouse.pressed ? 0.98 : 1.0
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
                            // Armed tint overlay (danger wash, Theme token only).
                            Rectangle {
                                anchors.fill: parent
                                visible: isArmed
                                color: root.cDanger
                                opacity: 0.15
                                radius: root.cRadius
                            }
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 12
                                Text {
                                    width: 26
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.glyph
                                    font.family: root.cFontFamily
                                    font.pixelSize: 18
                                    color: isArmed ? root.cDanger : root.cAccent
                                }
                                Text {
                                    width: parent.width - 26 - 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: isArmed ? "Click again to confirm" : modelData.label
                                    font.family: root.cFontFamily
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: isArmed ? root.cDanger : ((pHover.hovered || isCurrent) ? root.cAccentHover : root.cText)
                                }
                            }
                            HoverHandler {
                                id: pHover
                            }
                            MouseArea {
                                id: pMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: if (root.hoverArmed) root.current = index
                                onPositionChanged: root.hoverArmed = true
                                onPressed: root.hoverArmed = true
                                onClicked: {
                                    root.current = index;
                                    root.press(index);
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 4
                    }
                    Rectangle {
                        width: parent.width
                        height: 32
                        color: root.cRow
                        border.width: 1
                        border.color: (cHover.hovered || root.current === root.actions.length) ? root.cAccent : root.cBorderStrong
                        radius: root.cRadius
                        transformOrigin: Item.Center
                        scale: cMouse.pressed ? 0.98 : 1.0
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
                            text: "Close"
                            font.family: root.cFontFamily
                            font.pixelSize: 12
                            font.bold: true
                            color: (cHover.hovered || root.current === root.actions.length) ? root.cAccentHover : root.cText
                        }
                        HoverHandler {
                            id: cHover
                        }
                        MouseArea {
                            id: cMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: if (root.hoverArmed) root.current = root.actions.length
                            onPositionChanged: root.hoverArmed = true
                            onPressed: root.hoverArmed = true
                            onClicked: {
                                root.current = root.actions.length;
                                root.close();
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "\u2191/\u2193 + Enter select \u00B7 Tab cycle \u00B7 lock at once, rest \u00D72 \u00B7 Esc closes"
                        font.family: root.cFontFamily
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
        target: "power"

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
