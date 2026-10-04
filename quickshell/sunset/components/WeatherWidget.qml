// WeatherWidget.qml — bar pill: condition icon + temperature.
// Lives in the bar's center cluster, left of the clock (Bar.qml). The
// cluster is a Row anchored to the bar's horizontalCenter, so this pill
// just contributes its implicitWidth and QML re-centers the group every
// time a reading changes width — nothing here is hand-pinned.
// Typography deliberately matches ClockWidget/PomodoroWidget (the two
// items flanking it): same pointSize, same bold, same text color, same
// 24px pill padding. Mismatched units (pixelSize vs pointSize) or a
// reserved text slot make the left of the cluster read as air, which is
// what unbalances the bar.
// Click toggles the weather popup via IPC:
//   qs -c sunset ipc call weather toggle

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

Rectangle {
    id: root
    readonly property color cRow: Theme.row
    readonly property color cDim: Theme.dim
    readonly property color cText: Theme.text
    readonly property color cAccentHover: Theme.accentHover

    readonly property int iconSize: 14
    // Same 12px-per-side pill padding as the clock (implicitWidth =
    // label + 24), so the reading sits equidistant from the clock edge
    // on both sides of the center cluster.
    readonly property int padX: 12

    radius: 0
    color: weatherArea.containsMouse ? root.cRow : "transparent"
    border.width: 0
    implicitWidth: weatherRow.implicitWidth + padX * 2
    implicitHeight: 24

    Behavior on color {
        ColorAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic }
    }

    Row {
        id: weatherRow
        anchors.centerIn: parent
        spacing: 4

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconSize
            height: root.iconSize
            fillMode: Image.PreserveAspectFit
            source: "file://" + Theme.iconDir + "weather.svg"
            opacity: weatherArea.containsMouse ? 0.65 : 1
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: WeatherService.temperature || "--°"
            font.family: "JetBrainsMono Nerd Font"
            font.pointSize: 11
            font.bold: true
            color: weatherArea.containsMouse ? root.cAccentHover : (WeatherService.temperature ? root.cText : root.cDim)

            Behavior on color {
                ColorAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        id: weatherArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "weather", "toggle"])
    }
}
