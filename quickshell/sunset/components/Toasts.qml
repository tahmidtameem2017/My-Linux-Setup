// Toasts.qml — sunset notification toasts. Replaces dunst.
//
// Dunst parity (from dunst/dunstrc):
//   geometry 300px wide, origin top-right, offset (25, 25)
//   notification_limit 5 on-screen, history_length 20, sticky_history yes
//   font "JetBrainsMono Nerd Font 11", format "<b>summary</b>\nbody"
//   padding 8, horizontal_padding 8, frame_width 2, corner_radius 0,
//   gap_size 5, icon_position left, min/max icon 64
//   mouse: left close_current, middle do_action+close_current,
//          right close_all
//   urgency_low:    bg #000000e6 fg #F7C7A1 timeout 10
//   urgency_normal: bg #000000e6 fg #F7C7A1 frame #E85D2Fe6 timeout 10
//   urgency_critical: bg #000000e6 fg #F7C7A1 frame #c30505e6 timeout 0 (sticky)
//
// Quickshell mapping:
//   bg #000000e6 -> Theme.bg at 0.9 alpha. NOT the literal "#e6000000": dunst's
//     #000000e6 is "the background colour at 90%", and pinning black froze every
//     toast to sunset under a wallpaper/curated palette.
//   low/normal frame -> Theme.accent (dunst low was #3D2B24, now unified to accent)
//   critical frame -> Theme.danger, sticky (no auto-expire)
//   fg #F7C7A1 -> Theme.text, hint #7C8A6A -> Theme.muted
//   Do NOT run dunst alongside quickshell (both claim org.freedesktop.Notifications).
//
// niri layer-rule doc (do NOT edit rules.kdl here — for the shell owner to add):
//   # Toasts are a quickshell layer-shell popup; keep them out of the
//   # backdrop/screencast and above windows:
//   layer-rule {
//       match namespace="^quickshell$"
//       block-out-from "screencast"
//   }
//   # Verify namespaces while running: `niri msg layers`
//
// IPC: `qs -c sunset ipc call notifications toggleSilent`
//   (flips DND; mirrors `dunstctl set-paused toggle` on Mod+N)

import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import qs.services

Scope {
    id: root

    // DND flag. When true, toasts are hidden but still tracked + kept in history.
    property bool silent: false

    // JS-side history (dunst `history_length 20` + `sticky_history yes`).
    // Holds plain data (max 20, newest first) so history survives dismiss.
    property var history: []
    readonly property int historyLimit: 20
    // Dunst `notification_limit 5`: max toasts on screen at once.
    readonly property int visibleLimit: 5

    // Vertical space the toast stack occupies at the top-right (0 when idle).
    // Other top-right surfaces (NowPlayingPopup) read this to slide below the
    // stack instead of stacking on top of a toast — the toast window itself
    // cannot tell them apart, so the offset is published from here instead.
    readonly property real occupiedHeight: {
        if (silent || server.trackedNotifications.values.length === 0)
            return 0;
        // 8px bottom margin + the 5px inter-toast gap, so a toast never
        // touches the card below it.
        return win.height + 13;
    }

    function pushHistory(n: Notification): void {
        const entry = {
            "app": n.appName,
            "summary": n.summary,
            "body": n.body,
            "urgency": n.urgency.toString(),
            "time": Date.now()
        };
        history = [entry].concat(history).slice(0, historyLimit);
    }

    function dismissAll(): void {
        const vals = server.trackedNotifications.values;
        for (let i = 0; i < vals.length; ++i)
            vals[i].dismiss();
    }

    NotificationServer {
        id: server
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true
        keepOnReload: false

        onNotification: (n) => {
            n.tracked = true;
            root.pushHistory(n);
            // Enforce on-screen cap: dismiss oldest non-critical beyond limit.
            // Critical stays sticky (dunst timeout 0).
            const vals = server.trackedNotifications.values;
            if (vals.length > root.visibleLimit) {
                let victim = null;
                for (let i = 0; i < vals.length; ++i) {
                    if (vals[i].urgency !== NotificationUrgency.Critical) {
                        victim = vals[i];
                        break;
                    }
                }
                (victim ?? vals[0]).dismiss();
            }
        }
    }

    PanelWindow {
        id: win
        anchors {
            top: true
            right: true
        }
        margins {
            top: 25
            right: 25
        }
        implicitWidth: 300
        // Tall enough for `visibleLimit` toasts; ListView clips any overflow.
        implicitHeight: Math.min(toastList.contentHeight, 900)
        exclusiveZone: 0
        color: "transparent"
        visible: !root.silent && server.trackedNotifications.values.length > 0

        ListView {
            id: toastList
            anchors.fill: parent
            spacing: 5 // dunst gap_size
            clip: true
            interactive: false
            model: server.trackedNotifications
            // Micro-animation: slide-in from top-right (x +40->0, 200ms
            // OutCubic) via add; auto-dismiss fade (opacity 1->0, 250ms)
            // via remove + delegate Behavior. Max 5 on-screen, history 20,
            // single NotificationServer owner — all untouched.
            add: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        property: "x"
                        from: 40
                        to: 0
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            }
            displaced: Transition {
                NumberAnimation {
                    properties: "y"
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            remove: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            }
            delegate: Rectangle {
                id: toast
                required property Notification modelData
                required property int index
                width: toastList.width
                // Dynamic height (dunst height 0..300), sharp corners (taste.md).
                height: Math.min(bodyCol.implicitHeight + 16, 300)
                radius: 0
                color: Theme.withAlpha(Theme.bg, 0.9) // dunst #000000e6 = bg at 90%
                border.width: 2 // dunst frame_width
                border.color: toast.isCritical ? Theme.danger : Theme.accent
                clip: true
                // Remove Transition handles the fade (250ms); no delegate
                // Behavior (double fade = 2x frames on weak iGPU).
                opacity: 1
                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }

                readonly property bool isCritical: toast.modelData.urgency === NotificationUrgency.Critical
                // dunst timeouts: 10s low/normal, 0 (sticky) critical.
                // Freedesktop expireTimeout: -1 = server default, 0 = sticky.
                readonly property int timeoutMs: {
                    if (toast.isCritical)
                        return 0;
                    if (toast.modelData.expireTimeout > 0)
                        return Math.round(toast.modelData.expireTimeout * 1000);
                    if (toast.modelData.expireTimeout === 0)
                        return 0;
                    return 10000;
                }

                Timer {
                    interval: toast.timeoutMs
                    running: toast.timeoutMs > 0
                    repeat: false
                    onTriggered: toast.modelData.expire()
                }

                Row {
                    id: row
                    anchors.fill: parent
                    anchors.margins: 8 // dunst padding + horizontal_padding
                    spacing: 8

                    IconImage {
                        id: toastIcon
                        visible: toast.modelData.appIcon !== "" || toast.modelData.image !== ""
                        source: toast.modelData.image !== "" ? toast.modelData.image : toast.modelData.appIcon
                        implicitWidth: 48
                        implicitHeight: 48
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        id: bodyCol
                        width: parent.width - (toastIcon.visible ? toastIcon.width + parent.spacing : 0)
                        spacing: 2
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            width: parent.width
                            text: toast.modelData.summary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pointSize: 11
                            font.bold: true
                            color: Theme.text
                            elide: Text.ElideMiddle
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }
                        Text {
                            width: parent.width
                            visible: toast.modelData.body !== ""
                            text: toast.modelData.body
                            font.family: "JetBrainsMono Nerd Font"
                            font.pointSize: 11
                            color: Theme.text
                            opacity: 0.9
                            elide: Text.ElideMiddle
                            maximumLineCount: 6
                            wrapMode: Text.Wrap
                            textFormat: Text.RichText
                        }
                        Text {
                            // dunst show_indicators parity: hint at URL/action presence.
                            visible: toast.modelData.actions.length > 0
                            text: "[A] " + toast.modelData.actions.length + " action(s) — middle-click to run"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pointSize: 9
                            color: Theme.muted
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            // dunst close_current
                            toast.modelData.dismiss();
                        } else if (mouse.button === Qt.MiddleButton) {
                            // dunst do_action, close_current
                            if (toast.modelData.actions.length > 0)
                                toast.modelData.actions[0].invoke();
                            toast.modelData.dismiss();
                        } else if (mouse.button === Qt.RightButton) {
                            // dunst close_all
                            root.dismissAll();
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "notifications"

        function toggleSilent(): void {
            root.silent = !root.silent;
        }

        function clearAll(): void {
            root.dismissAll();
        }
    }
}
