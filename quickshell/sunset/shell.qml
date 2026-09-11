// shell.qml — sunset entry point (`qs -c sunset`).
// Quickshell loads <configDir>/sunset/shell.qml for `-c sunset`.
// Repo layout mirrors that: quickshell/sunset/shell.qml.
//
// OWNERSHIP (parallel builders):
//   Builder #1 (this file): ShellRoot wiring + Theme + services contract.
//   Bar builder:             components/Bar.qml
//   Popup builders:          components/CalendarPopup.qml, VolumePopup.qml,
//                            QuickSettings.qml, ClipboardPopup.qml,
//                            WallpaperPicker.qml, PowerMenu.qml
//   Launcher builder:        components/Launcher.qml
//   Toasts builder:          components/Toasts.qml (already landed)
// Do NOT add colors/fonts here — use Theme.* (taste.md tokens).

import Quickshell
import QtQuick
import qs.services
import qs.components

ShellRoot {
    id: root

    // Force singleton instantiation so services connect even before
    // Bar/popup bindings reference them. No visual output.
    Component.onCompleted: {
        // Touch singletons (property read keeps binding, avoids unused-import purge).
        console.info("sunset: NIRI_SOCKET=" + NiriService.socketPath + " audio=" + AudioService.ready);
        console.info("sunset: media=" + MediaService.hasPlayer + " wallpaper=" + WallpaperService.currentPath);
        console.info("sunset: dnd=" + NotificationService.dnd);
    }

    // Top bar (one instance; Bar.qml itself fans out per-screen with Variants).
    Bar {
        id: bar
    }

    // Popups — all hidden by default, toggled by Bar buttons / keybinds.
    // Each is owned by its builder; shell only guarantees single instantiation.
    CalendarPopup {
        id: calendarPopup
    }
    VolumePopup {
        id: volumePopup
    }
    QuickSettings {
        id: quickSettings
    }
    ClipboardPopup {
        id: clipboardPopup
    }
    WallpaperPicker {
        id: wallpaperPicker
    }
    PowerMenu {
        id: powerMenu
    }
    Launcher {
        id: launcher
    }
    Toasts {
        id: toasts
    }
}
