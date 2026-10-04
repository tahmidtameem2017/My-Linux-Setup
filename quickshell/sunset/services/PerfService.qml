pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// PerfService — the readings behind the bar's performance pill
// (components/PerfWidget.qml, the malleable island). OFF by
// default: the pill is collapsed to zero width and nothing is
// sampled until the user turns it on (Mod+Alt+P, the launcher
// "Performance" row, or `qs -c sunset ipc call perf toggle`).
// While on, scripts/perf-stats.sh is sampled every 2s.
//
// One line of integer key=value pairs from the sampler:
//   cpu=<0-100> gpu=<MHz|0> gpuBusy=<0-100|-1> memUsed=<MiB>
//   memTotal=<MiB> batPct=<0-100|-1> batCharging=<0|1>
// 0 / -1 mean "no sensor" and the pill hides that segment.
//
// State is deliberately in-memory only: a restart is a fresh
// island (weather + clock) until the monitor is asked for again.

Singleton {
    id: root

    readonly property string setupHome: Quickshell.env("NIRI_SETUP_HOME") ?? (Quickshell.env("HOME") + "/niri-setup")

    // The master switch. Default off — the island is weather +
    // clock until the user needs the monitor.
    property bool enabled: false
    // First sample has landed (the pill stays collapsed until
    // then, so it never flashes empty labels).
    property bool hasSample: false

    property int cpu: 0
    property int gpuMhz: 0
    property int gpuBusy: -1
    property int memUsed: 0
    property int memTotal: 0
    property int batPct: -1
    property bool batCharging: false

    function toggle(): void {
        root.enabled = !root.enabled;
    }
    function turnOn(): void {
        root.enabled = true;
    }
    function turnOff(): void {
        root.enabled = false;
    }

    // Sample at once on enable so the pill is populated within
    // the sampler's 0.5s window, then every 2s while on.
    onEnabledChanged: {
        if (root.enabled)
            sampleProc.running = true;
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.enabled
        onTriggered: sampleProc.running = true
    }

    Process {
        id: sampleProc
        command: [root.setupHome + "/scripts/perf-stats.sh"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    function parse(raw: string): void {
        const fields = String(raw).trim().split(/\s+/);
        for (let i = 0; i < fields.length; ++i) {
            const eq = fields[i].indexOf("=");
            if (eq < 0)
                continue;
            const val = parseInt(fields[i].slice(eq + 1), 10);
            if (isNaN(val))
                continue;
            switch (fields[i].slice(0, eq)) {
                case "cpu": root.cpu = val; break;
                case "gpu": root.gpuMhz = val; break;
                case "gpuBusy": root.gpuBusy = val; break;
                case "memUsed": root.memUsed = val; break;
                case "memTotal": root.memTotal = val; break;
                case "batPct": root.batPct = val; break;
                case "batCharging": root.batCharging = val === 1; break;
            }
        }
        root.hasSample = true;
    }
}
