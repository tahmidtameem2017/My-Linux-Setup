// Workspaces.qml — niri workspaces strip. Repeater over NiriService.workspaces.
// waybar parity (style.css #niri-workspaces):
//   inactive text dim (#555 -> root.cDim), active black-on-accent
//   (Theme.onAccent on Theme.accent - the pill text colour is MEASURED against
//   the accent fill, never assumed to be the background), hover accent-hover
//   (#FF8B4A -> root.cAccentHover). Flat idle (transparent, no borders);
//   hover is a faint row wash + accentHover text + 2px underline.
// Click: NiriService.focusWorkspace(idx); fallback when the service method is
// missing: `niri msg action focus-workspace <idx>` (waybar "on-click": "activate").

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

RowLayout {
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
    spacing: 4
    Layout.alignment: Qt.AlignVCenter

    Repeater {
        model: NiriService.workspaces

        delegate: Rectangle {
            id: ws
            required property var modelData
            required property int index

            readonly property int wsIdx: modelData.idx ?? modelData.index ?? modelData.id ?? (index + 1)
            readonly property bool isActive: modelData.is_focused ?? modelData.isActive ?? modelData.is_active ?? modelData.active ?? modelData.focused ?? false

            implicitWidth: Math.max(24, wsLabel.implicitWidth + 16)
            implicitHeight: 24
            radius: 0
            // Flat idle: active keeps accent fill, inactive is transparent
            // with a faint row wash on hover only (no boxes, no borders,
            // no scale — re-raster cost on weak iGPUs).
            color: ws.isActive ? root.cAccent : (wsArea.containsMouse ? root.cRow : "transparent")
            border.width: 0

            Behavior on color {
                ColorAnimation {
                    duration: Theme.animHover
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                id: wsLabel
                anchors.centerIn: parent
                text: String(ws.wsIdx)
                font.family: "JetBrainsMono Nerd Font"
                font.pointSize: 10
                font.bold: true
                color: ws.isActive ? Theme.onAccent : (wsArea.containsMouse ? root.cAccentHover : root.cDim)

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animHover
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // Active/hover underline: cheap 2px opacity fade (no x tracking
            // needed in a Repeater, no slide anim).
            // Active fill is accent, so the underline is black-on-accent;
            // hover on an inactive pill previews in accentHover.
            Rectangle {
                id: wsUnderline
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: 2
                color: ws.isActive ? Theme.onAccent : root.cAccentHover
                opacity: ws.isActive ? 1.0 : (wsArea.containsMouse ? 0.6 : 0.0)

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.animHover
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animHover
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MouseArea {
                id: wsArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (typeof NiriService.focusWorkspace === "function")
                        NiriService.focusWorkspace(ws.wsIdx);
                    else
                        Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(ws.wsIdx)]);
                }
            }
        }
    }
}
