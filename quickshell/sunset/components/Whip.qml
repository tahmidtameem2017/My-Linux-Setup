// Whip.qml — fun "digital whip": a whip floats on screen whipping
// (animated), then goes away.
//
// Trigger: `qs -c sunset ipc call whip toggle` (keybind) or the Launcher
// Controls row "Crack the Whip" (ipcTarget "whip").
//
// Visual: pure-QML, no new dependencies. A Canvas draws a sine-wave lash
// (accent) driven by a looping NumberAnimation on `phase`, next to a
// handle rect; a "CRACK!" flash pops at the lash peak via a looping
// SequentialAnimation (scale + opacity). Silent: no crack sound file
// exists in the repo, so no paplay hook (do not download anything).
//
// niri layer-rule doc (for the shell owner — do NOT edit rules.kdl here):
//   layer-rule { match namespace="sunset-whip" ... }
//   Verify while running: `niri msg layers`
//
// IPC: `qs -c sunset ipc call whip toggle` (also: open, close)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    // ---- theme (Theme.qml Sunset Orange AMOLED tokens only, no hex) ----
    readonly property color bg: Theme.bg
    readonly property color panel: Theme.panel
    readonly property color textCol: Theme.text
    readonly property color accent: Theme.accent
    readonly property color accentHover: Theme.accentHover
    readonly property color muted: Theme.muted
    readonly property color handleCol: Theme.borderStrong
    readonly property string fontFamily: Theme.fontFamily
    readonly property int cardRadius: Theme.radius
    readonly property int cardWidth: 520

    property bool isOpen: false
    // Lash driver: loops 0..2π while open; Canvas repaints on change.
    property real phase: 0

    function open(): void {
        isOpen = true;
        phase = 0;
        crackAnim.restart();
        dismissTimer.restart();
        focusTimer.restart();
    }

    function close(): void {
        isOpen = false;
        crackAnim.stop();
    }

    function toggle(): void {
        if (isOpen)
            close();
        else
            open();
    }

    // Re-crack without closing (Space/Enter while open).
    function replay(): void {
        phase = 0;
        crackAnim.restart();
        dismissTimer.restart();
    }

    onPhaseChanged: lashCanvas.requestPaint()

    // Whip floats briefly, then goes away on its own.
    Timer {
        id: dismissTimer
        interval: 3000
        repeat: false
        onTriggered: root.close()
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: keys.forceActiveFocus()
    }

    // Lash wave driver: one full whip cycle per ~550ms.
    NumberAnimation {
        id: lashDriver
        target: root
        property: "phase"
        from: 0
        to: 6.283185307179586
        duration: 550
        loops: Animation.Infinite
        running: root.isOpen
    }

    PanelWindow {
        id: win
        visible: root.isOpen
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "sunset-whip"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(root.cardWidth, parent.width - 48)
            height: col.implicitHeight + 32
            radius: root.cardRadius // Theme.radius (sharp sunset cards)
            color: root.bg
            border.width: 2
            border.color: root.accent
            // Micro-animation: subtle entrance (opacity 150ms OutCubic +
            // scale 0.96->1 180ms OutBack overshoot 1.2 + y -6->0).
            // Close stays instant (visible flips with isOpen, <200ms).
            // Existing lashDriver/crackAnim/dismissTimer untouched.
            transformOrigin: Item.Center
            scale: root.isOpen ? 1.0 : 0.96
            opacity: root.isOpen ? 1 : 0
            transform: Translate {
                y: root.isOpen ? 0 : -6
                Behavior on y {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            Column {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 16
                spacing: 8

                Text {
                    width: parent.width - 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "Digital Whip"
                    font.family: root.fontFamily
                    font.pointSize: 13
                    font.bold: true
                    color: root.accent
                }

                Item {
                    id: stage
                    width: parent.width - 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 190

                    Canvas {
                        id: lashCanvas
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";

                            var midY = height * 0.52;
                            var x0 = 64;              // handle tip
                            var x1 = width - 26;      // lash tip rest
                            var span = x1 - x0;

                            // Handle: short thick grip from card edge to tip.
                            ctx.strokeStyle = root.handleCol;
                            ctx.lineWidth = 12;
                            ctx.beginPath();
                            ctx.moveTo(14, midY + 34);
                            ctx.lineTo(x0, midY);
                            ctx.stroke();
                            // Handle pommel dot.
                            ctx.fillStyle = root.accent;
                            ctx.beginPath();
                            ctx.arc(14, midY + 34, 5, 0, 6.283185307179586);
                            ctx.fill();

                            // Lash: sine wave whose amplitude swells toward
                            // the tip; phase scroll makes it whip.
                            ctx.strokeStyle = root.accent;
                            ctx.lineWidth = 6;
                            ctx.beginPath();
                            var steps = 48;
                            for (var i = 0; i <= steps; ++i) {
                                var t = i / steps;
                                var x = x0 + t * span;
                                var amp = 6 + t * t * 52;
                                var y = midY + Math.sin(t * 9.0 + root.phase * 3.0) * amp * 0.55 + t * 10;
                                if (i === 0)
                                    ctx.moveTo(x, y);
                                else
                                    ctx.lineTo(x, y);
                            }
                            ctx.stroke();

                            // Lash tip spark at the travelling wave crest.
                            var tipT = 0.5 - 0.5 * Math.cos(root.phase * 3.0);
                            tipT = Math.max(0.15, Math.min(1.0, tipT));
                            var tx = x0 + tipT * span;
                            var tamp = 6 + tipT * tipT * 52;
                            var ty = midY + Math.sin(tipT * 9.0 + root.phase * 3.0) * tamp * 0.55 + tipT * 10;
                            ctx.fillStyle = root.accentHover;
                            ctx.beginPath();
                            ctx.arc(tx, ty, 7, 0, 6.283185307179586);
                            ctx.fill();
                        }
                    }

                    // "CRACK!" flash at the lash peak.
                    Text {
                        id: crackText
                        anchors.centerIn: parent
                        text: "CRACK!"
                        font.family: root.fontFamily
                        font.pointSize: 44
                        font.bold: true
                        color: root.accentHover
                        opacity: 0
                        scale: 0.6
                        transformOrigin: Item.Center

                        SequentialAnimation {
                            id: crackAnim
                            loops: Animation.Infinite
                            PauseAnimation {
                                duration: 150
                            }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: crackText
                                    property: "opacity"
                                    to: 1
                                    duration: 120
                                }
                                NumberAnimation {
                                    target: crackText
                                    property: "scale"
                                    to: 1.25
                                    duration: 180
                                }
                            }
                            PauseAnimation {
                                duration: 120
                            }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: crackText
                                    property: "opacity"
                                    to: 0
                                    duration: 200
                                }
                                NumberAnimation {
                                    target: crackText
                                    property: "scale"
                                    to: 0.9
                                    duration: 200
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width - 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "Esc / click outside to dismiss"
                    font.family: root.fontFamily
                    font.pointSize: 10
                    color: root.muted
                }
            }

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.close()
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        event.accepted = true;
                        root.replay();
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "whip"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }
    }
}
