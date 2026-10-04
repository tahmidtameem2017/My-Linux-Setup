// WallpaperMenu.qml — thin sunset wallpaper menu. Dispatches to the EXISTING
// wallpaper engine scripts + the NATIVE WallpaperPicker popup (no HTML).
//
// Menu parity (from waybar/scripts/wallpaper-menu.sh — 8 rows, kept):
//   Next      -> scripts/change-wallpaper-simple.sh next
//   Previous  -> scripts/change-wallpaper-simple.sh prev
//   Random    -> scripts/change-wallpaper-simple.sh random
//   Pick...   -> NATIVE WallpaperPicker popup via IPC
//               (qs -c sunset ipc call wallpaper toggle).
//               The old Brave HTML gallery (wallpaper-gallery.sh +
//               wallpaper-server.py on localhost) is NOT invoked anymore;
//               it stays on disk only for rollback.
//   Download  -> float alacritty -e scripts/wallhaven-fetch.sh
//                (alacritty/float.toml, like Mod+Ctrl+W picker terminal)
//   Auto: Start  -> scripts/auto-wallpaper.sh (daemon)
//   Auto: Stop   -> scripts/auto-wallpaper.sh --stop
//   Auto: Status -> scripts/auto-wallpaper.sh --status (output shown in the
//                footer line below; the fuzzel version discarded it)
//
// Fuzzel parity (from fuzzel/wallpaper.ini — KEPT as fallback):
//   lines=8, width=32, prompt="  ", layer=overlay, anchor=center,
//   same Sunset colors.
// Untouched: scripts/wallpaper.sh, auto-wallpaper.sh,
//   change-wallpaper.sh (gum picker), change-wallpaper-simple.sh,
//   wallhaven-fetch.sh. wallpaper-gallery.sh + wallpaper-server.py stay on
//   disk for rollback but are never launched from Quickshell.
//
// Suggested trigger (for the binds/bar owner — do NOT edit here):
//   waybar wallpaper module today runs wallpaper-menu.sh; point it at:
//     `qs -c sunset ipc call wallpaper-menu toggle`
//
// niri layer-rule doc (for the shell owner — do NOT edit rules.kdl here):
//   layer-rule { match namespace="sunset-wallpaper" ... }
//   Verify while running: `niri msg layers`
//
// IPC: `qs -c sunset ipc call wallpaper-menu toggle`
//      (also: open, close, next, previous, random, startAuto, stopAuto,
//       refreshStatus)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    // ---- theme (Theme.qml Sunset Orange AMOLED tokens only, no hex) ----
    readonly property color bg: Theme.bg
    readonly property color textCol: Theme.text
    readonly property color accent: Theme.accent
    readonly property color muted: Theme.muted
    readonly property color selText: Theme.onAccent
    readonly property string fontFamily: Theme.fontFamily
    readonly property int cardRadius: Theme.radius
    readonly property int rowRadius: Theme.radius
    readonly property int menuWidth: 520 // fuzzel wallpaper width=32
    readonly property int rowHeight: 34 // fuzzel line-height=34
    readonly property int pageStep: 4 // half the 8-row list

    readonly property string repoHome: "/home/me/niri-setup"
    readonly property string simpleScript: repoHome + "/scripts/change-wallpaper-simple.sh"
    // NOTE: no galleryScript — Pick... opens the native WallpaperPicker popup
    // via IPC (zero HTML/Brave). Old HTML gallery kept on disk for rollback only.
    readonly property string wallhavenScript: repoHome + "/scripts/wallhaven-fetch.sh"
    readonly property string autoScript: repoHome + "/scripts/auto-wallpaper.sh"
    readonly property string floatConf: repoHome + "/alacritty/float.toml"

    property bool isOpen: false
    property string statusText: ""
    // Vim `gg` parity: first g arms, second g (within 800ms) goes first.
    property bool gPending: false

    // Same 8 rows, same order, same labels as wallpaper-menu.sh.
    property var items: [
        {
            "label": "Next",
            "fn": "next"
        },
        {
            "label": "Previous",
            "fn": "prev"
        },
        {
            "label": "Random",
            "fn": "random"
        },
        {
            "label": "Pick...",
            "fn": "pick"
        },
        {
            "label": "Download",
            "fn": "download"
        },
        {
            "label": "Auto: Start",
            "fn": "start"
        },
        {
            "label": "Auto: Stop",
            "fn": "stop"
        },
        {
            "label": "Auto: Status",
            "fn": "status"
        }
    ]

    function open(): void {
        isOpen = true;
        gPending = false;
        menuList.currentIndex = 0;
        refreshStatus();
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

    function runItem(item): void {
        if (!item)
            return;
        const fn = item.fn;
        if (fn === "next")
            next();
        else if (fn === "prev")
            previous();
        else if (fn === "random")
            random();
        else if (fn === "pick") {
            root.close();
            Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "wallpaper", "open"]);
        } else if (fn === "download")
            Quickshell.execDetached(["alacritty", "--config-file", root.floatConf, "-e", root.wallhavenScript]);
        else if (fn === "start")
            Quickshell.execDetached([root.autoScript]);
        else if (fn === "stop")
            Quickshell.execDetached([root.autoScript, "--stop"]);
        else if (fn === "status")
            refreshStatus();
        // Pick/Download open their own UI, Status stays for its footer;
        // the rest just switch the wallpaper and dismiss.
        if (fn === "next" || fn === "prev" || fn === "random" || fn === "start" || fn === "stop")
            close();
    }

    function activateCurrent(): void {
        if (menuList.currentIndex < 0 || menuList.currentIndex >= items.length)
            return;
        runItem(items[menuList.currentIndex]);
    }

    function next(): void {
        Quickshell.execDetached([root.simpleScript, "next"]);
    }

    function previous(): void {
        Quickshell.execDetached([root.simpleScript, "prev"]);
    }

    function random(): void {
        Quickshell.execDetached([root.simpleScript, "random"]);
    }

    function startAuto(): void {
        Quickshell.execDetached([root.autoScript]);
    }

    function stopAuto(): void {
        Quickshell.execDetached([root.autoScript, "--stop"]);
    }

    function refreshStatus(): void {
        root.statusText = "…";
        statusProc.exec({
            "command": [root.autoScript, "--status"]
        });
    }

    function moveSelection(delta: int): void {
        if (items.length === 0)
            return;
        root.gPending = false;
        let idx = menuList.currentIndex + delta;
        if (idx < 0)
            idx = 0;
        if (idx >= items.length)
            idx = items.length - 1;
        menuList.currentIndex = idx;
        menuList.positionViewAtIndex(idx, ListView.Contain);
    }

    function goFirst(): void {
        root.gPending = false;
        menuList.currentIndex = 0;
        menuList.positionViewAtIndex(0, ListView.Contain);
    }

    function goLast(): void {
        root.gPending = false;
        menuList.currentIndex = items.length - 1;
        menuList.positionViewAtIndex(items.length - 1, ListView.Contain);
    }

    function goIndex(i: int): void {
        root.gPending = false;
        if (i < 0 || i >= items.length)
            return;
        menuList.currentIndex = i;
        menuList.positionViewAtIndex(i, ListView.Contain);
    }

    Timer {
        id: gTimer
        interval: 800
        repeat: false
        onTriggered: root.gPending = false
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: menuList.forceActiveFocus()
    }

    Process {
        id: statusProc
        stdout: SplitParser {
            onRead: (data) => {
                if (root.statusText === "…")
                    root.statusText = data;
                else
                    root.statusText += "\n" + data;
            }
        }
    }

    PanelWindow {
        id: win
        visible: root.isOpen
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        // fuzzel layer=overlay; take no bar space.
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "sunset-wallpaper"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(root.menuWidth, parent.width - 48)
            // Content-driven: header + 8 rows + status. All terms intrinsic.
            height: headerText.height + menuList.height + (root.statusText !== "" ? statusText.implicitHeight : 0) + 56
            radius: root.cardRadius // Theme.radius (sharp sunset cards)
            color: root.bg
            border.width: 2
            border.color: root.accent
            // Micro-animation: subtle entrance (opacity 150ms OutCubic +
            // scale 0.96->1 180ms OutBack overshoot 1.2 + y -6->0).
            // Close stays instant (visible flips with isOpen, <200ms).
            transformOrigin: Item.Center
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

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                Text {
                    id: headerText
                    width: parent.width
                    // fuzzel wallpaper prompt="  " + menu purpose.
                    text: "  Wallpaper"
                    font.family: root.fontFamily
                    font.pointSize: 13
                    font.bold: true
                    color: root.accent
                }

                ListView {
                    id: menuList
                    width: parent.width
                    height: root.items.length * root.rowHeight
                    clip: true
                    // All 8 rows fit; keep non-scrollable but add an
                    // explicit WheelHandler below so wheel moves selection.
                    interactive: false
                    model: root.items
                    // Full keyboard nav: Up/Down + j/k, Home/End first/last,
                    // PageUp/PageDown ±pageStep, 1..8 jump, gg first / G
                    // last (vim parity), Enter activates, Esc closes.
                    Keys.onPressed: (event) => {
                        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                        if (event.key === Qt.Key_Escape) {
                            event.accepted = true;
                            root.gPending = false;
                            root.close();
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                            event.accepted = true;
                            root.moveSelection(-1);
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                            event.accepted = true;
                            root.moveSelection(1);
                        } else if (event.key === Qt.Key_Home) {
                            event.accepted = true;
                            root.goFirst();
                        } else if (event.key === Qt.Key_End) {
                            event.accepted = true;
                            root.goLast();
                        } else if (event.key === Qt.Key_PageUp) {
                            event.accepted = true;
                            root.moveSelection(-root.pageStep);
                        } else if (event.key === Qt.Key_PageDown) {
                            event.accepted = true;
                            root.moveSelection(root.pageStep);
                        } else if (event.key === Qt.Key_G) {
                            event.accepted = true;
                            if (shift) {
                                root.goLast();
                            } else if (root.gPending) {
                                root.goFirst();
                            } else {
                                root.gPending = true;
                                gTimer.restart();
                            }
                        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_8) {
                            event.accepted = true;
                            root.goIndex(event.key - Qt.Key_1);
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            event.accepted = true;
                            root.gPending = false;
                            root.activateCurrent();
                        }
                    }
                    WheelHandler {
                        // Wheel moves selection (list fits, no scroll).
                        onWheel: (event) => {
                            if (event.angleDelta.y < 0)
                                root.moveSelection(1);
                            else if (event.angleDelta.y > 0)
                                root.moveSelection(-1);
                        }
                    }

                    delegate: Rectangle {
                        id: row
                        property var itemData: modelData
                        width: menuList.width
                        height: root.rowHeight
                        radius: root.rowRadius
                        color: menuList.currentIndex === index ? root.accent : "transparent"
                        transformOrigin: Item.Center
                        scale: wmenuMouse.pressed ? 0.98 : 1.0
                        Behavior on scale {
                            NumberAnimation {
                                duration: 100
                                easing.type: Easing.OutQuad
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            verticalAlignment: Text.AlignVCenter
                            text: row.itemData ? row.itemData.label : ""
                            font.family: root.fontFamily
                            font.pointSize: 11
                            font.bold: true
                            color: menuList.currentIndex === index ? root.selText : root.textCol
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: wmenuMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            hoverEnabled: true
                            onEntered: menuList.currentIndex = index
                            onClicked: {
                                menuList.currentIndex = index;
                                root.runItem(row.itemData);
                            }
                        }
                    }
                }

                Text {
                    id: statusText
                    width: parent.width
                    visible: root.statusText !== ""
                    text: root.statusText
                    font.family: root.fontFamily
                    font.pointSize: 10
                    color: root.muted
                    maximumLineCount: 3
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    IpcHandler {
        target: "wallpaper-menu"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        function next(): void {
            root.next();
        }

        function previous(): void {
            root.previous();
        }

        function random(): void {
            root.random();
        }

        function startAuto(): void {
            root.startAuto();
        }

        function stopAuto(): void {
            root.stopAuto();
        }

        function refreshStatus(): void {
            root.refreshStatus();
        }
    }
}
