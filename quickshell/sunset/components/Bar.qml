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
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: 32
    exclusiveZone: 32
    color: Theme.bg

    Rectangle {
        anchors.fill: parent
        color: Theme.bg

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ---- left (waybar modules-left) ----
            TrayWidgets.LogoIcon {}
            Workspaces {}
            WindowWidget {}

            // ---- center (waybar modules-center) ----
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ClockWidget {
                    anchors.centerIn: parent
                }
            }

            // ---- right (waybar modules-right order) ----
            MediaWidget {}
            VolumeWidget {}
            TrayWidgets.NetworkIcon {}
            TrayWidgets.ClipboardIcon {}
            TrayWidgets.WallpaperIcon {}
            TrayWidgets.SettingsIcon {}
            BatteryWidget {}
            TrayWidgets.PowerIcon {}
        }
    }
}
