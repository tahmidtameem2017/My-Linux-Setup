// TrayWidgets.qml — thin tray-icon wrappers (waybar image#* modules).
// Bar.qml instantiates the inline components individually to preserve the
// waybar/config right-side order (network | clipboard | wallpaper | settings |
// battery | power; logo goes left). BatteryIcon is kept for *-icon.sh parity
// but Bar.qml prefers BatteryWidget.qml (UPower) so icon+text stay in sync.
//
// Conventions per icon: sharp Rectangle (Theme.panel/border, radius 0, no
// blur), SVG from waybar/icons/*.svg, hover opacity .65 (logo .75, per
// style.css). Left clicks that open popups/launcher go through IpcHandler
// targets (`qs -c sunset ipc call <target> toggle`); middle/scroll actions
// call scripts/*.sh + waybar/scripts/*.sh paths verbatim (noted per icon).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.services

Item {
    id: root
    visible: false
    width: 0
    height: 0

    // Logo (waybar image#logo: logo.svg, size 15, hover opacity .75).
    // Left + middle -> native Launcher popup (unified fuzzel+walker replacement).
    // Old fuzzel fallback stays on disk for rollback, never launched here.
    component LogoIcon: Rectangle {
        id: logoBox
        radius: 0
        color: Theme.panel
        border.width: 1
        border.color: logoArea.containsMouse ? Theme.borderStrong : Theme.border
        implicitWidth: 15 + 24
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Image {
            anchors.centerIn: parent
            width: 15
            height: 15
            fillMode: Image.PreserveAspectFit
            source: "file:///home/me/niri-setup/waybar/icons/logo.svg"
            opacity: logoArea.containsMouse ? 0.75 : 1.0
        }

        MouseArea {
            id: logoArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: (mouse) => {
                Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "launcher", "toggle"]);
            }
        }
    }

    // Network (native: nmcli directly, no network-icon.sh, no HTML).
    // Icon: wifi.svg when any active wifi/ethernet connection, else wifi-off.svg.
    // Click: alacritty float nmtui connect (terminal tool Quickshell keeps).
    component NetworkIcon: Rectangle {
        id: netBox
        radius: 0
        color: Theme.panel
        border.width: 1
        border.color: netArea.containsMouse ? Theme.borderStrong : Theme.border
        implicitWidth: 14 + 24
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter

        property string iconSrc: "file:///home/me/niri-setup/waybar/icons/wifi.svg"
        property string tooltipText: ""

        Process {
            id: netPoll
            command: ["nmcli", "-t", "-f", "TYPE,STATE", "device", "status"]
            stdout: StdioCollector {
                id: netOut
                onStreamFinished: {
                    const txt = netOut.text;
                    const online = /(wifi|ethernet):connected/.test(txt);
                    netBox.iconSrc = online ? "file:///home/me/niri-setup/waybar/icons/wifi.svg" : "file:///home/me/niri-setup/waybar/icons/wifi-off.svg";
                }
            }
        }

        Timer {
            interval: 10000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: netPoll.running = true
        }

        Image {
            anchors.centerIn: parent
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            source: netBox.iconSrc
            opacity: netArea.containsMouse ? 0.65 : 1.0
        }

        MouseArea {
            id: netArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["alacritty", "--title", "nmtui", "--config-file", "/home/me/niri-setup/alacritty/float.toml", "-e", "nmtui", "connect"])
        }
    }

    // Clipboard (native ClipboardPopup; no cliphist-fuzzel dmenu, no HTML).
    // Left -> IPC `clipboard`. Middle: clear-clipboard.sh (kept engine script).
    component ClipboardIcon: Rectangle {
        id: clipBox
        radius: 0
        color: Theme.panel
        border.width: 1
        border.color: clipArea.containsMouse ? Theme.borderStrong : Theme.border
        implicitWidth: 14 + 24
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Image {
            anchors.centerIn: parent
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            source: "file:///home/me/niri-setup/waybar/icons/clipboard.svg"
            opacity: clipArea.containsMouse ? 0.65 : 1.0
        }

        MouseArea {
            id: clipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.MiddleButton)
                    Quickshell.execDetached(["/home/me/niri-setup/scripts/clear-clipboard.sh"]);
                else
                    Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "clipboard", "toggle"]);
            }
        }
    }

    // Wallpaper (native WallpaperPicker popup; no gallery.sh / Brave HTML).
    // Left -> IPC `wallpaper`. Middle/scroll: change-wallpaper-simple.sh
    //   random (middle), next (scroll-up), prev (scroll-down) — kept engine.
    component WallpaperIcon: Rectangle {
        id: wallBox
        radius: 0
        color: Theme.panel
        border.width: 1
        border.color: wallArea.containsMouse ? Theme.borderStrong : Theme.border
        implicitWidth: 14 + 24
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Image {
            anchors.centerIn: parent
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            source: "file:///home/me/niri-setup/waybar/icons/wallpaper.svg"
            opacity: wallArea.containsMouse ? 0.65 : 1.0
        }

        MouseArea {
            id: wallArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.MiddleButton)
                    Quickshell.execDetached(["/home/me/niri-setup/scripts/change-wallpaper-simple.sh", "random"]);
                else
                    Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "wallpaper", "toggle"]);
            }
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                if (event.angleDelta.y > 0)
                    Quickshell.execDetached(["/home/me/niri-setup/scripts/change-wallpaper-simple.sh", "next"]);
                else if (event.angleDelta.y < 0)
                    Quickshell.execDetached(["/home/me/niri-setup/scripts/change-wallpaper-simple.sh", "prev"]);
            }
        }
    }

    // Settings (native QuickSettings popup; no settings.sh / Brave HTML).
    // Left -> IPC `settings`.
    component SettingsIcon: Rectangle {
        id: setBox
        radius: 0
        color: Theme.panel
        border.width: 1
        border.color: setArea.containsMouse ? Theme.borderStrong : Theme.border
        implicitWidth: 14 + 24
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Image {
            anchors.centerIn: parent
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            source: "file:///home/me/niri-setup/waybar/icons/settings.svg"
            opacity: setArea.containsMouse ? 0.65 : 1.0
        }

        MouseArea {
            id: setArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "settings", "toggle"])
        }
    }

    // Battery icon (native UPower; no battery-icon.sh polling).
    // Empty (desktop, no battery) collapses the icon. Click:
    //   alacritty float btop (terminal tool Quickshell keeps).
    // NOTE: Bar.qml uses BatteryWidget.qml (UPower) instead, so icon+text stay
    // in sync; this wrapper is kept for layout parity only.
    component BatteryIcon: Rectangle {
        id: batIconBox
        radius: 0
        color: Theme.panel
        border.width: 1
        border.color: batIconArea.containsMouse ? Theme.borderStrong : Theme.border
        implicitWidth: 14 + 24
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter

        visible: batIconBox.iconSrc !== ""

        property string iconSrc: "file:///home/me/niri-setup/waybar/icons/battery.svg"
        property bool charging: false

        // Native UPower binding; polled refresh keeps desktop-hide semantics
        // without shelling out to battery-icon.sh every 30s.
        Timer {
            interval: 30000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                const dev = UPower.displayDevice;
                const ok = dev && dev.isPresent && !dev.isLaptopBattery !== undefined ? true : (dev && dev.isPresent);
                // DisplayDevice.isPresent false on desktops -> collapse icon.
                if (!dev || !dev.isPresent) {
                    batIconBox.iconSrc = "";
                    return;
                }
                batIconBox.charging = (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged);
                batIconBox.iconSrc = batIconBox.charging ? "file:///home/me/niri-setup/waybar/icons/battery-charging.svg" : "file:///home/me/niri-setup/waybar/icons/battery.svg";
            }
        }

        Image {
            anchors.centerIn: parent
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            source: batIconBox.iconSrc
            opacity: batIconArea.containsMouse ? 0.65 : 1.0
        }

        MouseArea {
            id: batIconArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["alacritty", "--config-file", "/home/me/niri-setup/alacritty/float.toml", "-e", "btop"])
        }
    }

    // Power (native PowerMenu popup; no Brave HTML, no wlogout).
    // Left + middle -> IpcHandler `power`. wlogout stays on disk for rollback only.
    component PowerIcon: Rectangle {
        id: powerBox
        radius: 0
        color: Theme.panel
        border.width: 1
        border.color: powerArea.containsMouse ? Theme.borderStrong : Theme.border
        implicitWidth: 14 + 24
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Image {
            anchors.centerIn: parent
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            source: "file:///home/me/niri-setup/waybar/icons/power.svg"
            opacity: powerArea.containsMouse ? 0.65 : 1.0
        }

        MouseArea {
            id: powerArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: (mouse) => {
                Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "power", "toggle"]);
            }
        }
    }
}
