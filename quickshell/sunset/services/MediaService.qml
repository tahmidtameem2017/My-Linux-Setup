pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// MediaService.qml — Mpris active-player picker.
// Waybar parity: waybar/scripts/media-icon.sh + media-menu.sh behaved as
//   scroll-up = playerctl next, scroll-down = playerctl previous,
//   click = media menu. Bar builder wires those to toggle()/next()/previous().
//
// Single source of truth for "what is playing": the bar widget (MediaWidget)
// and the NowPlayingPopup both read THIS, so the icon can never disagree with
// the popup about which player is active.
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

    // True only when the player holds an actual track (Playing or Paused).
    // A player that is merely connected with an empty queue reports Stopped
    // and should not surface a NowPlayingPopup with no media in it.
    readonly property bool hasTrack: hasPlayer && (activePlayer.playbackState === MprisPlaybackState.Playing || activePlayer.playbackState === MprisPlaybackState.Paused)

    // ---- now-playing surface (album / art / seek) ----
    readonly property string album: activePlayer ? (activePlayer.trackAlbum || "") : ""
    readonly property string artUrl: activePlayer ? (activePlayer.trackArtUrl || "") : ""
    // xesam:url, when the player publishes one. READ IT AND NEVER TRUST IT:
    // Chromium publishes no URL at all (the reason downloads used to be a
    // YouTube search), mpv points it at the LOCAL FILE (file:///…), and
    // Spotify at a `spotify:track:` URI. So callers must test the scheme, not
    // just emptiness — see trackWebUrl below, which is the form to use.
    readonly property string trackUrl: {
        if (!activePlayer)
            return "";
        const meta = activePlayer.metadata;
        if (!meta)
            return "";
        return meta["xesam:url"] ?? "";
    }
    // The same value narrowed to something a downloader could actually fetch.
    readonly property string trackWebUrl: root.trackUrl.indexOf("http://") === 0 || root.trackUrl.indexOf("https://") === 0 ? root.trackUrl : ""
    readonly property bool canSeek: hasPlayer && activePlayer.canSeek && activePlayer.positionSupported && activePlayer.length > 0
    readonly property real length: activePlayer ? activePlayer.length : 0

    // MprisPlayer.position does NOT tick on its own (the MPRIS spec only
    // pushes it on seeks). This timer samples it while the track is actually
    // playing, so a progress bar advances smoothly. Idle costs nothing.
    property real position: 0

    Timer {
        id: posTimer
        interval: 500
        repeat: true
        running: root.hasTrack && root.isPlaying
        onTriggered: root.position = root.activePlayer ? root.activePlayer.position : 0
    }

    // Fraction 0..1 of the current track.
    readonly property real progress: length > 0 ? Math.max(0, Math.min(1, position / length)) : 0

    function seek(fraction: real): void {
        if (!canSeek)
            return;
        const target = Math.max(0, Math.min(1, fraction)) * length;
        // Relative seek avoids writing `position` on players that expose it
        // read-only, which is common (canSeek true, positionSupported false).
        const delta = target - (activePlayer.position || 0);
        if (Math.abs(delta) < 0.5)
            return;
        activePlayer.seek(delta);
        position = target;
    }

    // ---- multiple sources / source switching ----
    // Every MPRIS player that currently holds a track (Playing or Paused),
    // plus the active one, in bus order. Elements are the LIVE MprisPlayer
    // objects, so UI rows binding `modelData.identity` etc. update on their
    // own — no polling, and no need for the UI to import the Mpris module.
    readonly property var sources: {
        const out = [];
        const all = Mpris.players.values;
        for (let i = 0; i < all.length; ++i) {
            const p = all[i];
            if (!p)
                continue;
            if (p === root.activePlayer || p.playbackState === MprisPlaybackState.Playing || p.playbackState === MprisPlaybackState.Paused)
                out.push(p);
        }
        return out;
    }
    readonly property bool multipleSources: sources.length > 1

    // Manual pick, keyed by bus name (stable across re-registration, unlike a
    // list index). Empty string = auto (the old pickPlayer behaviour).
    property string pinnedDbusName: ""

    // Plain strings so UI files need no Mpris import; reactive because the
    // property reads happen inside the binding that calls this.
    function stateLabel(p): string {
        if (!p)
            return "";
        if (p.playbackState === MprisPlaybackState.Playing)
            return "playing";
        if (p.playbackState === MprisPlaybackState.Paused)
            return "paused";
        return "stopped";
    }

    function sourceName(p): string {
        if (!p)
            return "";
        return p.identity !== "" ? p.identity : (p.dbusName || "");
    }

    function selectSource(p): void {
        if (!p)
            return;
        pinnedDbusName = p.dbusName;
        if (activePlayer !== p) {
            activePlayer = p;
            // Seeded, not left at the old player's clock (same reason as in
            // pickPlayer: a paused player gets no timer ticks).
            position = p.position || 0;
        }
    }

    function cycleSource(): void {
        const n = sources.length;
        if (n < 2)
            return;
        let i = -1;
        for (let k = 0; k < n; ++k) {
            if (sources[k].dbusName === pinnedDbusName) {
                i = k;
                break;
            }
        }
        selectSource(sources[(i + 1) % n]);
    }

    // Back to "whatever is playing" (what the pin replaced).
    function releaseSource(): void {
        pinnedDbusName = "";
        pickPlayer();
    }

    function pickPlayer() {
        const players = Mpris.players.values;
        // A manual pick wins over auto as long as that player is still on the
        // bus; a vanished pick silently returns to auto.
        if (pinnedDbusName !== "") {
            for (let i = 0; i < players.length; ++i) {
                if (players[i].dbusName === pinnedDbusName) {
                    activePlayer = players[i];
                    position = players[i].position || 0;
                    return;
                }
            }
            pinnedDbusName = "";
        }
        if (players.length === 0) {
            activePlayer = null;
            position = 0;
            return;
        }
        let picked = null;
        // 1) currently playing.
        for (let i = 0; i < players.length; ++i) {
            if (players[i].isPlaying) {
                picked = players[i];
                break;
            }
        }
        // 2) paused with a track (most recently paused wins — last item).
        if (!picked) {
            for (let j = players.length - 1; j >= 0; --j) {
                if (players[j].playbackState === MprisPlaybackState.Paused) {
                    picked = players[j];
                    break;
                }
            }
        }
        // 3) fallback: first available.
        if (!picked)
            picked = players[0];
        activePlayer = picked;
        // Track change resets the clock; re-seeding avoids a stale bar until
        // the first timer tick (and is the only value a paused track gets).
        position = picked.position || 0;
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

    // ---- repeat / shuffle ----
    //
    // MPRIS LoopStatus is a 3-state string enum (None | Track | Playlist) and
    // quickshell exposes it as the numeric `MprisLoopState` enum, so the UI
    // never sees or has to spell the strings.
    //
    // `loopSupported` / `shuffleSupported` are NOT decoration — they are the
    // difference between a control that works and one that silently does
    // nothing, and the difference is not guessable from the metaobject. Brave's
    // MPRIS implementation does not export LoopStatus or Shuffle AT ALL (a raw
    // Properties.Get on the bus fails outright for both), while mpv exports
    // both and honours them. So the card hides the controls per player instead
    // of rendering buttons that quietly discard clicks.
    readonly property bool canLoop: hasPlayer && activePlayer.loopSupported
    readonly property bool canShuffle: hasPlayer && activePlayer.shuffleSupported
    readonly property bool loopTrack: hasPlayer && activePlayer.loopState === MprisLoopState.Track
    readonly property bool loopPlaylist: hasPlayer && activePlayer.loopState === MprisLoopState.Playlist
    readonly property bool shuffleOn: hasPlayer && activePlayer.shuffle

    // Cycles None -> Track -> Playlist -> None, the order every player uses
    // (Spotify, mpv and the MPRIS spec agree), so the button reads the same
    // everywhere. Written through the setter, so the round-trip is the
    // player's own: we never cache a mode we did not confirm.
    function cycleLoop(): void {
        if (!canLoop)
            return;
        const order = [MprisLoopState.None, MprisLoopState.Track, MprisLoopState.Playlist];
        const next = order[(order.indexOf(activePlayer.loopState) + 1) % order.length];
        activePlayer.loopState = next;
    }

    function toggleShuffle(): void {
        if (!canShuffle)
            return;
        // Read the live value, not a remembered one: the mode can also change
        // in the player itself, and a stale mirror would flip the wrong way.
        activePlayer.shuffle = !activePlayer.shuffle;
    }

    // ---- pinning the source ----
    //
    // A pin is a promise the card makes about WHERE playback lives: while set,
    // auto-pick never steals the card for another player. `releaseSource()`
    // existed from the start but nothing could reach it, so the pin was
    // permanent the moment anyone used the source switcher — that is what made
    // the switcher feel like it latched. This is the unpin path.
    readonly property bool sourcePinned: pinnedDbusName !== ""

    // Pin the player the card is showing right now. Clicking the pin while
    // already pinned unpins, so one button is the whole feature. Pinning is
    // only meaningful when there IS a choice to make: with a single source
    // there is nothing for auto-pick to steal the card from, so the control
    // stays hidden rather than advertising a protection that cannot be tested.
    function togglePin(): void {
        if (!hasPlayer)
            return;
        if (sourcePinned) {
            releaseSource();
            return;
        }
        pinnedDbusName = activePlayer.dbusName;
    }

    Connections {
        target: Mpris.players
        function onValuesChanged() {
            root.pickPlayer();
        }
    }

    // Re-pick when the active player's state changes: without this, stopping
    // one player never promotes the next one (only the player LIST changing
    // triggered pickPlayer before), so the popup could latch onto a dead
    // player while another was playing.
    //
    // A pin survives this — that is the whole point of picking a source — but
    // NOT the picked player losing its track: once the queue ends there is
    // nothing to show, so the pin is released and auto-pick resumes.
    Connections {
        target: root.activePlayer
        function onPlaybackStateChanged() {
            if (root.pinnedDbusName !== "" && !root.hasTrack)
                root.pinnedDbusName = "";
            if (root.pinnedDbusName === "")
                root.pickPlayer();
        }
        function onTrackChanged() {
            root.position = root.activePlayer ? root.activePlayer.position : 0;
        }
    }

    Component.onCompleted: pickPlayer()
}
