pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// WallpaperService.qml — thin Process wrapper over repo scripts.
//   scripts/wallpaper.sh <path>       (slow: magick backdrop regen, ~1-2min)
//   scripts/auto-wallpaper.sh --next | --oneshot | --status | --stop
// Waybar parity: bar wallpaper button left = gallery popup,
//   middle = random, scroll up/down = next/prev (change-wallpaper-simple.sh).
// WallpaperPicker builder owns the gallery UI; this service owns execution
// + busy state so the UI can disable double-clicks while magick runs.
Singleton {
    id: root

    readonly property string setupHome: Quickshell.env("NIRI_SETUP_HOME") ?? (Quickshell.env("HOME") + "/niri-setup")
    readonly property string setScript: setupHome + "/scripts/wallpaper.sh"
    readonly property string autoScript: setupHome + "/scripts/auto-wallpaper.sh"
    readonly property string stateFile: setupHome + "/.state/current_wallpaper"

    property string currentPath: ""
    property bool busy: setProc.running
    property string lastError: ""
    property string daemonStatus: ""

    function setWallpaper(path) {
        if (!path || setProc.running)
            return;
        lastError = "";
        setProc.targetPath = String(path);
        setProc.running = true;
    }

    function next() {
        lastError = "";
        nextProc.running = true;
    }

    function random() {
        // auto-wallpaper --next pops the shuffled queue (random-ish).
        next();
    }

    function refreshCurrent() {
        readProc.running = true;
    }

    function daemonStatusRefresh() {
        statusProc.running = true;
    }

    // Long-running set (timeout 300s per taste.md — server parity).
    Process {
        id: setProc
        property string targetPath: ""
        command: [root.setScript, targetPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                // wallpaper.sh prints "[OK] Wallpaper set: ..." on success.
                console.info("sunset/WallpaperService set: " + text.trim().split("\n").pop());
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.lastError = text.trim().split("\n").pop();
            }
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.currentPath = targetPath;
            } else if (root.lastError === "") {
                root.lastError = "wallpaper.sh exited " + exitCode;
            }
        }
    }

    Process {
        id: nextProc
        command: [root.autoScript, "--next"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.refreshCurrent();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.lastError = text.trim().split("\n").pop();
            }
        }
    }

    Process {
        id: readProc
        command: ["cat", root.stateFile]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t !== "")
                    root.currentPath = t;
            }
        }
    }

    Process {
        id: statusProc
        command: [root.autoScript, "--status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.daemonStatus = text.trim();
            }
        }
    }

    Component.onCompleted: refreshCurrent()
}
