// ScreenshotActions.qml — one floating pill for the whole capture utility:
//   mode "actions"   → after a screenshot (kind "image": OCR/Copy/Open/Delete)
//                      or a recording (kind "video": Play/Reveal/Copy path/Delete)
//   mode "recording" → live indicator while gpu-screen-recorder runs:
//                      pulsing dot, elapsed mm:ss, Stop / Discard buttons.
// Lifecycle: qs IPC `screenshots open|open-video|record-start|record-stop|close`
// (shimmed in shell.qml, parked while the LazyLoader builds us). Auto-dismiss
// only in actions mode; in recording mode the ✕/outside-click just hides the
// pill while the recording continues (Mod+Shift+R or the pill's Stop ends it).
// IPC: `qs -c sunset ipc call screenshots <verb>`

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    readonly property color cAccent: Theme.accent
    readonly property color cAccentHover: Theme.accentHover
    readonly property color cBg: Theme.bg
    readonly property color cBorder: Theme.border
    readonly property color cBorderStrong: Theme.borderStrong
    readonly property color cDim: Theme.dim
    readonly property string cFont: Theme.fontFamily
    readonly property color cMuted: Theme.muted
    readonly property color cOnAccent: Theme.onAccent
    readonly property color cPanel: Theme.panel
    readonly property int cRadius: Theme.radius
    readonly property color cRow: Theme.row
    readonly property color cText: Theme.text
    readonly property color cRec: Theme.danger

    property bool isOpen: false
    property string shotPath: ""
    property string mode: "actions"   // "actions" | "recording"
    property string kind: "image"     // "image" | "video"
    property double recordStartMs: 0
    property int tick: 0              // 1s clock pulse while recording
    readonly property string setupHome: Quickshell.env("NIRI_SETUP_HOME") ?? (Quickshell.env("HOME") + "/niri-setup")

    readonly property int autoDismissMs: 8000

    function open(path): void {
        shotPath = path;
        kind = "image";
        mode = "actions";
        isOpen = true;
        dismissTimer.restart();
        focusTimer.restart();
    }
    function openVideo(path): void {
        shotPath = path;
        kind = "video";
        mode = "actions";
        isOpen = true;
        dismissTimer.restart();
        focusTimer.restart();
    }
    function recordStart(path): void {
        shotPath = path;
        mode = "recording";
        isOpen = true;
        recordStartMs = Date.now();
        tick = 0;
        dismissTimer.stop();
        focusTimer.restart();
    }
    function recordStop(): void {
        // Keep mode until record-screen.sh follows with open-video / close.
        isOpen = false;
        dismissTimer.stop();
    }
    function close(): void {
        isOpen = false;
        dismissTimer.stop();
    }
    function toggle(): void {
        if (isOpen)
            close();
        else if (shotPath !== "") {
            if (mode === "recording") {
                // Restore the hidden indicator WITHOUT resetting its clock.
                isOpen = true;
                dismissTimer.stop();
                focusTimer.restart();
            } else {
                open(shotPath);
            }
        }
    }

    function elapsedText(): string {
        const s = Math.max(0, Math.floor((Date.now() - recordStartMs) / 1000));
        const m = Math.floor(s / 60), r = s % 60;
        return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r;
    }

    // 1s tick for the recording clock.
    Timer {
        interval: 1000
        repeat: true
        running: root.isOpen && root.mode === "recording"
        onTriggered: root.tick++
    }

    Timer {
        id: dismissTimer
        interval: root.autoDismissMs
        repeat: false
        onTriggered: root.close()
    }
    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: keys.forceActiveFocus()
    }
    function run(cmd): void {
        actProc.command = cmd;
        actProc.running = true;
        close();
    }

    Process {
        id: actProc
    }

    PanelWindow {
        id: win
        visible: root.isOpen
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "sunset-screenshots"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: pill
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 92
            implicitWidth: row.implicitWidth + 24
            implicitHeight: row.implicitHeight + 16
            width: implicitWidth
            height: implicitHeight
            color: root.cPanel
            border.width: 1
            border.color: root.cBorderStrong
            radius: root.cRadius
            transformOrigin: Item.Center
            scale: root.isOpen ? 1.0 : 0.96
            opacity: root.isOpen ? 1 : 0
            transform: Translate {
                y: root.isOpen ? 0 : -6
                Behavior on y {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
            }
            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
            }
            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.close()

                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 8

                    // ---- recording indicator ---------------------------
                    Rectangle {
                        visible: root.mode === "recording"
                        implicitHeight: 28
                        implicitWidth: 28
                        radius: 14
                        color: "transparent"
                        Rectangle {
                            anchors.centerIn: parent
                            width: 10; height: 10; radius: 5
                            color: root.cRec
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { from: 1; to: 0.25; duration: 700 }
                                NumberAnimation { from: 0.25; to: 1; duration: 700 }
                            }
                        }
                    }
                    Text {
                        visible: root.mode === "recording"
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.tick >= 0 ? root.elapsedText() : ""
                        font.family: root.cFont
                        font.pixelSize: 13
                        font.bold: true
                        color: root.cText
                    }
                    Rectangle {
                        visible: root.mode === "recording"
                        implicitHeight: 28
                        implicitWidth: stopText.implicitWidth + 20
                        radius: root.cRadius - 4
                        color: stopMouse.containsMouse ? root.cAccentHover : root.cRow
                        Text {
                            id: stopText
                            anchors.centerIn: parent
                            text: "Stop"
                            font.family: root.cFont
                            font.pixelSize: 12
                            font.bold: true
                            color: root.cText
                        }
                        MouseArea {
                            id: stopMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.run([root.setupHome + "/scripts/record-screen.sh", "stop"])
                        }
                    }
                    Rectangle {
                        visible: root.mode === "recording"
                        implicitHeight: 28
                        implicitWidth: discardText.implicitWidth + 20
                        radius: root.cRadius - 4
                        color: discardMouse.containsMouse ? root.cAccentHover : root.cRow
                        Text {
                            id: discardText
                            anchors.centerIn: parent
                            text: "Discard"
                            font.family: root.cFont
                            font.pixelSize: 12
                            font.bold: true
                            color: root.cText
                        }
                        MouseArea {
                            id: discardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.run([root.setupHome + "/scripts/record-screen.sh", "cancel"])
                        }
                    }

                    // ---- actions pill (image + video) ------------------
                    Repeater {
                        model: root.mode === "actions" && root.kind === "image" ? [
                            { label: "OCR", cmd: function() { root.run([root.setupHome + "/scripts/ocr.sh", root.shotPath]); } },
                            { label: "Copy", cmd: function() { root.run(["bash", "-c", 'wl-copy --type image/png < "$1"', "_", root.shotPath]); } },
                            { label: "Open", cmd: function() { root.run(["xdg-open", root.shotPath]); } },
                            { label: "Delete", cmd: function() { root.deleteShot(); } },
                        ] : root.mode === "actions" ? [
                            { label: "Play", cmd: function() { root.run(["mpv", "--force-window=no", root.shotPath]); } },
                            { label: "Reveal", cmd: function() { root.run(["xdg-open", root.shotPath.substring(0, root.shotPath.lastIndexOf("/"))]); } },
                            { label: "Copy path", cmd: function() { root.run(["bash", "-c", 'printf %s "$1" | wl-copy', "_", root.shotPath]); } },
                            { label: "Delete", cmd: function() { root.deleteShot(); } },
                        ] : []
                        delegate: Rectangle {
                            implicitHeight: 28
                            implicitWidth: btnText.implicitWidth + 20
                            radius: root.cRadius - 4
                            color: btnMouse.containsMouse ? root.cAccentHover : root.cRow
                            Text {
                                id: btnText
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: root.cFont
                                font.pixelSize: 12
                                font.bold: true
                                color: root.cText
                            }
                            MouseArea {
                                id: btnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: modelData.cmd()
                            }
                        }
                    }

                    Rectangle {
                        implicitHeight: 28
                        implicitWidth: 28
                        radius: root.cRadius - 4
                        color: closeMouse.containsMouse ? root.cRow : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.family: root.cFont
                            font.pixelSize: 12
                            color: root.cMuted
                        }
                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.close()
                        }
                    }
                }
            }
        }
    }

    function deleteShot(): void {
        const p = shotPath;
        const trash = ["bash", "-c", 'rm -- "$1" && notify-send -a niri "Screenshot" "Deleted $(basename "$1")"', "_", p];
        root.run(trash);
    }

    IpcHandler {
        target: "screenshots"
        function toggle(): void { root.toggle(); }
        function open(path): void { root.open(path); }
        function openVideo(path): void { root.openVideo(path); }
        function recordStart(path): void { root.recordStart(path); }
        function recordStop(): void { root.recordStop(); }
        function close(): void { root.close(); }
    }
}
