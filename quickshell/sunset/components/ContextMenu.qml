// ContextMenu.qml — right-click menus for the desktop and the status bar.
//
//   Desktop: a transparent input plane on the layer-shell BOTTOM layer
//   ("desktop background", above swaybg wallpaper, below windows). Right
//   click on any visible wallpaper opens the desktop menu at the cursor;
//   left click is a no-op (closes an open menu). Compositor-level niri
//   binds (incl. any WheelScroll*) are intercepted before this surface
//   sees them, so nothing is lost by sitting under the pointer here.
//   Note: the plane is ABOVE swaybg even when swaybg restarts (wallpaper
//   change) because bottom > background in the layer-shell stack order.
//
//   Bar: Bar.qml emits contextMenuRequested(x, y) on right click and
//   shell.qml routes it here -> openBar() below the click point. Widgets
//   that claim the right button themselves (VolumeWidget mute, Pomodoro)
//   keep their behavior; the event falls through to the bar handler
//   everywhere else.
//
//   Row sets (desktopItems / barItems below) are plain text rows. The
//   clipboard + wallpaper rows here are where the removed bar icons went,
//   so the features stay reachable now that TrayWidgets.ClipboardIcon /
//   WallpaperIcon are gone.
//
//   Menu parity (thin dispatcher, WallpaperMenu/PowerMenu card pattern):
//   rows are text-only, sharp Theme tokens, keyboard nav (Up/Down + j/k,
//   Home/End, Enter/Space, Esc), hover follows mouse only after movement
//   (hoverArmed parity), actions go through the established IPC dispatch
//   `qs -c sunset ipc call <target> open` or a fixed command allowlist.
//
// niri layer-rule doc (for the shell owner — do NOT edit rules.kdl here):
//   layer-rule { match namespace="sunset-desktop" }
//   layer-rule { match namespace="sunset-context-menu" }
//   Verify while running: `niri msg layers`
//
// IPC: `qs -c sunset ipc call menu toggle` (also: openDesktop, openBar,
//      open, close)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    // ---- theme (Theme.qml Sunset Orange AMOLED tokens only, no hex) ----
    readonly property color cAccent: Theme.accent
    readonly property color cAccentHover: Theme.accentHover
    readonly property color cBg: Theme.bg
    readonly property color cBorder: Theme.border
    readonly property color cBorderStrong: Theme.borderStrong
    readonly property string cFontFamily: Theme.fontFamily
    readonly property color cPanel: Theme.panel
    readonly property int cRadius: Theme.radius
    readonly property color cText: Theme.text

    readonly property string setupHome: Quickshell.env("NIRI_SETUP_HOME") ?? (Quickshell.env("HOME") + "/niri-setup")
    readonly property string simpleScript: setupHome + "/scripts/change-wallpaper-simple.sh"
    readonly property string swaylockScript: setupHome + "/scripts/swaylock.sh"
    // External (non-quickshell) target since 2026-10-02: help/index.html
    // replaced the native Help Center popup. The script self-toggles.
    readonly property string openHelpScript: setupHome + "/scripts/open-help.sh"

    property bool isOpen: false
    // Which item set is showing: "desktop" | "bar".
    property string menuKind: "desktop"
    property var items: desktopItems
    // Menu top-left in overlay-window coords (= screen coords).
    property real menuX: 0
    property real menuY: 0
    // Selection index into `items` (skips separators); -1 = none.
    property int current: -1
    // Mouse must not vote until it moves (PowerMenu hoverArmed parity).
    property bool hoverArmed: false

    readonly property int rowHeight: 24
    readonly property int menuWidth: 236

    // Right-click on the desktop. Dispatcher rows only; destructive power
    // actions live behind "Power..." (own confirm-to-run popup).
    readonly property var desktopItems: [
        {
            "label": "Terminal",
            "fn": "terminal"
        },
        {
            "label": "App Launcher",
            "fn": "launcher"
        },
        {
            "sep": true
        },
        {
            "label": "Next Wallpaper",
            "fn": "wall-next"
        },
        {
            "label": "Random Wallpaper",
            "fn": "wall-random"
        },
        {
            "label": "Wallpaper Gallery...",
            "fn": "wall-gallery"
        },
        {
            "label": "Clipboard",
            "fn": "clipboard"
        },
        {
            "label": "Screenshot",
            "fn": "capture"
        },
        {
            "label": "Themes...",
            "fn": "themes"
        },
        {
            "label": "Help & Guide",
            "fn": "help"
        },
        {
            "sep": true
        },
        {
            "label": "Lock",
            "fn": "lock"
        },
        {
            "label": "Power...",
            "fn": "power"
        }
    ]

    // Right-click on the status bar.
    readonly property var barItems: [
        {
            "label": "Themes...",
            "fn": "themes"
        },
        {
            "label": "Help & Guide",
            "fn": "help"
        },
        {
            "sep": true
        },
        {
            "label": "Next Wallpaper",
            "fn": "wall-next"
        },
        {
            "label": "Random Wallpaper",
            "fn": "wall-random"
        },
        {
            "label": "Wallpaper Gallery...",
            "fn": "wall-gallery"
        },
        {
            "sep": true
        },
        {
            "label": "Clipboard",
            "fn": "clipboard"
        },
        {
            "label": "Screenshot",
            "fn": "capture"
        },
        {
            "sep": true
        },
        {
            "label": "Lock",
            "fn": "lock"
        },
        {
            "label": "Power...",
            "fn": "power"
        },
        {
            "sep": true
        },
        {
            "label": "Restart Shell",
            "fn": "restart-shell"
        }
    ]

    function openDesktop(x: real, y: real): void {
        menuKind = "desktop";
        items = desktopItems;
        open(x, y);
    }

    // Bar right click: (x, y) is (click x, bar bottom edge) — anchor the
    // menu just below the bar so it drops down at the click column.
    function openBar(x: real, y: real): void {
        menuKind = "bar";
        items = barItems;
        open(x + 2, y + 2);
    }

    function open(x: real, y: real): void {
        menuX = x;
        menuY = y;
        current = firstIndex();
        hoverArmed = false;
        isOpen = true;
        focusTimer.restart();
    }

    function close(): void {
        isOpen = false;
        hoverArmed = false;
    }

    function toggle(): void {
        if (isOpen)
            close();
        else
            openDesktop(640, 360);
    }

    // Fixed allowlist dispatch (fn string -> action). Unknown fn: never
    // execute anything (PowerMenu allowlist parity).
    function runOp(fn: string): void {
        if (fn === "terminal")
            Quickshell.execDetached(["alacritty"]);
        else if (fn === "launcher")
            Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "launcher", "open"]);
        else if (fn === "wall-next")
            Quickshell.execDetached([root.simpleScript, "next"]);
        else if (fn === "wall-random")
            Quickshell.execDetached([root.simpleScript, "random"]);
        else if (fn === "wall-gallery")
            Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "wallpaper", "open"]);
        else if (fn === "clipboard")
            Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "clipboard", "open"]);
        else if (fn === "capture")
            Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "capture", "toggle"]);
        else if (fn === "themes")
            Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "themes", "open"]);
        else if (fn === "help")
            Quickshell.execDetached(["sh", "-c", root.openHelpScript]);
        else if (fn === "lock")
            Quickshell.execDetached(["bash", root.swaylockScript]);
        else if (fn === "power")
            Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "power", "open"]);
        else if (fn === "restart-shell")
            Quickshell.execDetached(["sh", "-c", "pkill quickshell; quickshell -c sunset &"]);
        else
            return;
        close();
    }

    function isActionable(i: int): bool {
        return i >= 0 && i < items.length && items[i].sep !== true;
    }

    function firstIndex(): int {
        for (let i = 0; i < items.length; ++i)
            if (items[i].sep !== true)
                return i;
        return -1;
    }

    function moveSelection(delta: int): void {
        hoverArmed = true;
        if (items.length === 0)
            return;
        let idx = current;
        for (let step = 0; step < items.length; ++step) {
            idx += delta;
            if (idx < 0 || idx >= items.length) {
                idx = current;
                break;
            }
            if (items[idx].sep !== true)
                break;
        }
        if (isActionable(idx))
            current = idx;
    }

    function goFirst(): void {
        hoverArmed = true;
        current = firstIndex();
    }

    function goLast(): void {
        hoverArmed = true;
        for (let i = items.length - 1; i >= 0; --i)
            if (items[i].sep !== true) {
                current = i;
                return;
            }
    }

    function activateCurrent(): void {
        if (!isActionable(current))
            return;
        runOp(items[current].fn);
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: keys.forceActiveFocus()
    }

    // ---- desktop input plane (layer-shell bottom: above wallpaper, below
    // windows). Right click opens the menu at the cursor; everything else
    // is a no-op. Windows keep all their input: this only ever sees the
    // wallpaper gaps. ----
    PanelWindow {
        id: desktopLayer
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "sunset-desktop"

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (mouse) => {
                if (mouse.button === Qt.RightButton)
                    root.openDesktop(mouse.x, mouse.y);
            }
        }
    }

    // ---- menu popup (WallpaperMenu/PowerMenu card pattern, placed at the
    // cursor instead of centered; clamped to stay on screen). ----
    PanelWindow {
        id: menuWin
        visible: root.isOpen
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "sunset-context-menu"

        MouseArea {
            id: backdrop
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: root.close()
        }

        Rectangle {
            id: card
            // Content-driven height; clamped into the visible area.
            width: root.menuWidth
            height: col.implicitHeight + 12
            x: Math.max(8, Math.min(root.menuX, backdrop.width - width - 8))
            y: Math.max(8, Math.min(root.menuY, backdrop.height - height - 8))
            color: root.cPanel
            border.width: 1
            border.color: root.cBorderStrong
            radius: root.cRadius
            // Subtle entrance (popup pattern: opacity + scale + y); close
            // stays instant (visible flips with isOpen).
            transformOrigin: Item.TopLeft
            scale: root.isOpen ? 1.0 : 0.96
            opacity: root.isOpen ? 1 : 0
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
                Keys.onEscapePressed: root.close()
                // Keyboard nav (PowerMenu parity): Up/Down + j/k, Home/End
                // first/last, Enter/Space activates, Esc closes.
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
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
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        event.accepted = true;
                        root.activateCurrent();
                    }
                }
                Keys.onTabPressed: event => {
                    event.accepted = true;
                    root.moveSelection(1);
                }
                Keys.onBacktabPressed: event => {
                    event.accepted = true;
                    root.moveSelection(-1);
                }

                Column {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 6

                    Repeater {
                        model: root.items
                        delegate: Rectangle {
                            id: row
                            readonly property bool isSep: itemData ? itemData.sep === true : false
                            readonly property bool isCurrent: root.current === index && !isSep
                            readonly property bool lit: isCurrent || (mHover.hovered && !isSep && root.hoverArmed)
                            property var itemData: modelData
                            width: col.width
                            height: isSep ? 6 : root.rowHeight
                            color: lit ? root.cAccent : "transparent"
                            radius: root.cRadius
                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }

                            Rectangle {
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: parent.left
                                    right: parent.right
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                visible: row.isSep
                                height: 1
                                color: root.cBorder
                            }

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                visible: !row.isSep
                                verticalAlignment: Text.AlignVCenter
                                text: row.itemData && row.itemData.label ? row.itemData.label : ""
                                font.family: root.cFontFamily
                                font.pointSize: 10
                                font.bold: true
                                color: row.lit ? root.cBg : root.cText
                                elide: Text.ElideRight
                            }

                            HoverHandler {
                                id: mHover
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                visible: !row.isSep
                                hoverEnabled: true
                                onEntered: if (root.hoverArmed)
                                    root.current = index
                                onPositionChanged: root.hoverArmed = true
                                onPressed: root.hoverArmed = true
                                onClicked: {
                                    root.current = index;
                                    root.runOp(row.itemData.fn);
                                }
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

    IpcHandler {
        target: "menu"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.openDesktop(640, 360);
        }
        function openDesktop(): void {
            root.openDesktop(640, 360);
        }
        function openBar(): void {
            root.openBar(320, 34);
        }
        function close(): void {
            root.close();
        }
    }
}
