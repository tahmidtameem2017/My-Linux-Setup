// QuickSettings.qml — quick-settings popup (volume/brightness/bt/power/dnd/idle).
//
// Replaces: waybar/settings/settings.html + settings-server.py +
//           launcher (waybar settings backend on 127.0.0.3) + Brave profile
//           ~/.cache/niri-settings (old app-id brave-127.0.0.3__-Default,
//           window 400x600). Also replaces the fuzzel idle-time.ini and
//           power-profile.ini pickers (segmented controls below cover the
//           same modes). The Brave profile, the settings-server.py daemon
//           and the 127.0.0.3 backend are all deleted by this migration.
//
// Wi-Fi is NOT here (moved 2026-10-03): a network list wants the top-right
// corner the Bluetooth card already owns, not the middle of a slider card,
// and it needed no `nmtui connect` terminal once it was its own surface. See
// components/WifiPopup.qml + services/WifiService.qml and the `wifi` IPC
// target (bar network icon, launcher row, Mod+Alt+F).
//
// Backend parity (from settings-server.py — same commands, same clamps):
//   volume     -> wpctl set-volume @DEFAULT_AUDIO_SINK@ N% (cap 100) via
//                 AudioService (Pipewire); mute toggle via AudioService.
//   brightness -> brightnessctl get/max read, `brightnessctl set N%`
//                 write, clamp 5-100.
//   bluetooth  -> bluetoothctl power on|off, connect/disconnect <MAC>
//                 (MAC validated like the server), Connected via info.
//   power      -> PowerProfiles singleton (radio); `powerprofilesctl set`
//                 runs alongside as the authoritative setter (old backend
//                 parity); Performance hidden without hasPerformanceProfile.
//   dnd        -> NotificationService.dnd is authoritative (dunst was never
//                 installed here; swaync retired at cutover).
//   idle       -> FileView on ~/.local/state/idle-time (modes exactly
//                 5/10/20/30 minutes + infinity, default display
//                 "10 minutes"); select writes the file, then pkill swayidle
//                 + relaunches scripts/swayidle.sh (server idle_set parity).
// Polling (old 3s status loop) runs only while open; slider/brightness
// writes debounce 150ms and pause repaint while dragging (old drag-pause).
//
// Shell contract (landed sunset pattern, cf. ClipboardPopup/Launcher):
//   - exclusiveKeyboardFocus == WlrLayershell.keyboardFocus Exclusive.
//   - Esc/M/arrows; outside-click closes; Bar re-click toggles via IPC.
//   - DOCKED TOP-RIGHT under the bar (2026-10-03) with the Bluetooth, Wi-Fi
//     and mixer cards: one corner for hardware state instead of a centered
//     card floating over the middle of the screen. `toastOffset` (shell.qml
//     wires `toasts.occupiedHeight`) keeps it clear of a toast stack.
//   - Card width 340; the card is height-capped (600, or the screen minus
//     margins) and the content scrolls inside it.
//   - niri layer-rule doc (shell owner adds, do NOT edit rules.kdl here):
//       layer-rule { match namespace="sunset-settings" }
//     Verify: `niri msg layers`
// IPC: `qs -c sunset ipc call settings toggle` (also: open, close)

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
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

    function open(): void {
        swCurrent = 0;
        isOpen = true;
        focusTimer.restart();
    }
    function close(): void {
        swCurrent = -1;
        isOpen = false;
    }
    function toggle(): void {
        if (isOpen)
            close();
        else
            open();
    }

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string repoDir: Quickshell.env("NIRI_SETUP_HOME") ?? (homeDir + "/niri-setup")
    readonly property string swayidleScript: repoDir + "/scripts/swayidle.sh"
    readonly property string idlePath: homeDir + "/.local/state/idle-time"
    readonly property var idleModes: ["5 minutes", "10 minutes", "20 minutes", "30 minutes", "infinity"]
    readonly property var idleShort: {
        "5 minutes": "5m",
        "10 minutes": "10m",
        "20 minutes": "20m",
        "30 minutes": "30m",
        "infinity": "\u221E"
    }

    property string msg: ""
    function say(t: string): void {
        msg = t;
    }

    // Keyboard focus over the three toggle rows (-1 = volume/sliders,
    // 0 = bluetooth, 1 = do-not-disturb). Tab cycles,
    // Enter/Space toggles the focused row (else mutes).
    property int swCurrent: -1
    function moveSw(dir: int): void {
        const order = [-1, 0, 1];
        let i = order.indexOf(swCurrent);
        if (i === -1)
            i = 0;
        i = (i + dir + order.length) % order.length;
        swCurrent = order[i];
    }
    function toggleSwCurrent(): void {
        if (swCurrent === 0) {
            BluetoothService.togglePower();
        } else if (swCurrent === 1) {
            NotificationService.toggleDnd();
        } else {
            AudioService.toggleMute();
        }
    }

    // ---------- brightness ----------
    property int briPct: 50

    // ---------- bluetooth ----------
    // State lives in BluetoothService (Quickshell.Bluetooth live bindings);
    // this file keeps no btModel/btProc of its own any more.

    // ---------- idle ----------
    property string idleCurrent: "10 minutes"

    // ================= brightness =================
    Process {
        id: briGetProc
        command: ["bash", "-c", "echo \"$(brightnessctl get 2>/dev/null) $(brightnessctl max 2>/dev/null)\""]
        running: false
        stdout: StdioCollector {
            id: briGetOut
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                const cur = parseInt(parts[0]);
                const mx = parseInt(parts[1]);
                if (!isNaN(cur) && !isNaN(mx) && mx > 0)
                    root.briPct = Math.max(0, Math.min(100, Math.round(cur / mx * 100)));
            }
        }
    }
    Process {
        id: briSetProc
        property int val: 50
        command: ["brightnessctl", "set", val + "%"]
        running: false
    }
    Timer {
        id: briDebounce
        interval: 150
        running: false
        repeat: false
        onTriggered: {
            briSetProc.val = Math.max(5, Math.min(100, briSlider.value));
            briSetProc.running = true;
        }
    }

    // ================= volume (AudioService = Pipewire default sink) =================
    Timer {
        id: volDebounce
        interval: 150
        running: false
        repeat: false
        onTriggered: AudioService.setVolumePercent(volSlider.value)
    }

    // Re-assert keyboard focus on open (Launcher/WallpaperMenu parity).
    Timer {
        id: focusTimer
        interval: 60
        running: false
        repeat: false
        onTriggered: keys.forceActiveFocus()
    }

    function adjustBri(delta: int): void {
        briPct = Math.max(5, Math.min(100, briPct + delta));
        briDebounce.stop();
        briDebounce.start();
    }

    // ================= power profile =================
    readonly property var powerOptions: [
        {
            "label": "Performance",
            "ctl": "performance",
            "prof": PowerProfile.Performance
        },
        {
            "label": "Balanced",
            "ctl": "balanced",
            "prof": PowerProfile.Balanced
        },
        {
            "label": "Power Saver",
            "ctl": "power-saver",
            "prof": PowerProfile.PowerSaver
        }
    ]
    Process {
        id: powerSetProc
        property string profile: "balanced"
        command: ["powerprofilesctl", "set", profile]
        running: false
    }

    // ================= dnd (native only) =================
    // dunst was never installed on this machine (binary absent), and swaync
    // is being retired at cutover — NotificationService.dnd is authoritative.
    function dndGetProcRefresh(): void {
    }

    // ================= idle timeout =================
    FileView {
        id: idleFile
        path: root.idlePath
        watchChanges: true
        onLoaded: root.readIdle(text())
        onFileChanged: reload()
        onSaved: root.restartSwayidle()
    }
    function readIdle(t: string): void {
        const v = t.trim();
        idleCurrent = idleModes.indexOf(v) !== -1 ? v : "10 minutes";
    }
    function setIdle(mode: string): void {
        if (idleModes.indexOf(mode) === -1)
            return;
        idleFile.setText(mode + "\n");
    }
    Process {
        id: idleKillProc
        command: ["pkill", "swayidle"]
        running: false
        onExited: Quickshell.execDetached(["bash", root.swayidleScript])
    }
    function restartSwayidle(): void {
        idleFile.reload();
        if (!idleKillProc.running)
            idleKillProc.running = true;
    }

    // ================= refresh loop (while open only) =================
    function refreshAll(): void {
        if (!briGetProc.running)
            briGetProc.running = true;
        dndGetProcRefresh();
    }
    Timer {
        id: refreshTimer
        interval: 5000
        running: root.isOpen
        repeat: true
        onTriggered: root.refreshAll()
    }
    onIsOpenChanged: {
        if (isOpen)
            refreshAll();
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
        WlrLayershell.namespace: "sunset-settings"

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
            // Same width as the Bluetooth/Wi-Fi/mixer cards. Content scrolls
            // inside (the idle-timeout + power-profile rows alone are taller
            // than the cap on a short screen).
            implicitWidth: Math.min(340, parent.width - 24)
            implicitHeight: Math.min(col.implicitHeight + 26, 600, parent.height - 48)
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
                // Tab cycles the toggle rows (kept out of onPressed so Qt
                // focus navigation never steals it). A focused password
                // field traps Tab back to the card (single field, nothing
                // else Qt-focusable in here).
                Keys.onTabPressed: event => {
                    const f = win.activeFocusItem;
                    if (f && (f.objectName === "pwEdit")) {
                        event.accepted = true;
                        keys.forceActiveFocus();
                        return;
                    }
                    event.accepted = true;
                    root.moveSw(1);
                }
                Keys.onBacktabPressed: event => {
                    const f = win.activeFocusItem;
                    if (f && (f.objectName === "pwEdit")) {
                        event.accepted = true;
                        keys.forceActiveFocus();
                        return;
                    }
                    event.accepted = true;
                    root.moveSw(-1);
                }
                Keys.onPressed: event => {
                    const f = win.activeFocusItem;
                    if (f && (f.objectName === "pwEdit"))
                        return;
                    if (event.key === Qt.Key_M) {
                        AudioService.toggleMute();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                        AudioService.increase(2);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                        AudioService.decrease(2);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left) {
                        root.adjustBri(-5);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Right) {
                        root.adjustBri(5);
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
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.toggleSwCurrent();
                        event.accepted = true;
                    }
                }

                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 14
                    anchors.bottomMargin: 10
                    // Reserve scrollbar gutter so content never slides under it.
                    // NOTE: children of Flickable attach to its contentItem,
                    // so Column must use flick.<prop>, never parent.<prop>.
                    readonly property real gutter: 12
                    contentWidth: width - gutter
                    contentHeight: col.implicitHeight
                    clip: true
                    ScrollBar.vertical: ScrollBar {
                        contentItem: Rectangle {
                            implicitWidth: 8
                            color: root.cBorderStrong
                            radius: root.cRadius
                        }
                    }

                    Column {
                        id: col
                        width: flick.width - flick.gutter
                        spacing: 0

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: "QUICK SETTINGS"
                            font.family: root.cFont
                            font.pixelSize: 12
                            font.bold: true
                            color: root.cAccent
                            bottomPadding: 4
                        }

                        // ---- volume ----
                        SectionLabel {
                            cAccent: root.cAccent
                            cFont: root.cFont
                            text: "VOLUME \u00B7 " + AudioService.volume + "%"
                        }
                        VolSlider {
                            cAccent: root.cAccent
                            cAccentHover: root.cAccentHover
                            cBg: root.cBg
                            cBorder: root.cBorder
                            id: volSlider
                            width: parent.width
                            Binding {
                                target: volSlider
                                property: "value"
                                value: AudioService.volume
                                when: !volSlider.pressed
                            }
                            onMovedTo: v => {
                                volDebounce.stop();
                                volDebounce.start();
                            }
                        }
                        Item {
                            width: parent.width
                            height: 6
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
                                cols: 4
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
                                cols: 4
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
                                cols: 4
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
                                cols: 4
                                gap: 8
                                label: "75"
                                onClicked: AudioService.setVolumePercent(75)
                            }
                        }

                        // ---- brightness ----
                        SectionLabel {
                            cAccent: root.cAccent
                            cFont: root.cFont
                            text: "BRIGHTNESS \u00B7 " + root.briPct + "%"
                        }
                        VolSlider {
                            cAccent: root.cAccent
                            cAccentHover: root.cAccentHover
                            cBg: root.cBg
                            cBorder: root.cBorder
                            id: briSlider
                            width: parent.width
                            minimum: 5
                            Binding {
                                target: briSlider
                                property: "value"
                                value: root.briPct
                                when: !briSlider.pressed
                            }
                            onMovedTo: v => {
                                root.briPct = Math.round(v);
                                briDebounce.stop();
                                briDebounce.start();
                            }
                        }

                        // ---- bluetooth ----
                        SectionLabel {
                            cAccent: root.cAccent
                            cFont: root.cFont
                            text: "BLUETOOTH"
                        }
                        SwitchRow {
                            cAccent: root.cAccent
                            cBorder: root.cBorder
                            cBorderStrong: root.cBorderStrong
                            cDim: root.cDim
                            cFont: root.cFont
                            cMuted: root.cMuted
                            cRadius: root.cRadius
                            cRow: root.cRow
                            cText: root.cText
                            width: parent.width
                            title: "󰂯 Bluetooth"
                            kbActive: root.swCurrent === 0
                            sub: BluetoothService.powered ? root.btSummary() : "Off"
                            on: BluetoothService.powered
                            onClicked: BluetoothService.togglePower()
                        }
                        ListView {
                            width: parent.width
                            height: Math.min(contentHeight, 100)
                            visible: BluetoothService.powered && BluetoothService.devices.length > 0
                            model: BluetoothService.devices
                            clip: true
                            interactive: contentHeight > height
                            ScrollBar.vertical: ScrollBar {
                                contentItem: Rectangle {
                                    implicitWidth: 8
                                    color: root.cBorderStrong
                                    radius: root.cRadius
                                }
                            }
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool btConn: modelData.connected
                                readonly property int btBat: BluetoothService.batteryPercent(modelData)
                                width: ListView.view.width
                                height: 30
                                color: "transparent"
                                border.width: 1
                                border.color: btConn ? root.cAccent : "transparent"
                                radius: root.cRadius
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8
                                    Text {
                                        width: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        text: BluetoothService.glyph(modelData.icon)
                                        font.family: root.cFont
                                        font.pixelSize: 13
                                        color: btConn ? root.cAccent : root.cDim
                                    }
                                    Text {
                                        width: parent.width - 16 - 76 - 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        text: BluetoothService.displayName(modelData)
                                        font.family: root.cFont
                                        font.pixelSize: 12
                                        color: bHover.hovered ? root.cAccentHover : root.cText
                                    }
                                    Text {
                                        width: 76
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: btConn ? (btBat >= 0 ? btBat + "%" : "connected") : ""
                                        font.family: root.cFont
                                        font.pixelSize: 11
                                        color: root.cMuted
                                    }
                                }
                                HoverHandler {
                                    id: bHover
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        root.say((btConn ? "Disconnecting " : "Connecting ") + BluetoothService.displayName(modelData) + "…");
                                        BluetoothService.toggleConnection(modelData);
                                    }
                                }
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: 30
                            visible: BluetoothService.powered && BluetoothService.devices.length === 0
                            color: "transparent"
                            radius: root.cRadius
                            Text {
                                anchors.centerIn: parent
                                text: "No paired devices — open Settings to pair"
                                font.family: root.cFont
                                font.pixelSize: 11
                                color: btEmptyHover.hovered ? root.cAccentHover : root.cMuted
                            }
                            HoverHandler {
                                id: btEmptyHover
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached([root.repoDir + "/scripts/gnome-settings.sh", "bluetooth"])
                            }
                        }

                        // ---- power profile ----
                        SectionLabel {
                            cAccent: root.cAccent
                            cFont: root.cFont
                            text: "POWER PROFILE"
                        }
                        Row {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: root.powerOptions
                                delegate: Rectangle {
                                    readonly property bool isSel: PowerProfiles.profile === modelData.prof
                                    visible: index !== 0 || PowerProfiles.hasPerformanceProfile
                                    width: visible ? (parent.width - 12) / 3 : 0
                                    height: 34
                                    color: isSel ? root.cAccent : root.cRow
                                    border.width: 1
                                    border.color: isSel ? root.cAccent : (ppHover.hovered ? root.cAccentHover : root.cBorder)
                                    radius: root.cRadius
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 120
                                        }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.family: root.cFont
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: isSel ? Theme.onAccent : (ppHover.hovered ? root.cAccentHover : root.cText)
                                    }
                                    HoverHandler {
                                        id: ppHover
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            PowerProfiles.profile = modelData.prof;
                                            powerSetProc.profile = modelData.ctl;
                                            powerSetProc.running = true;
                                        }
                                    }
                                }
                            }
                        }

                        // ---- dnd ----
                        SectionLabel {
                            cAccent: root.cAccent
                            cFont: root.cFont
                            text: "DO NOT DISTURB"
                        }
                        SwitchRow {
                            cAccent: root.cAccent
                            cBorder: root.cBorder
                            cBorderStrong: root.cBorderStrong
                            cDim: root.cDim
                            cFont: root.cFont
                            cMuted: root.cMuted
                            cRadius: root.cRadius
                            cRow: root.cRow
                            cText: root.cText
                            width: parent.width
                            title: "󰂛 Do Not Disturb"
                            kbActive: root.swCurrent === 1
                            sub: NotificationService.dnd ? "On \u00B7 notifications paused" : "Off"
                            on: NotificationService.dnd
                            onClicked: {
                                NotificationService.toggleDnd();
                            }
                        }

                        // ---- idle timeout ----
                        SectionLabel {
                            cAccent: root.cAccent
                            cFont: root.cFont
                            text: "IDLE TIMEOUT"
                        }
                        Row {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: root.idleModes
                                delegate: Rectangle {
                                    readonly property bool isSel: root.idleCurrent === modelData
                                    width: (parent.width - 24) / 5
                                    height: 34
                                    color: isSel ? root.cAccent : root.cRow
                                    border.width: 1
                                    border.color: isSel ? root.cAccent : (idleHover.hovered ? root.cAccentHover : root.cBorder)
                                    radius: root.cRadius
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 120
                                        }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.idleShort[modelData] ?? modelData
                                        font.family: root.cFont
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: isSel ? Theme.onAccent : (idleHover.hovered ? root.cAccentHover : root.cText)
                                    }
                                    HoverHandler {
                                        id: idleHover
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.setIdle(modelData)
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: root.msg
                            font.family: root.cFont
                            font.pixelSize: 11
                            color: root.cMuted
                            elide: Text.ElideRight
                            topPadding: 8
                        }
                        Item {
                            width: parent.width
                            height: 12
                        }
                        Row {
                            width: parent.width
                            spacing: 6
                            SunsetBtn {
                                cAccent: root.cAccent
                                cAccentHover: root.cAccentHover
                                cBorderStrong: root.cBorderStrong
                                cFont: root.cFont
                                cRadius: root.cRadius
                                cRow: root.cRow
                                cText: root.cText
                                cols: 2
                                hot: true
                                label: "GNOME Settings…"
                                // NOTE: gnome-control-center 50+ exits unless
                                // XDG_CURRENT_DESKTOP contains GNOME (scoped
                                // override — session stays niri).
                                onClicked: {
                                    Quickshell.execDetached(["env", "XDG_CURRENT_DESKTOP=GNOME", "gnome-control-center"]);
                                    root.close();
                                }
                            }
                            SunsetBtn {
                                cAccent: root.cAccent
                                cAccentHover: root.cAccentHover
                                cBorderStrong: root.cBorderStrong
                                cFont: root.cFont
                                cRadius: root.cRadius
                                cRow: root.cRow
                                cText: root.cText
                                cols: 2
                                label: "Close"
                                onClicked: root.close()
                            }
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: "\u2191/\u2193 vol \u00B7 \u2190/\u2192 bright \u00B7 Tab switch \u00B7 Enter toggle \u00B7 M mute \u00B7 Esc"
                            font.family: root.cFont
                            font.pixelSize: 10
                            color: root.cMuted
                            topPadding: 10
                        }
                    }
                }
            }
        }

        onVisibleChanged: {
            if (visible)
                focusTimer.restart();
        }
    }

    function btSummary(): string {
        let names = [];
        const devs = BluetoothService.devices;
        for (let i = 0; i < devs.length; ++i) {
            if (devs[i].connected)
                names.push(BluetoothService.displayName(devs[i]));
        }
        return names.length > 0 ? names.join(", ") : "On \u00B7 not connected";
    }

    component SectionLabel: Text {
        // injected props (inline component scope is isolated)
        property color cAccent: root.cAccent
        property string cFont: root.cFont
        width: parent ? parent.width : 100
        font.family: cFont
        font.pixelSize: 11
        font.bold: true
        color: cAccent
        topPadding: 12
        bottomPadding: 6
    }

    component VolSlider: Slider {
        // injected props (inline component scope is isolated)
        property color cAccent: root.cAccent
        property color cAccentHover: root.cAccentHover
        property color cBg: root.cBg
        property color cBorder: root.cBorder
        id: sl
        property real minimum: 0
        signal movedTo(real v)
        from: minimum
        to: 100
        stepSize: 1
        focusPolicy: Qt.NoFocus
        implicitHeight: 26
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
            width: 20
            height: 20
            radius: 10
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

    component SwitchRow: Rectangle {
        // injected props (inline component scope is isolated)
        property color cAccent: root.cAccent
        property color cBorder: root.cBorder
        property color cBorderStrong: root.cBorderStrong
        property color cDim: root.cDim
        property string cFont: root.cFont
        property color cMuted: root.cMuted
        property int cRadius: 0
        property color cRow: root.cRow
        property color cText: root.cText
        id: sw
        property string title: ""
        property string sub: ""
        property bool on: false
        // Keyboard selection (Tab cycle): accent outline like hover.
        property bool kbActive: false
        signal clicked
        height: 42
        color: cRow
        border.width: 1
        border.color: (kbActive || rowHover.hovered) ? cAccent : cBorder
        radius: cRadius
        transformOrigin: Item.Center
        scale: swMouse.pressed ? 0.98 : 1.0
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
        Row {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10
            Column {
                width: parent.width - 54 - 10
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: sw.title
                    font.family: cFont
                    font.pixelSize: 13
                    font.bold: true
                    color: cText
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: sw.sub
                    font.family: cFont
                    font.pixelSize: 10
                    color: cMuted
                }
            }
            Rectangle {
                width: 44
                height: 24
                radius: 12
                anchors.verticalCenter: parent.verticalCenter
                color: "transparent"
                border.width: 1
                border.color: sw.on ? cAccent : cBorderStrong
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: cAccent
                    opacity: 0.25
                    visible: sw.on
                }
                Rectangle {
                    x: sw.on ? parent.width - width - 2 : 2
                    y: 2
                    width: 18
                    height: 18
                    radius: 9
                    color: sw.on ? cAccent : cDim
                }
            }
        }
        HoverHandler {
            id: rowHover
        }
        // Whole row toggles (single click anywhere selects/activates).
        MouseArea {
            id: swMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: sw.clicked()
        }
    }

    IpcHandler {
        target: "settings"

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
