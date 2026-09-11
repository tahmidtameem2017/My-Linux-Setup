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

Scope {
    id: root

    property bool isOpen: false
    // Task term "exclusiveKeyboardFocus" == the Exclusive layer-shell
    // keyboard focus set on the PanelWindow below.
    readonly property bool exclusiveKeyboardFocus: true

    // Armed (awaiting confirm) row index; -1 = none.
    property int armed: -1

    function open(): void {
        isOpen = true;
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
            color: Theme.panel
            border.width: 1
            border.color: Theme.borderStrong
            radius: Theme.radius

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.close()

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
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        color: Theme.accent
                    }
                    Item {
                        width: parent.width
                        height: 4
                    }

                    Repeater {
                        model: root.actions
                        delegate: Rectangle {
                            readonly property bool isArmed: root.armed === index
                            width: col.width
                            height: 50
                            color: Theme.row
                            border.width: 1
                            border.color: isArmed ? Theme.danger : (pHover.hovered ? Theme.accent : Theme.border)
                            radius: Theme.radius
                            // Armed tint overlay (danger wash, Theme token only).
                            Rectangle {
                                anchors.fill: parent
                                visible: isArmed
                                color: Theme.danger
                                opacity: 0.15
                                radius: Theme.radius
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
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 18
                                    color: isArmed ? Theme.danger : Theme.accent
                                }
                                Text {
                                    width: parent.width - 26 - 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: isArmed ? "Click again to confirm" : modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: isArmed ? Theme.danger : (pHover.hovered ? Theme.accentHover : Theme.text)
                                }
                            }
                            HoverHandler {
                                id: pHover
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.press(index)
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
                        color: Theme.row
                        border.width: 1
                        border.color: Theme.borderStrong
                        radius: Theme.radius
                        Text {
                            anchors.centerIn: parent
                            text: "Close"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            color: cHover.hovered ? Theme.accentHover : Theme.text
                        }
                        HoverHandler {
                            id: cHover
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.close()
                        }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "lock runs at once \u00B7 the rest need a second click \u00B7 Esc closes"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.muted
                        topPadding: 2
                    }
                }
            }
        }

        onVisibleChanged: {
            if (visible)
                keys.forceActiveFocus();
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
