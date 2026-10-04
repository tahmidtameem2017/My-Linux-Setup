// WifiService.qml — singleton NetworkManager state for the bar network icon,
// the WifiPopup (top-right card) and anything else that needs the SSID list.
//
// One nmcli parser and one set of actions, shared by every surface. The old
// arrangement had two independent copies of the parsing (the 30s poll inside
// TrayWidgets.NetworkIcon, and a 5s poll plus six action Processes inside
// QuickSettings.qml) which could disagree: the icon said wifi-off while the
// settings card still listed networks.
//
// TWO POLL TIERS, because the two questions cost very different amounts:
//   cheap  (always on, 30s, 2 forks): `nmcli radio wifi` + `nmcli dev status`
//           -> enabled / connected / wired. Enough for a 14px bar icon.
//   list   (only while listening, 5s): `nmcli dev wifi list` re-scans the
//           visible APs (~200ms) and is also how the stored profiles are read.
//           WifiPopup sets `listening` while it is open; a bar icon must not
//           pay for that forever.
// Every mutating action refreshes both tiers on exit, so a connect/forget is
// visible immediately rather than at the next tick.
//
// nmtui is deliberately gone from the shell. The popup does radio on/off,
// connect (stored profile or open or with a typed password), disconnect,
// forget and rescan natively, which is everything nmtui connect was reached
// for; a terminal window for that was the last piece of waybar-era scaffolding
// left in the live session.
//
// Escape handling in the nmcli parser: `nmcli -t` escapes `:` as `\:` and
// `\` as `\\`, so splitting on a bare ":" truncates any SSID containing a
// colon (guest networks love them). splitEscaped() undoes that first.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ================= state =================
    // `nmcli radio wifi` state.
    property bool enabled: false
    // Any network device up (wireless or wired) — what the bar icon shows.
    property bool connected: false
    property bool wired: false
    // Active wireless SSID ("" when off, disconnected, or a hidden AP we
    // cannot name; a hidden network is not in `dev wifi list` by name).
    property string ssid: ""
    // [{ ssid, signal, security, active, saved, profile }] — active first,
    // then by signal, capped at 12 (same cap the settings card used).
    property var networks: []
    // WifiPopup sets this while it is open; gates the list tier.
    property bool listening: false
    property bool scanning: false
    // One-line status; `lastError` non-empty means it is an error.
    property string msg: ""
    property string lastError: ""

    // ================= glyphs =================
    // Nerd Font codepoints as escapes via fromCodePoint: these are all
    // astral-plane (U+F0xxx in the nf-md range), so "\uXXXX" cannot express
    // them (cf. AGENTS.md — never paste the raw PUA character).
    readonly property var glyphSignalLow: String.fromCodePoint(0xF091F)
    readonly property var glyphSignalMid: String.fromCodePoint(0xF0925)
    readonly property var glyphSignalHigh: String.fromCodePoint(0xF0928)
    readonly property string glyphLock: String.fromCodePoint(0xF033E)
    readonly property string glyphWifi: String.fromCodePoint(0xF075F)

    function signalGlyph(sig: int): string {
        if (sig >= 70)
            return glyphSignalHigh;
        if (sig >= 40)
            return glyphSignalMid;
        return glyphSignalLow;
    }

    // ================= status =================
    Timer {
        id: msgTimer
        interval: 5000
        repeat: false
        onTriggered: {
            root.msg = "";
            root.lastError = "";
        }
    }
    function say(t: string): void {
        msg = t;
        lastError = "";
        msgTimer.restart();
    }
    function fail(t: string): void {
        msg = t;
        lastError = t;
        msgTimer.restart();
    }
    // nmcli errors are one line, but it is often two ("Error: ...\n1: ...");
    // take the last non-empty line so the popup never shows a wrapped blob.
    function lastLine(t: string): string {
        const parts = t.trim().split("\n");
        for (let i = parts.length - 1; i >= 0; --i) {
            const s = parts[i].trim();
            if (s !== "")
                return s;
        }
        return "failed";
    }

    // ================= nmcli parsing =================
    // Split a terse line on unescaped colons, undoing nmcli's escaping.
    // No return-type annotation on purpose: QML has no `array` type, and
    // declaring one makes it coerce every result to void ("should be coerced
    // to void because the function called is insufficiently annotated").
    function splitEscaped(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; ++i) {
            const ch = line.charAt(i);
            if (ch === "\\") {
                const next = line.charAt(i + 1);
                if (next !== "") {
                    cur += next;
                    ++i;
                    continue;
                }
                cur += ch;
                continue;
            }
            if (ch === ":") {
                out.push(cur);
                cur = "";
                continue;
            }
            cur += ch;
        }
        out.push(cur);
        return out;
    }

    // ---- cheap tier ----
    Process {
        id: lightProc
        command: ["bash", "-c", "echo \"STATE:$(nmcli -t -f WIFI g 2>/dev/null)\"; nmcli -t -f TYPE,STATE device status 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            id: lightOut
            onStreamFinished: root.parseLight(text)
        }
    }
    Timer {
        id: lightTimer
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshLight()
    }
    function refreshLight(): void {
        if (!lightProc.running)
            lightProc.running = true;
    }
    function parseLight(t: string): void {
        const lines = t.split("\n");
        let en = enabled;
        let wifiUp = false;
        let wiredUp = false;
        for (let i = 0; i < lines.length; ++i) {
            const ln = lines[i].replace(/\r$/, "");
            if (ln.indexOf("STATE:") === 0) {
                en = ln.slice(6).trim() === "enabled";
                continue;
            }
            const ci = ln.lastIndexOf(":");
            if (ci <= 0)
                continue;
            const type = ln.slice(0, ci);
            const state = ln.slice(ci + 1);
            const up = state === "connected" || state.indexOf("connected(") === 0;
            if (type === "wifi" || type === "802-11-wireless") {
                if (up)
                    wifiUp = true;
            } else if (type === "ethernet" || type === "802-3-ethernet") {
                if (up)
                    wiredUp = true;
            }
        }
        enabled = en;
        wired = wiredUp;
        connected = wifiUp || wiredUp;
        if (!en && ssid !== "")
            ssid = "";
    }

    // ---- list tier ----
    Process {
        id: listProc
        command: ["bash", "-c", "echo \"STATE:$(nmcli -t -f WIFI g 2>/dev/null)\"; echo \"PROFILES:\"; nmcli -t -f NAME,TYPE connection show 2>/dev/null; echo \"NETS:\"; nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY device wifi list --rescan no 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            id: listOut
            onStreamFinished: root.parseList(text)
        }
    }
    Timer {
        id: listTimer
        interval: 5000
        running: root.listening
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshList()
    }
    function refreshList(): void {
        if (!listProc.running)
            listProc.running = true;
    }
    function parseList(t: string): void {
        const lines = t.split("\n");
        const saved = {};
        let section = "";
        let en = enabled;
        let active = "";
        const nets = [];
        const seen = {};
        for (let i = 0; i < lines.length; ++i) {
            const ln = lines[i].replace(/\r$/, "");
            if (ln.indexOf("STATE:") === 0) {
                en = ln.slice(6).trim() === "enabled";
                continue;
            }
            if (ln === "PROFILES:") {
                section = "profiles";
                continue;
            }
            if (ln === "NETS:") {
                section = "nets";
                continue;
            }
            if (section === "profiles") {
                const p = splitEscaped(ln);
                // Stored connection profiles: a name here means nmcli can
                // activate that network without being handed a password.
                if (p.length >= 2 && p[0] !== "" && p[1] === "802-11-wireless")
                    saved[p[0]] = p[0];
                continue;
            }
            if (section === "nets") {
                const p = splitEscaped(ln);
                if (p.length < 4)
                    continue;
                const ss = p[1];
                // "--" is a hidden AP (no SSID broadcast): not addressable
                // by name, so it cannot be joined from here.
                if (!ss || ss === "--" || seen[ss])
                    continue;
                seen[ss] = true;
                const sig = parseInt(p[2]);
                nets.push({
                    "ssid": ss,
                    "signal": isNaN(sig) ? 0 : sig,
                    "security": p[3] !== "" && p[3] !== "--",
                    "active": p[0] === "yes",
                    "saved": saved[ss] !== undefined,
                    "profile": saved[ss] !== undefined ? saved[ss] : ss
                });
            }
        }
        for (let i = 0; i < nets.length; ++i) {
            if (nets[i].active) {
                active = nets[i].ssid;
                break;
            }
        }
        nets.sort((a, b) => ((b.active ? 1 : 0) - (a.active ? 1 : 0)) || (b.signal - a.signal));
        enabled = en;
        ssid = en ? active : "";
        networks = nets.slice(0, 12);
    }

    // ================= actions =================
    // Anything that changes the radio refreshes both tiers when it exits.
    function afterChange(): void {
        refreshLight();
        refreshList();
    }

    function setRadio(on: bool): void {
        if (radioProc.running)
            return;
        radioProc.arg = on ? "on" : "off";
        radioProc.running = true;
    }
    Process {
        id: radioProc
        property string arg: "on"
        command: ["nmcli", "radio", "wifi", arg]
        running: false
        onExited: {
            if (exitCode !== 0)
                root.fail("Could not turn Wi-Fi " + arg);
            afterChange();
        }
    }
    function toggleRadio(): void {
        setRadio(!enabled);
    }

    // `password` empty covers both open networks and stored profiles: nmcli
    // then activates the existing connection silently. Wrong-password APs
    // report it here, which is why the popup keeps the field on failure.
    function connect(ssid: string, password: string): void {
        if (ssid === "" || connectProc.running)
            return;
        connectProc.ssid = ssid;
        connectProc.password = password;
        connectProc.outText = "";
        connectProc.running = true;
    }
    Process {
        id: connectProc
        property string ssid: ""
        property string password: ""
        property string outText: ""
        command: password !== "" ? ["nmcli", "device", "wifi", "connect", ssid, "password", password] : ["nmcli", "device", "wifi", "connect", ssid]
        running: false
        stdout: StdioCollector {
            id: connectOut
            onStreamFinished: connectProc.outText = text
        }
        onExited: {
            if (exitCode === 0)
                root.say("\u2713 Connected to " + ssid);
            else
                root.fail("\u2717 " + root.lastLine(outText));
            afterChange();
        }
    }

    // Activate a stored profile (what "Connect" does on a known network).
    function activate(ssid: string): void {
        if (ssid === "" || upProc.running)
            return;
        upProc.ssid = ssid;
        upProc.outText = "";
        upProc.running = true;
    }
    Process {
        id: upProc
        property string ssid: ""
        property string outText: ""
        command: ["nmcli", "connection", "up", ssid]
        running: false
        stdout: StdioCollector {
            id: upOut
            onStreamFinished: upProc.outText = text
        }
        onExited: {
            if (exitCode === 0)
                root.say("\u2713 Connected to " + ssid);
            else
                root.fail("\u2717 " + root.lastLine(outText));
            afterChange();
        }
    }

    function disconnect(ssid: string): void {
        if (ssid === "" || downProc.running)
            return;
        downProc.ssid = ssid;
        downProc.outText = "";
        downProc.running = true;
    }
    Process {
        id: downProc
        property string ssid: ""
        property string outText: ""
        command: ["nmcli", "connection", "down", ssid]
        running: false
        stdout: StdioCollector {
            id: downOut
            onStreamFinished: downProc.outText = text
        }
        onExited: {
            if (exitCode === 0)
                root.say("\u2713 Disconnected " + ssid);
            else
                root.fail("\u2717 " + root.lastLine(outText));
            if (ssid === root.ssid)
                root.ssid = "";
            afterChange();
        }
    }

    // `profile` is the connection id (name), which is what `connection delete`
    // wants; it equals the SSID for every network NetworkManager saved.
    function forget(profile: string): void {
        if (profile === "" || forgetProc.running)
            return;
        forgetProc.profile = profile;
        forgetProc.outText = "";
        forgetProc.running = true;
    }
    Process {
        id: forgetProc
        property string profile: ""
        property string outText: ""
        command: ["nmcli", "connection", "delete", profile]
        running: false
        stdout: StdioCollector {
            id: forgetOut
            onStreamFinished: forgetProc.outText = text
        }
        onExited: {
            if (exitCode === 0)
                root.say("\u2713 Forgot " + profile);
            else
                root.fail("\u2717 " + root.lastLine(outText));
            if (profile === root.ssid)
                root.ssid = "";
            afterChange();
        }
    }

    // A rescan populates the list asynchronously, so the result is re-read
    // once the scan window has passed (parity with the old settings card).
    function rescan(): void {
        if (rescanProc.running)
            return;
        scanning = true;
        scanWatchdog.restart();
        rescanProc.outText = "";
        rescanProc.running = true;
    }
    Process {
        id: rescanProc
        property string outText: ""
        command: ["nmcli", "device", "wifi", "rescan"]
        running: false
        stdout: StdioCollector {
            id: rescanOut
            onStreamFinished: rescanProc.outText = text
        }
        onExited: {
            scanning = false;
            scanWatchdog.stop();
            if (exitCode === 0) {
                root.say("Scanning\u2026");
                rescanSettle.restart();
            } else {
                root.fail("\u2717 " + root.lastLine(outText));
                refreshLight();
            }
        }
    }
    Timer {
        id: rescanSettle
        interval: 2500
        repeat: false
        onTriggered: root.refreshList()
    }
    // nmcli rescan can hang on a throttled/driverless adapter; the spinning
    // header icon must not spin forever.
    Timer {
        id: scanWatchdog
        interval: 15000
        repeat: false
        onTriggered: {
            root.scanning = false;
            root.fail("Scan timed out");
            if (rescanProc.running)
                rescanProc.signal(15);
            root.refreshList();
        }
    }

    // ================= lifecycle for the popup =================
    function startListening(): void {
        listening = true;
        refreshLight();
        refreshList();
    }
    function stopListening(): void {
        listening = false;
    }
}