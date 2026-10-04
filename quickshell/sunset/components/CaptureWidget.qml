// CaptureWidget.qml — small camera pill in the bar's center cluster
// (Weather | Capture | Clock | Pomodoro). Clicking toggles the
// always-on-top CaptureBar options row:
//   qs -c sunset ipc call capture toggle
// A red dot overlays the icon while gpu-screen-recorder is live (polled
// the same way CaptureBar polls, so the icon matches reality however
// recording was started or stopped).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

Rectangle {
    id: root
    readonly property color cRow: Theme.row
    readonly property int iconSize: 14
    // 12px per side, same as WeatherWidget/PomodoroWidget, so the pill
    // gaps in the center Row stay equal.
    readonly property int padX: 12

    property bool recording: false
    readonly property string setupHome: Quickshell.env("NIRI_SETUP_HOME") ?? (Quickshell.env("HOME") + "/niri-setup")

    visible: CaptureService.pinned
    width: CaptureService.pinned ? root.iconSize + root.padX * 2 : 0
    height: 24
    clip: true

    Behavior on width {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    radius: 0
    color: area.containsMouse ? root.cRow : "transparent"

    Behavior on color {
        ColorAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic }
    }

    Image {
        id: icon
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        source: "file://" + Theme.iconDir + "camera.svg"
        smooth: true
    }

    // Live-recording dot, top-right of the icon.
    Rectangle {
        visible: root.recording
        anchors.top: icon.top
        anchors.right: icon.right
        width: 6; height: 6; radius: 3
        color: Theme.danger
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: statusProc.running = true
    }
    Process {
        id: statusProc
        command: [root.setupHome + "/scripts/record-screen.sh", "--status"]
        stdout: StdioCollector {
            onStreamFinished: root.recording = text.indexOf("recording:") === 0
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton)
                Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "capture", "show"]);
            else
                Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "capture", "toggle"]);
        }
    }
}
