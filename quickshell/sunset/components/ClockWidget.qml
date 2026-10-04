// ClockWidget.qml — HH:MM clock (waybar clock format {:%H:%M}).
// Click toggles the NATIVE calendar popup via IPC:
//   qs -c sunset ipc call calendar toggle   (no calendar.sh / Brave HTML)
// waybar parity: peach text (root.cText), orange hover (root.cAccentHover).
// Flat idle (transparent, no border); hover is a faint row wash. Sharp,
// no blur, no scale (perf: re-raster cost on weak iGPUs).

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

Rectangle {
    id: root
    // Theme aliases (nested scopes cannot see file imports).
    readonly property color cAccent: Theme.accent
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
    implicitWidth: clockLabel.implicitWidth + 24
    implicitHeight: 24
    radius: 0
    // Flat idle (transparent, no border); hover is a faint row wash only.
    color: clockArea.containsMouse ? root.cRow : "transparent"
    border.width: 0
    Layout.alignment: Qt.AlignVCenter

    Behavior on color {
        ColorAnimation {
            duration: Theme.animHover
            easing.type: Easing.OutCubic
        }
    }

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    Text {
        id: clockLabel
        anchors.centerIn: parent
        text: Qt.formatTime(sysClock.date, "HH:mm")
        font.family: "JetBrainsMono Nerd Font"
        font.pointSize: 11
        font.bold: true
        color: clockArea.containsMouse ? root.cAccentHover : root.cText

        Behavior on color {
            ColorAnimation {
                duration: Theme.animHover
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: clockArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "calendar", "toggle"])
    }
}
