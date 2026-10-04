// Bar.qml — sunset top bar. Mirrors waybar/config module order.
//   left:   logo | workspaces | window
//   center: weather + clock + pomodoro (the group is re-centered on every
//           width change, so the cluster never looks lopsided)
//   right:  media | volume | bluetooth | network | settings | battery | power
//
// PanelWindow anchored top/left/right, height 34. Sharp rects (radius 0),
// no blur anywhere. Colors via Theme tokens only.
// Entrance: subtle slide-down on load (entryY -34 -> 0, 180ms OutCubic, startup-only).
// 1px bottom accent hairline (accent at 35% opacity).
// All popup/launcher toggles go through IpcHandler targets:
//   `qs -c sunset ipc call <calendar|volume|wallpaper|settings|power|launcher|clipboard> toggle`

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

PanelWindow {
    id: bar
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
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: 34
    exclusiveZone: 34
    color: bar.cBg

    // Right click anywhere on the bar (except widgets that claim the right
    // button themselves, e.g. VolumeWidget mute) opens the bar context menu.
    // shell.qml routes this to ContextMenu.openBar(); the point is (click x,
    // bar bottom) so the menu drops below the bar.
    signal contextMenuRequested(real x, real y)

    // Entrance: subtle slide-down on load (y -34 -> 0, 180ms OutCubic, startup-only).
    property real entryY: -34
    Behavior on entryY {
        NumberAnimation {
            duration: Theme.animEnter
            easing.type: Easing.OutCubic
        }
    }
    Component.onCompleted: entryY = 0

    Rectangle {
        id: barBg
        x: 0
        y: bar.entryY
        width: parent.width
        height: parent.height
        color: bar.cBg

        // Declared first so widget MouseAreas stack above it: right clicks
        // fall through to here wherever they are not already consumed.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: (mouse) => bar.contextMenuRequested(mouse.x, barBg.y + barBg.height)
        }

        // macOS-style: left/right clusters hug the edges; the clock is
        // pinned to the true screen center, immune to title/preset widths.
        RowLayout {
            id: leftRow
            anchors {
                left: parent.left
                leftMargin: 6
                verticalCenter: parent.verticalCenter
            }
            spacing: 4

            // ---- left (waybar modules-left) ----
            TrayWidgets.LogoIcon {
                cBorder: bar.cBorder
                cBorderStrong: bar.cBorderStrong
                cPanel: bar.cPanel}
            Workspaces {}
            WindowWidget {}
        }

        // Center cluster: weather | recording | clock | capture | pomodoro,
        // centered as ONE group. Dynamic centering: the Row is anchored to
        // the bar's horizontalCenter, so every width change (recording pill
        // appearing, camera icon pinning, pomodoro pill, temperature digits)
        // makes QML re-center the whole cluster — nothing is hand-pinned.
        Row {
            id: centerRow
            anchors {
                horizontalCenter: parent.horizontalCenter
                verticalCenter: parent.verticalCenter
            }
            spacing: 0

            WeatherWidget {}
            RecordingWidget {}
            ClockWidget {}
            CaptureWidget {}
            PomodoroWidget {}
        }

        RowLayout {
            id: rightRow
            anchors {
                right: parent.right
                rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            spacing: 4

            // ---- right (waybar modules-right order) ----
            MediaWidget {}
            VolumeWidget {}
            // Mic capture indicator (MicWidget) is intentionally NOT in the bar
            // (2026-10-03, "don't need the mic icon"): the dot that lit up when
            // another process held the mic was noise, not information. The
            // component, its MicService and its test stay on disk for rollback —
            // re-add one line here to get the indicator back.
            BluetoothWidget {}
            TrayWidgets.NetworkIcon {
                cBorder: bar.cBorder
                cBorderStrong: bar.cBorderStrong
                cPanel: bar.cPanel}
            TrayWidgets.SettingsIcon {
                cBorder: bar.cBorder
                cBorderStrong: bar.cBorderStrong
                cPanel: bar.cPanel}
            BatteryWidget {}
            TrayWidgets.PowerIcon {
                cBorder: bar.cBorder
                cBorderStrong: bar.cBorderStrong
                cPanel: bar.cPanel}
        }

        // 1px bottom accent hairline (accent at 35% opacity).
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 1
            color: bar.cAccent
            opacity: 0.35
        }
    }
}
