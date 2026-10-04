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
    readonly property string manageScript: setupHome + "/scripts/manage-wallpaper.sh"
    readonly property string stateFile: setupHome + "/.state/current_wallpaper"

    property string currentPath: ""
    property bool busy: setProc.running || delProc.running || renProc.running
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

    // Delete (trash) a library file. Empty path => current wallpaper.
    // Deleting the current one auto-sets a successor via the script.
    function deleteWallpaper(path) {
        if (delProc.running || renProc.running || setProc.running)
            return;
        lastError = "";
        delProc.targetPath = String(path ?? "");
        delProc.running = true;
    }

    // Rename a library file. Prints the new abs path on stdout (last line).
    function renameWallpaper(path, newName) {
        if (delProc.running || renProc.running || setProc.running)
            return;
        lastError = "";
        renProc.targetPath = String(path);
        renProc.targetName = String(newName);
        renProc.running = true;
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

    // manage-wallpaper.sh delete: stdout last line is "[OK] ...".
    Process {
        id: delProc
        property string targetPath: ""
        command: [root.manageScript, "delete", targetPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                console.info("sunset/WallpaperService delete: " + text.trim().split("\n").pop());
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
                root.refreshCurrent();
            } else if (root.lastError === "") {
                root.lastError = "manage-wallpaper.sh delete exited " + exitCode;
            }
        }
    }

    // manage-wallpaper.sh rename: stdout last line is the new abs path.
    Process {
        id: renProc
        property string targetPath: ""
        property string targetName: ""
        command: [root.manageScript, "rename", targetPath, targetName]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                console.info("sunset/WallpaperService rename: " + text.trim().split("\n").pop());
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
                root.refreshCurrent();
            } else if (root.lastError === "") {
                root.lastError = "manage-wallpaper.sh rename exited " + exitCode;
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
