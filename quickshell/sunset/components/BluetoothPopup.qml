// BluetoothPopup.qml — dedicated Bluetooth panel, docked top-right under the
// bar (NowPlayingPopup positioning parity: full-screen transparent window,
// card pinned to the top-right corner, slides below toasts via toastOffset).
//
// Pure view over BluetoothService (Quickshell.Bluetooth live bindings): no
// bluetoothctl, no polling. Rows connect/disconnect on click; pairing new
// devices stays in GNOME Settings (footer + empty state open it).
//
// Shell contract (landed sunset pattern, cf. NowPlayingPopup/VolumePopup):
//   - exclusiveKeyboardFocus == WlrLayershell.keyboardFocus Exclusive.
//   - Esc closes; outside-click closes; Bar re-click toggles via IPC.
//   - Card width 340; height is content-driven.
// IPC: `qs -c sunset ipc call bluetooth toggle` (also: open, close)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    // Theme aliases (inline component scopes cannot see file imports).
    readonly property color cAccent: Theme.accent
    readonly property color cAccentHover: Theme.accentHover
    readonly property color cBg: Theme.bg
    readonly property color cBorder: Theme.border
    readonly property color cBorderStrong: Theme.borderStrong
    readonly property color cDim: Theme.dim
    readonly property string cFont: Theme.fontFamily
    readonly property color cMuted: Theme.muted
    readonly property color cOnAccent: Theme.onAccent
    readonly property color cPanel: Theme.panel
    readonly property int cRadius: Theme.radius
    readonly property color cRow: Theme.row
    readonly property color cText: Theme.text

    property bool isOpen: false
    // Offset from the toast stack (shell.qml wires `toasts.occupiedHeight`).
    property real toastOffset: 0
    // Bar height, from Bar.qml (shell.qml wires `bar.implicitHeight`). The
    // card is anchored to the SCREEN top, so without this it slides under the
    // bar and loses its own header whenever no toast is up.
    property int topInset: 0

    readonly property string repoDir: Quickshell.env("NIRI_SETUP_HOME") ?? (Quickshell.env("HOME") + "/niri-setup")

    function open(): void {
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
    function searchToggle(): void {
        if (!BluetoothService.powered)
            return;
        if (BluetoothService.searchActive)
            BluetoothService.stopSearch();
        else
            BluetoothService.startSearch();
    }

    readonly property string statusText: {
        if (!BluetoothService.available)
            return "No adapter";
        if (!BluetoothService.powered)
            return "Off";
        const n = BluetoothService.connectedCount;
        return n > 0 ? "On \u00B7 " + n + " connected" : "On \u00B7 not connected";
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: keys.forceActiveFocus()
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
        WlrLayershell.namespace: "sunset-bluetooth"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            // Pinned top-right under the bar; slides below toasts.
            anchors {
                top: parent.top
                right: parent.right
                topMargin: root.topInset + root.toastOffset
                rightMargin: 0
            }
            implicitWidth: Math.min(340, parent.width - 24)
            implicitHeight: col.implicitHeight + 28
            width: implicitWidth
            height: implicitHeight
            color: root.cPanel
            border.width: 1
            border.color: root.cBorderStrong
            radius: root.cRadius
            transformOrigin: Item.TopRight
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

                Column {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    // ---- header: search button + title + power switch ----
                    Item {
                        width: parent.width
                        height: 22

                        Rectangle {
                            id: searchBtn
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 22
                            radius: root.cRadius
                            color: searchMouse.containsMouse ? root.cRow : "transparent"
                            opacity: BluetoothService.powered ? 1.0 : 0.4

                            Image {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                fillMode: Image.PreserveAspectFit
                                source: "file://" + Theme.iconDir + "refresh.svg"
                                opacity: searchMouse.containsMouse ? 0.65 : 1.0

                                RotationAnimation on rotation {
                                    running: BluetoothService.searchActive && !Theme.reduceMotion
                                    from: 0
                                    to: 360
                                    duration: 1200
                                    loops: Animation.Infinite
                                }
                            }
                            MouseArea {
                                id: searchMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.searchToggle()
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "BLUETOOTH"
                            font.family: root.cFont
                            font.pixelSize: 11
                            font.bold: true
                            color: root.cAccent
                        }

                        Rectangle {
                            id: powerSwitch
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 18
                            radius: 9
                            color: BluetoothService.powered ? root.cAccent : root.cRow
                            border.width: 1
                            border.color: BluetoothService.powered ? root.cAccent : root.cBorderStrong

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.animFast
                                }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: BluetoothService.powered ? parent.width - width - 3 : 3
                                width: 12
                                height: 12
                                radius: 6
                                color: BluetoothService.powered ? root.cOnAccent : root.cDim

                                Behavior on x {
                                    NumberAnimation {
                                        duration: Theme.animFast
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: BluetoothService.togglePower()
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: BluetoothService.searchActive ? "Searching\u2026" : root.statusText
                        font.family: root.cFont
                        font.pixelSize: 10
                        color: root.cMuted
                    }
                    Text {
                        width: parent.width
                        visible: BluetoothService.available
                        horizontalAlignment: Text.AlignHCenter
                        text: "this PC appears as \"" + BluetoothService.adapterName + "\""
                        font.family: root.cFont
                        font.pixelSize: 10
                        color: root.cDim
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.cBorder
                    }

                    // ---- device list ----
                    ListView {
                        width: parent.width
                        height: Math.min(contentHeight, 220)
                        visible: BluetoothService.powered && BluetoothService.devices.length > 0
                        model: BluetoothService.devices
                        clip: true
                        interactive: contentHeight > height

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 38
                            radius: root.cRadius
                            color: devHover.hovered ? root.cRow : "transparent"
                            border.width: 1
                            border.color: modelData.connected ? root.cAccent : "transparent"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Text {
                                    width: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: BluetoothService.glyph(modelData.icon)
                                    font.family: root.cFont
                                    font.pixelSize: 15
                                    color: modelData.connected ? root.cAccent : root.cDim
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 20 - 92 - 20
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: BluetoothService.displayName(modelData)
                                        font.family: root.cFont
                                        font.pixelSize: 12
                                        color: devHover.hovered ? root.cAccentHover : root.cText
                                    }
                                    Text {
                                        readonly property int bat: BluetoothService.batteryPercent(modelData)
                                        visible: bat >= 0
                                        text: bat + "% battery"
                                        font.family: root.cFont
                                        font.pixelSize: 10
                                        color: root.cMuted
                                    }
                                }
                                Text {
                                    width: 92
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: BluetoothService.stateLabel(modelData)
                                    font.family: root.cFont
                                    font.pixelSize: 10
                                    color: modelData.connected ? root.cAccent : root.cMuted
                                }
                            }
                            HoverHandler {
                                id: devHover
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: BluetoothService.toggleConnection(modelData)
                            }
                        }
                    }

                    // ---- empty / off / no-adapter states ----
                    Text {
                        width: parent.width
                        visible: !BluetoothService.available
                        horizontalAlignment: Text.AlignHCenter
                        text: "No Bluetooth adapter found"
                        font.family: root.cFont
                        font.pixelSize: 11
                        color: root.cMuted
                        topPadding: 6
                        bottomPadding: 6
                    }
                    Text {
                        width: parent.width
                        visible: BluetoothService.available && !BluetoothService.powered
                        horizontalAlignment: Text.AlignHCenter
                        text: "Bluetooth is off"
                        font.family: root.cFont
                        font.pixelSize: 11
                        color: root.cMuted
                        topPadding: 6
                        bottomPadding: 6
                    }
                    Rectangle {
                        width: parent.width
                        height: 30
                        visible: BluetoothService.powered && BluetoothService.devices.length === 0
                        color: "transparent"
                        radius: root.cRadius
                        Text {
                            anchors.centerIn: parent
                            text: "No paired devices \u2014 open Settings to pair"
                            font.family: root.cFont
                            font.pixelSize: 11
                            color: btEmptyHover.hovered ? root.cAccentHover : root.cMuted
                        }
                        HoverHandler {
                            id: btEmptyHover
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached([root.repoDir + "/scripts/gnome-settings.sh", "bluetooth"])
                        }
                    }

                    // ---- nearby (scan results) ----
                    Column {
                        width: parent.width
                        spacing: 4
                        visible: BluetoothService.searchActive

                        Text {
                            text: "NEARBY"
                            font.family: root.cFont
                            font.pixelSize: 11
                            font.bold: true
                            color: root.cAccent
                            bottomPadding: 2
                        }
                        Text {
                            width: parent.width
                            visible: BluetoothService.nearby.length === 0
                            horizontalAlignment: Text.AlignHCenter
                            text: "Looking for devices\u2026"
                            font.family: root.cFont
                            font.pixelSize: 11
                            color: root.cMuted
                            topPadding: 4
                            bottomPadding: 4
                        }
                        // BLE gadgets advertise a random address and no name
                        // until paired/connected; a phone only broadcasts its
                        // name while its Bluetooth settings screen is open.
                        Text {
                            width: parent.width
                            visible: BluetoothService.nearby.length > 0
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: "Address-only entries broadcast no name \u2014 on a phone, open its Bluetooth screen to make it show up by name"
                            font.family: root.cFont
                            font.pixelSize: 9
                            color: root.cDim
                            topPadding: 2
                            bottomPadding: 2
                        }
                        ListView {
                            width: parent.width
                            height: Math.min(contentHeight, 140)
                            visible: BluetoothService.nearby.length > 0
                            model: BluetoothService.nearby
                            clip: true
                            interactive: contentHeight > height

                            delegate: Rectangle {
                                required property var modelData
                                width: ListView.view.width
                                height: 34
                                radius: root.cRadius
                                color: nearHover.hovered ? root.cRow : "transparent"

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Text {
                                        width: 20
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        text: BluetoothService.glyph(modelData.icon)
                                        font.family: root.cFont
                                        font.pixelSize: 14
                                        color: root.cDim
                                    }
                                    Text {
                                        width: parent.width - 20 - 92 - 20
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        text: BluetoothService.nearbyLabel(modelData)
                                        font.family: root.cFont
                                        font.pixelSize: 12
                                        color: nearHover.hovered ? root.cAccentHover : root.cText
                                    }
                                    Text {
                                        width: 92
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: modelData.pairing ? "pairing\u2026" : "tap to pair"
                                        font.family: root.cFont
                                        font.pixelSize: 10
                                        color: root.cMuted
                                    }
                                }
                                HoverHandler {
                                    id: nearHover
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: BluetoothService.pairAndConnect(modelData)
                                }
                            }
                        }
                    }

                    // ---- footer ----
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.cBorder
                    }
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: root.cRadius
                        color: settingsHover.hovered ? root.cRow : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "Open Settings"
                            font.family: root.cFont
                            font.pixelSize: 11
                            color: settingsHover.hovered ? root.cAccentHover : root.cMuted
                        }
                        HoverHandler {
                            id: settingsHover
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.execDetached([root.repoDir + "/scripts/gnome-settings.sh", "bluetooth"]);
                                root.close();
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "bluetooth"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.open();
        }
        function close(): void {
            root.close();
        }
        // Start/stop a 25s discovery session (same path as the header button).
        function search(): void {
            root.searchToggle();
        }
    }
}
