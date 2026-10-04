// TrayWidgets.qml — thin tray-icon wrappers (waybar image#* modules).
// Bar.qml instantiates the inline components individually to preserve the
// waybar/config right-side order (network | clipboard | wallpaper | settings |
// battery | power; logo goes left). BatteryIcon is kept for *-icon.sh parity
// but Bar.qml prefers BatteryWidget.qml (UPower) so icon+text stay in sync.
//
// Conventions per icon: flat transparent Rectangle (radius 0, no blur,
// no border); hover is a faint Theme.row wash only — no scale (texture
// re-raster cost on weak iGPUs), press is instant. SVG from
// themed assets/icons/theme/<fp>/, hover icon opacity .65 (logo .75, per style.css)
// via Theme.animFast fade. Kept Behaviors are color/opacity only.
// Left clicks that open popups/launcher go through IpcHandler
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
    visible: false
    width: 0
    height: 0

    // Logo (sunset assets/icons/logo.svg 9-square app grid, size 15, hover opacity .75).
    // Live source is the sunset asset (decoupled from waybar/icons rollback gold;
    // waybar/icons/logo.svg is synced to the same glyph for rollback parity).
    // Left + middle -> native Launcher popup (unified fuzzel+walker replacement).
    // Old fuzzel fallback stays on disk for rollback, never launched here.
    component LogoIcon: Rectangle {
        // injected props (inline component scope is isolated)
        property color cBorder: root.cBorder
        property color cBorderStrong: root.cBorderStrong
        property color cPanel: root.cPanel
        id: logoBox
        radius: 0
        // Flat idle (transparent, no border); hover is a faint row wash
        // only. No scale (perf: re-raster cost on weak iGPUs).
        color: logoArea.containsMouse ? Theme.row : "transparent"
        border.width: 0
        implicitWidth: 15 + 24
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Behavior on color {
            ColorAnimation {
                duration: Theme.animHover
                easing.type: Easing.OutCubic
            }
        }

        Image {
            anchors.centerIn: parent
            width: 15
            height: 15
            fillMode: Image.PreserveAspectFit
            source: "file://" + Theme.iconDir + "logo.svg"
            opacity: logoArea.containsMouse ? 0.75 : 1.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animFast
                }
            }
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

    // Network (native WifiService state, no network-icon.sh, no HTML, and no
    // nmtui). Icon: wifi.svg when any wifi/ethernet connection is up, else
    // wifi-off.svg. Click -> the top-right WifiPopup (`wifi` IPC target).
    // The icon state is a binding, not a poll of this file's own: WifiService
    // already asks nmcli the same question on a 30s timer for the whole shell,
    // so a second private poll here could disagree with the card's list.
    component NetworkIcon: Rectangle {
        // injected props (inline component scope is isolated)
        property color cBorder: root.cBorder
        property color cBorderStrong: root.cBorderStrong
        property color cPanel: root.cPanel
        id: netBox
        radius: 0
        // Flat idle (transparent, no border); hover is a faint row wash
        // only. No scale (perf: re-raster cost on weak iGPUs).
        color: netArea.containsMouse ? Theme.row : "transparent"
        border.width: 0
        implicitWidth: 14 + 24
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Behavior on color {
            ColorAnimation {
                duration: Theme.animHover
                easing.type: Easing.OutCubic
            }
        }

        // One WifiService instance for the shell answers this (30s poll of
        // `nmcli radio wifi` + `nmcli dev status`), so this widget costs
        // nothing but a property read.
        readonly property string iconSrc: "file://" + Theme.iconDir + (WifiService.connected ? "wifi.svg" : "wifi-off.svg")

        Image {
            anchors.centerIn: parent
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            source: netBox.iconSrc
            opacity: netArea.containsMouse ? 0.65 : 1.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animFast
                }
            }
        }

        MouseArea {
            id: netArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["qs", "-c", "sunset", "ipc", "call", "wifi", "toggle"])
        }
    }

    // Settings (native QuickSettings popup; no settings.sh / Brave HTML).
    // Left -> IPC `settings`.
    component SettingsIcon: Rectangle {
        // injected props (inline component scope is isolated)
        property color cBorder: root.cBorder
        property color cBorderStrong: root.cBorderStrong
        property color cPanel: root.cPanel
        id: setBox
        radius: 0
        // Flat idle (transparent, no border); hover is a faint row wash
        // only. No scale (perf: re-raster cost on weak iGPUs).
        color: setArea.containsMouse ? Theme.row : "transparent"
        border.width: 0
        implicitWidth: 14 + 24
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Behavior on color {
            ColorAnimation {
                duration: Theme.animHover
                easing.type: Easing.OutCubic
            }
        }

        Image {
            anchors.centerIn: parent
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            source: "file://" + Theme.iconDir + "settings.svg"
            opacity: setArea.containsMouse ? 0.65 : 1.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animFast
                }
            }
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
        // injected props (inline component scope is isolated)
        property color cBorder: root.cBorder
        property color cBorderStrong: root.cBorderStrong
        property color cPanel: root.cPanel
        id: batIconBox
        radius: 0
        // Flat idle (transparent, no border); hover is a faint row wash
        // only. No scale (perf: re-raster cost on weak iGPUs).
        color: batIconArea.containsMouse ? Theme.row : "transparent"
        border.width: 0
        implicitWidth: 14 + 24
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Behavior on color {
            ColorAnimation {
                duration: Theme.animHover
                easing.type: Easing.OutCubic
            }
        }

        visible: batIconBox.iconSrc !== ""

        property string iconSrc: "file://" + Theme.iconDir + "battery.svg"
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
                batIconBox.iconSrc = "file://" + Theme.iconDir + (batIconBox.charging ? "battery-charging.svg" : "battery.svg");
            }
        }

        Image {
            anchors.centerIn: parent
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            source: batIconBox.iconSrc
            opacity: batIconArea.containsMouse ? 0.65 : 1.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animFast
                }
            }
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
        // injected props (inline component scope is isolated)
        property color cBorder: root.cBorder
        property color cBorderStrong: root.cBorderStrong
        property color cPanel: root.cPanel
        id: powerBox
        radius: 0
        // Flat idle (transparent, no border); hover is a faint row wash
        // only. No scale (perf: re-raster cost on weak iGPUs).
        color: powerArea.containsMouse ? Theme.row : "transparent"
        border.width: 0
        implicitWidth: 14 + 24
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter

        Behavior on color {
            ColorAnimation {
                duration: Theme.animHover
                easing.type: Easing.OutCubic
            }
        }

        Image {
            anchors.centerIn: parent
            width: 14
            height: 14
            fillMode: Image.PreserveAspectFit
            source: "file://" + Theme.iconDir + "power.svg"
            opacity: powerArea.containsMouse ? 0.65 : 1.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animFast
                }
            }
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
