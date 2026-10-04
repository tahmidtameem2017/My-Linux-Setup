// RecordingWidget.qml — minimal always-on-bar recording indicator:
// pulsing red dot + mm:ss, docked next to the clock while
// gpu-screen-recorder is live, collapsed to zero width otherwise.
// Polls record-screen.sh --status the same way CaptureWidget does, so it
// tracks reality however recording was started (bind, pill, launcher).
// Click toggles the recording pill (ScreenshotActions) so Stop is one
// click away.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

Rectangle {
    id: root
    property bool recording: false
    property double recordStartMs: 0
    property int tick: 0
    readonly property string setupHome: Quickshell.env("NIRI_SETUP_HOME") ?? (Quickshell.env("HOME") + "/niri-setup")

    width: recording ? (row.implicitWidth + 24) : 0
    height: 24
    clip: true
    radius: 0
    color: area.containsMouse ? Theme.row : "transparent"

    Behavior on width {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 8; radius: 4
            color: Theme.danger
            SequentialAnimation on opacity {
                running: root.recording
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.25; duration: 600 }
                NumberAnimation { from: 0.25; to: 1; duration: 600 }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                root.tick; // re-evaluate once a second
                const s = Math.max(0, Math.floor((Date.now() - root.recordStartMs) / 1000));
                const m = Math.floor(s / 60), r = s % 60;
                return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r;
            }
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: true
            color: Theme.danger
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.tick++
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
            onStreamFinished: {
                const nowRec = text.indexOf("recording:") === 0;
                if (nowRec && !root.recording)
                    root.recordStartMs = Date.now();
                root.recording = nowRec;
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "screenshots", "toggle"])
    }
}
