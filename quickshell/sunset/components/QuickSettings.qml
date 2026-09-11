// QuickSettings.qml — quick-settings popup (volume/brightness/wifi/bt/power/dnd/idle).
//
// Replaces: waybar/settings/settings.html + settings-server.py +
//           launcher (waybar settings backend on 127.0.0.3) + Brave profile
//           ~/.cache/niri-settings (old app-id brave-127.0.0.3__-Default,
//           window 400x600). Also replaces the fuzzel idle-time.ini and
//           power-profile.ini pickers (segmented controls below cover the
//           same modes). The Brave profile, the settings-server.py daemon
//           and the 127.0.0.3 backend are all deleted by this migration.
//
// Backend parity (from settings-server.py — same commands, same clamps):
//   volume     -> wpctl set-volume @DEFAULT_AUDIO_SINK@ N% (cap 100) via
//                 AudioService (Pipewire); mute toggle via AudioService.
//   brightness -> brightnessctl get/max read, `brightnessctl set N%`
//                 write, clamp 5-100.
//   wifi       -> nmcli radio wifi on|off, `nmcli dev wifi connect SSID
//                 [password PW]`; list parsed like the server
//                 (ACTIVE:SSID:SIGNAL:SECURITY, top 12, active-first).
//   bluetooth  -> bluetoothctl power on|off, connect/disconnect <MAC>
//                 (MAC validated like the server), Connected via info.
//   power      -> PowerProfiles singleton (radio); `powerprofilesctl set`
//                 runs alongside as the authoritative setter (old backend
//                 parity); Performance hidden without hasPerformanceProfile.
//   dnd        -> NotificationService.dnd is the switch state; every toggle
//                 also flips `dunstctl set-paused` (old backend parity, so
//                 system popups pause too), and polls re-sync the service
//                 from dunst (dunst authoritative: preserves Mod+N binds).
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
//   - Card width 400 (old 400x600 window); content scrolls past 600.
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
    // Task term "exclusiveKeyboardFocus" == the Exclusive layer-shell
    // keyboard focus set on the PanelWindow below.
    readonly property bool exclusiveKeyboardFocus: true

    function open(): void {
        isOpen = true;
    }
    function close(): void {
        pendingSsid = "";
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

    // ---------- brightness ----------
    property int briPct: 50

    // ---------- wifi ----------
    property bool wifiEnabled: false
    property string wifiSsid: ""
    property string pendingSsid: ""
    ListModel {
        id: wifiModel
    }

    // ---------- bluetooth ----------
    property bool btPowered: false
    property var btQueue: []
    ListModel {
        id: btModel
    }

    // ---------- idle ----------
    property string idleCurrent: "10 minutes"

    // ================= poll: wifi =================
    Process {
        id: wifiProc
        command: ["bash", "-c", "echo \"STATE:$(nmcli -t -f WIFI g 2>/dev/null)\"; echo \"ACTIVE:\"; nmcli -t -f NAME,TYPE connection show --active 2>/dev/null; echo \"NETS:\"; nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY dev wifi 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            id: wifiOut
            onStreamFinished: root.parseWifi(text)
        }
    }
    function parseWifi(text: string): void {
        // Section split mirrors the server's three nmcli calls.
        const lines = text.split("\n");
        let section = "";
        let enabled = false;
        let active = "";
        const nets = [];
        const seen = {};
        for (let i = 0; i < lines.length; ++i) {
            const ln = lines[i];
            if (ln.indexOf("STATE:") === 0) {
                enabled = ln.slice(6).trim() === "enabled";
                continue;
            }
            if (ln === "ACTIVE:") {
                section = "active";
                continue;
            }
            if (ln === "NETS:") {
                section = "nets";
                continue;
            }
            if (section === "active") {
                const ci = ln.lastIndexOf(":");
                if (ci > 0 && ln.slice(ci + 1) === "802-11-wireless" && active === "")
                    active = ln.slice(0, ci);
            } else if (section === "nets") {
                const parts = ln.split(":");
                if (parts.length < 4)
                    continue;
                const ssid = parts[1];
                if (!ssid || seen[ssid])
                    continue;
                seen[ssid] = true;
                const sig = parseInt(parts[2]);
                nets.push({
                    "ssid": ssid,
                    "signal": isNaN(sig) ? 0 : sig,
                    "security": parts[3] !== "" && parts[3] !== "--",
                    "active": parts[0] === "yes" || ssid === active
                });
            }
        }
        nets.sort((a, b) => ((b.active ? 1 : 0) - (a.active ? 1 : 0)) || (b.signal - a.signal));
        wifiEnabled = enabled;
        wifiSsid = active;
        wifiModel.clear();
        const top = nets.slice(0, 12);
        for (let j = 0; j < top.length; ++j)
            wifiModel.append(top[j]);
    }
    Process {
        id: wifiToggleProc
        property string arg: "on"
        command: ["nmcli", "radio", "wifi", arg]
        running: false
        onExited: wifiProcRefresh()
    }
    Process {
        id: wifiJoinProc
        property string ssid: ""
        property string password: ""
        property string outText: ""
        command: password !== "" ? ["nmcli", "dev", "wifi", "connect", ssid, "password", password] : ["nmcli", "dev", "wifi", "connect", ssid]
        running: false
        stdout: StdioCollector {
            id: wifiJoinOut
            onStreamFinished: wifiJoinProc.outText = text
        }
        onExited: {
            if (exitCode === 0)
                root.say("\u2713 Connected to " + ssid);
            else
                root.say("\u2717 " + (outText.trim().split("\n").pop() ?? "Failed"));
            root.pendingSsid = "";
            wifiProcRefresh();
        }
    }
    function wifiProcRefresh(): void {
        if (!wifiProc.running)
            wifiProc.running = true;
    }
    function joinWifi(ssid: string, pw: string): void {
        say("Connecting to " + ssid + "\u2026");
        pendingSsid = "";
        wifiJoinProc.ssid = ssid;
        wifiJoinProc.password = pw;
        wifiJoinProc.running = true;
    }

    // ================= poll: bluetooth =================
    Process {
        id: btProc
        command: ["bash", "-c", "echo \"SHOW:\"; bluetoothctl show 2>/dev/null; echo \"DEVS:\"; bluetoothctl devices 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            id: btOut
            onStreamFinished: root.parseBt(text)
        }
    }
    function parseBt(text: string): void {
        const lines = text.split("\n");
        let section = "";
        let powered = false;
        const devs = [];
        for (let i = 0; i < lines.length; ++i) {
            const ln = lines[i];
            if (ln === "SHOW:") {
                section = "show";
                continue;
            }
            if (ln === "DEVS:") {
                section = "devs";
                continue;
            }
            if (section === "show") {
                if (/^\s*Powered:\s*yes/.test(ln))
                    powered = true;
            } else if (section === "devs") {
                const m = /^Device\s+(\S+)\s+(.*)/.exec(ln);
                if (m)
                    devs.push({
                        "address": m[1],
                        "name": m[2],
                        "connected": false
                    });
            }
        }
        btPowered = powered;
        btModel.clear();
        const top = devs.slice(0, 12);
        for (let j = 0; j < top.length; ++j)
            btModel.append(top[j]);
        // Resolve Connected per device serially (server parity: info call).
        btQueue = top.map(d => d.address);
        pumpBtInfo();
    }
    Process {
        id: btInfoProc
        property string addr: ""
        command: ["bluetoothctl", "info", addr]
        running: false
        stdout: StdioCollector {
            id: btInfoOut
            onStreamFinished: {
                const conn = /^\s*Connected:\s*yes/m.test(text);
                for (let i = 0; i < btModel.count; ++i) {
                    if (btModel.get(i).address === btInfoProc.addr)
                        btModel.setProperty(i, "connected", conn);
                }
            }
        }
        onExited: root.pumpBtInfo()
    }
    function pumpBtInfo(): void {
        if (btInfoProc.running || btQueue.length === 0)
            return;
        btInfoProc.addr = btQueue.shift();
        btInfoProc.running = true;
    }
    function btProcRefresh(): void {
        if (!btProc.running)
            btProc.running = true;
    }
    Process {
        id: btOpProc
        property var cmd: ["bluetoothctl", "power", "on"]
        command: cmd
        running: false
        onExited: btProcRefresh()
    }
    function btOp(args: var): void {
        btOpProc.cmd = args;
        btOpProc.running = true;
    }

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

    // ================= dnd (NotificationService + dunst mirror) =================
    Process {
        id: dndGetProc
        command: ["dunstctl", "is-paused"]
        running: false
        stdout: StdioCollector {
            id: dndGetOut
            onStreamFinished: {
                // dunst is authoritative (preserves Mod+N binds): the
                // quickshell service follows it.
                NotificationService.dnd = text.trim() === "true";
            }
        }
    }
    Process {
        id: dndToggleProc
        command: ["dunstctl", "set-paused", "toggle"]
        running: false
        onExited: dndGetProcRefresh()
    }
    function dndGetProcRefresh(): void {
        if (!dndGetProc.running)
            dndGetProc.running = true;
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
        wifiProcRefresh();
        btProcRefresh();
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

    function wifiSignalIcon(sig: int): string {
        if (sig >= 70)
            return "󰤨";
        if (sig >= 40)
            return "󰤥";
        return "󰤟";
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
            anchors.centerIn: parent
            // Old Brave window was 400x600; content scrolls past 600.
            implicitWidth: Math.min(400, parent.width - 32)
            implicitHeight: Math.min(col.implicitHeight + 26, 600, parent.height - 48)
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
                    const f = win.activeFocusItem;
                    if (f && (f.objectName === "pwEdit"))
                        return;
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

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 14
                    anchors.bottomMargin: 10
                    contentWidth: width
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
                        width: parent.width
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

                        // ---- wifi ----
                        SectionLabel {
                            cAccent: root.cAccent
                            cFont: root.cFont
                            text: "WI-FI"
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
                            title: "󰖩 Wi-Fi"
                            sub: root.wifiEnabled ? (root.wifiSsid !== "" ? root.wifiSsid : "On \u00B7 not connected") : "Off"
                            on: root.wifiEnabled
                            onClicked: {
                                wifiToggleProc.arg = root.wifiEnabled ? "off" : "on";
                                wifiToggleProc.running = true;
                            }
                        }
                        ListView {
                            width: parent.width
                            height: Math.min(contentHeight, 124)
                            visible: root.wifiEnabled && wifiModel.count > 0
                            model: wifiModel
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
                                width: ListView.view.width
                                height: 30
                                color: "transparent"
                                border.width: 1
                                border.color: model.active ? root.cAccent : "transparent"
                                radius: root.cRadius
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8
                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: model.active ? root.cAccent : root.cDim
                                    }
                                    Text {
                                        width: parent.width - 16 - 70
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        text: (model.security ? "󰌾 " : "") + model.ssid
                                        font.family: root.cFont
                                        font.pixelSize: 12
                                        color: wHover.hovered ? root.cAccentHover : root.cText
                                    }
                                    Text {
                                        width: 62
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: root.wifiSignalIcon(model.signal) + " " + model.signal + "%"
                                        font.family: root.cFont
                                        font.pixelSize: 11
                                        color: root.cMuted
                                    }
                                }
                                HoverHandler {
                                    id: wHover
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (model.active)
                                            return;
                                        if (!model.security)
                                            root.joinWifi(model.ssid, "");
                                        else {
                                            root.pendingSsid = model.ssid;
                                            pwInput.text = "";
                                            pwInput.forceActiveFocus();
                                        }
                                    }
                                }
                            }
                        }
                        Item {
                            width: parent.width
                            height: 4
                            visible: root.pendingSsid !== ""
                        }
                        Row {
                            width: parent.width
                            spacing: 6
                            visible: root.pendingSsid !== ""
                            TextField {
                                id: pwInput
                                objectName: "pwEdit"
                                width: parent.width - 70
                                placeholderText: "Password\u2026"
                                echoMode: TextInput.Password
                                font.family: root.cFont
                                font.pixelSize: 12
                                color: root.cText
                                placeholderTextColor: root.cDim
                                background: Rectangle {
                                    color: root.cBg
                                    border.width: 1
                                    border.color: pwInput.activeFocus ? root.cAccent : root.cBorderStrong
                                    radius: root.cRadius
                                }
                                onAccepted: root.joinWifi(root.pendingSsid, text)
                            }
                            SunsetBtn {
                                cAccent: root.cAccent
                                cAccentHover: root.cAccentHover
                                cBorderStrong: root.cBorderStrong
                                cFont: root.cFont
                                cRadius: root.cRadius
                                cRow: root.cRow
                                cText: root.cText
                                cols: 1
                                label: "Join"
                                width: 64
                                onClicked: root.joinWifi(root.pendingSsid, pwInput.text)
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
                            sub: root.btPowered ? root.btSummary() : "Off"
                            on: root.btPowered
                            onClicked: root.btOp(root.btPowered ? ["bluetoothctl", "power", "off"] : ["bluetoothctl", "power", "on"])
                        }
                        ListView {
                            width: parent.width
                            height: Math.min(contentHeight, 100)
                            visible: root.btPowered && btModel.count > 0
                            model: btModel
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
                                width: ListView.view.width
                                height: 30
                                color: "transparent"
                                border.width: 1
                                border.color: model.connected ? root.cAccent : "transparent"
                                radius: root.cRadius
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8
                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: model.connected ? root.cAccent : root.cDim
                                    }
                                    Text {
                                        width: parent.width - 16 - 80
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        text: model.name
                                        font.family: root.cFont
                                        font.pixelSize: 12
                                        color: bHover.hovered ? root.cAccentHover : root.cText
                                    }
                                    Text {
                                        width: 72
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: model.connected ? "connected" : ""
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
                                        if (!/^[0-9A-Fa-f:]{17}$/.test(model.address))
                                            return;
                                        root.say((model.connected ? "Disconnecting " : "Connecting ") + model.name + "\u2026");
                                        root.btOp(["bluetoothctl", model.connected ? "disconnect" : "connect", model.address]);
                                    }
                                }
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
                                    visible: index !== 0 || PowerProfiles.hasPerformanceProfile
                                    width: visible ? (parent.width - 12) / 3 : 0
                                    height: 34
                                    color: PowerProfiles.profile === modelData.prof ? root.cAccent : root.cRow
                                    border.width: 1
                                    border.color: PowerProfiles.profile === modelData.prof ? root.cAccent : root.cBorder
                                    radius: root.cRadius
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.family: root.cFont
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: PowerProfiles.profile === modelData.prof ? root.cBg : root.cText
                                    }
                                    MouseArea {
                                        anchors.fill: parent
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
                            sub: NotificationService.dnd ? "On \u00B7 notifications paused" : "Off"
                            on: NotificationService.dnd
                            onClicked: {
                                NotificationService.toggleDnd();
                                if (!dndToggleProc.running)
                                    dndToggleProc.running = true;
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
                                    width: (parent.width - 24) / 5
                                    height: 34
                                    color: root.idleCurrent === modelData ? root.cAccent : root.cRow
                                    border.width: 1
                                    border.color: root.idleCurrent === modelData ? root.cAccent : root.cBorder
                                    radius: root.cRadius
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.idleShort[modelData] ?? modelData
                                        font.family: root.cFont
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: root.idleCurrent === modelData ? root.cBg : root.cText
                                    }
                                    MouseArea {
                                        anchors.fill: parent
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
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: "tap a network or device to connect \u00B7 \u2191/\u2193 volume \u00B7 M mute \u00B7 Esc closes"
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
                keys.forceActiveFocus();
        }
    }

    function btSummary(): string {
        let names = [];
        for (let i = 0; i < btModel.count; ++i) {
            if (btModel.get(i).connected)
                names.push(btModel.get(i).name);
        }
        return names.length > 0 ? names.join(", ") : "On \u00B7 not connected";
    }

    component SectionLabel: Text {
        // injected props (inline component scope is isolated)
        property color cAccent: "#E85D2F"
        property string cFont: "JetBrainsMono Nerd Font"
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
        property color cAccent: "#E85D2F"
        property color cAccentHover: "#FF8B4A"
        property color cBg: "#000000"
        property color cBorder: "#1a1210"
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
        property color cAccent: "#E85D2F"
        property color cAccentHover: "#FF8B4A"
        property color cBorderStrong: "#3D2B24"
        property string cFont: "JetBrainsMono Nerd Font"
        property int cRadius: 0
        property color cRow: "#141010"
        property color cText: "#F7C7A1"
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

    component SwitchRow: Rectangle {
        // injected props (inline component scope is isolated)
        property color cAccent: "#E85D2F"
        property color cBorder: "#1a1210"
        property color cBorderStrong: "#3D2B24"
        property color cDim: "#555555"
        property string cFont: "JetBrainsMono Nerd Font"
        property color cMuted: "#7C8A6A"
        property int cRadius: 0
        property color cRow: "#141010"
        property color cText: "#F7C7A1"
        id: sw
        property string title: ""
        property string sub: ""
        property bool on: false
        signal clicked
        height: 42
        color: cRow
        border.width: 1
        border.color: cBorder
        radius: cRadius
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
                // Only the pill itself is clickable (matches old toggle UX).
                MouseArea {
                    anchors.fill: parent
                    onClicked: sw.clicked()
                }
            }
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
