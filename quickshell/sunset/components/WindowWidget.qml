// WindowWidget.qml — focused-window title (waybar custom/window).
// Polls `niri msg -j windows` via Process every 1s (waybar interval 1,
// exec window_info.py). Ports that script's logic:
//   - focused window's app_id/title; nothing focused -> "Desktop"
//   - Alacritty passes the title through verbatim (terminal tools)
//   - otherwise a friendly name via the JS map below (the script's
//     Gio.DesktopAppInfo lookup); unmapped ids fall back to the last
//     dotted segment capitalized, like the script.
// waybar parity: muted text (Theme.muted), hover peach (Theme.text).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

Rectangle {
    id: root
    implicitWidth: Math.min(winLabel.implicitWidth + 28, 420)
    implicitHeight: 24
    radius: 0
    color: "transparent"
    Layout.alignment: Qt.AlignVCenter

    property string title: "Desktop"

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

    Process {
        id: winPoll
        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector {
            id: winOut
            onStreamFinished: {
                try {
                    const wins = JSON.parse(winOut.text);
                    let focused = null;
                    for (const w of wins) {
                        if (w.is_focused) {
                            focused = w;
                            break;
                        }
                    }
                    if (!focused) {
                        root.title = "Desktop";
                        return;
                    }
                    const appId = focused.app_id ?? "";
                    const winTitle = focused.title ?? "";
                    if (appId === "Alacritty" && winTitle)
                        root.title = winTitle;
                    else if (appId)
                        root.title = root.friendlyName(appId);
                    else
                        root.title = "Desktop";
                } catch (e) {
                    root.title = "Desktop";
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: winPoll.running = true
    }

    Text {
        id: winLabel
        anchors.centerIn: parent
        width: Math.min(implicitWidth, 392)
        text: root.title
        font.family: "JetBrainsMono Nerd Font"
        font.pointSize: 10
        color: winHover.containsMouse ? Theme.text : Theme.muted
        elide: Text.ElideRight
    }

    MouseArea {
        id: winHover
        anchors.fill: parent
        hoverEnabled: true
    }
}
