// Bar.qml — sunset top bar. Mirrors waybar/config module order.
//   left:   logo | workspaces | window
//   center: clock
//   right:  media | volume | network | clipboard | wallpaper | settings | battery | power
//
// PanelWindow anchored top/left/right, height 32. Sharp rects (radius 0),
// no blur anywhere. Colors via Theme tokens only.
// All popup/launcher toggles go through IpcHandler targets:
//   `qs -c sunset ipc call <calendar|volume|wallpaper|settings|power|launcher|clipboard> toggle`

import QtQuick
import QtQuick.Layouts
import Quickshell
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
    implicitHeight: 32
    exclusiveZone: 32
    color: bar.cBg

    Rectangle {
        anchors.fill: parent
        color: bar.cBg

        // macOS-style: left/right clusters hug the edges; the clock is
        // pinned to the true screen center, immune to title/preset widths.
        RowLayout {
            id: leftRow
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            spacing: 0

            // ---- left (waybar modules-left) ----
            TrayWidgets.LogoIcon {
                cBorder: bar.cBorder
                cBorderStrong: bar.cBorderStrong
                cPanel: bar.cPanel}
            Workspaces {}
            WindowWidget {}
        }

        ClockWidget {
            id: clockWidget
            anchors {
                horizontalCenter: parent.horizontalCenter
                verticalCenter: parent.verticalCenter
            }
        }

        RowLayout {
            id: rightRow
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            spacing: 0

            // ---- right (waybar modules-right order) ----
            MediaWidget {}
            VolumeWidget {}
            TrayWidgets.NetworkIcon {
                cBorder: bar.cBorder
                cBorderStrong: bar.cBorderStrong
                cPanel: bar.cPanel}
            TrayWidgets.ClipboardIcon {
                cBorder: bar.cBorder
                cBorderStrong: bar.cBorderStrong
                cPanel: bar.cPanel}
            TrayWidgets.WallpaperIcon {
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
    }
}
