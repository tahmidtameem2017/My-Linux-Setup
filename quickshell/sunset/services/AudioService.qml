pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire

// AudioService.qml — Pipewire default-sink wrapper.
// Mirrors waybar pulseaudio + scripts/set-volume.sh conventions:
//   - volume capped at 100% (never above 1.0).
//   - step 5% up/down; bar left = mixer popup, right = mute toggle,
//     middle = pavucontrol (wiring lives in Bar/VolumePopup builders).
Singleton {
    id: root

    readonly property bool ready: Pipewire.ready
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var sinkAudio: Pipewire.defaultAudioSink?.audio ?? null

    // 0..100 integer for bar text. 0 when no sink yet.
    readonly property int volume: {
        if (!sinkAudio)
            return 0;
        return Math.round(sinkAudio.volume * 100);
    }
    readonly property bool muted: sinkAudio ? sinkAudio.muted : false
    readonly property string sinkName: sink ? (sink.description || sink.name || "") : ""
    readonly property string iconState: {
        if (!sink || muted || volume === 0)
            return "muted";
        return "on";
    }

    function _clamp01(v) {
        return Math.max(0, Math.min(1, v));
    }

    // Set 0..100, hard-capped at 100 (matches set-volume.sh cap).
    function setVolumePercent(pct) {
        if (!sinkAudio)
            return;
        const p = Math.max(0, Math.min(100, Math.round(pct)));
        sinkAudio.volume = _clamp01(p / 100);
    }

    function increase(step) {
        setVolumePercent(volume + (step ?? 5));
    }

    function decrease(step) {
        setVolumePercent(volume - (step ?? 5));
    }

    function toggleMute() {
        if (!sinkAudio)
            return;
        sinkAudio.muted = !sinkAudio.muted;
    }

    function openMixer() {
        Quickshell.execDetached(["pavucontrol"]);
    }
}
