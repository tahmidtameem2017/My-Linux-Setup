// ClockWidget.qml — HH:MM clock (waybar clock format {:%H:%M}).
// Click toggles the NATIVE calendar popup via IPC:
//   qs -c sunset ipc call calendar toggle   (no calendar.sh / Brave HTML)
// waybar parity: peach text (Theme.text), orange hover (Theme.accentHover),
// section-box look (Theme.panel + Theme.border, sharp, no blur).

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

Rectangle {
    id: root
    implicitWidth: clockLabel.implicitWidth + 24
    implicitHeight: 24
    radius: 0
    color: Theme.panel
    border.width: 1
    border.color: clockArea.containsMouse ? Theme.borderStrong : Theme.border
    Layout.alignment: Qt.AlignVCenter

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
        color: clockArea.containsMouse ? Theme.accentHover : Theme.text
    }

    MouseArea {
        id: clockArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "calendar", "toggle"])
    }
}
