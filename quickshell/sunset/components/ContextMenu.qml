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
//   Launcher rows (2026-10-05): the launcher is a context menu host too.
//   Launcher.qml builds its OWN item set per highlighted row (kind decides
//   the items — file rows get Reveal/Terminal/Copy, app+control rows get
//   Pin to top, bookmarks get Delete) and hands it to openRow(). Items there
//   carry `op` instead of `fn`, because the work is a launcher method, not a
//   fixed command: a right click must NEVER be able to run an arbitrary
//   command, so `op` is resolved through the same closed `runLauncherOp`
//   allowlist rather than dispatched by string. Right-clicking the launcher's
//   search box or empty space (not a row) opens helpMenu's "how to use this".
//
//   One menu, three item sets (desktop | bar | caller-supplied), because the
//   launcher's window is top-level like the others: a menu that is a CHILD of
//   the launcher card cannot be positioned in screen coords, cannot take
//   Exclusive keyboard focus off the launcher without ending the launcher's
//   own focusTimer war, and would have to duplicate this whole card.
//
// IPC: `qs -c sunset ipc call menu toggle` (also: openDesktop, openBar,
//      open, close)
//
// Deliberately NO `openRow` verb: a caller-supplied item set cannot cross the
// IPC boundary (QVariant), so such a verb could not carry a menu anyway. The
// launcher reaches openRow() directly through shell.qml, and the keybind
// path is F10 inside the launcher itself.

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
    // Theme.withAlpha(Theme.muted, …) for the same reason Launcher.qml does it:
    // a literal alpha freezes the surface to sunset colours under every other
    // palette. Used for the hint column and for disabled (informational) rows.
    readonly property color cMuted: Theme.withAlpha(Theme.muted, 0.75)
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
    // Which item set is showing: "desktop" | "bar" | "launcher".
    property string menuKind: "desktop"
    property var items: desktopItems
    // Caller-supplied item set (launcher openRow). Set by openRow() and
    // CLEARED on close(), so a stale launcher set can never outlive the menu
    // and later be reopened by an unrelated openDesktop()/openBar() call.
    property var rowItems: null
    // Menu top-left in overlay-window coords (= screen coords).
    property real menuX: 0
    property real menuY: 0
    // Selection index into `items` (skips separators); -1 = none.
    property int current: -1
    // Mouse must not vote until it moves (PowerMenu hoverArmed parity).
    property bool hoverArmed: false
    // Disabled rows (hint text in the launcher's help menu) render muted and
    // cannot be selected or activated, but still count as rows for layout.
    readonly property var shownItems: rowItems !== null ? rowItems : items

    readonly property int rowHeight: 24
    readonly property int menuWidthDesktop: 236
    // Desktop/bar menus are short commands. Launcher menus carry a label AND
    // a chord ("Open in file manager" + "Ctrl+Enter"), which does not fit the
    // narrow desktop width. Derived from the longest label rather than
    // hardcoded, so adding a longer item cannot silently ellipsis it — and it
    // is a readonly BINDING on the data, so there is nothing to keep in sync
    // by hand.
    readonly property int menuWidthLauncher: {
        let w = 236;
        const list = rowItems !== null ? rowItems : [];
        for (let i = 0; i < list.length; ++i) {
            const it = list[i];
            if (!it || it.sep === true)
                continue;
            // ~6.2px per char at 10pt bold monospace + label/hint margins.
            const chars = String(it.label || "").length + String(it.hint || "").length + 3;
            w = Math.max(w, Math.round(chars * 6.2) + 40);
        }
        return Math.min(w, 400);
    }
    readonly property int menuWidth: menuKind === "launcher" ? menuWidthLauncher : menuWidthDesktop

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
        rowItems = null;
        items = desktopItems;
        open(x, y);
    }

    // Bar right click: (x, y) is (click x, bar bottom edge) — anchor the
    // menu just below the bar so it drops down at the click column.
    function openBar(x: real, y: real): void {
        menuKind = "bar";
        rowItems = null;
        items = barItems;
        open(x + 2, y + 2);
    }

    // Launcher right click / F10: the caller passes its OWN item set.
    // `x`/`y` are screen coords, which is what the launcher's PanelWindow
    // mapToItem gives for a point inside its fullscreen surface.
    function openRow(list: var, x: real, y: real): void {
        if (!list || list.length === 0)
            return;
        menuKind = "launcher";
        rowItems = list;
        open(x, y);
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
        // Drop the caller's set: a launcher menu left bound here would be
        // re-shown by the next openDesktop()/openBar() (both of which reset
        // rowItems themselves, but `toggle`/`open` over IPC do not go
        // through them).
        rowItems = null;
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

    // Launcher row menu dispatch: `op` -> the launcher's own rowMenuItem().
    //
    // Closed allowlist for the same reason runOp() is: a right click must
    // never be able to execute an arbitrary command. The launcher builds its
    // item set (rowMenuItems) and this resolves it; neither side can invent
    // an op the other has not heard of. `rowMenuItem` then re-checks the op
    // against ITS own closed set before acting, so this list and that one
    // must agree — scripts/test_launcher_row_menu.py pins that.
    //
    // Named after the launcher rather than reusing runOp(), so a launcher menu
    // can never accidentally execute a desktop-menu command (`lock`,
    // `restart-shell`, …) if the two item sets are ever mixed up.
    //
    // Informational rows (the help menu's key legend) carry NO op at all and
    // land in the final `else return;` — they render, and choosing one does
    // nothing. That is also why `isActionable` skips them.
    function runLauncherOp(op: string): void {
        if (op === undefined || op === null || op === "")
            return;
        launcherIpc("rowMenuItem", String(op));
        close();
    }

    // Resolve `op` on the LAUNCHER root. dispatch() in shell.qml requires the
    // verb name to be a method on the popup root, so `rowMenuItem` must exist
    // as a root method there (2026-10-05) and as a shim in shell.qml's
    // `launcher` IpcHandler — without the shim this is a no-op, exactly like
    // `themes set`.
    //
    // The verb is called with the launcher NOT closed, so an op that is a
    // no-op for the current row (which rowMenuItem's own guards handle) leaves
    // the launcher exactly as it was. close() here is the MENU's close, not
    // the launcher's — they are different surfaces.
    function launcherIpc(verb: string, arg: string): void {
        Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "launcher", verb, arg]);
    }

    function isActionable(i: int): bool {
        if (i < 0 || i >= root.shownItems.length)
            return false;
        // A disabled row (the help menu's key legend) is rendered but never
        // selectable: navigation must be able to step over it, so it is
        // skipped exactly like a separator.
        return root.shownItems[i].sep !== true && root.shownItems[i].disabled !== true;
    }

    function firstIndex(): int {
        const list = root.shownItems;
        for (let i = 0; i < list.length; ++i)
            if (isActionable(i))
                return i;
        return -1;
    }

    function moveSelection(delta: int): void {
        hoverArmed = true;
        const list = root.shownItems;
        if (list.length === 0)
            return;
        let idx = current;
        for (let step = 0; step < list.length; ++step) {
            idx += delta;
            if (idx < 0 || idx >= list.length) {
                idx = current;
                break;
            }
            if (isActionable(idx))
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
        const list = root.shownItems;
        for (let i = list.length - 1; i >= 0; --i)
            if (isActionable(i)) {
                current = i;
                return;
            }
    }

    function activateCurrent(): void {
        if (!isActionable(current))
            return;
        // The launcher set uses `op` (a launcher root method); the desktop and
        // bar sets use `fn` (a fixed command). Two closed allowlists, chosen
        // by which item set is showing — a launcher menu can never execute a
        // desktop command, and vice versa.
        if (menuKind === "launcher")
            runLauncherOp(shownItems[current].op);
        else
            runOp(shownItems[current].fn);
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
                        // shownItems, not items: the launcher hands this menu a
                        // caller-supplied set (openRow) while items still holds
                        // the desktop set.
                        model: root.shownItems
                        delegate: Rectangle {
                            id: row
                            readonly property bool isSep: itemData ? itemData.sep === true : false
                            readonly property bool isDisabled: itemData ? itemData.disabled === true : false
                            readonly property bool isCurrent: root.current === index && !isSep && !isDisabled
                            readonly property bool lit: isCurrent || (mHover.hovered && !isSep && !isDisabled && root.hoverArmed)
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
                                // Right margin leaves room for the hint column
                                // (the launcher's "Enter" / "Ctrl+T" chords),
                                // so a long label never runs under it.
                                anchors.rightMargin: row.itemData && row.itemData.hint ? 64 : 12
                                visible: !row.isSep
                                verticalAlignment: Text.AlignVCenter
                                text: row.itemData && row.itemData.label ? row.itemData.label : ""
                                font.family: root.cFontFamily
                                font.pointSize: 10
                                font.bold: true
                                // Theme.muted for a disabled row: it must read
                                // as a hint, never as something you can click.
                                // A lit row still inverts to cBg on the accent fill
                                // (a disabled row can never be lit, by isActionable).
                                color: row.isDisabled ? root.cMuted : (row.lit ? root.cBg : root.cText)
                                elide: Text.ElideRight
                            }

                            // Right-hand keyboard chord. Keyboard twins are the
                            // point of this menu (a beginner can see the chord
                            // instead of hunting for it), and they double as the
                            // item's own hint when it has no chord.
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !row.isSep && !!(row.itemData && row.itemData.hint)
                                text: row.itemData && row.itemData.hint ? row.itemData.hint : ""
                                font.family: root.cFontFamily
                                font.pointSize: 9
                                color: row.isDisabled ? root.cMuted : (row.lit ? root.cBg : root.cMuted)
                                opacity: row.lit ? 0.85 : 1.0
                            }

                            HoverHandler {
                                id: mHover
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                // A disabled row is not clickable at all, so the
                                // press falls through to the menu's backdrop,
                                // which closes the menu — the same as clicking
                                // outside it.
                                enabled: !row.isSep && !row.isDisabled
                                hoverEnabled: true
                                onEntered: if (root.hoverArmed)
                                    root.current = index
                                onPositionChanged: root.hoverArmed = true
                                onPressed: root.hoverArmed = true
                                onClicked: {
                                    root.current = index;
                                    root.activateCurrent();
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
