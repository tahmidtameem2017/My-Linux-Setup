// VolumePopup.qml — per-sink volume mixer popup.
//
// Replaces: waybar/volume/volume.html + waybar/volume/volume-server.py +
//           launcher waybar/scripts/volume.sh + Brave profile
//           ~/.cache/niri-volume (old app-id brave-127.0.0.1__-Default,
//           window 400x440, backend on 127.0.0.1). The Brave profile, the
//           volume-server.py daemon and the 127.0.0.1 backend are all deleted
//           by this migration; nothing else needs them.
//
// Backend parity (from volume-server.py):
//   status  -> default sink volume 0-100 (capped, never above),
//              muted flag, default sink description, sink list with
//              per-sink mute + default marker.
//   volume  -> wpctl set-volume @DEFAULT_AUDIO_SINK@ N%  == Pipewire
//              node.audio.volume write, clamped 0..1 (100% cap kept).
//   mute    -> toggle (or explicit) == node.audio.muted flip.
//   sink    -> pactl set-default-sink <name> ==
//              Pipewire.preferredDefaultAudioSink assignment.
// Live Pipewire bindings replace the 1.5s status poll; slider writes are
// held while dragging (pressed guard), mirroring the old drag-pause.
//
// Shell contract (landed sunset pattern, cf. ClipboardPopup/Launcher):
//   - exclusiveKeyboardFocus == WlrLayershell.keyboardFocus Exclusive.
//   - Esc/M/arrows; outside-click closes; Bar re-click toggles via IPC.
//   - Card width 400 (old 400x440 window); height is content-driven,
//     sink list scrolls past ~2 rows (old page scrolled extra sinks).
//   - niri layer-rule doc (shell owner adds, do NOT edit rules.kdl here):
//       layer-rule { match namespace="sunset-volume" }
//     Verify: `niri msg layers`
// IPC: `qs -c sunset ipc call volume toggle` (also: open, close)

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs.services

Scope {
    id: root

    // Theme aliases (inline component scopes cannot see file imports).
    readonly property color cAccent: Theme.accent
    readonly property color cAccentHover: Theme.accentHover
    readonly property color cBg: Theme.bg
    readonly property color cBorder: Theme.border
    readonly property color cBorderStrong: Theme.borderStrong
    readonly property color cDim: Theme.dim
    readonly property string cFont: Theme.fontFamily
    readonly property color cMuted: Theme.muted
    readonly property color cPanel: Theme.panel
    readonly property int cRadius: Theme.radius
    readonly property color cRow: Theme.row
    readonly property color cText: Theme.text

    property bool isOpen: false
    // Task term "exclusiveKeyboardFocus" == the Exclusive layer-shell
    // keyboard focus set on the PanelWindow below.
    readonly property bool exclusiveKeyboardFocus: true

    function open(): void {
        isOpen = true;
    }
    function close(): void {
        isOpen = false;
    }
    function toggle(): void {
        if (isOpen)
            close();
        else
            open();
    }

    // Audio sinks only (mirrors pactl list sinks filtering).
    // Reading count inside the binding keeps it reactive to add/remove.
    function filterSinks(): var {
        const cnt = Pipewire.nodes.count;
        const vals = Pipewire.nodes.values;
        const out = [];
        for (let i = 0; i < vals.length; ++i) {
            const n = vals[i];
            if (n && n.isSink && n.audio)
                out.push(n);
        }
        return out;
    }
    property var sinkList: filterSinks()

    function volIcon(volume: int, muted: bool): string {
        if (muted || volume === 0)
            return "󰝟";
        if (volume < 50)
            return "󰕿";
        return "󰕾";
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
        WlrLayershell.namespace: "sunset-volume"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            // Old Brave window was 400 wide; height is content-driven.
            implicitWidth: Math.min(400, parent.width - 32)
            implicitHeight: Math.min(col.implicitHeight + 32, parent.height - 48)
            width: implicitWidth
            height: implicitHeight
            color: root.cPanel
            border.width: 1
            border.color: root.cBorderStrong
            radius: root.cRadius

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true

                Keys.onEscapePressed: root.close()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_M) {
                        AudioService.toggleMute();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        AudioService.increase(5);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        AudioService.decrease(5);
                        event.accepted = true;
                    }
                }

                Column {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 18
                    anchors.topMargin: 18
                    anchors.bottomMargin: 14
                    spacing: 0

                    // ---- header: default sink ----
                    PwObjectTracker {
                        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.volIcon(AudioService.volume, AudioService.muted)
                        font.family: root.cFont
                        font.pixelSize: 26
                        color: AudioService.muted ? root.cDim : root.cAccent
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: AudioService.volume + "%"
                        font.family: root.cFont
                        font.pixelSize: 34
                        font.bold: true
                        color: root.cText
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: AudioService.sinkName !== "" ? AudioService.sinkName : "No output"
                        font.family: root.cFont
                        font.pixelSize: 11
                        color: root.cMuted
                    }
                    Item {
                        width: parent.width
                        height: 10
                    }
                    VolSlider {
                        cAccent: root.cAccent
                        cAccentHover: root.cAccentHover
                        cBg: root.cBg
                        cBorder: root.cBorder
                        id: masterSlider
                        width: parent.width
                        Binding {
                            target: masterSlider
                            property: "value"
                            value: AudioService.volume
                            when: !masterSlider.pressed
                        }
                        onMovedTo: v => AudioService.setVolumePercent(v)
                    }
                    Item {
                        width: parent.width
                        height: 10
                    }
                    Row {
                        width: parent.width
                        spacing: 8
                        SunsetBtn {
                            cAccent: root.cAccent
                            cAccentHover: root.cAccentHover
                            cBorderStrong: root.cBorderStrong
                            cFont: root.cFont
                            cRadius: root.cRadius
                            cRow: root.cRow
                            cText: root.cText
                            cols: 5
                            gap: 8
                            label: AudioService.muted ? "󰝟 Unmute" : "󰝟 Mute"
                            hot: AudioService.muted
                            onClicked: AudioService.toggleMute()
                        }
                        SunsetBtn {
                            cAccent: root.cAccent
                            cAccentHover: root.cAccentHover
                            cBorderStrong: root.cBorderStrong
                            cFont: root.cFont
                            cRadius: root.cRadius
                            cRow: root.cRow
                            cText: root.cText
                            cols: 5
                            gap: 8
                            label: "25"
                            onClicked: AudioService.setVolumePercent(25)
                        }
                        SunsetBtn {
                            cAccent: root.cAccent
                            cAccentHover: root.cAccentHover
                            cBorderStrong: root.cBorderStrong
                            cFont: root.cFont
                            cRadius: root.cRadius
                            cRow: root.cRow
                            cText: root.cText
                            cols: 5
                            gap: 8
                            label: "50"
                            onClicked: AudioService.setVolumePercent(50)
                        }
                        SunsetBtn {
                            cAccent: root.cAccent
                            cAccentHover: root.cAccentHover
                            cBorderStrong: root.cBorderStrong
                            cFont: root.cFont
                            cRadius: root.cRadius
                            cRow: root.cRow
                            cText: root.cText
                            cols: 5
                            gap: 8
                            label: "75"
                            onClicked: AudioService.setVolumePercent(75)
                        }
                        SunsetBtn {
                            cAccent: root.cAccent
                            cAccentHover: root.cAccentHover
                            cBorderStrong: root.cBorderStrong
                            cFont: root.cFont
                            cRadius: root.cRadius
                            cRow: root.cRow
                            cText: root.cText
                            cols: 5
                            gap: 8
                            label: "100"
                            onClicked: AudioService.setVolumePercent(100)
                        }
                    }

                    // ---- outputs ----
                    Text {
                        width: parent.width
                        text: "OUTPUTS"
                        font.family: root.cFont
                        font.pixelSize: 11
                        font.bold: true
                        color: root.cAccent
                        topPadding: 14
                        bottomPadding: 6
                    }
                    Flickable {
                        width: parent.width
                        height: Math.min(sinkCol.implicitHeight, 148)
                        contentWidth: width
                        contentHeight: sinkCol.implicitHeight
                        clip: true
                        ScrollBar.vertical: ScrollBar {
                            policy: sinkCol.implicitHeight > 148 ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                            contentItem: Rectangle {
                                implicitWidth: 8
                                color: root.cBorderStrong
                                radius: root.cRadius
                            }
                        }
                        Column {
                            id: sinkCol
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: root.sinkList
                                delegate: Rectangle {
                                    property var node: modelData
                                    readonly property bool isDefault: node === Pipewire.defaultAudioSink
                                    width: sinkCol.width
                                    height: 62
                                    color: root.cRow
                                    border.width: 1
                                    border.color: isDefault ? root.cAccent : root.cBorder
                                    radius: root.cRadius

                                    PwObjectTracker {
                                        objects: node ? [node] : []
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (node)
                                                Pipewire.preferredDefaultAudioSink = node;
                                        }
                                    }
                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        anchors.topMargin: 6
                                        anchors.bottomMargin: 6
                                        spacing: 8
                                        Rectangle {
                                            id: dot
                                            width: 8
                                            height: 8
                                            radius: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: isDefault ? root.cAccent : root.cDim
                                        }
                                        Column {
                                            width: parent.width - 16 - 44 - 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 4
                                            Text {
                                                width: parent.width
                                                elide: Text.ElideRight
                                                text: (isDefault ? "\u2713 " : "") + (node ? (node.description || node.name) : "")
                                                font.family: root.cFont
                                                font.pixelSize: 12
                                                color: root.cText
                                            }
                                            VolSlider {
                                                cAccent: root.cAccent
                                                cAccentHover: root.cAccentHover
                                                cBg: root.cBg
                                                cBorder: root.cBorder
                                                id: rowSlider
                                                width: parent.width
                                                compact: true
                                                Binding {
                                                    target: rowSlider
                                                    property: "value"
                                                    value: (node && node.audio) ? Math.round(Math.min(1, node.audio.volume) * 100) : 0
                                                    when: !rowSlider.pressed
                                                }
                                                onMovedTo: v => {
                                                    if (node && node.audio)
                                                        node.audio.volume = Math.max(0, Math.min(1, v / 100));
                                                }
                                            }
                                        }
                                        Text {
                                            width: 44
                                            anchors.verticalCenter: parent.verticalCenter
                                            horizontalAlignment: Text.AlignRight
                                            text: (node && node.audio) ? Math.round(Math.min(1, node.audio.volume) * 100) + "%" : "--"
                                            font.family: root.cFont
                                            font.pixelSize: 11
                                            color: root.cMuted
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 10
                    }
                    Row {
                        width: parent.width
                        SunsetBtn {
                            cAccent: root.cAccent
                            cAccentHover: root.cAccentHover
                            cBorderStrong: root.cBorderStrong
                            cFont: root.cFont
                            cRadius: root.cRadius
                            cRow: root.cRow
                            cText: root.cText
                            cols: 1
                            label: "Close"
                            onClicked: root.close()
                        }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "drag slider \u00B7 \u2191/\u2193 \u00B15 \u00B7 M mute \u00B7 Esc close"
                        font.family: root.cFont
                        font.pixelSize: 10
                        color: root.cMuted
                        topPadding: 10
                    }
                }
            }
        }

        onVisibleChanged: {
            if (visible)
                keys.forceActiveFocus();
        }
    }

    // Volume slider (Sunset track + accent fill + round thumb).
    component VolSlider: Slider {
        // injected props (inline component scope is isolated)
        property color cAccent: "#E85D2F"
        property color cAccentHover: "#FF8B4A"
        property color cBg: "#000000"
        property color cBorder: "#1a1210"
        id: sl
        property bool compact: false
        signal movedTo(real v)
        from: 0
        to: 100
        stepSize: 1
        focusPolicy: Qt.NoFocus
        implicitHeight: compact ? 20 : 30
        background: Rectangle {
            x: sl.leftPadding
            y: sl.topPadding + sl.availableHeight / 2 - height / 2
            width: sl.availableWidth
            height: 8
            radius: 4
            color: cBorder
            Rectangle {
                width: sl.visualPosition * parent.width
                height: parent.height
                radius: 4
                color: cAccent
            }
        }
        handle: Rectangle {
            x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
            y: sl.topPadding + sl.availableHeight / 2 - height / 2
            width: compact ? 16 : 20
            height: compact ? 16 : 20
            radius: compact ? 8 : 10
            color: sl.pressed ? cAccentHover : cAccent
            border.width: 2
            border.color: cBg
        }
        onMoved: sl.movedTo(sl.value)
    }

    component SunsetBtn: Rectangle {
        // injected props (inline component scope is isolated)
        property color cAccent: "#E85D2F"
        property color cAccentHover: "#FF8B4A"
        property color cBorderStrong: "#3D2B24"
        property string cFont: "JetBrainsMono Nerd Font"
        property int cRadius: 0
        property color cRow: "#141010"
        property color cText: "#F7C7A1"
        id: sBtn
        property string label: ""
        // Accent outline (e.g. muted-on) without filling.
        property bool hot: false
        property int cols: 1
        property real gap: 8
        signal clicked
        width: parent ? (parent.width - (cols - 1) * gap) / cols : 100
        height: 32
        color: cRow
        border.width: 1
        border.color: hot ? cAccent : cBorderStrong
        radius: cRadius
        Text {
            anchors.centerIn: parent
            text: sBtn.label
            font.family: cFont
            font.pixelSize: 12
            font.bold: true
            color: hot ? cAccent : (sHover.hovered ? cAccentHover : cText)
        }
        HoverHandler {
            id: sHover
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: sBtn.clicked()
        }
    }

    IpcHandler {
        target: "volume"

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
