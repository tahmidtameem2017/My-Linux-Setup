// PerfWidget.qml — on-demand performance pill for the bar's
// malleable island (center cluster): CPU | GPU | MEM | BAT,
// live from PerfService. OFF by default — collapsed to zero
// width, so the island is just weather + clock until
// Mod+Alt+P / the launcher row / `qs -c sunset ipc call
// perf toggle` turns it on. Width (not visible) animates,
// the RecordingWidget pattern, so the island stretches and
// shrinks around it instead of snapping.
//   Click: btop in a floating Alacritty (BatteryWidget
//   precedent — the pill is the glance, btop is the detail).
// Segments with no sensor are hidden (gpuBusy/gpuMhz/batPct
// are -1/0 when absent), so a desktop shows CPU | GPU | MEM
// and a laptop shows all four.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

Rectangle {
    id: root
    // Theme aliases (nested scopes cannot see file imports).
    readonly property color cAccent: Theme.accent
    readonly property color cAccentHover: Theme.accentHover
    readonly property color cDim: Theme.dim
    readonly property color cRow: Theme.row
    readonly property color cText: Theme.text

    // Same 12px-per-side pill padding as the neighbouring
    // pills, so the island's gaps stay equal.
    readonly property int padX: 12
    readonly property bool hover: perfArea.containsMouse

    // Collapsed while off (and until the first sample lands,
    // so it never flashes empty labels). clip: true keeps the
    // content inside during the width animation.
    width: (PerfService.enabled && PerfService.hasSample) ? perfRow.implicitWidth + padX * 2 : 0
    height: 24
    clip: true
    radius: 0
    color: root.hover ? root.cRow : "transparent"

    Behavior on width {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }
    Behavior on color {
        ColorAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic }
    }

    Row {
        id: perfRow
        anchors.centerIn: parent
        spacing: 7

        // ---- CPU ----
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "CPU"
                font.family: "JetBrainsMono Nerd Font"
                font.pointSize: 9
                color: root.cDim
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: PerfService.cpu + "%"
                font.family: "JetBrainsMono Nerd Font"
                font.pointSize: 10
                color: root.hover ? root.cAccentHover : root.cText
            }
        }

        // ---- GPU: busy% when the kernel exposes it, MHz
        // otherwise, nothing when there is no sensor. ----
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            visible: PerfService.gpuBusy >= 0 || PerfService.gpuMhz > 0
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "GPU"
                font.family: "JetBrainsMono Nerd Font"
                font.pointSize: 9
                color: root.cDim
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: PerfService.gpuBusy >= 0
                      ? PerfService.gpuBusy + "%"
                      : PerfService.gpuMhz + "MHz"
                font.family: "JetBrainsMono Nerd Font"
                font.pointSize: 10
                color: root.hover ? root.cAccentHover : root.cText
            }
        }

        // ---- MEM: used GiB ----
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "MEM"
                font.family: "JetBrainsMono Nerd Font"
                font.pointSize: 9
                color: root.cDim
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (PerfService.memUsed / 1024).toFixed(1) + "G"
                font.family: "JetBrainsMono Nerd Font"
                font.pointSize: 10
                color: root.hover ? root.cAccentHover : root.cText
            }
        }

        // ---- BAT: only with a battery; the waybar
        // warning/critical thresholds colour the value. ----
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            visible: PerfService.batPct >= 0
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "BAT"
                font.family: "JetBrainsMono Nerd Font"
                font.pointSize: 9
                color: root.cDim
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (PerfService.batCharging ? "+" : "") + PerfService.batPct + "%"
                font.family: "JetBrainsMono Nerd Font"
                font.pointSize: 10
                color: PerfService.batPct <= 20 ? root.cAccent
                     : (PerfService.batPct <= 30 || root.hover ? root.cAccentHover : root.cText)
            }
        }
    }

    MouseArea {
        id: perfArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["alacritty", "--config-file", "/home/me/niri-setup/alacritty/float.toml", "-e", "btop"])
    }
}
