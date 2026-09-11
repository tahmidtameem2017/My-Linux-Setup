// Workspaces.qml — niri workspaces strip. Repeater over NiriService.workspaces.
// waybar parity (style.css #niri-workspaces):
//   inactive text dim (#555 -> Theme.dim), active black-on-accent
//   (#000 on #E85D2F -> Theme.bg on Theme.accent), hover accent-hover
//   (#FF8B4A -> Theme.accentHover) on border-strong (#3D2B24 -> Theme.borderStrong).
// Click: NiriService.focusWorkspace(idx); fallback when the service method is
// missing: `niri msg action focus-workspace <idx>` (waybar "on-click": "activate").

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

RowLayout {
    id: root
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
            color: ws.isActive ? Theme.accent : "transparent"

            Text {
                id: wsLabel
                anchors.centerIn: parent
                text: String(ws.wsIdx)
                font.family: "JetBrainsMono Nerd Font"
                font.pointSize: 10
                font.bold: true
                color: ws.isActive ? Theme.bg : (wsArea.containsMouse ? Theme.accentHover : Theme.dim)
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
