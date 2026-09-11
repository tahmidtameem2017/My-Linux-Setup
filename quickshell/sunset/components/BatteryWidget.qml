// BatteryWidget.qml — UPower displayDevice icon + level (waybar group/battery:
// image#battery + battery). Collapses (visible false) on desktops with no
// battery — waybar parity with battery-icon.sh printing blank when
// /sys/class/power_supply/BAT* is missing.
//   Click (verbatim, as in waybar battery on-click):
//     alacritty --config-file /home/me/niri-setup/alacritty/float.toml -e btop
// Text parity: "NN%" discharging, "+NN%" charging (format-charging).
// Colors: root.cText, warning (<=30%) root.cAccentHover, critical (<=20%)
// root.cAccent — the waybar warning/critical thresholds. Sharp, no blur.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
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
    radius: 0
    color: root.cPanel
    border.width: 1
    border.color: batArea.containsMouse ? root.cBorderStrong : root.cBorder
    implicitWidth: batRow.implicitWidth + 24
    implicitHeight: 24
    Layout.alignment: Qt.AlignVCenter

    visible: root.present

    readonly property var dev: UPower.displayDevice
    readonly property bool present: root.dev != null && root.dev.isPresent !== false
    readonly property real frac: {
        if (!root.dev)
            return 0;
        if (root.dev.percentage !== undefined && root.dev.percentage !== null) {
            const p = Number(root.dev.percentage);
            return p > 1 ? p / 100 : p;
        }
        if (root.dev.percent !== undefined && root.dev.percent !== null) {
            const q = Number(root.dev.percent);
            return q > 1 ? q / 100 : q;
        }
        return 0;
    }
    readonly property int pct: Math.round(root.frac * 100)
    readonly property bool charging: {
        if (!root.dev)
            return false;
        const s = root.dev.state;
        try {
            if (typeof UPowerDeviceState !== "undefined" && s === UPowerDeviceState.Charging)
                return true;
        } catch (e) {}
        return s === 1 || String(s).toLowerCase().indexOf("charg") >= 0;
    }

    Row {
        id: batRow
        anchors.centerIn: parent
        spacing: 4

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            source: root.charging ? "file:///home/me/niri-setup/waybar/icons/battery-charging.svg" : "file:///home/me/niri-setup/waybar/icons/battery.svg"
            opacity: batArea.containsMouse ? 0.65 : 1.0
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (root.charging ? "+" : "") + root.pct + "%"
            font.family: "JetBrainsMono Nerd Font"
            font.pointSize: 10
            color: root.pct <= 20 ? root.cAccent : (root.pct <= 30 || batArea.containsMouse ? root.cAccentHover : root.cText)
        }
    }

    MouseArea {
        id: batArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["alacritty", "--config-file", "/home/me/niri-setup/alacritty/float.toml", "-e", "btop"])
    }
}
