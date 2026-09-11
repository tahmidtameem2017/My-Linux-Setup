// MediaWidget.qml — MPRIS status icon (waybar image#media).
// Source: Mpris.players[0]. Icon mapping verbatim from
// waybar/scripts/media-icon.sh: Playing -> play.svg, Paused -> pause.svg,
// anything else -> empty, and the widget collapses (style.css .empty).
//   Left click: play/pause toggle. Middle: next track (native MPRIS, no fuzzel).
//   Scroll up: playerctl next, down: previous (waybar on-scroll-up/down).
// Hover opacity .65, sharp rect, no blur, Theme tokens only.
// NOTE: old fuzzel menu (waybar/scripts/media-menu.sh) is NOT invoked —
// it stays on disk for rollback only.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
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
    border.color: mediaArea.containsMouse ? root.cBorderStrong : root.cBorder
    implicitWidth: 14 + 24
    implicitHeight: 24
    Layout.alignment: Qt.AlignVCenter

    visible: root.hasPlayer

    readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    readonly property bool hasPlayer: root.player !== null && (root.player.playbackState === MprisPlaybackState.Playing || root.player.playbackState === MprisPlaybackState.Paused)
    readonly property bool isPlaying: root.hasPlayer && root.player.playbackState === MprisPlaybackState.Playing

    function toggle(): void {
        if (!root.player)
            return;
        if (typeof root.player.togglePlaying === "function")
            root.player.togglePlaying();
        else if (typeof root.player.playPause === "function")
            root.player.playPause();
    }

    Image {
        anchors.centerIn: parent
        width: 14
        height: 14
        fillMode: Image.PreserveAspectFit
        source: root.isPlaying ? "file:///home/me/niri-setup/waybar/icons/play.svg" : "file:///home/me/niri-setup/waybar/icons/pause.svg"
        opacity: mediaArea.containsMouse ? 0.65 : 1.0
    }

    function nextTrack(): void {
        if (root.player && typeof root.player.next === "function")
            root.player.next();
    }

    MouseArea {
        id: mediaArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton)
                root.nextTrack();
            else
                root.toggle();
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            if (!root.player)
                return;
            if (event.angleDelta.y > 0)
                root.player.next();
            else if (event.angleDelta.y < 0)
                root.player.previous();
        }
    }
}
