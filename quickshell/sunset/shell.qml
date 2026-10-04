//@ pragma IconTheme Colloid
// shell.qml — sunset entry point (`qs -c sunset`).
// Quickshell loads <configDir>/sunset/shell.qml for `-c sunset`.
// Repo layout mirrors that: quickshell/sunset/shell.qml.
//
// OWNERSHIP (parallel builders):
//   Builder #1 (this file): ShellRoot wiring + Theme + services contract
//                           + the lazy-popup plumbing and the IPC shims.
//   Bar builder:             components/Bar.qml
//   Popup builders:          components/CalendarPopup.qml, VolumePopup.qml,
//                            QuickSettings.qml, ClipboardPopup.qml,
//                            WallpaperPicker.qml, PowerMenu.qml,
//                            WifiPopup.qml (top-right, replaces the WI-FI
//                            section of QuickSettings + `nmtui connect`)
//   Launcher builder:        components/Launcher.qml
//   Toasts builder:          components/Toasts.qml (already landed)
// NOT in this shell anymore (moved out 2026-10-02):
//   Settings Center  -> GNOME Settings   (scripts/gnome-settings.sh, Mod+Alt+S)
//   Help & Guide     -> help/index.html   (scripts/open-help.sh,    Mod+Alt+H)
// Do NOT add colors/fonts here — use Theme.* (taste.md tokens).
//
// ------------------------------------------------------------------
// LAZY POPUPS (2026-10-03, memory work)
// ------------------------------------------------------------------
// Building all 15 popups up front cost ~39MB resident (measured: empty
// ShellRoot 108MB -> Bar only 159MB -> + all popups 198MB). Each popup is
// now a LazyLoader that compiles + instantiates its component on first use,
// so a popup you never open costs nothing. Same config measures 162MB with
// every popup still unopened.
//
// Two facts drive the design, both verified rather than assumed:
//
//  1. LazyLoader.active is ASYNCHRONOUS. Setting it does NOT make `item`
//     available in the same tick (probe: read an id declared inside the
//     deferred PanelWindow immediately after flipping the flag -> undefined).
//     So an IPC call cannot just activate and call. Calls are parked in
//     `pending` and replayed from each loader's onItemChanged.
//
//  2. Deferring the COMPONENT (whole file) is what saves the memory, not
//     just the object tree. Wrapping only the inner PanelWindow keeps the
//     file compiled and measured worse (176MB vs 162MB) while forcing
//     async-aware fixes at ~29 cross-boundary id references across 15 files
//     — several reachable with the popup closed (`themes next` reads
//     menuList, `clipboard refresh` reads clipList, QuickSettings' service
//     handlers read volSlider/briSlider, Whip's onPhaseChanged reads
//     lashCanvas, NowPlayingPopup's Timer binding reads win.visible).
//     Deferring the whole file touches none of that.
//
// The popups keep their own IpcHandler; it only starts answering once the
// loader has built them. The shims below are what keep `qs -c sunset ipc
// call <target> ...` working from the very first keypress, including every
// target listed in binds.kdl / binds-quickshell.kdl. Mirroring the surface
// here is deliberate drift risk, contained to this one file: if a popup
// gains an IPC verb, add it to the matching shim below.
//
// EAGER, deliberately NOT lazy:
//   Bar       — always on screen.
//   Toasts    — owns org.freedesktop.Notifications (one owner allowed) and
//               must exist to receive notifications at all. Lazy would drop
//               the server between toasts.
//   Osd       — 340x52, driven by brightness/volume keys; laziness saves
//               nothing and costs a build on every keypress.
//   ContextMenu — owns the transparent `sunset-desktop` input plane on the
//               bottom layer that eats clicks on wallpaper gaps. It must be
//               mapped from startup or the desktop stops responding.
// Its `menu` and `notifications` and `osd` targets therefore live in those
// files and are untouched by the shims below.
//
// Closing unloads (after UNLOAD_MS, so exit animations finish) which is
// what makes the saving durable rather than one-shot-per-boot. Popups
// rebuild their view in open(), so reopening is correct; the only state
// that does not survive a close+reopen is CalendarPopup's browsed month
// (it reopens on the current month, which is the sane default anyway).

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import qs.components

ShellRoot {
    id: root

    // How long after close() before the component is torn down. Must exceed
    // the longest exit animation in the popups so nothing pops out abruptly.
    readonly property int unloadDelay: 600

    // Height of the top bar, taken from the bar itself so a change there does
    // not silently push every docked card's header under it. The top-right
    // cards anchor to the SCREEN top (their PanelWindows span the screen so an
    // outside click can close them), so each one subtracts this via its
    // `topInset` property. Bluetooth, Wi-Fi, mixer, quick settings and now
    // playing all dock in that corner.
    readonly property int topInset: bar.implicitHeight

    // Parked IPC calls awaiting their loader: loader -> {fn, args}.
    property var pending: ({})
    property var unloadQueue: []

    // Activate `loader` if needed, then invoke the popup root method `fn`.
    // If the popup is already built this is a straight call, so the common
    // "toggle an open popup" path stays synchronous and feels instant.
    function dispatch(loader, fn): void {
        const args = [];
        for (let i = 2; i < arguments.length; i++)
            args.push(arguments[i]);
        if (loader.item) {
            loader.item[fn].apply(loader.item, args);
            return;
        }
        pending[String(loader)] = { "fn": fn, "args": args };
        loader.active = true;
    }

    // Replay whatever dispatch parked for this loader. Called from its
    // onItemChanged; no-ops once the queue for that loader is empty.
    function runPending(loader): void {
        const key = String(loader);
        const p = pending[key];
        if (!p || !loader.item)
            return;
        delete pending[key];
        // Guard: an IPC verb is not always spelled like the root method it
        // forwards to, and a typo here must not throw inside a signal
        // handler (it would surface as a TypeError and silently no-op).
        if (typeof loader.item[p.fn] !== "function")
            console.warn("sunset: " + key + " has no method '" + p.fn + "'");
        else
            loader.item[p.fn].apply(loader.item, p.args);
    }

    // Ask for a teardown once the popup has finished closing.
    function scheduleUnload(loader): void {
        root.unloadQueue = root.unloadQueue.concat([loader]);
        unloadTimer.restart();
    }

    // Force a build without acting on it (used by the "open" verb).
    function ensureLoaded(loader): void {
        if (!loader.item)
            loader.active = true;
    }

    Timer {
        id: unloadTimer
        interval: root.unloadDelay
        repeat: false
        onTriggered: {
            const q = root.unloadQueue;
            root.unloadQueue = [];
            for (let i = 0; i < q.length; i++) {
                const ldr = q[i];
                // Skip if it was reopened inside the delay window.
                if (ldr.item && !ldr.item.isOpen)
                    ldr.active = false;
            }
        }
    }

    // Force singleton instantiation so services connect even before
    // Bar/popup bindings reference them. No visual output.
    Component.onCompleted: {
        // Touch singletons (property read keeps binding, avoids unused-import purge).
        console.info("sunset: NIRI_SOCKET=" + NiriService.socketPath + " audio=" + AudioService.ready);
        console.info("sunset: media=" + MediaService.hasPlayer + " wallpaper=" + WallpaperService.currentPath);
        console.info("sunset: dnd=" + NotificationService.dnd + " pomo=" + PomodoroService.pomoPhase + " running=" + PomodoroService.pomoRunning);
        console.info("sunset: weather=" + WeatherService.city + " capture-pinned=" + CaptureService.pinned);
    }

    // Top bar (one instance; Bar.qml itself fans out per-screen with Variants).
    Bar {
        id: bar
        onContextMenuRequested: (x, y) => contextMenu.openBar(x, y)
    }

    // ---- lazy popups -------------------------------------------------
    // One LazyLoader per popup. `source:` (a URL) rather than an inline
    // component so the .qml file is not compiled until first activation.

    LazyLoader {
        id: calendarLoader
        active: false
        source: Qt.resolvedUrl("components/CalendarPopup.qml")
        onItemChanged: root.runPending(calendarLoader)
    }
    LazyLoader {
        id: volumeLoader
        active: false
        source: Qt.resolvedUrl("components/VolumePopup.qml")
        onItemChanged: root.runPending(volumeLoader)
    }
    LazyLoader {
        id: weatherLoader
        active: false
        source: Qt.resolvedUrl("components/WeatherPopup.qml")
        onItemChanged: root.runPending(weatherLoader)
    }
    LazyLoader {
        id: nowPlayingLoader
        active: false
        source: Qt.resolvedUrl("components/NowPlayingPopup.qml")
        onItemChanged: root.runPending(nowPlayingLoader)
    }
    LazyLoader {
        id: settingsLoader
        active: false
        source: Qt.resolvedUrl("components/QuickSettings.qml")
        onItemChanged: root.runPending(settingsLoader)
    }
    LazyLoader {
        id: bluetoothLoader
        active: false
        source: Qt.resolvedUrl("components/BluetoothPopup.qml")
        onItemChanged: root.runPending(bluetoothLoader)
    }
    LazyLoader {
        id: wifiLoader
        active: false
        source: Qt.resolvedUrl("components/WifiPopup.qml")
        onItemChanged: root.runPending(wifiLoader)
    }
    LazyLoader {
        id: clipboardLoader
        active: false
        source: Qt.resolvedUrl("components/ClipboardPopup.qml")
        onItemChanged: root.runPending(clipboardLoader)
    }
    LazyLoader {
        id: wallpaperLoader
        active: false
        source: Qt.resolvedUrl("components/WallpaperPicker.qml")
        onItemChanged: root.runPending(wallpaperLoader)
    }
    LazyLoader {
        id: wallpaperMenuLoader
        active: false
        source: Qt.resolvedUrl("components/WallpaperMenu.qml")
        onItemChanged: root.runPending(wallpaperMenuLoader)
    }
    LazyLoader {
        id: powerLoader
        active: false
        source: Qt.resolvedUrl("components/PowerMenu.qml")
        onItemChanged: root.runPending(powerLoader)
    }
    LazyLoader {
        id: launcherLoader
        active: false
        source: Qt.resolvedUrl("components/Launcher.qml")
        onItemChanged: root.runPending(launcherLoader)
    }
    LazyLoader {
        id: whipLoader
        active: false
        source: Qt.resolvedUrl("components/Whip.qml")
        onItemChanged: root.runPending(whipLoader)
    }
    LazyLoader {
        id: themesLoader
        active: false
        source: Qt.resolvedUrl("components/ThemePicker.qml")
        onItemChanged: root.runPending(themesLoader)
    }
    LazyLoader {
        id: sessionsLoader
        active: false
        source: Qt.resolvedUrl("components/SessionEditor.qml")
        onItemChanged: root.runPending(sessionsLoader)
    }
    LazyLoader {
        id: screenshotsLoader
        active: false
        source: Qt.resolvedUrl("components/ScreenshotActions.qml")
        onItemChanged: root.runPending(screenshotsLoader)
    }

    // ---- IPC shims ---------------------------------------------------
    // Verb-for-verb mirror of each popup's own IpcHandler so every
    // `qs -c sunset ipc call <target> <verb>` works before the popup has
    // ever been opened. Keep in sync with the target's IpcHandler.

    IpcHandler {
        target: "calendar"

        function toggle(): void {
            root.dispatch(calendarLoader, "toggle");
        }
        function open(): void {
            root.dispatch(calendarLoader, "open");
        }
        function close(): void {
            root.dispatch(calendarLoader, "close");
            root.scheduleUnload(calendarLoader);
        }
        // Direct pomo/timer control (bar widget, keybinds, scripts).
        // No auto-open: status + sticky toasts already surface progress.
        // These forward straight to PomodoroService instead of loading the
        // calendar: the popup is only a conduit for them, so a keybind must
        // not pay for building a 1000-line window it never shows.
        function pomoStart(): void {
            PomodoroService.pomoCmd("start");
        }
        function pomoPause(): void {
            PomodoroService.pomoCmd("pause");
        }
        function pomoReset(): void {
            PomodoroService.pomoCmd("reset");
        }
        function pomoSkip(): void {
            PomodoroService.pomoCmd("skip");
        }
        function timerPause(): void {
            PomodoroService.timerPause();
        }
    }

    IpcHandler {
        target: "volume"

        function toggle(): void {
            root.dispatch(volumeLoader, "toggle");
        }
        function open(): void {
            root.dispatch(volumeLoader, "open");
        }
        function close(): void {
            root.dispatch(volumeLoader, "close");
            root.scheduleUnload(volumeLoader);
        }
    }

    IpcHandler {
        target: "weather"

        function toggle(): void {
            root.dispatch(weatherLoader, "toggle");
        }
        function open(): void {
            root.dispatch(weatherLoader, "open");
        }
        function close(): void {
            root.dispatch(weatherLoader, "close");
            root.scheduleUnload(weatherLoader);
        }
    }

    IpcHandler {
        target: "now-playing"

        function toggle(): void {
            root.dispatch(nowPlayingLoader, "toggle");
        }
        function open(): void {
            root.dispatch(nowPlayingLoader, "open");
        }
        function close(): void {
            root.dispatch(nowPlayingLoader, "close");
            root.scheduleUnload(nowPlayingLoader);
        }
        // URL-based download. Builds the popup when it is closed — a script
        // or keybind asking for a track needs no visible card.
        //
        // `url` is typed `string` and MUST stay that way: quickshell refuses
        // an untyped argument across IPC ("Type of argument 3 (url: QVariant)
        // cannot be used across IPC"), and a default value is refused too
        // ("Type annotations are not supported (yet)"), so a 3-parameter verb
        // can never take the url as optional. With the type, an omitted
        // argument is coerced to the string "undefined" rather than arriving as
        // undefined, and that text used to die on "unusable link: undefined".
        // `download` below is the 2-argument form, and resolveLink() in the
        // popup folds every spelling of "no link" — undefined, "undefined",
        // "null", "" — back to the search.
        function downloadUrl(mode: string, quality: string, url: string): void {
            root.dispatch(nowPlayingLoader, "downloadUrl", mode, quality, url);
        }

        function download(mode: string, quality: string): void {
            root.dispatch(nowPlayingLoader, "download", mode, quality);
        }

        // Repeat / shuffle / pin go STRAIGHT to MediaService, not through
        // dispatch(). A keybind changing the repeat mode has no business
        // building the whole card it would never show — same reason the
        // calendar pomo/timer verbs bypass their popup. They are no-ops on a
        // player that does not implement the property (MediaService gates on
        // loopSupported/shuffleSupported), so a bind is always safe to fire.
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

    IpcHandler {
        target: "settings"

        function toggle(): void {
            root.dispatch(settingsLoader, "toggle");
        }
        function open(): void {
            root.dispatch(settingsLoader, "open");
        }
        function close(): void {
            root.dispatch(settingsLoader, "close");
            root.scheduleUnload(settingsLoader);
        }
    }

    IpcHandler {
        target: "bluetooth"

        function toggle(): void {
            root.dispatch(bluetoothLoader, "toggle");
        }
        function open(): void {
            root.dispatch(bluetoothLoader, "open");
        }
        function close(): void {
            root.dispatch(bluetoothLoader, "close");
            root.scheduleUnload(bluetoothLoader);
        }
        function search(): void {
            root.dispatch(bluetoothLoader, "searchToggle");
        }
    }

    IpcHandler {
        target: "wifi"

        function toggle(): void {
            root.dispatch(wifiLoader, "toggle");
        }
        function open(): void {
            root.dispatch(wifiLoader, "open");
        }
        function close(): void {
            root.dispatch(wifiLoader, "close");
            root.scheduleUnload(wifiLoader);
        }
        function rescan(): void {
            root.dispatch(wifiLoader, "rescan");
        }
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            root.dispatch(clipboardLoader, "toggle");
        }
        function open(): void {
            root.dispatch(clipboardLoader, "open");
        }
        function close(): void {
            root.dispatch(clipboardLoader, "close");
            root.scheduleUnload(clipboardLoader);
        }
        function refresh(): void {
            root.dispatch(clipboardLoader, "refresh");
        }
    }

    IpcHandler {
        target: "wallpaper"

        function toggle(): void {
            root.dispatch(wallpaperLoader, "toggle");
        }
        function open(): void {
            root.dispatch(wallpaperLoader, "open");
        }
        function close(): void {
            root.dispatch(wallpaperLoader, "close");
            root.scheduleUnload(wallpaperLoader);
        }
        function refresh(): void {
            root.dispatch(wallpaperLoader, "refresh");
        }
        // NOTE: no `dbg` shim. Its handler runs a Process declared inside
        // the deferred window (dbgProc), which is unreachable by name from
        // here. It is a leftover debug verb, referenced by no bind or
        // script, so it answers only once the picker has been opened once
        // and the picker's own IpcHandler is alive.
    }

    IpcHandler {
        target: "wallpaper-menu"

        function toggle(): void {
            root.dispatch(wallpaperMenuLoader, "toggle");
        }
        function open(): void {
            root.dispatch(wallpaperMenuLoader, "open");
        }
        function close(): void {
            root.dispatch(wallpaperMenuLoader, "close");
            root.scheduleUnload(wallpaperMenuLoader);
        }
        function next(): void {
            root.dispatch(wallpaperMenuLoader, "next");
        }
        function previous(): void {
            root.dispatch(wallpaperMenuLoader, "previous");
        }
        function random(): void {
            root.dispatch(wallpaperMenuLoader, "random");
        }
        function startAuto(): void {
            root.dispatch(wallpaperMenuLoader, "startAuto");
        }
        function stopAuto(): void {
            root.dispatch(wallpaperMenuLoader, "stopAuto");
        }
        function refreshStatus(): void {
            root.dispatch(wallpaperMenuLoader, "refreshStatus");
        }
    }

    IpcHandler {
        target: "power"

        function toggle(): void {
            root.dispatch(powerLoader, "toggle");
        }
        function open(): void {
            root.dispatch(powerLoader, "open");
        }
        function close(): void {
            root.dispatch(powerLoader, "close");
            root.scheduleUnload(powerLoader);
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.dispatch(launcherLoader, "toggle");
        }
        function open(): void {
            root.dispatch(launcherLoader, "open");
        }
        function close(): void {
            root.dispatch(launcherLoader, "close");
            root.scheduleUnload(launcherLoader);
        }

        // Ctrl+Space parity (`qs -c sunset ipc call launcher preview`).
        function preview(): void {
            root.dispatch(launcherLoader, "preview");
        }
    }

    IpcHandler {
        target: "whip"

        function toggle(): void {
            root.dispatch(whipLoader, "toggle");
        }
        function open(): void {
            root.dispatch(whipLoader, "open");
        }
        function close(): void {
            root.dispatch(whipLoader, "close");
            root.scheduleUnload(whipLoader);
        }
    }

    IpcHandler {
        target: "themes"

        function toggle(): void {
            root.dispatch(themesLoader, "toggle");
        }
        function open(): void {
            root.dispatch(themesLoader, "open");
        }
        function close(): void {
            root.dispatch(themesLoader, "close");
            root.scheduleUnload(themesLoader);
        }
        function next(): void {
            root.dispatch(themesLoader, "next");
        }
        function previous(): void {
            root.dispatch(themesLoader, "previous");
        }
        // The picker's own handler spells this `set` but forwards to root.runItem().
        function set(name: string): void {
            root.dispatch(themesLoader, "runItem", name);
        }
        // Auto-theming is pure Theme state; no window required.
        function autoToggle(): void {
            Theme.toggleAuto();
        }
        function autoOn(): void {
            Theme.setAuto(true);
        }
        function autoOff(): void {
            Theme.setAuto(false);
        }
    }

    IpcHandler {
        target: "sessions"

        function toggle(): void {
            root.dispatch(sessionsLoader, "toggle");
        }
        function open(): void {
            root.dispatch(sessionsLoader, "open");
        }
        function close(): void {
            root.dispatch(sessionsLoader, "close");
            root.scheduleUnload(sessionsLoader);
        }
    }

    IpcHandler {
        target: "screenshots"

        function toggle(): void {
            root.dispatch(screenshotsLoader, "toggle");
        }
        function open(path: string): void {
            root.dispatch(screenshotsLoader, "open", path);
        }
        function openVideo(path: string): void {
            root.dispatch(screenshotsLoader, "openVideo", path);
        }
        function recordStart(path: string): void {
            root.dispatch(screenshotsLoader, "recordStart", path);
        }
        function recordStop(): void {
            root.dispatch(screenshotsLoader, "recordStop");
        }
        function close(): void {
            root.dispatch(screenshotsLoader, "close");
            root.scheduleUnload(screenshotsLoader);
        }
    }

    // ---- eager components -------------------------------------------

    Toasts {
        id: toasts
    }

    // Osd: brightness/volume feedback (XF86MonBrightness*, volume keys).
    Osd {
        id: osd
    }

    // Persistent capture front-end: screenshot/recording/OCR/library triggers.
    // Eager like Toasts/Osd so it maps at startup; owns its `capture` IPC
    // target directly (no LazyLoader shim needed for an eager component).
    CaptureBar {
        id: captureBar
    }


    // Desktop + bar right-click menus (ContextMenu owns the desktop input
    // plane and both menu item sets). Eager on purpose: that input plane
    // must be mapped from startup.
    ContextMenu {
        id: contextMenu
    }

    // NowPlaying slides below the toast stack instead of covering a toast.
    // The popup is lazy, so this binding is declared here and simply waits
    // for the loader to produce an item (Binding with a null target and
    // when:false is inert).
    Binding {
        target: nowPlayingLoader.item
        property: "toastOffset"
        value: toasts.occupiedHeight
        when: nowPlayingLoader.item !== null
    }
    Binding {
        target: nowPlayingLoader.item
        property: "topInset"
        value: root.topInset
        when: nowPlayingLoader.item !== null
    }
    // One corner for hardware state: Bluetooth, Wi-Fi, the mixer, quick
    // settings and now playing all dock top-right under the bar, clear it by
    // `topInset` and slide below a toast stack (`toastOffset`).
    Binding {
        target: bluetoothLoader.item
        property: "toastOffset"
        value: toasts.occupiedHeight
        when: bluetoothLoader.item !== null
    }
    Binding {
        target: bluetoothLoader.item
        property: "topInset"
        value: root.topInset
        when: bluetoothLoader.item !== null
    }
    Binding {
        target: wifiLoader.item
        property: "toastOffset"
        value: toasts.occupiedHeight
        when: wifiLoader.item !== null
    }
    Binding {
        target: wifiLoader.item
        property: "topInset"
        value: root.topInset
        when: wifiLoader.item !== null
    }
    Binding {
        target: volumeLoader.item
        property: "toastOffset"
        value: toasts.occupiedHeight
        when: volumeLoader.item !== null
    }
    Binding {
        target: volumeLoader.item
        property: "topInset"
        value: root.topInset
        when: volumeLoader.item !== null
    }
    Binding {
        target: settingsLoader.item
        property: "toastOffset"
        value: toasts.occupiedHeight
        when: settingsLoader.item !== null
    }
    Binding {
        target: settingsLoader.item
        property: "topInset"
        value: root.topInset
        when: settingsLoader.item !== null
    }
}