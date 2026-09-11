// VolumeWidget.qml — Pipewire default-sink icon + level (waybar group/volume:
// image#volume + pulseaudio). Icon mapping verbatim from
// waybar/scripts/volume-icon.sh: muted -> volume-muted.svg else volume.svg.
// Text parity with pulseaudio format/format-muted: "NN%" or "muted".
//   Left: NATIVE mixer popup via IPC (qs -c sunset ipc call volume toggle,
//     no volume.sh / Brave HTML). Right: wpctl set-mute toggle (native).
//   Middle: pavucontrol (terminal tool kept). Scroll: AudioService ±5%
//   with 100% cap (was scripts/set-volume.sh; kept as fallback path).
// Hover opacity .65, sharp rect, no blur, Theme tokens only.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
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
    border.color: volArea.containsMouse ? root.cBorderStrong : root.cBorder
    implicitWidth: volRow.implicitWidth + 24
    implicitHeight: 24
    Layout.alignment: Qt.AlignVCenter

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: root.sink ? root.sink.audio : null
    readonly property real level: root.audio ? root.audio.volume : 0
    readonly property bool muted: root.audio ? root.audio.muted : false
    readonly property int pct: Math.round(root.level * 100)

    Row {
        id: volRow
        anchors.centerIn: parent
        spacing: 4

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            source: root.muted ? "file:///home/me/niri-setup/waybar/icons/volume-muted.svg" : "file:///home/me/niri-setup/waybar/icons/volume.svg"
            opacity: volArea.containsMouse ? 0.65 : 1.0
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.muted ? "muted" : root.pct + "%"
            font.family: "JetBrainsMono Nerd Font"
            font.pointSize: 10
            color: root.muted ? root.cDim : (volArea.containsMouse ? root.cText : root.cMuted)
        }
    }

    MouseArea {
        id: volArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton)
                AudioService.toggleMute();
            else if (mouse.button === Qt.MiddleButton)
                Quickshell.execDetached(["pavucontrol"]);
            else
                Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "volume", "toggle"]);
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            // Native AudioService (100% cap inside); no set-volume.sh fork.
            if (event.angleDelta.y > 0)
                AudioService.increase(5);
            else if (event.angleDelta.y < 0)
                AudioService.decrease(5);
        }
    }
}
