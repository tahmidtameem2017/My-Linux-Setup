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
//   - DOCKED TOP-RIGHT under the bar (2026-10-03) with the Bluetooth and
//     Wi-Fi cards, not centered: the card belongs to the corner whose bar
//     widget opened it, and the top-right cluster is where the eye already
//     goes for hardware state. `toastOffset` (shell.qml wires
//     `toasts.occupiedHeight`) keeps it clear of a toast stack.
//   - Card width 340 (the 400 of the old Brave window is gone with the dock);
//     height is content-driven, sink list scrolls past ~2 rows.
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
    // Offset from the toast stack (shell.qml wires `toasts.occupiedHeight`).
    property real toastOffset: 0
    // Bar height, from Bar.qml (shell.qml wires `bar.implicitHeight`). The
    // card is anchored to the SCREEN top, so without this it slides under the
    // bar and loses its own header whenever no toast is up.
    property int topInset: 0
    // Task term "exclusiveKeyboardFocus" == the Exclusive layer-shell
    // keyboard focus set on the PanelWindow below.
    readonly property bool exclusiveKeyboardFocus: true
    // Keyboard selection over the sink list (-1 = none).
    property int sinkCurrent: -1
    // Mouse must not vote until the user actually moves it (Launcher
    // hoverArmed parity): hover only takes selection once armed.
    property bool hoverArmed: false

    function open(): void {
        hoverArmed = false;
        isOpen = true;
        sinkCurrent = (sinkList && sinkList.length > 0) ? 0 : -1;
        focusTimer.restart();
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

    // Audio sources (mics). Mirrors the sink filter; devices are
    // media.class "Audio/Source" (+ capture streams for parity with how
    // output streams like mpv show up as sinks).
    function filterSources(): var {
        const cnt = Pipewire.nodes.count;
        const vals = Pipewire.nodes.values;
        const out = [];
        for (let i = 0; i < vals.length; ++i) {
            const n = vals[i];
            if (!n || !n.audio || !n.properties)
                continue;
            const mc = n.properties["media.class"];
            if (mc === "Audio/Source" || mc === "Stream/Input/Audio")
                out.push(n);
        }
        return out;
    }
    property var sourceList: filterSources()

    function sourceIcon(node): string {
        if (!node || !node.audio)
            return "󰍭";
        return node.audio.muted ? "󰍭" : "󰍬";
    }

    function volIcon(volume: int, muted: bool): string {
        if (muted || volume === 0)
            return "󰝟";
        if (volume < 50)
            return "󰕿";
        return "󰕾";
    }

    // Re-assert keyboard focus on open (Launcher/WallpaperMenu parity).
    Timer {
        id: focusTimer
        interval: 60
        running: false
        repeat: false
        onTriggered: keys.forceActiveFocus()
    }

    // Point keyboard selection at the default sink (else first row).
    function refreshSinkCurrent(): void {
        const list = root.sinkList;
        if (!list || list.length === 0) {
            sinkCurrent = -1;
            return;
        }
        let idx = 0;
        const d = Pipewire.defaultAudioSink;
        if (d) {
            for (let i = 0; i < list.length; ++i) {
                if (list[i] === d) {
                    idx = i;
                    break;
                }
            }
        }
        sinkCurrent = idx;
    }

    function moveSink(delta: int): void {
        hoverArmed = true;
        const n = root.sinkList ? root.sinkList.length : 0;
        if (n === 0) {
            sinkCurrent = -1;
            return;
        }
        let idx = sinkCurrent + delta;
        if (idx < 0)
            idx = 0;
        if (idx >= n)
            idx = n - 1;
        sinkCurrent = idx;
    }

    function goSinkFirst(): void {
        hoverArmed = true;
        sinkCurrent = (root.sinkList && root.sinkList.length > 0) ? 0 : -1;
    }

    function goSinkLast(): void {
        hoverArmed = true;
        sinkCurrent = (root.sinkList && root.sinkList.length > 0) ? root.sinkList.length - 1 : -1;
    }

    function selectSinkCurrent(): void {
        if (sinkCurrent < 0 || !root.sinkList || sinkCurrent >= root.sinkList.length)
            return;
        const node = root.sinkList[sinkCurrent];
        if (node)
            Pipewire.preferredDefaultAudioSink = node;
    }

    onSinkListChanged: {
        // Clamp keyboard selection when devices appear/disappear.
        const n = sinkList ? sinkList.length : 0;
        if (n === 0)
            sinkCurrent = -1;
        else if (sinkCurrent < 0)
            sinkCurrent = 0;
        else if (sinkCurrent >= n)
            sinkCurrent = n - 1;
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
            // Pinned top-right under the bar; slides below toasts.
            anchors {
                top: parent.top
                right: parent.right
                topMargin: root.topInset + root.toastOffset
                rightMargin: 0
            }
            // Same width as the Bluetooth/Wi-Fi cards; height is
            // content-driven.
            implicitWidth: Math.min(340, parent.width - 24)
            implicitHeight: Math.min(col.implicitHeight + 32, parent.height - 48)
            width: implicitWidth
            height: implicitHeight
            color: root.cPanel
            border.width: 1
            border.color: root.cBorderStrong
            radius: root.cRadius
            // Micro-animation: subtle entrance (opacity 150ms OutCubic +
            // scale 0.96->1 180ms OutBack overshoot 1.2 + y -6->0).
            // Close stays instant (visible flips with isOpen, <200ms).
            transformOrigin: Item.TopRight
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

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true

                Keys.onEscapePressed: root.close()
                // Full keyboard nav: Up/Down/Left/Right + j/k adjust ±5,
                // PageUp/PageDown ±10, Home/End 0/100, M/Space mute,
                // Tab cycles sinks, Enter selects the highlighted sink.
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_M || event.key === Qt.Key_Space) {
                        AudioService.toggleMute();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Right || event.key === Qt.Key_K) {
                        AudioService.increase(2);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Left || event.key === Qt.Key_J) {
                        AudioService.decrease(2);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageUp) {
                        AudioService.increase(10);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageDown) {
                        AudioService.decrease(10);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Home) {
                        AudioService.setVolumePercent(0);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_End) {
                        AudioService.setVolumePercent(100);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.selectSinkCurrent();
                        event.accepted = true;
                    }
                }
                // Tab cycles the sink list (kept out of onPressed so Qt
                // focus navigation never steals it).
                Keys.onTabPressed: event => {
                    event.accepted = true;
                    root.moveSink(1);
                }
                Keys.onBacktabPressed: event => {
                    event.accepted = true;
                    root.moveSink(-1);
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
                        id: sinkFlick
                        width: parent.width
                        height: Math.min(sinkCol.implicitHeight, 148)
                        readonly property real gutter: 12
                        contentWidth: width - gutter
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
                            width: sinkFlick.width - sinkFlick.gutter
                            spacing: 6
                            Repeater {
                                model: root.sinkList
                                delegate: Rectangle {
                                    property var node: modelData
                                    readonly property bool isDefault: node === Pipewire.defaultAudioSink
                                    readonly property bool isCurrent: index === root.sinkCurrent
                                    width: sinkCol.width
                                    height: 62
                                    color: root.cRow
                                    border.width: 1
                                    border.color: isDefault ? root.cAccent : (isCurrent ? root.cAccentHover : root.cBorder)
                                    radius: root.cRadius
                                    transformOrigin: Item.Center
                                    scale: sinkMouse.pressed ? 0.98 : 1.0
                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 100
                                            easing.type: Easing.OutQuad
                                        }
                                    }
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 120
                                        }
                                    }

                                    PwObjectTracker {
                                        objects: node ? [node] : []
                                    }

                                    MouseArea {
                                        id: sinkMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onEntered: if (root.hoverArmed) root.sinkCurrent = index
                                        onPositionChanged: root.hoverArmed = true
                                        onPressed: root.hoverArmed = true
                                        onClicked: {
                                            root.sinkCurrent = index;
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

                    // ---- inputs ----
                    Text {
                        width: parent.width
                        text: "INPUTS"
                        font.family: root.cFont
                        font.pixelSize: 11
                        font.bold: true
                        color: root.cAccent
                        topPadding: 14
                        bottomPadding: 6
                    }
                    Flickable {
                        id: sourceFlick
                        width: parent.width
                        height: Math.min(sourceCol.implicitHeight, 148)
                        readonly property real gutter: 12
                        contentWidth: width - gutter
                        contentHeight: sourceCol.implicitHeight
                        clip: true
                        ScrollBar.vertical: ScrollBar {
                            policy: sourceCol.implicitHeight > 148 ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                            contentItem: Rectangle {
                                implicitWidth: 8
                                color: root.cBorderStrong
                                radius: root.cRadius
                            }
                        }
                        Column {
                            id: sourceCol
                            width: sourceFlick.width - sourceFlick.gutter
                            spacing: 6
                            Repeater {
                                model: root.sourceList
                                delegate: Rectangle {
                                    property var node: modelData
                                    readonly property bool isDefault: node === Pipewire.defaultAudioSource
                                    width: sourceCol.width
                                    height: 62
                                    color: root.cRow
                                    border.width: 1
                                    border.color: isDefault ? root.cAccent : root.cBorder
                                    radius: root.cRadius
                                    transformOrigin: Item.Center
                                    scale: srcMouse.pressed ? 0.98 : 1.0
                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 100
                                            easing.type: Easing.OutQuad
                                        }
                                    }
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 120
                                        }
                                    }

                                    PwObjectTracker {
                                        objects: node ? [node] : []
                                    }

                                    MouseArea {
                                        id: srcMouse
                                        anchors.fill: parent
                                        onClicked: {
                                            if (node)
                                                Pipewire.preferredDefaultAudioSource = node;
                                        }
                                    }
                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        anchors.topMargin: 6
                                        anchors.bottomMargin: 6
                                        spacing: 8
                                        Rectangle {
                                            width: 8
                                            height: 8
                                            radius: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: isDefault ? root.cAccent : root.cDim
                                        }
                                        Column {
                                            width: parent.width - 16 - 44 - 16 - 24
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 4
                                            Text {
                                                width: parent.width
                                                elide: Text.ElideRight
                                                text: (isDefault ? "\u2713 " : "") + (node ? (node.description || node.name) : "")
                                                    + (node && node.audio && node.audio.muted ? "  ·  off" : "")
                                                font.family: root.cFont
                                                font.pixelSize: 12
                                                color: (node && node.audio && node.audio.muted) ? root.cMuted : root.cText
                                            }
                                            VolSlider {
                                                cAccent: root.cAccent
                                                cAccentHover: root.cAccentHover
                                                cBg: root.cBg
                                                cBorder: root.cBorder
                                                id: srcSlider
                                                width: parent.width
                                                compact: true
                                                Binding {
                                                    target: srcSlider
                                                    property: "value"
                                                    value: (node && node.audio) ? Math.round(Math.min(1, node.audio.volume) * 100) : 0
                                                    when: !srcSlider.pressed
                                                }
                                                onMovedTo: v => {
                                                    if (node && node.audio)
                                                        node.audio.volume = Math.max(0, Math.min(1, v / 100));
                                                }
                                            }
                                        }
                                        // Tap the mic icon to mute/unmute this input.
                                        Rectangle {
                                            width: 24
                                            height: 24
                                            radius: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: (node && node.audio && node.audio.muted) ? root.cAccent : "transparent"
                                            border.width: 1
                                            border.color: root.cBorderStrong
                                            Text {
                                                anchors.centerIn: parent
                                                text: root.sourceIcon(node)
                                                font.family: root.cFont
                                                font.pixelSize: 12
                                                color: (node && node.audio && node.audio.muted) ? root.cBg : root.cText
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    if (node && node.audio)
                                                        node.audio.muted = !node.audio.muted;
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
                                            color: (node && node.audio && node.audio.muted) ? root.cDim : root.cMuted
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
                        text: "\u2191\u2193\u2190\u2192 \u00B15 \u00B7 PgUp/Dn \u00B110 \u00B7 Tab sink \u00B7 Enter select \u00B7 M mute \u00B7 Esc close"
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
                focusTimer.restart();
        }
    }

    // Volume slider (Sunset track + accent fill + round thumb).
    component VolSlider: Slider {
        // injected props (inline component scope is isolated)
        property color cAccent: root.cAccent
        property color cAccentHover: root.cAccentHover
        property color cBg: root.cBg
        property color cBorder: root.cBorder
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
        property color cAccent: root.cAccent
        property color cAccentHover: root.cAccentHover
        property color cBorderStrong: root.cBorderStrong
        property string cFont: root.cFont
        property int cRadius: 0
        property color cRow: root.cRow
        property color cText: root.cText
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
        transformOrigin: Item.Center
        scale: sMouse.pressed ? 0.98 : 1.0
        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutQuad
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
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
            id: sMouse
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
