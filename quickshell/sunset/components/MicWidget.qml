// MicWidget.qml — "is the microphone actually on?" indicator.
//
// Answers, in the order they matter:
//   1. is something RECORDING from the mic right now -> breathing accent dot
//   2. is the mic muted, or is there no mic at all   -> slashed icon, dim step
//
// The dot, not the icon, carries "recording". That is forced by the icon
// pipeline: ICON_ROLE_BY_SUNSET_HEX in sync-external-theme.py collapses
// accent/accentHover/text/muted all onto ONE neutral `icon` colour, so an icon
// cannot render "more alarming" than its idle self — an accent-coloured
// microphone would come out the same grey. Recording therefore has to be a
// QML-drawn overlay (Theme.accent), the same reasoning that made the
// battery/charging and play/pause pairs carry state by shape.
//
// microphone-off.svg is the only icon of the pair that keeps its own step
// (`dim` -> iconMuted), which is the convention for the off half of a stateful
// pair (volume/volume-muted, wifi/wifi-off). Without that the off state would
// be indistinguishable from the on state.
//
// There is deliberately NO input level meter. PwNodePeakMonitor's `channels`
// property is read-only and defaults to channels 3/4, which do not exist on a
// mono source, so it reports 0 forever — verified while ffmpeg recorded from
// the same device. See the MicService.qml header for the measurements.
//
// Left click toggles mute — the one privacy action worth a single click, with
// no popup. The right button is left to the bar context menu (Bar routes it to
// ContextMenu), so this widget must NOT claim it.
//
// Flat idle, sharp rect, no blur, Theme tokens only.

import QtQuick
import qs.services

Rectangle {
    id: root
    // Theme aliases (nested scopes cannot see file imports).
    readonly property color cAccent: Theme.accent
    readonly property color cDim: Theme.dim
    readonly property color cRow: Theme.row
    radius: 0
    color: micArea.containsMouse ? root.cRow : "transparent"
    border.width: 0
    implicitWidth: micRow.implicitWidth + 24
    implicitHeight: 24

    Behavior on color {
        ColorAnimation {
            duration: Theme.animHover
            easing.type: Easing.OutCubic
        }
    }

    readonly property bool muted: MicService.muted
    readonly property bool absent: !MicService.hasSource
    // Muted and absent are the same OFF half: neither is a privacy concern, and
    // both mean "nothing can reach the mic right now".
    readonly property bool off: root.muted || root.absent
    readonly property bool capturing: MicService.capturing
    readonly property string iconSrc: Theme.iconDir.replace(/\/$/, "") + (root.off ? "/microphone-off.svg" : "/microphone.svg")

    Row {
        id: micRow
        anchors.centerIn: parent
        spacing: 5

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            // Theme.iconDir, NOT waybar/icons: that is the rollback gold whose
            // strokes are frozen sunset hexes, so it would ignore the palette
            // and render a different colour from every themed neighbour.
            source: "file://" + root.iconSrc
            opacity: micArea.containsMouse ? 0.65 : 1.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animFast
                }
            }
        }

        // Recording dot. Breathing so "recording" reads peripherally, which is
        // the whole point of a privacy light. Both loops are gated on
        // Theme.reduceMotion, matching the NowPlaying waveform convention.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: root.cAccent
            visible: root.capturing

            SequentialAnimation on scale {
                running: root.capturing && !Theme.reduceMotion
                loops: Animation.Infinite
                NumberAnimation {
                    to: 1.3
                    duration: 620
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: 1.0
                    duration: 620
                    easing.type: Easing.InOutSine
                }
            }
            SequentialAnimation on opacity {
                running: root.capturing && !Theme.reduceMotion
                loops: Animation.Infinite
                NumberAnimation {
                    to: 0.5
                    duration: 620
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: 1.0
                    duration: 620
                    easing.type: Easing.InOutSine
                }
            }
        }
    }

    MouseArea {
        id: micArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Left only — the right button belongs to the bar context menu.
        acceptedButtons: Qt.LeftButton
        onClicked: MicService.toggleMute()
    }
}