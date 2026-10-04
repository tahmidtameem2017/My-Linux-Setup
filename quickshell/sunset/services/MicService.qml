pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// MicService.qml — is anything actually recording from the microphone?
//
// Two facts, deliberately kept separate:
//   capturing — another process holds a capture stream on the mic. This is the
//               privacy-relevant one and the reason this service exists, and it
//               is the thing that must never be silently wrong.
//   muted     — the source is muted (deliberate, or hardware).
//
// WHY THE TYPE FIELD NEEDS BIT MATH, NOT THE ENUM
// ------------------------------------------------
// PwNodeType's QML enum is a flat 0..12 list, but the property is a BITMASK.
// Decoded from the four nodes this machine actually has:
//   alsa_input (Audio/Source)       =  9 = Audio(1)          | Source(8)
//   pw-record / quickshell (capture)= 13 = Audio(1)|Stream(4)| Source(8)
//   alsa_output (Audio/Sink)        = 17 = Audio(1)          | Sink(16)
//   mpv (playback stream)           = 21 = Audio(1)|Stream(4) | Sink(16)
// The enum names line up 1:1 with the bits (Audio=1, Stream=4, Source=8,
// Sink=16), so testing PwNodeType.AudioInStream would compare 13 against the
// index 10 and silently never match. Bits only, forever.
//
// THREE TRAPS, ALL MEASURED ON THIS MACHINE
// -----------------------------------------
// 1. WE POLLUTE OUR OWN DETECTION. Anything that opens the mic registers as a
//    capture client, so an indicator that counted every capture stream would
//    light up from its own instrumentation. Node identity is therefore used to
//    exclude ourselves (see selfNames).
//
// 2. `node.properties` IS EMPTY ON STREAM NODES. The Audio/Source node carries
//    54 keys, an ffmpeg capture stream carries 0 — so
//    `properties["application.name"]` / `["media.class"]` are NOT available for
//    identifying the client. Client identity comes from `node.name`.
//
// 3. THE NODE ADD/REMOVE SIGNALS DO NOT EXIST (quickshell 0.3.1).
//    `Pipewire.nodeAdded`/`nodeRemoved` are listed among the *methods* in
//    qmltypes, not the signals, so `Connections { target: Pipewire }` logs
//        WARN scene: ... no signal of the target matches the name
//    on every config load and the handler never runs. Meanwhile
//    `Pipewire.nodes.values` IS live and correct — measured growing 8 -> 9 -> 8
//    as an ffmpeg capture opened and closed. A service that refreshes only on
//    `onNodeAdded` sees the graph once at startup and then never again, which
//    looks exactly like "detection does not work". Hence the reconcile timer,
//    and the on-change-only assignment: a privacy indicator that silently never
//    updates is worse than no indicator.
//
// NO INPUT LEVEL METER, AND THAT IS NOT AN OMISSION
// -------------------------------------------------
// PwNodePeakMonitor would be the obvious way to draw a level bar, and it does
// not work here. Its `channels` property is READ-ONLY (QML: "Invalid property
// assignment: channels is a read-only property") and defaults to channels 3 and
// 4 — which do not exist on a mono source. Measured: `pmChannels=3,4`,
// `pmPeaks=0,0`, `peak=0` at all times, including while ffmpeg was actively
// recording from that exact device. There is no channel layout this mono mic
// has that the monitor can be pointed at, so a live level readout is simply not
// available from quickshell's Pipewire API on this machine.
//
// Re-check with the debug line in `sampleCapture()` below before adding a meter
// again. Where a level reading IS genuinely useful — showing that dictation is
// hearing you — the right place is the dictation pipeline itself, which already
// holds the raw PCM, not the bar.
Singleton {
    id: root

    // PwNodeType bits (see header). Named so tests can assert the numbers.
    readonly property int flagAudio: 1
    readonly property int flagStream: 4
    readonly property int flagSource: 8
    readonly property int captureBits: root.flagStream | root.flagSource // 12

    readonly property bool ready: Pipewire.ready
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool hasSource: root.source !== null && root.source !== undefined
    readonly property bool muted: root.hasSource && root.source.audio ? root.source.audio.muted : false
    readonly property string sourceName: root.hasSource ? (root.source.description || root.source.name || "") : ""

    // Node names that are us (instrumentation) rather than a third party.
    property var selfNames: ["quickshell", "quickshell-out"]

    // Capture clients other than ourselves, as display names.
    property var clients: []
    readonly property bool capturing: root.clients.length > 0
    readonly property string capturingLabel: root.capturing ? root.clients.join(", ") : ""

    // Debug hook for the level question above; see sampleCapture().
    property bool debug: Quickshell.env("SUNSET_MIC_DEBUG") === "1"

    // Rebuild the capture-client list. Reads Pipewire.nodes.values, which is
    // live. Never called from a binding: a binding would re-run on every
    // `properties` change of every node, which is a lot for nothing.
    function refreshClients(): void {
        const names = [];
        if (Pipewire.ready) {
            const vals = Pipewire.nodes.values;
            for (let i = 0; i < vals.length; ++i) {
                const n = vals[i];
                if (!n)
                    continue;
                if ((n.type & root.captureBits) !== root.captureBits)
                    continue; // not a capture stream (playback, device, driver)
                const nm = n.name || "";
                if (root.selfNames.indexOf(nm) !== -1)
                    continue; // our own instrumentation — see header trap 1
                names.push(root.friendlyName(nm));
            }
        }
        // Assign ONLY on a real change. Reassigning every tick would churn the
        // `clients` binding (a fresh array is never === the old one) and wake
        // the widget's dot bindings once a second for no reason.
        const key = names.join(",");
        if (key === root._lastKey)
            return;
        root._lastKey = key;
        root.clients = names;
    }
    property string _lastKey: ","

    // PipeWire node names are whatever the client chose, and some are useless
    // to a human: ffmpeg records itself as "Lavf63.1.101" (its libavcodec
    // version), which is not what anyone wants to read next to a lit dot. Map
    // the common ones; anything unrecognised passes through untouched, so the
    // raw name is still available rather than swallowed.
    function friendlyName(nm: string): string {
        if (!nm)
            return "unknown";
        if (nm.indexOf("Lavf") === 0)
            return "ffmpeg";
        return nm;
    }

    // There are deliberately NO Connections{target: Pipewire} handlers here;
    // see header trap 3 for why they would be dead weight.

    Component.onCompleted: {
        root.refreshClients();
    }

    // The reconciliation that actually makes this work. 1s feels instant for a
    // privacy indicator and costs one pass over ~9 nodes.
    Timer {
        running: true
        interval: 1000
        repeat: true
        onTriggered: root.refreshClients()
    }

    // Kept as the place to re-test a level reading if quickshell ever makes
    // PwNodePeakMonitor.channels writable. Disabled: it cannot work as written.
    property bool levelProbe: false
    Timer {
        id: sample
        interval: 500
        repeat: true
        running: root.debug && root.levelProbe
        onTriggered: root.sampleCapture()
    }
    PwNodePeakMonitor {
        id: peak
        node: root.hasSource ? root.source : null
        enabled: root.debug && root.levelProbe && root.hasSource
    }
    function sampleCapture(): void {
        console.info("[MICDBG] ready=" + root.ready + " hasSource=" + root.hasSource +
                     " muted=" + root.muted + " pmChannels=" + peak.channels +
                     " pmPeaks=" + peak.peaks + " peak=" + peak.peak +
                     " pmNode=" + (peak.node ? peak.node.name : "null") +
                     " clients=" + JSON.stringify(root.clients));
    }

    function toggleMute(): void {
        if (root.hasSource && root.source.audio)
            root.source.audio.muted = !root.source.audio.muted;
    }
}