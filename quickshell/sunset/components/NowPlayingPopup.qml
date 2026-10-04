// NowPlayingPopup.qml — MPRIS now-playing card, pinned top-right under the bar.
//
// The only popup that is NOT centered: it docks to the top-right so it never
// covers the workspace. Reads Toasts.occupiedHeight via `toastOffset` (wired
// in shell.qml) so it slides below the toast stack instead of covering a toast.
//
// Shell contract (landed sunset pattern, cf. VolumePopup/CalendarPopup):
//   - exclusiveKeyboardFocus == WlrLayershell.keyboardFocus Exclusive.
//   - Esc closes; outside-click closes; Bar/MediaWidget re-click toggles via IPC.
//   - Card width 360; height is content-driven.
// Timeline: Material 3 Expressive layered wave (see the Progress column and
// taste.md -> "Now-playing timeline").
// IPC: `qs -c sunset ipc call now-playing toggle` (also: open, close)

import QtQuick
import QtQuick.Controls
// Row/Flow live in Layouts. The rest of this file uses Column/Row from
// QtQuick's built-in positions, which is why the import was never needed
// until the source switcher.
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    readonly property color cAccent: Theme.accent
    readonly property color cAccentHover: Theme.accentHover
    readonly property color cBg: Theme.bg
    readonly property color cBorder: Theme.border
    readonly property color cBorderStrong: Theme.borderStrong
    readonly property color cDanger: Theme.danger
    readonly property color cDim: Theme.dim
    readonly property string cFont: Theme.fontFamily
    readonly property color cMuted: Theme.muted
    readonly property color cPanel: Theme.panel
    readonly property int cRadius: Theme.radius
    readonly property color cRow: Theme.row
    readonly property color cText: Theme.text

    property bool isOpen: false
    // Offset from the toast stack (shell.qml wires `toasts.occupiedHeight`).
    // Added to the top margin so the card sits below toasts.
    // Offset from the toast stack (shell.qml wires `toasts.occupiedHeight`).
    property real toastOffset: 0
    // Bar height, from Bar.qml (shell.qml wires `bar.implicitHeight`). The
    // card is anchored to the SCREEN top, so without this it slides under the
    // bar and loses its own header whenever no toast is up.
    property int topInset: 0

    // Motion kill-switch for the timeline: 1 = expressive, 0 = flat bar.
    readonly property real motion: Theme.reduceMotion ? 0 : 1
// Wave swell: crest/trough depth tracks the sink level, so the bar
    // breathes with the music instead of just looping. The floor is high on
    // purpose (0.7, was 0.4): at a low volume the old scale shrank the
    // amplitude to ~1px, and a 10px-thick stroke wobbling that little reads
    // as a jagged rope rather than a wave. 0.7 muted -> 1.45 at 100%.
    readonly property real swell: 0.7 + 0.75 * ((AudioService.muted ? 0 : AudioService.volume) / 100)
    // Play/pause gate on the wave, eased BOTH ways (420ms InOutSine): the
    // sine keeps travelling while it settles to a flatline on pause and
    // swells back up on play. NOT readonly — a Behavior can't animate a
    // read-only property.
    property real waveLevel: root.playing ? 1 : 0
    Behavior on waveLevel {
        NumberAnimation {
            duration: 420
            easing.type: Easing.InOutSine
        }
    }
    // ONE shared phase for every wave layer (see the Progress column).
    // 60fps on purpose: the sine is the whole point of the timeline, and a
    // cheaper 30fps drive was visibly choppy. `waveLevel` (not `playing`) as
    // the gate: the phase must outlive the pause by the length of the
    // ease-out, or the wave freezes mid-ripple.
    property real flow: 0
    NumberAnimation on flow {
        from: 0
        to: 1
        duration: 3400
        loops: Animation.Infinite
        running: win.visible && root.motion > 0 && root.waveLevel > 0.01
    }

    readonly property bool hasTrack: MediaService.hasTrack
    readonly property string trackTitle: MediaService.title !== "" ? MediaService.title : (MediaService.identity !== "" ? MediaService.identity : "Nothing playing")
    readonly property string trackArtist: MediaService.artist
    readonly property string trackAlbum: MediaService.album
    readonly property string trackArt: MediaService.artUrl
    readonly property bool playing: MediaService.isPlaying

    // Download-to-Music button. Chromium MPRIS exposes no URL, so the
    // script searches YouTube for "<artist> <title>" and grabs the top hit.
    // dlState: 0 idle, 1 busy, 2 done, 3 error (2/3 flash, then reset).
    // While busy, dlPhase is "fetching" | "downloading" | "processing" and
    // dlPercent carries the download fraction (0-100), both streamed from
    // the script's machine-readable stdout lines. "timedout" is not streamed:
    // it is the fetch watchdog's verdict (below), not a script phase.
    readonly property string setupHome: Quickshell.env("NIRI_SETUP_HOME") ?? (Quickshell.env("HOME") + "/niri-setup")
    property int dlState: 0
    property string dlPhase: "fetching"
    // Why the last run failed, streamed as `STATUS failed <why>` by
    // download-track.sh (yt-dlp's own error line). Without it the card only
    // ever showed a ✕ for 2.5s, which is indistinguishable between "Sign in to
    // confirm you're not a bot", "Video unavailable" and a DNS stall — all of
    // which need a different fix.
    property string dlError: ""
    property real dlPercent: 0
    // Set by the watchdog so onExited can tell our own SIGTERM apart from a
    // real result: QProcess reports a signalled process as CrashExit with a
    // 0 exit code, which would otherwise flash "✓ done" and re-read the
    // library for a file that was never finished.
    property bool dlAborted: false
    // True when the run in flight was a LINK, not the "<artist> <title>"
    // search — the status line has to say which, because "Fetching…" for a
    // pasted link and for a search are very different failures.
    property bool dlFromUrl: false
    // Explicit link for the next download; empty = search. Lives in the
    // download menu's field (two-way bound) and is what download-track.sh's
    // 5th argument carries, where clean-url.py canonicalises it.
    property string dlUrl: ""
    // The field holds something clean-url.py refused. Kept and flagged rather
    // than dropped, so the paste is still visible and the reason is on screen;
    // the script refuses the download instead of falling back to the search,
    // which would fetch a different video than the one that was asked for.
    property bool dlUrlBad: false
    // A link that arrived while the canonicaliser was already running; see
    // setUrl().
    property string urlCleanPending: ""
    property bool dlMenuOpen: false
    // Library stays folded away so the card reads as a player, not a file
    // browser; opening it shrinks the artwork cap to keep the card on a
    // 720-tall screen.
    property bool libOpen: false
    onIsOpenChanged: {
        if (!isOpen) {
            dlMenuOpen = false;
            // A link is a one-off request, not a mode: reopening the card must
            // not silently re-download whatever was pasted last time.
            dlUrl = "";
            dlUrlBad = false;
            urlCleanPending = "";
            // The last failure belongs to the session that hit it: a
            // "Sign in to confirm you're not a bot" from an hour ago must
            // not greet the next time the card is opened.
            dlError = "";
        } else {
            refreshLibrary();
        }
    }

    readonly property var dlOptions: [
        { label: "Audio · MP3 · Best", mode: "audio", quality: "0" },
        { label: "Audio · MP3 · 320k", mode: "audio", quality: "320K" },
        { label: "Audio · MP3 · 128k", mode: "audio", quality: "128K" },
        { label: "Video · MP4 · 1080p", mode: "video", quality: "1080" },
        { label: "Video · MP4 · 720p", mode: "video", quality: "720" },
        { label: "Video · MP4 · 480p", mode: "video", quality: "480" }
    ]

    // One place that answers "which link is this request for?", because the
    // three callers spell "no link" three different ways:
    //   - the quality menu calls downloadTrack(mode, quality)      -> undefined
    //   - `qs ipc call now-playing downloadUrl audio 0` (omitted) -> the string
    //     "undefined", because the IpcHandler coerces a missing argument to
    //     the parameter's declared type
    //   - the field itself, when empty                              -> ""
    // The middle one is the bug this fixes: the literal text "undefined" was
    // canonicalised, rejected, and reported as "unusable link: undefined",
    // which is what an empty field — meaning "download what is playing" —
    // used to do when a keybind or a script asked for it.
    function resolveLink(url) {
        if (url === undefined || url === null)
            return root.dlUrl.trim();
        const s = String(url).trim();
        if (s === "" || s === "undefined" || s === "null")
            return root.dlUrl.trim();
        return s;
    }

    function downloadTrack(mode: string, quality: string, url: string): void {
        // `url` is optional: the menu passes what its field holds, the IPC
        // verb passes an explicit link, and a bare click means "use the field
        // as it is". A link and a search are different requests, so an
        // explicit link also skips the MPRIS title/artist — pasting a URL while
        // something else plays must not tag the download with that other song.
        const link = root.resolveLink(url);
        if (dlProc.running || root.dlState === 1)
            return;
        // A search needs a track to search for; a link does not. Only the
        // title/artist are passed here: with an empty field the SCRIPT reads
        // them off the MPRIS bus, so "what is playing" stays correct even if
        // the track changes between the click and the download starting.
        if (link === "" && !root.hasTrack)
            return;
        root.dlMenuOpen = false;
        root.dlState = 1;
        root.dlAborted = false;
        root.dlFromUrl = link !== "";
        root.dlPhase = "fetching";
        root.dlPercent = 0;
        root.dlError = "";
        dlProc.command = [root.setupHome + "/scripts/download-track.sh", mode, quality, link === "" ? root.trackTitle : "", link === "" ? root.trackArtist : "", link];
        dlProc.running = true;
        dlFetchWatch.restart();
    }

    // The clipboard is the realistic source of a link (copied straight out of
    // the address bar), and what arrives is full of `&t=`/`&list=`/`&si=`
    // junk or wrapped in a chat message — so it goes through clean-url.py, the
    // SAME canonicaliser download-track.sh uses, and the field then shows
    // exactly what will be fetched rather than what was pasted.
    function pasteUrl(): void {
        if (root.dlState === 1 || pasteProc.running)
            return;
        pasteProc.running = true;
    }

    // One entry point for "the field now holds this link", so the paste button
    // and the player's own link cannot drift apart. A second request while the
    // canonicaliser is still starting is PARKED, not dropped: restarting a
    // running Process is a no-op, so without the queue a double paste would
    // silently leave the field showing the raw text.
    function setUrl(url: string): void {
        root.dlUrl = url.trim();
        root.dlUrlBad = false;
        if (cleanProc.running) {
            root.urlCleanPending = root.dlUrl;
            return;
        }
        cleanProc.command = [root.setupHome + "/scripts/clean-url.py", root.dlUrl];
        cleanProc.running = true;
    }

    function useTrackUrl(): void {
        if (MediaService.trackWebUrl === "")
            return;
        root.setUrl(MediaService.trackWebUrl);
    }

    // The ROOT methods behind the download IPC verbs, and they have to exist
    // on the root: shell.qml's shim does `loader.item[fn].apply(...)`, and an
    // IpcHandler function is not reachable that way. `downloadUrl` used to be
    // defined only inside the IpcHandler, so the shim threw "Value is
    // undefined and could not be converted to an object" on every call and the
    // download silently never started.
    //
    // Two verbs, because quickshell's IPC surface cannot express an optional
    // argument: a default value is refused outright ("Type annotations are not
    // supported (yet)") and a 3-parameter verb invoked with 2 arguments only
    // works because it warns first. So:
    //   download <mode> <quality>              use the link field as it is
    //   downloadUrl <mode> <quality> <url>     download that link ("": search)
    // An empty field means search what's playing, in both.

    function downloadUrl(mode: string, quality: string, url: string): void {
        root.downloadTrack(mode, quality, url);
    }

    function download(mode: string, quality: string): void {
        root.downloadTrack(mode, quality, undefined);
    }

    Process {
        id: pasteProc
        running: false
        command: ["wl-paste", "-t", "text", "--no-newline"]
        stdout: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    root.setUrl(line);
            }
        }
    }

    Process {
        id: cleanProc
        running: false
        stdout: SplitParser {
            onRead: line => root.dlUrl = line.trim()
        }
        onExited: code => {
            root.dlUrlBad = code !== 0 && root.dlUrl !== "";
            // Drain the parked request, if any, now that the slot is free.
            if (root.urlCleanPending !== "") {
                const next = root.urlCleanPending;
                root.urlCleanPending = "";
                root.setUrl(next);
            }
        }
    }

    Process {
        id: dlProc
        running: false
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("DL ") === 0) {
                    dlFetchWatch.stop();
                    root.dlPhase = "downloading";
                    const p = parseFloat(line.substring(3).replace("%", "").trim());
                    if (isFinite(p))
                        root.dlPercent = p;
                } else if (line.indexOf("PP ") === 0) {
                    dlFetchWatch.stop();
                    root.dlPhase = "processing";
                } else if (line.indexOf("STATUS failed ") === 0) {
                    // The script's own verdict, quoted verbatim so the card
                    // can say what went wrong instead of just showing ✕.
                    dlFetchWatch.stop();
                    root.dlError = line.substring("STATUS failed ".length).trim();
                } else if (line.indexOf("STATUS fetching") === 0) {
                    root.dlPhase = "fetching";
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            const aborted = root.dlAborted;
            dlFetchWatch.stop();
            root.dlAborted = false;
            root.dlState = aborted || exitCode !== 0 ? 3 : 2;
            dlReset.restart();
            if (root.dlState === 2)
                root.refreshLibrary();
        }
    }

    // Fetch watchdog. "Fetching" is yt-dlp resolving the search hit before a
    // single byte moves, and it is the one phase that can hang indefinitely —
    // a throttled extract, a stalled resolver or DNS, none of which the
    // socket timeout covers — which left the popup saying "Fetching…" forever
    // with no way back but reopening it. A minute is far longer than a resolve
    // ever needs, so past that we stop it: SIGTERM the script (it forwards the
    // signal to yt-dlp, so nothing is left writing into ~/Music), flash the
    // error and hand the button back. Armed by downloadTrack(), stopped by
    // the first progress line or by the process exiting.
    Timer {
        id: dlFetchWatch
        interval: 60000
        repeat: false
        onTriggered: {
            root.dlAborted = true;
            root.dlPhase = "timedout";
            root.dlState = 3;
            dlReset.restart();
            if (dlProc.running)
                dlProc.signal(15);
        }
    }

    // Local library: plain audio files in ~/Music, played through mpv so
    // they land in MediaService as a normal MPRIS source (seek, wave, art
    // and the source switcher all keep working — no second player engine).
    property var library: []

    function refreshLibrary(): void {
        root.library = [];
        root.libFilter = "";
        libProc.running = true;
    }

    // Both go through play-library.sh, which queues the WHOLE dir in mpv
    // (same find|sort order as this list) — a bare `mpv file` makes a
    // one-track playlist and Prev/Next die at the ends.
    function playFile(path: string): void {
        Quickshell.execDetached([root.setupHome + "/scripts/play-library.sh", path]);
    }

    function playRandom(): void {
        if (root.library.length === 0)
            return;
        Quickshell.execDetached([root.setupHome + "/scripts/play-library.sh", "RANDOM"]);
    }

    Process {
        id: libProc
        // Accumulate into a plain array and assign ONCE on exit: a concat
        // per line is O(n²) and fires a binding per file — fine at ten
        // tracks, a visible stall at a few thousand.
        property var pending: []
        // music-lib.sh owns the glob + sort order so this list, mpv's playlist and
        // the duplicate check can never drift apart (play-library.sh uses the
        // same order, which is what makes --playlist-start line up with the
        // row the user clicked).
        command: ["sh", root.setupHome + "/scripts/music-lib.sh", "list"]
        onRunningChanged: if (running)
            pending = []
        stdout: SplitParser {
            onRead: line => {
                const name = line.split("/").pop().replace(/\.[^.]+$/, "");
                libProc.pending.push({
                    path: line,
                    name: name
                });
            }
        }
        onExited: root.library = libProc.pending
    }

    property string libFilter: ""
    readonly property var filteredLibrary: {
        const f = root.libFilter.trim().toLowerCase();
        if (f === "")
            return root.library;
        return root.library.filter(e => e.name.toLowerCase().indexOf(f) !== -1);
    }
    Timer {
        id: dlReset
        interval: 2500
        repeat: false
        onTriggered: {
            root.dlState = 0;
            root.dlPhase = "fetching";
        }
    }

    function open(): void {
        isOpen = true;
        focusTimer.restart();
    }
    function close(): void {
        isOpen = false;
    }
    function toggle(): void {
        if (isOpen)
            close();
        else
            open();
    }

    function fmtSecs(s: real): string {
        if (!isFinite(s) || s < 0)
            return "0:00";
        const total = Math.floor(s);
        const m = Math.floor(total / 60);
        const sec = total % 60;
        return m + ":" + (sec < 10 ? "0" + sec : "" + sec);
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: keys.forceActiveFocus()
    }

    PanelWindow {
        id: win
        visible: root.isOpen
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "sunset-now-playing"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            // Pinned top-right under the bar; slides below toasts.
            anchors {
                top: parent.top
                right: parent.right
                topMargin: root.topInset + root.toastOffset
                rightMargin: 0
            }
            implicitWidth: Math.min(360, parent.width - 24)
            implicitHeight: col.implicitHeight + 32
            width: implicitWidth
            height: implicitHeight
            color: root.cPanel
            border.width: 1
            border.color: root.cBorderStrong
            radius: root.cRadius
            transformOrigin: Item.TopRight
            scale: root.isOpen ? 1.0 : 0.96
            opacity: root.isOpen ? 1 : 0
            transform: Translate {
                y: root.isOpen ? 0 : -6
                Behavior on y {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            FocusScope {
                id: keys
                anchors.fill: parent
focus: true
        // Menu first, card second: the quality/link menu is a layer over the
        // card, so Esc dismissing it feels like closing the panel you opened
        // last rather than throwing away the whole player.
        Keys.onEscapePressed: {
            if (root.dlMenuOpen)
                root.dlMenuOpen = false;
            else
                root.close();
        }
                Keys.onSpacePressed: MediaService.toggle()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_J) {
                        MediaService.previous();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_K) {
                        MediaService.next();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_S) {
                        // Cycle MPRIS source (no-op with fewer than two).
                        MediaService.cycleSource();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_D) {
                        if (root.dlState !== 1)
                            root.dlMenuOpen = !root.dlMenuOpen;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_R) {
                        root.playRandom();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_X) {
                        MediaService.toggleShuffle();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_L) {
                        MediaService.cycleLoop();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_P) {
                        MediaService.togglePin();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_E) {
                        // Stop. Moved off X when shuffle took it; E reads as
                        // "end" and sits clear of R (random) and F (refresh).
                        Quickshell.execDetached(["pkill", "mpv"]);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_F) {
                        root.refreshLibrary();
                        event.accepted = true;
                    }
                }

                Column {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    Item {
                        width: parent.width
                        height: Math.max(headerLabel.implicitHeight, dlBtn.height)

                        Text {
                            id: headerLabel
                            anchors.centerIn: parent
                            text: "NOW PLAYING"
                            font.family: root.cFont
                            font.pixelSize: 11
                            font.bold: true
                            color: root.cAccent
                        }

                        Rectangle {
                            id: stopBtn
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.hasTrack
                            width: 22
                            height: 22
                            radius: root.cRadius
                            color: stopMouse.containsMouse ? root.cRow : "transparent"

                            Image {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                fillMode: Image.PreserveAspectFit
                                source: "file://" + Theme.iconDir + "stop.svg"
                                opacity: stopMouse.containsMouse ? 0.65 : 1.0
                            }
                            MouseArea {
                                id: stopMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // pkill ALL mpv on purpose (user-facing Stop);
                                // library launches kill only their own kind.
                                onClicked: Quickshell.execDetached(["pkill", "mpv"])
                            }
                        }

                        Rectangle {
                            id: dlBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.hasTrack
                            width: 22
                            height: 22
                            radius: root.cRadius
                            color: dlMouse.containsMouse ? root.cRow : "transparent"

                            // Busy pulse. Animated on a plain property and
                            // multiplied into opacity so the hover binding
                            // survives (a property animation would destroy it).
                            property real pulse: 1.0
                            SequentialAnimation on pulse {
                                running: root.dlState === 1
                                loops: Animation.Infinite
                                NumberAnimation {
                                    to: 0.3
                                    duration: 600
                                    easing.type: Easing.InOutSine
                                }
                                NumberAnimation {
                                    to: 1.0
                                    duration: 600
                                    easing.type: Easing.InOutSine
                                }
                                onStopped: dlBtn.pulse = 1.0
                            }

                            Image {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                fillMode: Image.PreserveAspectFit
                                source: "file://" + Theme.iconDir + "download.svg"
                                visible: root.dlState !== 2 && root.dlState !== 3
                                opacity: (dlMouse.containsMouse ? 0.65 : 1.0) * dlBtn.pulse
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: root.dlState === 2 || root.dlState === 3
                                text: root.dlState === 2 ? "✓" : "✕"
                                font.family: root.cFont
                                font.pixelSize: 13
                                font.bold: true
                                color: root.dlState === 2 ? root.cAccent : root.cAccentHover
                            }

                            MouseArea {
                                id: dlMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.dlState !== 1)
                                        root.dlMenuOpen = !root.dlMenuOpen;
                                }
                            }
                        }
                    }

                    // Artwork: always spans the full card width (left edge
                    // aligned with Prev, right edge with Next) for every
                    // aspect ratio. Width is the anchor; height follows the
                    // natural aspect, capped at square so a tall portrait
                    // centre-crops instead of blowing up the card. Small
                    // sources (Brave hands over 150x83 thumbs) do upscale
                    // here — softness is inherent to the source, there are
                    // no pixels to recover. Mipmap keeps large sources crisp.
                    Item {
                        id: artBox
                        visible: root.trackArt !== ""
                        width: parent.width
                        // Box height: full scaled height, capped at square.
                        // 180 fallback while the image is still loading.
                        height: visible ? (artImage.status === Image.Ready && artImage.natW > 0 ? Math.min(root.libOpen ? 200 : parent.width, parent.width * artImage.natH / artImage.natW) : 180) : 0
                        Behavior on height {
                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                        }
                        clip: true
                        Image {
                            id: artImage
                            anchors.centerIn: parent
                            readonly property real natW: implicitWidth > 0 ? implicitWidth : 0
                            readonly property real natH: implicitHeight > 0 ? implicitHeight : 0
                            // Full-bleed width; height follows aspect. Taller
                            // than the box => centre-crop via clip.
                            width: artBox.width
                            height: natW > 0 ? artBox.width * natH / natW : artBox.height
                            fillMode: Image.PreserveAspectFit
                            source: root.trackArt
                            smooth: true
                            mipmap: true
                            asynchronous: true
                        }
                    }

                    Item {
                        id: titleMarquee
                        width: parent.width
                        height: titleText.implicitHeight
                        clip: true
                        readonly property real overflow: Math.max(0, titleText.implicitWidth - width)
                        readonly property bool scrolling: overflow > 0 && root.isOpen
                        readonly property real loopWidth: titleText.implicitWidth + gap
                        property real gap: 48

                        // One full loop per `periodMs`, advanced as a
                        // normalised 0..1 PHASE by a ~60fps timer instead of
                        // a NumberAnimation. Two reasons: pausing stops the
                        // timer, so the title freezes mid-scroll and RESUMES
                        // from the same offset (a stopped NumberAnimation
                        // restarts at `from` and would snap), and the title
                        // drifting on while the music is paused reads as the
                        // popup being unaware of playback.
                        readonly property real periodMs: Math.max(2000, loopWidth * 25)
                        property real phase: 0

                        Item {
                            id: titleTrack
                            width: titleMarquee.loopWidth * 2
                            height: parent.height
                            x: titleMarquee.scrolling ? -titleMarquee.phase * titleMarquee.loopWidth : (titleMarquee.width - titleText.implicitWidth) / 2

                            Text {
                                id: titleText
                                text: root.hasTrack ? root.trackTitle : "Nothing playing"
                                font.family: root.cFont
                                font.pixelSize: 15
                                font.bold: true
                                color: root.cText
                            }
                            Text {
                                x: titleMarquee.loopWidth
                                visible: titleMarquee.scrolling
                                text: titleText.text
                                font: titleText.font
                                color: titleText.color
                            }
                        }

                        // Timer, not an animation: the phase must be able to
                        // STOP and RESUME where it left off (see periodMs).
                        Timer {
                            interval: 17
                            repeat: true
                            running: titleMarquee.scrolling && root.playing
                            onTriggered: titleMarquee.phase = (titleMarquee.phase + 17 / titleMarquee.periodMs) % 1
                        }
                    }
                    Text {
                        width: parent.width
                        visible: root.hasTrack && (root.trackArtist !== "" || root.trackAlbum !== "")
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        wrapMode: Text.NoWrap
                        text: {
                            if (root.trackArtist !== "" && root.trackAlbum !== "")
                                return root.trackArtist + " — " + root.trackAlbum;
                            return root.trackArtist !== "" ? root.trackArtist : root.trackAlbum;
                        }
                        font.family: root.cFont
                        font.pixelSize: 12
                        color: root.cMuted
                    }
                    Text {
                        width: parent.width
                        visible: root.hasTrack && MediaService.identity !== "" && !MediaService.multipleSources
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: MediaService.identity
                        font.family: root.cFont
                        font.pixelSize: 10
                        color: root.cDim
                    }

                    // Source switcher. Only shown when 2+ MPRIS players hold a
                    // track — with one source the dim identity line above says
                    // everything already. The active source is an accent
                    // segment; the others are plain rows, and a playing source
                    // that is NOT active keeps a small accent dot so you can
                    // see at a glance that another app took over playback.
                    // ONE row, never wrapped, always centred. `Flow` was the
                    // wrong tool (it wrapped the second source onto its own
                    // line and the card lost vertical space), and plain `Row`
                    // has NO horizontalAlignment — that property is
                    // RowLayout-only, and assigning it fails the whole config.
                    // Centred manually instead: the Row is exactly as wide as
                    // its children plus spacing and is anchored by centre.
                    Item {
                        id: srcRow
                        width: parent.width
                        height: 22
                        visible: root.hasTrack && MediaService.multipleSources
                        readonly property int count: MediaService.sources.length
                        // Fair share per segment, so N sources never overflow.
                        readonly property int slotW: count > 0 ? Math.floor((width - 6 * (count - 1)) / count) : width
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Repeater {
                                model: MediaService.sources
                                delegate: NpSource {
                                    maxWidth: srcRow.slotW
                                    srcName: MediaService.sourceName(modelData)
                                    isActive: modelData === MediaService.activePlayer
                                    isPlaying: MediaService.stateLabel(modelData) === "playing"
                                    onPicked: MediaService.selectSource(modelData)
                                }
                            }
                        }
                    }

                    // Progress — layered Material 3 Expressive seek bar.
                    // Three stacked layers over one track: a soft aura, the
                    // crisp accent wave, and a pulsing ring around a CIRCLE
                    // head. The wave only travels while the track actually
                    // plays; paused is a flat bar (taste.md: restraint at
                    // rest). `expanded` (hover/drag) thickens the track and
                    // the head, Material's 12px expanded-track behaviour.
                    Column {
                        width: parent.width
                        visible: root.hasTrack && MediaService.length > 0
                        spacing: 4
                        Slider {
                            id: seekSlider
                            width: parent.width
                            from: 0
                            to: 1
                            stepSize: 0.001
                            enabled: MediaService.canSeek
                            focusPolicy: Qt.NoFocus
                            // REQUIRED: a custom `background` Rectangle has an
                            // implicitHeight of 0, and Slider takes its implicit
                            // size from it — without this the whole control
                            // collapses to 0px and the timeline disappears.
                            // 34 = the pressed circle head plus breathing
                            // room for a wave whose crests are ~2x the
                            // amplitude deep (a clipped crest is what made
                            // the sine look aliased).
                            implicitHeight: 34
                            readonly property bool expanded: pressed || seekHover.hovered
                            // Avoid fighting the 500ms position sampler while dragging.
                            Binding {
                                target: seekSlider
                                property: "value"
                                value: MediaService.progress
                                when: !seekSlider.pressed
                            }
                            onMoved: MediaService.seek(value)

                            HoverHandler {
                                id: seekHover
                            }

                            background: Rectangle {
                                id: track
                                x: seekSlider.leftPadding
                                y: seekSlider.topPadding + seekSlider.availableHeight / 2 - height / 2
                                width: seekSlider.availableWidth
                                // Taller than the old 10/16 so an 8.2px crest has somewhere to go
                                // (8.2 * swell up to 1.45 = ~12px, needs 24).
                                height: seekSlider.expanded ? 24 : 15
                                radius: height / 2
                                color: root.cBorder
                                // NOT readonly: QML refuses a Behavior on a
                                // read-only property ("Invalid property
                                // assignment").
                                property real fillW: seekSlider.visualPosition * width
                                // Playback ticks every 500ms; glide between
                                // ticks so the bar creeps instead of stepping.
                                // Off while dragging — a lag there reads as a bug.
                                Behavior on fillW {
                                    enabled: !seekSlider.pressed
                                    NumberAnimation {
                                        duration: 300
                                        easing.type: Easing.Linear
                                    }
                                }
                                Behavior on height {
                                    NumberAnimation {
                                        duration: Theme.animEnter
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on radius {
                                    NumberAnimation {
                                        duration: Theme.animEnter
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                // Layer 1 (back): wide + translucent, phase-lagged
                                // so the two layers never move in lockstep.
                                WaveTrack {
                                    anchors.fill: parent
                                    morphMs: Theme.animEnter
                                    flow: root.flow
                                    phaseOffset: 0.8
                                    waveColor: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.26)
                                    fillWidth: track.fillW
                                    strokeWidth: height - 2
                                    amplitude: root.motion * root.swell * root.waveLevel * (seekSlider.expanded ? 8.2 : 4.6)
                                }
                                // Layer 2 (front): the solid accent wave. Kept
                                // THIN on purpose — at full track height the
                                // round-capped stroke swallowed the sine and the
                                // pair read as a lumpy rope.
                                WaveTrack {
                                    anchors.fill: parent
                                    morphMs: Theme.animEnter
                                    flow: root.flow
                                    waveColor: root.cAccent
                                    fillWidth: track.fillW
                                    strokeWidth: seekSlider.expanded ? 7 : 5
                                    amplitude: root.motion * root.swell * root.waveLevel * (seekSlider.expanded ? 5.6 : 3.1)
                                }
                            }
                            handle: Rectangle {
                                id: seekHead
                                // Circle, always: it only grows, never morphs
                                // into a pill.
                                readonly property real lift: seekSlider.pressed ? 1 : (seekHover.hovered ? 0.55 : 0)
                                x: seekSlider.leftPadding + seekSlider.visualPosition * (seekSlider.availableWidth - width)
                                y: seekSlider.topPadding + seekSlider.availableHeight / 2 - height / 2
                                width: 20 + 8 * lift
                                height: width
                                radius: width / 2
                                color: seekSlider.pressed ? root.cAccentHover : root.cAccent
                                border.width: 3
                                border.color: root.cBg
                                Behavior on width {
                                    NumberAnimation {
                                        duration: 220
                                        easing.type: Easing.OutBack
                                        easing.overshoot: 1.6
                                    }
                                }
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.animHover
                                    }
                                }

                                // Layer 3: soft glow that carries hover/press.
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width + 26
                                    height: parent.height + 26
                                    radius: width / 2
                                    color: root.cAccent
                                    opacity: 0.07 + 0.12 * seekHead.lift
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: Theme.animHover
                                        }
                                    }
                                }
                                // Layer 4: ring pulse, only while playing. One
                                // animated property drives size + fade so they
                                // can never drift apart.
                                Rectangle {
                                    property real pulse: 0
                                    anchors.centerIn: parent
                                    width: parent.width + 6 + pulse * 26
                                    height: width
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: 2
                                    border.color: root.cAccent
                                    // The looping animation owns `opacity`
                                    // while it runs; on pause it stops and this
                                    // binding takes over, so the ring eases
                                    // away instead of freezing mid-pulse.
                                    opacity: root.playing ? 0.45 * (1 - pulse) : 0
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: Theme.animHover
                                        }
                                    }
                                    NumberAnimation on pulse {
                                        from: 0
                                        to: 1
                                        duration: 1700
                                        loops: Animation.Infinite
                                        running: root.playing && root.motion > 0 && !seekSlider.pressed
                                    }
                                }
                            }
                        }
                        Row {
                            width: parent.width
                            Text {
                                width: parent.width / 2
                                text: root.fmtSecs(MediaService.position)
                                font.family: root.cFont
                                font.pixelSize: 10
                                // Brighter while the track rolls, like every
                                // music player does with the elapsed time.
                                color: root.playing ? root.cText : root.cMuted
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.animHover
                                    }
                                }
                            }
                            Text {
                                width: parent.width / 2
                                horizontalAlignment: Text.AlignRight
                                text: root.fmtSecs(MediaService.length)
                                font.family: root.cFont
                                font.pixelSize: 10
                                color: root.cMuted
                            }
                        }
                    }

                    // Controls
                    Row {
                        width: parent.width
                        spacing: 8
                        NpBtn {
                            cols: 3; gap: 8
                            label: "⏮ Prev"
                            onClicked: MediaService.previous()
                        }
                        NpBtn {
                            cols: 3; gap: 8
                            primary: true
                            label: root.playing ? "⏸ Pause" : "▶ Play"
                            onClicked: MediaService.toggle()
                        }
                        NpBtn {
                            cols: 3; gap: 8
                            label: "Next ⏭"
                            onClicked: MediaService.next()
                        }
                    }

                    // Repeat / shuffle / pin. Only the modes the CURRENT
                    // player actually implements get a button: MPRIS
                    // `loopSupported`/`shuffleSupported` are false for Brave,
                    // which exports neither property at all, so a row rendered
                    // unconditionally is two dead controls that look live.
                    // The row spans the full card and centres itself, so it
                    // does not shift when a player drops shuffle.
                    Item {
                        width: parent.width
                        height: 26
                        visible: root.hasTrack && (MediaService.canLoop || MediaService.canShuffle || MediaService.sourcePinned || MediaService.multipleSources)
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            NpToggle {
                                visible: MediaService.canLoop
                                // Three shapes for three states: off, repeat
                                // one (track), repeat all (playlist). Cycling
                                // order is None -> Track -> Playlist.
                                offSvg: "repeat-off.svg"
                                onSvg: MediaService.loopTrack ? "repeat-one.svg" : "repeat.svg"
                                on: MediaService.loopTrack || MediaService.loopPlaylist
                                onToggled: MediaService.cycleLoop()
                            }
                            NpToggle {
                                visible: MediaService.canShuffle
                                offSvg: "shuffle.svg"
                                onSvg: "shuffle.svg"
                                on: MediaService.shuffleOn
                                onToggled: MediaService.toggleShuffle()
                            }
                            NpToggle {
                                // Only meaningful when there is a rival source:
                                // with one player there is nothing for auto-pick
                                // to steal the card from.
                                visible: MediaService.multipleSources
                                offSvg: "pin-off.svg"
                                onSvg: "pin.svg"
                                on: MediaService.sourcePinned
                                onToggled: MediaService.togglePin()
                            }
                        }
                    }

                    // Download progress: one status line + a 3px track.
                    // Invisible while idle, so the Column gives it no space.
                    Column {
                        width: parent.width
                        spacing: 4
                        // Stays up for the 2.5s error flash: the ✕ on the
                        // button alone says "failed", this line says why — and
                        // now it can, because the script streams yt-dlp's own
                        // error line instead of leaving three different
                        // failures looking identical.
                        visible: root.dlState === 1 || root.dlPhase === "timedout" || root.dlError !== ""

                        readonly property bool failed: root.dlState !== 1 && root.dlError !== ""

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            // The failure text can be a whole yt-dlp sentence,
                            // so it elides and wraps onto a second line rather
                            // than stretching the card.
                            text: parent.failed ? root.dlError : (root.dlPhase === "downloading" ? "Downloading " + Math.round(root.dlPercent) + "%" : (root.dlPhase === "processing" ? "Processing…" : (root.dlPhase === "timedout" ? "Fetch timed out (60s)" : (root.dlFromUrl ? "Resolving link…" : "Fetching…"))))
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            font.family: root.cFont
                            font.pixelSize: 10
                            color: (root.dlPhase === "timedout" || parent.failed) ? root.cText : root.cMuted
                        }
                        Rectangle {
                            width: parent.width
                            height: 3
                            radius: 1.5
                            color: root.cRow

                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                color: root.cAccent
                                // Fetching is indeterminate (bar waits at 0);
                                // processing shows a full track — the ffmpeg
                                // steps report no fraction of their own.
                                width: root.dlPhase === "downloading" ? parent.width * Math.min(1, root.dlPercent / 100) : (root.dlPhase === "processing" ? parent.width : 0)
                                Behavior on width {
                                    NumberAnimation {
                                        duration: 200
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        // Only mention a mode the current player actually
                        // implements, and only "S source" when there IS
                        // something to switch to — a hint line advertising
                        // keys that do nothing is worse than a shorter line.
                        text: {
                            let parts = ["Space play", "←/→ track", "Esc"];
                            if (MediaService.canLoop)
                                parts.push("L repeat");
                            if (MediaService.canShuffle)
                                parts.push("X shuffle");
                            if (MediaService.multipleSources)
                                parts.push(MediaService.sourcePinned ? "P unpin" : "S source · P pin");
                            return parts.join(" · ");
                        }
                        font.family: root.cFont
                        font.pixelSize: 10
                        color: root.cMuted
                        // Elide rather than overflow: this Text sits in a Column
                        // whose width IS the card, so an overflowing hint used to
                        // run off both edges and get clipped by the card border.
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        topPadding: 2
                    }

                    // Local ~/Music library. Hidden when empty; capped at
                    // five rows so a big collection cannot stretch the card
                    // past the screen.
                    Column {
                        width: parent.width
                        spacing: 6
                        visible: root.library.length > 0

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: root.cBorder
                        }

                        Item {
                            width: parent.width
                            height: Math.max(libLabel.implicitHeight, 20)

                            // Declared first so the shuffle button (later
                            // sibling) keeps its own clicks.
                            MouseArea {
                                id: libHeaderMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.libOpen = !root.libOpen
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.libOpen ? "▾" : "▸"
                                font.family: root.cFont
                                font.pixelSize: 11
                                color: root.cMuted
                            }

                            Text {
                                id: libLabel
                                anchors.centerIn: parent
                                text: "LIBRARY · " + root.library.length
                                font.family: root.cFont
                                font.pixelSize: 11
                                font.bold: true
                                color: libHeaderMouse.containsMouse ? root.cAccentHover : root.cAccent
                            }

                            Rectangle {
                                id: refreshBtn
                                anchors.right: shuffleBtn.left
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22
                                radius: root.cRadius
                                color: refreshMouse.containsMouse ? root.cRow : "transparent"

                                Image {
                                    anchors.centerIn: parent
                                    width: 14
                                    height: 14
                                    fillMode: Image.PreserveAspectFit
                                    source: "file://" + Theme.iconDir + "refresh.svg"
                                    opacity: refreshMouse.containsMouse ? 0.65 : 1.0
                                    RotationAnimation on rotation {
                                        running: libProc.running
                                        loops: Animation.Infinite
                                        from: 0
                                        to: 360
                                        duration: 900
                                    }
                                    onRotationChanged: if (!libProc.running)
                                        rotation = 0
                                }
                                MouseArea {
                                    id: refreshMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.refreshLibrary()
                                }
                            }

                            Rectangle {
                                id: shuffleBtn
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22
                                radius: root.cRadius
                                color: shuffleMouse.containsMouse ? root.cRow : "transparent"

                                Image {
                                    anchors.centerIn: parent
                                    width: 14
                                    height: 14
                                    fillMode: Image.PreserveAspectFit
                                    source: "file://" + Theme.iconDir + "shuffle.svg"
                                    opacity: shuffleMouse.containsMouse ? 0.65 : 1.0
                                }
                                MouseArea {
                                    id: shuffleMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.playRandom()
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 28
                            visible: root.libOpen
                            radius: root.cRadius
                            color: root.cRow

                            TextInput {
                                id: libFilterInput
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                color: root.cText
                                font.family: root.cFont
                                font.pixelSize: 11
                                onTextChanged: root.libFilter = text

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: libFilterInput.text.length === 0
                                    text: "Filter…"
                                    font: libFilterInput.font
                                    color: root.cMuted
                                }
                            }
                        }

                        ListView {
                            width: parent.width
                            // Folded by default; four rows when open, scrolls
                            // past that — the card must never outgrow a
                            // 720-tall screen.
                            visible: root.libOpen
                            height: visible ? Math.min(contentHeight, 4 * 28) : 0
                            clip: true
                            interactive: contentHeight > height
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.filteredLibrary

                            delegate: Rectangle {
                                required property var modelData
                                width: ListView.view.width
                                height: 26
                                radius: root.cRadius
                                // Accent when this file looks like the live
                                // track — MPRIS titles rarely match the file
                                // name exactly, so test both directions.
                                readonly property bool isLive: root.hasTrack && (root.trackTitle.indexOf(modelData.name) !== -1 || modelData.name.indexOf(root.trackTitle) !== -1)
                                color: libMouse.containsMouse ? root.cRow : "transparent"

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    text: modelData.name
                                    font.family: root.cFont
                                    font.pixelSize: 11
                                    color: parent.isLive ? root.cAccent : root.cText
                                }
                                MouseArea {
                                    id: libMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.playFile(modelData.path)
                                }
                            }
                        }
                    }
                }
            }

            // Quality picker for the header download button, plus the link
            // field the qualities download FROM. Floats above the artwork,
            // right-aligned with the card's 16px margin.
            Rectangle {
                id: dlMenu
                visible: root.dlMenuOpen
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 44
                anchors.rightMargin: 16
                width: 232
                height: menuCol.implicitHeight + 12
                color: root.cPanel
                border.width: 1
                border.color: root.cBorderStrong
                radius: root.cRadius
                z: 10

                Column {
                    id: menuCol
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 2

                    // Link field + paste button. Empty means "search
                    // <artist> <title>", so the common case stays one click:
                    // the field is a preamble, not a step.
                    Item {
                        width: menuCol.width
                        height: 26

                        TextField {
                            id: urlInput
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 26
                            height: 24
                            padding: 6
                            // Bound both ways: what the user types is what the
                            // next quality downloads.
                            text: root.dlUrl
                            onTextEdited: {
                                root.dlUrl = text;
                                root.dlUrlBad = false;
                            }
                            placeholderText: "Link, empty = search"
                            placeholderTextColor: root.cDim
                            font.family: root.cFont
                            font.pixelSize: 10
                            color: root.cText
                            selectByMouse: true
                            selectionColor: root.cAccent
                            selectedTextColor: root.cBg
                            background: Rectangle {
                                color: root.cRow
                                border.width: 1
                                // Red only when clean-url.py refused it, and
                                // that is the exact set of links the script
                                // will refuse — not a guess.
                                border.color: root.dlUrlBad ? root.cDanger : (urlInput.activeFocus ? root.cAccent : root.cBorderStrong)
                                radius: root.cRadius
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 22
                            radius: root.cRadius
                            color: pasteMouse.containsMouse ? root.cRow : "transparent"

                            Image {
                                anchors.centerIn: parent
                                width: 13
                                height: 13
                                fillMode: Image.PreserveAspectFit
                                source: "file://" + Theme.iconDir + "clipboard.svg"
                                opacity: pasteMouse.containsMouse ? 0.65 : 1.0
                            }
                            MouseArea {
                                id: pasteMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.pasteUrl()
                            }
                        }
                    }

                    // "Use the player's own link" — only for players that
                    // publish an http(s) xesam:url. Chromium publishes none,
                    // which is why the search path still exists at all.
                    Rectangle {
                        width: menuCol.width
                        height: 22
                        visible: MediaService.trackWebUrl !== ""
                        radius: root.cRadius
                        color: trackUrlMouse.containsMouse ? root.cRow : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Use this track's link"
                            font.family: root.cFont
                            font.pixelSize: 11
                            color: root.cText
                        }
                        MouseArea {
                            id: trackUrlMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.useTrackUrl()
                        }
                    }

                    Rectangle {
                        width: menuCol.width
                        height: 1
                        visible: MediaService.trackWebUrl !== ""
                        color: root.cBorder
                    }

                    Repeater {
                        model: root.dlOptions
                        delegate: Rectangle {
                            required property var modelData
                            width: menuCol.width
                            height: 26
                            radius: root.cRadius
                            color: optMouse.containsMouse ? root.cRow : "transparent"
                            opacity: root.dlState === 1 || root.dlUrlBad ? 0.5 : 1

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.family: root.cFont
                                font.pixelSize: 11
                                color: root.cText
                            }
                            MouseArea {
                                id: optMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.downloadTrack(modelData.mode, modelData.quality)
                            }
                        }
                    }
                }
            }
        }

        onVisibleChanged: {
            if (visible)
                focusTimer.restart();
        }
    }

    // One layer of the travelling sine (Material's "wavy linear" active
    // track). Layers differ only in strokeWidth / amplitude / alpha / phase,
    // so they are the same component with different props.
    //   flow        shared phase (0..1) — ONE animation on root feeds every
    //               layer; per-layer animations would drift and triple the
    //               per-frame property churn.
    //   phaseOffset stagger in radians so layers don't move in lockstep.
    // PathPolyline needs Qt.point() entries: a flat [x,y,x,y] list type-checks
    // but renders NOTHING (verified in isolation). Geometry renderer (the
    // default) on purpose — CurveRenderer needs a real RHI backend and this
    // must also draw on the software fallback.
    component WaveTrack: Shape {
        id: wv
        property color waveColor: "transparent"
        property real fillWidth: 0
        property real amplitude: 0
        property real wavelength: 72
        property real strokeWidth: 6
        property real flow: 0
        property real phaseOffset: 0
        property int morphMs: 180
        readonly property var points: {
            const pts = [];
            const mid = height / 2;
            if (fillWidth <= 0.5 || strokeWidth <= 0.1) {
                pts.push(Qt.point(0, mid));
                return pts;
            }
            const k = Math.PI * 2 / wavelength;
            const p = flow * Math.PI * 2 + phaseOffset;
            // 3px steps: ~24 samples per wavelength. Coarser steps turn the
            // round-capped stroke into a scalloped rope (read as
            // aliasing), so the density is a look requirement, not a
            // tuning knob.
            for (let x = 0; x < fillWidth; x += 3)
                pts.push(Qt.point(x, mid + amplitude * Math.sin(x * k - p)));
            pts.push(Qt.point(fillWidth, mid + amplitude * Math.sin(fillWidth * k - p)));
            return pts;
        }
        Behavior on amplitude {
            NumberAnimation {
                duration: morphMs
                easing.type: Easing.OutCubic
            }
        }
        Behavior on strokeWidth {
            NumberAnimation {
                duration: morphMs
                easing.type: Easing.OutCubic
            }
        }
        ShapePath {
            strokeWidth: wv.strokeWidth
            strokeColor: wv.waveColor
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathPolyline {
                path: wv.points
            }
        }
    }

    // One MPRIS source in the switcher row. Tokens are injected (inline
    // component scopes cannot see `root`); no hex literals — see taste.md.
    component NpSource: Rectangle {
        id: sBtn
        property color cAccent: root.cAccent
        property color cBg: root.cBg
        property color cBorderStrong: root.cBorderStrong
        property color cDim: root.cDim
        property string cFont: root.cFont
        property int cRadius: root.cRadius
        property color cRow: root.cRow
        property color cText: root.cText
        property string srcName: ""
        property bool isActive: false
        property bool isPlaying: false
        // Fair share of the source row; also the hard cap so a long player
        // name can never push siblings off the card.
        property int maxWidth: 150
        signal picked
        height: 22
        width: Math.min(maxWidth, sLabel.implicitWidth + 18 + (sDot.visible ? 12 : 0))
        color: isActive ? cAccent : cRow
        border.width: 1
        border.color: isActive ? cAccent : cBorderStrong
        radius: cRadius
        opacity: isActive ? 1.0 : 0.85
        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
        Row {
            anchors.centerIn: parent
            spacing: 5
            // Only for a source that is playing but NOT selected — that is
            // the one worth switching to.
            Rectangle {
                id: sDot
                anchors.verticalCenter: parent.verticalCenter
                visible: isPlaying && !isActive
                width: 5
                height: 5
                radius: 2.5
                color: cAccent
            }
            Text {
                id: sLabel
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Math.max(20, sBtn.width - 18 - (sDot.visible ? 12 : 0)))
                text: sBtn.srcName
                elide: Text.ElideRight
                font.family: sBtn.cFont
                font.pixelSize: 10
                font.bold: sBtn.isActive
                color: sBtn.isActive ? sBtn.cBg : (sHover.hovered ? sBtn.cAccent : sBtn.cText)
            }
        }
        HoverHandler {
            id: sHover
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sBtn.picked()
        }
    }

    component NpBtn: Rectangle {
        property color cAccent: root.cAccent
        property color cAccentHover: root.cAccentHover
        property color cBg: root.cBg
        property color cBorderStrong: root.cBorderStrong
        property string cFont: root.cFont
        property int cRadius: root.cRadius
        property color cRow: root.cRow
        property color cText: root.cText
        id: nBtn
        property string label: ""
        property bool primary: false
        property int cols: 3
        property real gap: 8
        signal clicked
        width: parent ? (parent.width - (cols - 1) * gap) / cols : 100
        height: 32
        color: primary ? cAccent : cRow
        border.width: 1
        border.color: primary ? cAccent : cBorderStrong
        radius: cRadius
        scale: nMouse.pressed ? 0.98 : 1.0
        Behavior on scale {
            NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
        }
        Text {
            anchors.centerIn: parent
            text: nBtn.label
            font.family: cFont
            font.pixelSize: 12
            font.bold: true
            color: primary ? cBg : cText
        }
        MouseArea {
            id: nMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: nBtn.clicked()
        }
    }

    // One icon toggle: repeat, shuffle, pin. A small pill rather than one of
    // the NpBtn transport buttons, because these are MODE switches, not
    // actions — the pressed state has to stay visible while the card is open.
    //
    // The state is drawn by SHAPE plus an accent underline, NOT by filling the
    // pill with the accent. An accent fill looks right for `Text` (Theme.onAccent
    // measures its foreground) but is a trap for a stroked SVG: QtQuick's
    // `Image` has no `color`, so there is no way to repaint the glyph for a
    // bright background — binding one does not tint, it fails to load. The
    // result was the exact regression the icon set exists to prevent: a
    // neutral icon dumped on an accent pill, reading as a grey smudge. So the
    // pill stays transparent/`row` and the underline carries the state, which is
    // the same trick Workspaces.qml uses for its active workspace pill.
    //
    // Off-state glyphs are authored on the `dim` hex, so the generator maps
    // them to iconMuted — the set's reserved "off" step, the same one
    // volume-muted.svg and wifi-off.svg use.
    component NpToggle: Rectangle {
        property color cAccent: root.cAccent
        property color cAccentHover: root.cAccentHover
        property int cRadius: root.cRadius
        property color cRow: root.cRow
        id: nTog
        property string offSvg: ""
        property string onSvg: ""
        property bool on: false
        signal toggled
        width: 34
        height: 26
        radius: cRadius
        color: togMouse.containsMouse ? cRow : "transparent"
        Behavior on color {
            ColorAnimation { duration: Theme.animHover }
        }

        Image {
            id: togIcon
            anchors.centerIn: parent
            anchors.verticalCenterOffset: nTog.on ? -1 : 0
            width: 16
            height: 16
            fillMode: Image.PreserveAspectFit
            source: "file://" + Theme.iconDir + (nTog.on ? nTog.onSvg : nTog.offSvg)
            opacity: togMouse.containsMouse ? 0.6 : 1.0
            Behavior on opacity {
                NumberAnimation { duration: Theme.animFast }
            }
        }

        // Accent underline = "this mode is on". 2px, full pill width, so it
        // reads as a state marker rather than a border.
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                leftMargin: 6
                rightMargin: 6
            }
            height: 2
            radius: 1
            color: nTog.on ? nTog.cAccent : "transparent"
            Behavior on color {
                ColorAnimation { duration: Theme.animHover }
            }
        }

        MouseArea {
            id: togMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nTog.toggled()
        }
    }

    IpcHandler {
        target: "now-playing"
        function toggle(): void { root.toggle(); }
        function open(): void { root.open(); }
        function close(): void { root.close(); }
        // URL-based download from a script or a keybind: the link is
        // canonicalised by download-track.sh, so a messy paste is fine here.
        // Search (no url, or "") still needs a track to search for.
        function downloadUrl(mode: string, quality: string, url: string): void {
            root.downloadUrl(mode, quality, url);
        }

        // Same request as picking a quality in the download menu with the link
        // box as it is left. Its own verb so it needs no trailing "".
        function download(mode: string, quality: string): void {
            root.download(mode, quality);
        }

        // Repeat / shuffle / pin. These are ROOT methods, not inline bodies,
        // because shell.qml's shim calls `loader.item[fn]` and an IpcHandler
        // function is unreachable that way — the same trap as downloadUrl.
        function loop(): void {
            MediaService.cycleLoop();
        }
        function shuffle(): void {
            MediaService.toggleShuffle();
        }
        function pin(): void {
            MediaService.togglePin();
        }
    }
}
