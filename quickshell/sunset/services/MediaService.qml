pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// MediaService.qml — Mpris active-player picker.
// Waybar parity: waybar/scripts/media-icon.sh + media-menu.sh behaved as
//   scroll-up = playerctl next, scroll-down = playerctl previous,
//   click = media menu. Bar builder wires those to toggle()/next()/previous().
Singleton {
    id: root

    // Preferred player: playing > paused > first. Null when none.
    property var activePlayer: null
    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool isPlaying: activePlayer ? activePlayer.isPlaying : false
    readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
    readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
    readonly property string identity: activePlayer ? (activePlayer.identity || "") : ""
    readonly property string label: {
        if (!activePlayer)
            return "";
        if (title !== "" && artist !== "")
            return artist + " — " + title;
        return title !== "" ? title : identity;
    }

    function pickPlayer() {
        const players = Mpris.players.values;
        if (players.length === 0) {
            activePlayer = null;
            return;
        }
        // 1) currently playing.
        for (let i = 0; i < players.length; ++i) {
            if (players[i].isPlaying) {
                activePlayer = players[i];
                return;
            }
        }
        // 2) paused with a track (most recently paused wins — last item).
        for (let j = players.length - 1; j >= 0; --j) {
            if (players[j].playbackState === MprisPlaybackState.Paused) {
                activePlayer = players[j];
                return;
            }
        }
        // 3) fallback: first available.
        activePlayer = players[0];
    }

    function toggle() {
        if (activePlayer && activePlayer.canTogglePlaying)
            activePlayer.togglePlaying();
    }

    function next() {
        if (activePlayer && activePlayer.canGoNext)
            activePlayer.next();
    }

    function previous() {
        if (activePlayer && activePlayer.canGoPrevious)
            activePlayer.previous();
    }

    Connections {
        target: Mpris.players
        function onValuesChanged() {
            root.pickPlayer();
        }
        function onCountChanged() {
            root.pickPlayer();
        }
    }

    Component.onCompleted: pickPlayer()
}
