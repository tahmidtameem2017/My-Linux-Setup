// BluetoothWidget.qml — bar Bluetooth button (right cluster, before network).
//
// Icon pair follows the set's stateful-pair convention (volume/volume-muted,
// wifi/wifi-off): bluetooth.svg (icon step) when the adapter is powered,
// bluetooth-off.svg (dim step) when off or absent. "Connected" is the one
// thing the baked icons cannot show — ICON_ROLE_BY_SUNSET_HEX collapses
// accent/text/muted onto ONE neutral — so it is a QML-drawn accent dot,
// the same trick MicWidget uses for "recording".
//
// Left click toggles BluetoothPopup via IPC. Right click is left to the bar
// menu (MicWidget convention: this widget must NOT claim the right button).
// Power toggle lives in the popup header and in QuickSettings.

import QtQuick
import Quickshell
import qs.services

Rectangle {
    id: root
    // Theme aliases (nested scopes cannot see file imports).
    readonly property color cAccent: Theme.accent
    readonly property color cRow: Theme.row
    radius: 0
    color: btArea.containsMouse ? root.cRow : "transparent"
    border.width: 0
    implicitWidth: 14 + 24 + (connDot.visible ? 8 : 0)
    implicitHeight: 24

    Behavior on color {
        ColorAnimation {
            duration: Theme.animHover
            easing.type: Easing.OutCubic
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 0

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            // Theme.iconDir, NOT waybar/icons (rollback gold, frozen hexes).
            source: "file://" + Theme.iconDir.replace(/\/$/, "") + (BluetoothService.powered ? "/bluetooth.svg" : "/bluetooth-off.svg")
            opacity: btArea.containsMouse ? 0.65 : 1.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animFast
                }
            }
        }

        // Connected-device marker; the accent dot carries the state the
        // monochrome SVG cannot.
        Rectangle {
            id: connDot
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: root.cAccent
            visible: BluetoothService.connectedCount > 0
        }
    }

    MouseArea {
        id: btArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Left only — the right button belongs to the bar context menu.
        acceptedButtons: Qt.LeftButton
        onClicked: Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "bluetooth", "toggle"])
    }
}
