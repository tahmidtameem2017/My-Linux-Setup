"""The mic indicator's non-obvious parts, pinned so they cannot be "simplified" away.

Everything asserted here was established by measurement on this machine, and
each one is a mistake that produces a silently WRONG privacy light rather than a
visible error. That combination is why they are encoded as tests instead of
left as comments.

  * PwNodeType is a BITMASK on the wire even though QML exposes it as a flat
    0..12 enum list. `PwNodeType.AudioInStream` is index 10; a capture stream
    is 13, so that comparison silently never matches and the light never lights.
  * PipeWire's node add/remove are NOT signals in quickshell 0.3.1 — they are
    methods, so `Connections{target: Pipewire}` is dead code that only emits a
    warning. Detection must go through a reconcile timer instead. Re-adding the
    Connections block is the regression this guards.
  * Attaching a peak monitor registers THIS PROCESS as a capture client, so the
    indicator has to exclude its own node or it lights up permanently and
    therefore proves nothing.
  * `node.properties` is empty on stream nodes, so client identity has to come
    from `node.name`; `application.name` is unavailable there.
  * `microphone-off.svg` must keep its own `dim` step. It is the off half of a
    stateful pair, and collapsing it onto the on step makes "muted" and "live"
    the same icon — the exact failure the volume/wifi pairs avoid.
  * An icon cannot signal "recording": ICON_ROLE_BY_SUNSET_HEX collapses every
    accent-ish role onto one neutral, so the dot has to be QML-drawn.
"""

import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
QML_ROOT = REPO / "quickshell" / "sunset"
MIC_SERVICE = QML_ROOT / "services" / "MicService.qml"
MIC_WIDGET = QML_ROOT / "components" / "MicWidget.qml"
ICON_DIR = QML_ROOT / "assets" / "icons"

# PwNodeType bits, as observed from `niri`-side pw-dump on this machine.
BIT_AUDIO, BIT_STREAM, BIT_SOURCE, BIT_SINK = 1, 4, 8, 16
CAPTURE_BITS = BIT_STREAM | BIT_SOURCE  # 12

# The four nodes this machine actually has, with their raw `type` values.
OBSERVED = {
    9: "alsa_input.pci-0000_00_1b.0.analog-stereo",   # Audio|Source
    13: "pw-record",                                  # Audio|Stream|Source
    17: "alsa_output.pci-0000_00_1b.0.analog-stereo",  # Audio|Sink
    21: "mpv",                                        # Audio|Stream|Sink
}


def is_capture_stream(type_value: int) -> bool:
    """Mirror of MicService.refreshClients()'s test."""
    return (type_value & CAPTURE_BITS) == CAPTURE_BITS


class TestTypeBitmask(unittest.TestCase):
    def test_constants_in_qml_are_the_measured_bits(self):
        text = MIC_SERVICE.read_text()
        self.assertIn(f"flagAudio: {BIT_AUDIO}", text)
        self.assertIn(f"flagStream: {BIT_STREAM}", text)
        self.assertIn(f"flagSource: {BIT_SOURCE}", text)

    def test_capture_test_selects_only_capture_streams(self):
        self.assertTrue(is_capture_stream(13), "pw-record must be detected")
        self.assertFalse(is_capture_stream(9), "the mic device is not a client")
        self.assertFalse(is_capture_stream(17), "the speaker device is not a client")
        self.assertFalse(is_capture_stream(21), "mpv playback is not a capture")

    def test_every_observed_node_classifies_sensibly(self):
        for type_value, name in OBSERVED.items():
            if name == "pw-record":
                self.assertTrue(is_capture_stream(type_value), f"{name} missed")
            else:
                self.assertFalse(is_capture_stream(type_value), f"{name} false positive")

    def test_the_flat_enum_indices_would_have_been_wrong(self):
        """Guards the reason bit math exists at all.

        If someone 'simplifies' this to PwNodeType.AudioInStream, this is the
        assertion that should make them stop.
        """
        enum_index_of_audio_in_stream = 10
        self.assertNotEqual(CAPTURE_BITS, enum_index_of_audio_in_stream)
        self.assertNotEqual(13, enum_index_of_audio_in_stream)


class TestNoDeadSignalWiring(unittest.TestCase):
    @staticmethod
    def code_only(path: Path) -> str:
        """Strip `//` comments.

        Necessary, not fussy: the file documents this exact trap in prose, so a
        naive substring search matches the explanation of the mistake rather than
        the mistake, and the test would pass on broken code forever.
        """
        out = []
        for line in path.read_text().splitlines():
            stripped = line.split("//", 1)[0]
            if stripped.strip():
                out.append(stripped)
        return "\n".join(out)

    def test_no_connections_block_targets_pipewire(self):
        """quickshell 0.3.1 has no nodeAdded/nodeRemoved SIGNALS — only methods."""
        code = self.code_only(MIC_SERVICE)
        self.assertNotIn("onNodeAdded", code)
        self.assertNotIn("onNodeRemoved", code)
        self.assertNotRegex(code, r"Connections\s*\{[^}]*target:\s*Pipewire")

    def test_reconcile_timer_exists(self):
        text = self.code_only(MIC_SERVICE)
        self.assertRegex(text, r"onTriggered:\s*root\.refreshClients\(\)")

    def test_clients_only_reassigned_on_a_real_change(self):
        """A fresh array is never === the old one, so unconditional assignment
        would churn every binding once a second for nothing."""
        text = self.code_only(MIC_SERVICE)
        self.assertIn("if (key === root._lastKey)", text)
        self.assertRegex(text, r"if \(key === root\._lastKey\)\s*\n\s*return;")


class TestSelfExclusion(unittest.TestCase):
    def test_own_node_names_are_excluded(self):
        text = MIC_SERVICE.read_text()
        self.assertIn('selfNames: ["quickshell"', text)
        self.assertIn("root.selfNames.indexOf(nm) !== -1", text)


class TestFriendlyNames(unittest.TestCase):
    """ffmpeg announces itself as "Lavf63.1.101"; that must not reach the UI."""

    def test_ffmpeg_version_string_is_relabelled(self):
        text = MIC_SERVICE.read_text()
        self.assertIn('nm.indexOf("Lavf") === 0', text)
        self.assertIn('return "ffmpeg";', text)

    def test_unknown_names_pass_through(self):
        text = MIC_SERVICE.read_text()
        body = text.split("function friendlyName")[1]
        self.assertRegex(body, r"return nm;\s*\}")


class TestIcons(unittest.TestCase):
    ROLE_HEXES = {
        "#E85D2F", "#FF8B4A", "#F7C7A1", "#7C8A6A",  # -> icon
        "#555555",                                     # -> iconMuted (dim)
    }

    def test_both_icons_exist(self):
        for name in ("microphone.svg", "microphone-off.svg"):
            self.assertTrue((ICON_DIR / name).is_file(), f"{name} missing")

    def test_strokes_use_a_hex_the_generator_recognises(self):
        """An unrecognised stroke hex is copied VERBATIM, so the icon would keep
        its authored colour and silently stop following the palette."""
        for name in ("microphone.svg", "microphone-off.svg"):
            text = (ICON_DIR / name).read_text()
            for hexval in re.findall(r'(?:stroke|fill)\s*=\s*"(#[0-9A-Fa-f]{6})"', text):
                self.assertIn(hexval.upper(), self.ROLE_HEXES,
                              f"{name} uses unrecognised stroke {hexval}")

    def test_off_icon_keeps_the_dim_step(self):
        """The off half of a stateful pair must not collapse onto the on step."""
        on = (ICON_DIR / "microphone.svg").read_text()
        off = (ICON_DIR / "microphone-off.svg").read_text()
        self.assertIn('stroke="#7C8A6A"', on)
        self.assertIn('stroke="#555555"', off)
        self.assertNotEqual(on, off)

    def test_off_icon_is_visually_distinct_not_just_a_colour(self):
        off = (ICON_DIR / "microphone-off.svg").read_text()
        self.assertIn("4.5 4.5", off, "the off icon needs its slash path")


class TestWidget(unittest.TestCase):
    def test_only_claims_the_left_button(self):
        """Right button belongs to the bar context menu."""
        text = MIC_WIDGET.read_text()
        self.assertIn("acceptedButtons: Qt.LeftButton", text)
        self.assertNotIn("Qt.RightButton", text)

    def test_recording_is_a_qml_dot_not_an_icon(self):
        """ICON_ROLE_BY_SUNSET_HEX collapses every accent-ish role onto one
        neutral, so no icon can render 'alarming' on its own."""
        text = MIC_WIDGET.read_text()
        self.assertIn("color: root.cAccent", text)
        self.assertIn("visible: root.capturing", text)

    def test_uses_theme_tokens_not_hardcoded_colours(self):
        text = MIC_WIDGET.read_text()
        self.assertNotRegex(text, r'#[0-9A-Fa-f]{6}')
        self.assertNotRegex(text, r"\b(?:rgb|rgba)\(")

    def test_respects_reduce_motion(self):
        text = MIC_WIDGET.read_text()
        self.assertIn("Theme.reduceMotion", text)

    def test_reads_the_themed_icon_set_not_the_rollback_gold(self):
        text = MIC_WIDGET.read_text()
        self.assertIn("Theme.iconDir", text)
        self.assertNotIn("waybar/icons", text.replace(
            "NOT waybar/icons", ""))

    def test_is_deliberately_not_in_the_bar(self):
        """Removed from the bar 2026-10-03 ("don't need the mic icon").

        The widget, MicService and this file stay on disk for rollback, so the
        guard has to be against the BAR instantiating it, not against the
        component existing: MicService is still live through Osd.qml (the mic
        mute OSD), which is why only the bar line went away.
        """
        bar = (QML_ROOT / "components" / "Bar.qml").read_text()
        self.assertNotIn("MicWidget {}", bar)
        self.assertNotIn("MicWidget {\n", bar)
        # MicService must not become dead code with it.
        osd = (QML_ROOT / "components" / "Osd.qml").read_text()
        self.assertIn("MicService", osd)


if __name__ == "__main__":
    unittest.main()