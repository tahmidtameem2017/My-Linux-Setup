// PomodoroWidget.qml — at-a-glance pomodoro/countdown pill for the bar.
// Source: PomodoroService (singleton). Hidden when idle (pillVisible),
// so the clock stays true-center until a session starts.
//   Left click: open calendar popup (pomo tab state kept in popup).
//   Middle click: start/pause toggle (pomo or countdown, whichever shows).
//   Wheel: skip to next pomodoro phase. Right click: reset pomo.
// Colors via Theme tokens only (running accent, break accentHover,
// paused muted, finished countdown danger). Sharp rect, no blur, flat idle
// (transparent, no border); hover is a faint row wash. No scale (perf).

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
    readonly property color cDanger: Theme.danger
    readonly property color cDim: Theme.dim
    readonly property string cFontFamily: Theme.fontFamily
    readonly property color cMuted: Theme.muted
    readonly property color cPanel: Theme.panel
    readonly property int cRadius: Theme.radius
    readonly property color cRow: Theme.row
    readonly property color cText: Theme.text
    implicitWidth: pomoLabel.implicitWidth + 24
    implicitHeight: 24
    radius: 0
    // Flat idle (transparent, no border); hover is a faint row wash only.
    color: pomoArea.containsMouse ? root.cRow : "transparent"
    border.width: 0
    Layout.alignment: Qt.AlignVCenter

    Behavior on color {
        ColorAnimation {
            duration: Theme.animHover
            easing.type: Easing.OutCubic
        }
    }

    // Hide when idle: clock stays true-center until a session starts.
    visible: PomodoroService.pillVisible

    readonly property bool showingTimer: PomodoroService.showTimer
    readonly property bool isFinished: root.showingTimer && PomodoroService.timerFinished
    readonly property bool isRunning: PomodoroService.pomoRunning || PomodoroService.timerRunning
    readonly property color stateColor: {
        if (root.isFinished)
            return root.cDanger;
        if (!root.isRunning)
            return root.cMuted;
        if (root.showingTimer)
            return root.cText;
        if (PomodoroService.pomoPhase !== "focus")
            return root.cAccentHover;
        return root.cAccent;
    }

    function togglePause() {
        if (root.showingTimer) {
            if (PomodoroService.timerRunning)
                PomodoroService.timerPause();
            else
                PomodoroService.timerStart(0); // resume paused countdown
        } else {
            PomodoroService.pomoCmd(PomodoroService.pomoRunning ? "pause" : "start");
        }
    }

    Text {
        id: pomoLabel
        anchors.centerIn: parent
        text: PomodoroService.pillText()
        font.family: "JetBrainsMono Nerd Font"
        font.pointSize: 11
        font.bold: true
        color: pomoArea.containsMouse ? root.cAccentHover : root.stateColor

        Behavior on color {
            ColorAnimation {
                duration: Theme.animHover
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: pomoArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton)
                root.togglePause();
            else if (mouse.button === Qt.RightButton)
                PomodoroService.pomoCmd("reset");
            else
                Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "calendar", "toggle"]);
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            if (event.angleDelta.y !== 0)
                PomodoroService.pomoCmd("skip");
        }
    }
}
