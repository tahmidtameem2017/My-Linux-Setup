// WindowWidget.qml — focused-window title (waybar custom/window).
// Event-driven via NiriService (EventStream socket, zero polling):
//   - NiriService.activeWindowTitle/AppId track the focused window live.
//   - Alacritty passes the title through verbatim (terminal tools)
//   - otherwise a friendly name via the JS map below (the script's
//     Gio.DesktopAppInfo lookup); unmapped ids fall back to the last
//     dotted segment capitalized, like the script.
// waybar parity: muted text (root.cMuted), hover peach (root.cText).

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

Rectangle {
    id: root
    // Theme aliases (nested scopes cannot see file imports).
    readonly property color cAccent: Theme.accent
    readonly property color cAccentHover: Theme.accentHover
    readonly property color cBg: Theme.bg
    readonly property color cBorder: Theme.border
    readonly property color cBorderStrong: Theme.borderStrong
    readonly property color cDim: Theme.dim
    readonly property string cFontFamily: Theme.fontFamily
    readonly property color cMuted: Theme.muted
    readonly property color cPanel: Theme.panel
    readonly property int cRadius: Theme.radius
    readonly property color cRow: Theme.row
    readonly property color cText: Theme.text
    implicitWidth: Math.min(winLabel.implicitWidth + 28, 420)
    implicitHeight: 24
    radius: 0
    color: "transparent"
    Layout.alignment: Qt.AlignVCenter
    // No width/opacity Behaviors here (perf): width tracks the title on
    // every focus change, animating it is layout thrash; the label fade
    // below is the only motion and runs only on title change.

    // Live from the event stream (no poll, no fork, no 2s staleness).
    // NiriService falls back to the focused workspace's active window
    // when nothing is keyboard-focused (empty-workspace "Desktop").
    readonly property string focusedTitle: NiriService.activeWindowTitle
    readonly property string focusedAppId: NiriService.activeWindowAppId

    property string title: {
        if (root.focusedAppId === "Alacritty" && root.focusedTitle !== "" && root.focusedTitle !== "Desktop")
            return root.focusedTitle;
        // Chromium app/PWA windows carry a synthetic app-id
        // (brave-<32-char extension id>-Profile when installed, or
        // brave-<host>__-Profile for --app=URL). Neither is human
        // readable and the dotted-segment fallback below would print the
        // raw id, so use the page title ("YouTube", "WhatsApp Web").
        if (root.isChromiumAppWindow(root.focusedAppId) && root.focusedTitle !== "" && root.focusedTitle !== "Desktop")
            return root.focusedTitle;
        if (root.focusedAppId !== "")
            return root.friendlyName(root.focusedAppId);
        return "Desktop";
    }

    // Installed PWA: browser-<32 chars a-p>-Profile. --app=URL: browser-<host>__-Profile.
    // Deliberately excludes plain "brave-browser"/"chromium" (no __ or a-p id).
    function isChromiumAppWindow(appId: string): bool {
        return appId !== "" && (/-[a-p]{32}-/.test(appId) || /-[a-z0-9.-]+__-/.test(appId));
    }

    // Fade the label on title change (elide stays).
    onTitleChanged: {
        winLabel.opacity = 0.35;
        titleFade.restart();
    }

    Timer {
        id: titleFade
        interval: Theme.animHover
        onTriggered: winLabel.opacity = 1.0
    }

    // Gio.DesktopAppInfo fallback as a JS map (common ids; the generic
    // fallback below covers everything else, as in window_info.py).
    function friendlyName(appId: string): string {
        const known = {
            "firefox": "Firefox",
            "chromium": "Chromium",
            "brave-browser": "Brave",
            "org.gnome.Nautilus": "Files",
            "org.gnome.Console": "Console",
            "Alacritty": "Alacritty",
            "kitty": "Kitty",
            "discord": "Discord",
            "spotify": "Spotify",
            "org.telegram.desktop": "Telegram",
            "code": "Code"
        };
        if (known[appId])
            return known[appId];
        const last = appId.split(".").pop();
        return last.charAt(0).toUpperCase() + last.slice(1);
    }

    Text {
        id: winLabel
        anchors.centerIn: parent
        width: Math.min(implicitWidth, 392)
        text: root.title
        font.family: "JetBrainsMono Nerd Font"
        font.pointSize: 10
        color: winHover.containsMouse ? root.cText : root.cMuted
        elide: Text.ElideRight

        Behavior on color {
            ColorAnimation {
                duration: Theme.animHover
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animHover
            }
        }
    }

    MouseArea {
        id: winHover
        anchors.fill: parent
        hoverEnabled: true
    }
}
