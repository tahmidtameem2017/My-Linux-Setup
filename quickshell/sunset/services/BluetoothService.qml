// BluetoothService.qml — singleton bluez state for the bar widget, the
// BluetoothPopup and the QuickSettings tile.
//
// Wraps Quickshell.Bluetooth (live bluez D-Bus bindings) so no component
// spawns bluetoothctl or polls: adapter power, device list, per-device
// connection/battery state all arrive as property notifications.
//
// The raw bluez device set is NOT exposed directly: it includes the
// discovery cache, which on a machine that has never paired is nothing but
// unpaired BLE ghosts with address-shaped names (the "gibberish list").
// `devices` keeps only paired-or-connected, sorted connected-first.
//
// Glyph map returns Nerd Font codepoints (all charset-verified in
// JetBrainsMono Nerd Font); \uXXXX escapes only, never raw PUA chars, and
// String.fromCodePoint for the one astral-plane glyph (the mouse).

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

Singleton {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool powered: available && adapter.enabled
    // The name other devices see for THIS machine (the adapter alias; kept
    // equal to the hostname via `bluetoothctl system-alias $(hostname)`).
    readonly property string adapterName: available ? adapter.name : ""

    // ================= discovery =================
    // Quickshell.Bluetooth exposes `discovering` but NO start/stop method,
    // and bluez ends a discovery session when the requesting D-Bus client
    // exits — so a one-shot `bluetoothctl scan on` is useless (it exits and
    // discovery dies with it). `bluetoothctl --timeout N scan on` stays
    // alive for N seconds holding the session, then exits and discovery
    // stops on its own; an early stop is just signal(15).
    readonly property bool discovering: available && adapter.discovering
    property bool searchActive: false
    property bool discoverableOurs: false

    // Unpaired+unconnected = what the scan is finding (the same discovery
    // cache the main list hides). Named devices sort above address-only ones.
    readonly property var nearby: {
        root.connectedCount;
        const vals = Bluetooth.devices.values;
        const out = [];
        for (let i = 0; i < vals.length; ++i) {
            const d = vals[i];
            if (d && !d.paired && !d.connected)
                out.push(d);
        }
        out.sort((a, b) => ((root.hasName(a) ? 0 : 1) - (root.hasName(b) ? 0 : 1)) || root.nearbyLabel(a).localeCompare(root.nearbyLabel(b)));
        return out;
    }

    Process {
        id: scanProc
        command: ["bluetoothctl", "--timeout", "25", "scan", "on"]
        running: false
        onExited: {
            root.searchActive = false;
            if (root.discoverableOurs) {
                root.discoverableOurs = false;
                if (root.adapter)
                    root.adapter.discoverable = false;
            }
        }
    }

    // Backstop in case --timeout's process never exits.
    Timer {
        id: searchWatchdog
        interval: 30000
        repeat: false
        onTriggered: root.stopSearch()
    }

    function startSearch(): void {
        if (!available || !powered || scanProc.running)
            return;
        searchActive = true;
        // Bidirectional visibility: the phone can find the PC back. Restored
        // when the scan process exits (ours only — if something else made the
        // adapter discoverable we leave that alone).
        if (adapter && !adapter.discoverable) {
            discoverableOurs = true;
            adapter.discoverable = true;
        }
        scanProc.running = true;
        searchWatchdog.restart();
    }
    function stopSearch(): void {
        searchWatchdog.stop();
        if (scanProc.running)
            scanProc.signal(15);
        // scanProc.onExited flips searchActive and restores discoverable.
    }

    // ================= pairing =================
    // pair() is fire-and-forget; most users expect one tap = paired AND
    // connected, so a short timer follows up with connect() once the bond
    // lands (and gives up rather than polling forever on a rejected pair).
    property var pairingDevice: null
    property int pairTries: 0

    Timer {
        id: pairTimer
        interval: 2000
        repeat: true
        onTriggered: {
            const dev = root.pairingDevice;
            if (!dev) {
                stop();
                return;
            }
            if (dev.paired) {
                if (!dev.connected)
                    dev.connect();
                root.pairingDevice = null;
                stop();
                return;
            }
            root.pairTries += 1;
            if (root.pairTries > 12) {
                root.pairingDevice = null;
                stop();
            }
        }
    }

    function pairAndConnect(dev): void {
        if (!dev || dev.paired)
            return;
        dev.trusted = true;
        pairingDevice = dev;
        pairTries = 0;
        dev.pair();
        pairTimer.restart();
    }


    readonly property int connectedCount: {
        let n = 0;
        const vals = Bluetooth.devices.values;
        for (let i = 0; i < vals.length; ++i) {
            const d = vals[i];
            if (d && d.connected)
                ++n;
        }
        return n;
    }

    // Paired + connected only, connected-first then alphabetical. Reading
    // connectedCount first makes this binding re-run (and re-sort) when any
    // device's connection state flips, not just when the set changes.
    readonly property var devices: {
        root.connectedCount;
        const vals = Bluetooth.devices.values;
        const out = [];
        for (let i = 0; i < vals.length; ++i) {
            const d = vals[i];
            if (d && (d.paired || d.connected))
                out.push(d);
        }
        out.sort((a, b) => ((b.connected ? 1 : 0) - (a.connected ? 1 : 0)) || root.displayName(a).localeCompare(root.displayName(b)));
        return out;
    }

    // `name` is the (writable) alias; fall back to the raw device name, then
    // to a placeholder when bluez only knows an address-shaped string.
    function displayName(dev): string {
        const n = ((dev.name !== "" ? dev.name : dev.deviceName) || "").trim();
        if (n === "" || /^([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}$/.test(n) || /^[0-9A-Fa-f]{12}$/.test(n))
            return "Unknown device";
        return n;
    }

    // bluez Icon property -> Nerd Font glyph.
    function glyph(icon: string): string {
        switch (icon) {
        case "audio-card":
        case "audio-headphones":
        case "audio-headset":
            return "\uf025";
        case "audio-speakers":
        case "multimedia-player":
            return "\uf028";
        case "phone":
            return "\uf10b";
        case "computer":
            return "\uf108";
        case "input-keyboard":
            return "\uf11c";
        case "input-mouse":
            return String.fromCodePoint(0xF037D);
        case "input-gaming":
            return "\uf11b";
        case "camera-photo":
        case "camera-video":
            return "\uf030";
        case "printer":
        case "scanner":
            return "\uf02f";
        case "video-display":
            return "\uf26c";
        case "modem":
        case "network-wireless":
            return "\uf1eb";
        default:
            return "\uf294";
        }
    }

    function batteryPercent(dev): int {
        return dev.batteryAvailable ? Math.round(dev.battery * 100) : -1;
    }

    function hasName(dev): bool {
        const n = ((dev.name !== "" ? dev.name : dev.deviceName) || "").trim();
        return n !== "" && !/^([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}$/.test(n) && !/^[0-9A-Fa-f]{12}$/.test(n);
    }

    // Scan rows: fall back to the raw address (useful while a device's name
    // is still unresolved) instead of the main list's "Unknown device".
    function nearbyLabel(dev): string {
        return hasName(dev) ? displayName(dev) : dev.address;
    }

    function stateLabel(dev): string {
        if (!dev)
            return "";
        if (dev.pairing)
            return "pairing\u2026";
        if (dev.state === BluetoothDeviceState.Connecting)
            return "connecting\u2026";
        if (dev.state === BluetoothDeviceState.Disconnecting)
            return "disconnecting\u2026";
        if (dev.connected)
            return "connected";
        return "paired";
    }

    function setPower(on: bool): void {
        if (available)
            adapter.enabled = on;
    }
    function togglePower(): void {
        setPower(!powered);
    }
    function toggleConnection(dev): void {
        if (!dev)
            return;
        if (dev.connected)
            dev.disconnect();
        else
            dev.connect();
    }
}
