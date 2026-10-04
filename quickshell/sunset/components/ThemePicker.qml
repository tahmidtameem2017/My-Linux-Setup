// ThemePicker.qml — Omarchy-style curated theme picker (native, no HTML).
//
// Lists the 15 Theme.qml palettes (same order as Theme.order):
//   Sunset Orange, Tokyo Night, Catppuccin Mocha, Gruvbox Dark, Everforest,
//   Kanagawa Wave, Nord, Rosé Pine, Dracula, Matte Black, Wallpaper Match,
//   Wallpaper Vibrant, Wallpaper Muted, Wallpaper Soft, Custom.
// Each row shows the display name + an 11-swatch strip bound to
// Theme.palettes[key] (full token palette) + ✓ on
// Theme.current. Enter applies via Theme.setTheme and STAYS OPEN
// (✓ follows live); Esc / outside click closes.
// Selection starts on first row (Sunset, index 0) on open so the first list item is highlighted orange; ✓ still marks current theme regardless of highlight.
// Wallpaper * swatches follow the last-set wallpaper live (wallust, 4 dark
// tonal variants: vivid, vibrant, muted, and soft). Custom swatches follow
// ~/.local/share/niri-setup/theme-custom.json live.
// Auto toggle: when ON, new wallpapers auto-apply Wallpaper Match.
//
// Suggested trigger (for the binds owner — do NOT edit here):
//   Mod+Alt+T -> `qs -c sunset ipc call themes toggle`
//
// niri layer-rule doc (for the shell owner — do NOT edit rules.kdl here):
//   layer-rule { match namespace="sunset-themes" ... }
//   Verify while running: `niri msg layers`
//
// IPC: `qs -c sunset ipc call themes toggle`
//      (also: open, close, next, previous, set, autoToggle)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    // ---- theme (Theme.qml tokens only, no hex) ----
    readonly property color bg: Theme.bg
    readonly property color textCol: Theme.text
    readonly property color accent: Theme.accent
    readonly property color muted: Theme.muted
    readonly property color selText: Theme.onAccent
    readonly property color selTextDim: Theme.onAccentMuted
    readonly property string fontFamily: Theme.fontFamily
    readonly property int cardRadius: Theme.radius
    readonly property int rowRadius: Theme.radius
    readonly property int menuWidth: 560
    readonly property int rowHeight: 36
    readonly property int pageStep: 5

    property bool isOpen: false
    // Vim `gg` parity: first g arms, second g (within 800ms) goes first.
    property bool gPending: false

    // Same order as Theme.order (kept local so the list renders even
    // if Theme is still loading its persisted value).
    readonly property var themeKeys: ["sunset", "tokyo-night", "catppuccin-mocha", "gruvbox-dark", "everforest", "kanagawa-wave", "nord", "rose-pine", "dracula", "matte-black", "wallpaper", "wallpaper-vibrant", "wallpaper-muted", "wallpaper-soft", "custom"]

    function open() {
        isOpen = true;
        gPending = false;
        menuList.currentIndex = 0;
        menuList.positionViewAtIndex(0, ListView.Contain);
        focusTimer.restart();
    }

    function close() {
        isOpen = false;
    }

    function toggle() {
        if (isOpen)
            close();
        else
            open();
    }

    function runItem(key) {
        if (!key)
            return;
        Theme.setTheme(key);
        // Stay open: ✓ follows Theme.current live via binding.
        const cur = themeKeys.indexOf(Theme.current);
        if (cur !== -1) {
            menuList.currentIndex = cur;
            menuList.positionViewAtIndex(cur, ListView.Contain);
        }
    }

    function activateCurrent() {
        if (menuList.currentIndex < 0 || menuList.currentIndex >= themeKeys.length)
            return;
        runItem(themeKeys[menuList.currentIndex]);
    }

    function next() {
        Theme.nextTheme();
        const cur = themeKeys.indexOf(Theme.current);
        if (cur !== -1) {
            menuList.currentIndex = cur;
            menuList.positionViewAtIndex(cur, ListView.Contain);
        }
    }

    function previous() {
        Theme.prevTheme();
        const cur = themeKeys.indexOf(Theme.current);
        if (cur !== -1) {
            menuList.currentIndex = cur;
            menuList.positionViewAtIndex(cur, ListView.Contain);
        }
    }

    function moveSelection(delta) {
        if (themeKeys.length === 0)
            return;
        root.gPending = false;
        let idx = menuList.currentIndex + delta;
        if (idx < 0)
            idx = 0;
        if (idx >= themeKeys.length)
            idx = themeKeys.length - 1;
        menuList.currentIndex = idx;
        menuList.positionViewAtIndex(idx, ListView.Contain);
    }

    function goFirst() {
        root.gPending = false;
        menuList.currentIndex = 0;
        menuList.positionViewAtIndex(0, ListView.Contain);
    }

    function goLast() {
        root.gPending = false;
        menuList.currentIndex = themeKeys.length - 1;
        menuList.positionViewAtIndex(themeKeys.length - 1, ListView.Contain);
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
        WlrLayershell.namespace: "sunset-themes"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(root.menuWidth, parent.width - 48)
            height: headerText.height + autoRow.height + 8 + menuList.height + footerText.implicitHeight + 64
            radius: root.cardRadius
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
                    text: "  Themes"
                    font.family: root.fontFamily
                    font.pointSize: 13
                    font.bold: true
                    color: root.accent
                }

                Rectangle {
                    id: autoRow
                    width: parent.width
                    height: 36
                    radius: root.rowRadius
                    color: Theme.autoTheming ? root.accent : Theme.panel
                    border.width: 1
                    border.color: Theme.autoTheming ? root.accent : Theme.borderStrong
                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 100
                        verticalAlignment: Text.AlignVCenter
                        text: "Auto: follow wallpaper"
                        font.family: root.fontFamily
                        font.pointSize: 11
                        font.bold: true
                        color: Theme.autoTheming ? root.selText : root.textCol
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 52
                        height: 22
                        radius: 11
                        color: Theme.autoTheming ? root.selText : Theme.row
                        border.width: 1
                        border.color: Theme.autoTheming ? root.selText : Theme.borderStrong

                        Rectangle {
                            width: 16
                            height: 16
                            radius: 8
                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.autoTheming ? parent.width - width - 3 : 3
                            color: Theme.autoTheming ? root.accent : Theme.muted
                            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.InOutQuad } }
                        }

                        Text {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: Theme.autoTheming ? -8 : 8
                            text: Theme.autoTheming ? "ON" : "OFF"
                            font.family: root.fontFamily
                            font.pointSize: 8
                            font.bold: true
                            color: Theme.autoTheming ? root.accent : Theme.muted
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.toggleAuto()
                    }
                }

                ListView {
                    id: menuList
                    width: parent.width
                    height: root.themeKeys.length * root.rowHeight
                    clip: true
                    interactive: false
                    model: root.themeKeys
                    // Full keyboard nav: Up/Down + j/k, Home/End first/last,
                    // PageUp/PageDown ±pageStep, gg first / G last
                    // (vim parity), Enter applies (stay open), Esc closes.
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
                        } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier) === 0) {
                            // Quick auto toggle with 'a'
                            event.accepted = true;
                            Theme.toggleAuto();
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
                        property string themeKey: modelData
                        width: menuList.width
                        height: root.rowHeight
                        radius: root.rowRadius
                        color: menuList.currentIndex === index ? root.accent : "transparent"
                        transformOrigin: Item.Center
                        scale: themeMouse.pressed ? 0.98 : 1.0
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
                            id: nameText
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 300
                            verticalAlignment: Text.AlignVCenter
                            text: Theme.names[row.themeKey] ?? row.themeKey
                            font.family: root.fontFamily
                            font.pointSize: 11
                            font.bold: true
                            color: menuList.currentIndex === index ? root.selText : root.textCol
                            elide: Text.ElideRight
                        }

                        Row {
                            id: swatches
                            anchors.right: checkText.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Repeater {
                                model: ["bg", "panel", "row", "border", "borderStrong", "accent", "accentHover", "text", "muted", "dim", "danger"]
                                Rectangle {
                                    required property string modelData
                                    width: 15
                                    height: 14
                                    color: Theme.legibility(Theme.palettes[row.themeKey])[modelData]
                                    border.width: 1
                                    border.color: root.muted
                                }
                            }
                        }

                        Text {
                            id: checkText
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: Theme.current === row.themeKey ? "✓" : ""
                            font.family: root.fontFamily
                            font.pointSize: 12
                            font.bold: true
                            color: menuList.currentIndex === index ? root.selText : root.accent
                        }

                        MouseArea {
                            id: themeMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            hoverEnabled: true
                            onEntered: menuList.currentIndex = index
                            onClicked: {
                                menuList.currentIndex = index;
                                root.runItem(row.themeKey);
                            }
                        }
                    }
                }

                Text {
                    id: footerText
                    width: parent.width
                    text: "Bar, menus, launcher, terminal, focus ring and the guide follow the theme live" + (Theme.autoTheming ? " — Auto ON" + (Theme.manualTheme ? " (not following)" : "") : " — Auto OFF") + "\nWallpaper * follows the last-set wallpaper via wallust (4 variants), and picking one keeps Auto on." + "\nAny other palette is your own preference and turns Auto off." + "\nCustom: use the Custom Editor, or edit ~/.local/share/niri-setup/theme-custom.json (11 hex keys)"
                    font.family: root.fontFamily
                    font.pointSize: 9
                    color: root.muted
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    IpcHandler {
        target: "themes"

        function toggle() {
            root.toggle();
        }

        function open() {
            root.open();
        }

        function close() {
            root.close();
        }

        function next() {
            root.next();
        }

        function previous() {
            root.previous();
        }

        function set(name: string) {
            root.runItem(name);
        }

        function autoToggle() {
            Theme.toggleAuto();
        }

        function autoOn() {
            Theme.setAuto(true);
        }

        function autoOff() {
            Theme.setAuto(false);
        }
    }
}
