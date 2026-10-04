pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire

// AudioService.qml — Pipewire default-sink wrapper.
// Mirrors waybar pulseaudio + scripts/set-volume.sh conventions:
//   - volume capped at 100% (never above 1.0).
//   - step 2% up/down; bar left = mixer popup, right = mute toggle,
//     middle = pavucontrol (wiring lives in Bar/VolumePopup builders).
Singleton {
    id: root

    readonly property bool ready: Pipewire.ready
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var sinkAudio: Pipewire.defaultAudioSink?.audio ?? null

    // PwObjectTracker, NOT decoration: VolumePopup wraps the default sink in
    // one and the bar was reading a node whose audio volume stayed 0 until
    // something else tracked it (measured: 0% in the bar while the mixer card
    // showed the true 53%, and `wpctl` agreed with the card). Tracking the
    // object here is what makes the plain property reads below live.
    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    // Last volume/mute read while a sink WAS present. An idle ALSA sink with
    // no active stream drops out of quickshell's Pipewire node cache for a
    // moment, `defaultAudioSink` goes null, and the naive read below painted
    // the bar 0% while `wpctl` was reporting 79% — the value was never wrong,
    // the sink reference just blinked. Hold the last known value instead; the
    // guards (`if (sinkAudio)`) keep the two bindings from looping.
    property int lastVolume: 0
    property bool lastMuted: false

    // 0..100 integer for bar text. Falls back to lastVolume with no sink.
    readonly property int volume: sinkAudio ? Math.round(sinkAudio.volume * 100) : lastVolume
    readonly property bool muted: sinkAudio ? sinkAudio.muted : lastMuted
    onVolumeChanged: {
        if (sinkAudio)
            lastVolume = volume;
    }
    onMutedChanged: {
        if (sinkAudio)
            lastMuted = muted;
    }
    readonly property string sinkName: sink ? (sink.description || sink.name || "") : ""
    readonly property string iconState: {
        if (!sinkAudio && lastVolume === 0)
            return "muted";
        if (muted || volume === 0)
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
        setVolumePercent(volume + (step ?? 2));
    }

    function decrease(step) {
        setVolumePercent(volume - (step ?? 2));
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
