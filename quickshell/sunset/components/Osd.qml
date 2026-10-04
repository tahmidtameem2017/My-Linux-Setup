// Osd.qml — volume/brightness on-screen display. Shows the current level
// for ~1.4s whenever it changes, INCLUDING over fullscreen video.
//
// Why a separate OSD: niri media/brightness keys work fullscreen, but the
// bar (where the % lives) is hidden behind the fullscreen window. This
// Overlay-layer pill is above fullscreen (overlay > fullscreen in niri),
// so the level is always visible while adjusting.
//
// Triggers (zero polling, zero idle cost):
//   volume:     reactive — AudioService.volume/muted change signals
//               (covers keys, bar scroll, mixer popup; no bind change).
//   brightness: `qs -c sunset ipc call osd brightness`, appended to the
//               XF86MonBrightness binds (brightnessctl has no push API).
//
// Perf: single 340x52 window, `visible: false` at idle (no cost).
// Show/hide is one 120ms opacity fade; auto-hide Timer only runs while
// visible. The level bar is a working slider: click/drag sets volume
// (live via AudioService) or brightness (committed to brightnessctl on
// release, min 5% so a drag can never black the screen).
// Theme tokens only, sharp rect, no blur.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    readonly property string iconDir: Theme.iconDir.replace(/\/$/, "")
    // Last-known brightness % (refreshed from brightnessctl on each show).
    property int brightPct: 100
    property string kind: "volume" // "volume" | "brightness" | "mic"
    property bool showing: false

    readonly property bool volMuted: AudioService.muted
    readonly property int volPct: AudioService.volume
    // Displayed %: live volume, or last-known brightness.
    readonly property int pct: {
        if (root.kind === "brightness")
            return root.brightPct;
        if (root.kind === "mic")
            return MicService.muted ? 0 : 100;
        return root.volPct;
    }
    readonly property string iconSrc: {
        if (root.kind === "brightness")
            return root.iconDir + "/brightness.svg";
        if (root.kind === "mic")
            return MicService.muted ? root.iconDir + "/microphone-off.svg" : root.iconDir + "/microphone.svg";
        return root.volMuted ? root.iconDir + "/volume-muted.svg" : root.iconDir + "/volume.svg";
    }
    readonly property string label: {
        if (root.kind === "volume" && root.volMuted)
            return "muted";
        if (root.kind === "mic")
            return MicService.muted ? "mic off" : "mic on";
        return root.pct + "%";
    }

    function flash(k) {
        root.kind = k;
        if (k === "brightness")
            brightProc.running = true;
        root.showing = true;
        hideTimer.restart();
    }

    // Slider scrub: x is the position within the 200px track.
    function scrub(x) {
        if (root.kind === "mic")
            return;
        const p = Math.max(0, Math.min(100, Math.round(x / 200 * 100)));
        if (root.kind === "brightness") {
            // Floor 5%: 0% would black the panel with no way to see.
            root.brightPct = Math.max(5, p);
        } else {
            if (root.volMuted)
                AudioService.toggleMute();
            AudioService.setVolumePercent(p);
        }
        hideTimer.restart();
    }

    // Push a dragged brightness value to hardware (volume applies live).
    function commit() {
        if (root.kind === "mic")
            return;
        if (root.kind === "brightness") {
            brightSetPct = root.brightPct;
            brightSetProc.running = true;
        }
        hideTimer.restart();
    }

    property int brightSetPct: 100

    // Reactive volume trigger — any sink change flashes the OSD.
    Connections {
        target: AudioService
        function onVolumeChanged() {
            root.flash("volume");
        }
        function onMutedChanged() {
            root.flash("volume");
        }
    }

    // Reactive mic trigger — any source mute change flashes the OSD.
    Connections {
        target: MicService
        function onMutedChanged() {
            root.flash("mic");
        }
    }

    // brightnessctl -m -> e.g. `intel_backlight,backlight,937,100%,937`
    // (% is the only field ending in %; version-independent parse).
    Process {
        id: brightProc
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/(\d+)%/);
                if (m)
                    root.brightPct = Math.max(0, Math.min(100, parseInt(m[1], 10)));
            }
        }
    }

    // Hardware commit for slider drags (one fork per release, not per move).
    Process {
        id: brightSetProc
        command: ["brightnessctl", "set", root.brightSetPct + "%"]
    }

    Timer {
        id: hideTimer
        interval: 1400
        repeat: false
        onTriggered: root.showing = false
    }

    PanelWindow {
        id: win
        anchors {
            bottom: true
        }
        margins {
            bottom: 64
        }
        implicitWidth: 340
        implicitHeight: 46
        exclusiveZone: 0
        color: "transparent"
        visible: root.showing
        // Overlay sits above fullscreen windows; None keeps video focus.
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "sunset-osd"

        Rectangle {
            id: pill
            anchors.centerIn: parent
            width: 340
            height: 46
            radius: 0
            color: Theme.panel
            border.width: 1
            border.color: Theme.borderStrong
            opacity: root.showing ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animFast
                    easing.type: Easing.OutCubic
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: 12

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    fillMode: Image.PreserveAspectFit
                    source: "file://" + root.iconSrc
                }

                // Level bar: 200px track, accent fill scaled by pct.
                // Working slider: press/drag seeks, release commits.
                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: 200
                    height: 12
                    radius: 0
                    color: Theme.row

                    Rectangle {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                        width: Math.round(200 * root.pct / 100)
                        height: parent.height
                        radius: 0
                        color: ((root.kind === "volume" && root.volMuted) || (root.kind === "mic" && MicService.muted)) ? Theme.dim : Theme.accent

                        Behavior on width {
                            NumberAnimation {
                                duration: Theme.animHover
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.animHover
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    // Slider input: click seeks, drag scrubs, release
                    // commits brightness to hardware (volume is live).
                    // Child of the pill: press here never reaches the
                    // pin-timer area below.
                    MouseArea {
                        anchors.fill: parent
                        // Taller hitbox than the 10px bar for touchpads.
                        anchors.topMargin: -12
                        anchors.bottomMargin: -12
                        hoverEnabled: true
                        cursorShape: Qt.SizeHorCursor
                        preventStealing: true
                        onPressed: (mouse) => root.scrub(mouse.x)
                        onPositionChanged: (mouse) => {
                            if (pressed)
                                root.scrub(mouse.x);
                        }
                        onReleased: root.commit()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 56
                    text: root.label
                    font.family: Theme.fontFamily
                    font.pointSize: 11
                    font.bold: true
                    color: Theme.text
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // Click pins the OSD a little longer; it never takes focus.
                onClicked: hideTimer.restart()
            }
        }
    }

    IpcHandler {
        target: "osd"

        function show(kind: string) {
            const k = kind === "brightness" ? "brightness" : (kind === "mic" ? "mic" : "volume");
            root.flash(k);
        }

        function brightness() {
            root.flash("brightness");
        }

        function volume() {
            root.flash("volume");
        }

        function mic() {
            root.flash("mic");
        }
    }
}
