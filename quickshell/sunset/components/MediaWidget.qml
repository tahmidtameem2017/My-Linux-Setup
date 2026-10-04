// MediaWidget.qml — MPRIS status icon (waybar image#media).
// Source: MediaService (single source of truth, same data the Now Playing
// popup reads, so the icon can never disagree with the card).
// Icon mapping verbatim from waybar/scripts/media-icon.sh: Playing ->
// play.svg, Paused -> pause.svg, anything else -> the widget collapses.
//   Left click: open the NowPlayingPopup (was a bare play/pause toggle —
//     the popup's own play/pause button handles that now).
//   Middle: next track. Scroll up/down: next/previous.
// Hover icon opacity .65, sharp rect, no blur, Theme tokens only.
// Flat idle (transparent, no border); hover is a faint row wash. No scale.
// NOTE: old fuzzel menu (waybar/scripts/media-menu.sh) is NOT invoked —
// it stays on disk for rollback only.

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
    radius: 0
    // Flat idle (transparent, no border); hover is a faint row wash only.
    color: mediaArea.containsMouse ? root.cRow : "transparent"
    border.width: 0
    implicitWidth: 14 + 24
    implicitHeight: 24
    Layout.alignment: Qt.AlignVCenter

    Behavior on color {
        ColorAnimation {
            duration: Theme.animHover
            easing.type: Easing.OutCubic
        }
    }

    visible: root.hasPlayer

    readonly property bool hasPlayer: MediaService.hasTrack
    readonly property bool isPlaying: MediaService.isPlaying

    Image {
        anchors.centerIn: parent
        width: 14
        height: 14
        fillMode: Image.PreserveAspectFit
        source: "file://" + Theme.iconDir + (root.isPlaying ? "play.svg" : "pause.svg")
        opacity: mediaArea.containsMouse ? 0.65 : 1.0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animFast
            }
        }
    }

    function nextTrack() {
        MediaService.next();
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
                Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "now-playing", "toggle"]);
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            if (!root.hasPlayer)
                return;
            if (event.angleDelta.y > 0)
                MediaService.next();
            else if (event.angleDelta.y < 0)
                MediaService.previous();
        }
    }
}
