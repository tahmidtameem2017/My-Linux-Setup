// Workspaces.qml — niri workspaces strip. Repeater over NiriService.workspaces.
// waybar parity (style.css #niri-workspaces):
//   inactive text dim (#555 -> root.cDim), active black-on-accent
//   (#000 on #E85D2F -> root.cBg on root.cAccent), hover accent-hover
//   (#FF8B4A -> root.cAccentHover) on border-strong (#3D2B24 -> root.cBorderStrong).
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
    spacing: 0
    Layout.alignment: Qt.AlignVCenter

    Repeater {
        model: NiriService.workspaces

        delegate: Rectangle {
            id: ws
            required property var modelData
            required property int index

            readonly property int wsIdx: modelData.idx ?? modelData.index ?? modelData.id ?? (index + 1)
            readonly property bool isActive: modelData.isActive ?? modelData.is_active ?? modelData.active ?? modelData.focused ?? false

            implicitWidth: Math.max(24, wsLabel.implicitWidth + 16)
            implicitHeight: 24
            radius: 0
            color: ws.isActive ? root.cAccent : "transparent"

            Text {
                id: wsLabel
                anchors.centerIn: parent
                text: String(ws.wsIdx)
                font.family: "JetBrainsMono Nerd Font"
                font.pointSize: 10
                font.bold: true
                color: ws.isActive ? root.cBg : (wsArea.containsMouse ? root.cAccentHover : root.cDim)
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
