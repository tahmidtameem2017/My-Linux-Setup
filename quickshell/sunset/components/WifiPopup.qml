// WifiPopup.qml — dedicated Wi-Fi panel, docked top-right under the bar
// (BluetoothPopup positioning parity: full-screen transparent window, card
// pinned to the top-right corner, slides below toasts via toastOffset).
//
// This used to be the WI-FI section inside QuickSettings, plus a bar icon
// that shelled out to `nmtui connect` in a floating Alacritty. Both are gone:
// the card is its own surface (the same top-right corner as Bluetooth, which
// is where a network list belongs — the centered settings card is for sliders),
// and every action is native nmcli, so there is no terminal to open.
//
// Pure view over WifiService (which owns the nmcli parsing and the action
// processes): the card only decides what a click means.
//
//   left click   -> connect (stored profile, open network) or ask for a
//                   password (secured network we have no profile for);
//                   on the live network it just opens the options
//   right click  -> open the options block for that network
//   options      -> Connect / Disconnect / Forget
//   header       -> rescan (spins while scanning) + radio on/off switch
//
// Shell contract (landed sunset pattern, cf. BluetoothPopup):
//   - exclusiveKeyboardFocus == WlrLayershell.keyboardFocus Exclusive.
//   - Esc closes; outside-click closes; bar re-click toggles via IPC.
//   - Up/Down/Tab walk the list, Enter activates, R rescans. The password
//     field keeps the keys while it has focus (it eats Esc via the parent
//     chain, but Space/arrows must reach the caret, not the list).
//   - Card width 340; height is content-driven.
// IPC: `qs -c sunset ipc call wifi toggle` (also: open, close, rescan)

import QtQuick
import QtQuick.Controls
import Quickshell
// IpcHandler lives in Quickshell.Io (same module as Process/StdioCollector),
// not in Quickshell itself — omitting this fails with "IpcHandler is not a
// type" and silently leaves the popup without IPC.
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    // Theme aliases (inline component scopes cannot see file imports).
    readonly property color cAccent: Theme.accent
    readonly property color cAccentHover: Theme.accentHover
    readonly property color cBg: Theme.bg
    readonly property color cBorder: Theme.border
    readonly property color cBorderStrong: Theme.borderStrong
    readonly property color cDim: Theme.dim
    readonly property string cFont: Theme.fontFamily
    readonly property color cMuted: Theme.muted
    readonly property color cOnAccent: Theme.onAccent
    readonly property color cPanel: Theme.panel
    readonly property int cRadius: Theme.radius
    readonly property color cRow: Theme.row
    readonly property color cText: Theme.text

    property bool isOpen: false
    // Offset from the toast stack (shell.qml wires `toasts.occupiedHeight`).
    property real toastOffset: 0
    // Bar height, from Bar.qml (shell.qml wires `bar.implicitHeight`). The
    // card is anchored to the SCREEN top, so without this it slides under the
    // bar and loses its own header whenever no toast is up.
    property int topInset: 0

    // Network whose options block is open (right-click, or tap on the live
    // network). "" = none.
    property string selectedSsid: ""
    // Network we are waiting on a password for ("" = no field).
    property string pendingSsid: ""
    // Keyboard cursor into WifiService.networks.
    property int kbIndex: 0

    readonly property string repoDir: Quickshell.env("NIRI_SETUP_HOME") ?? (Quickshell.env("HOME") + "/niri-setup")

    function open(): void {
        isOpen = true;
        kbIndex = 0;
        WifiService.startListening();
        focusTimer.restart();
    }
    function close(): void {
        isOpen = false;
        selectedSsid = "";
        pendingSsid = "";
        WifiService.stopListening();
    }
    function toggle(): void {
        if (isOpen)
            close();
        else
            open();
    }
    function rescan(): void {
        WifiService.rescan();
    }

    // ======== row actions ========
    function askPassword(ssid: string): void {
        selectedSsid = ssid;
        pendingSsid = ssid;
        pwInput.text = "";
        pwInput.forceActiveFocus();
    }
    // One tap on a row. The live network opens its options instead of
    // re-connecting (nmcli answers an already-active network with an error).
    function activateNet(net): void {
        if (!net)
            return;
        if (!WifiService.enabled)
            return;
        if (net.active) {
            selectedSsid = (selectedSsid === net.ssid) ? "" : net.ssid;
            return;
        }
        if (net.security && !net.saved) {
            askPassword(net.ssid);
            return;
        }
        selectedSsid = "";
        WifiService.connect(net.ssid, "");
    }
    function selectNet(ssid: string): void {
        selectedSsid = (selectedSsid === ssid) ? "" : ssid;
    }
    function forgetNet(net): void {
        if (!net)
            return;
        WifiService.forget(net.profile !== "" ? net.profile : net.ssid);
        selectedSsid = "";
    }
    function join(): void {
        if (pendingSsid === "")
            return;
        WifiService.connect(pendingSsid, pwInput.text);
        pendingSsid = "";
    }
    // ======== keyboard cursor ========
    function moveKb(dir: int): void {
        const n = WifiService.networks.length;
        if (n === 0) {
            kbIndex = 0;
            return;
        }
        kbIndex = (kbIndex + dir + n) % n;
        netList.positionViewAtIndex(kbIndex, ListView.Contain);
    }

    readonly property string statusText: {
        if (!WifiService.enabled)
            return "Off";
        if (WifiService.ssid !== "")
            return WifiService.ssid;
        // No SSID name but a link is up: a wired connection, or a hidden AP.
        if (WifiService.connected)
            return WifiService.wired ? "On \u00B7 wired" : "On \u00B7 connected";
        return "On \u00B7 not connected";
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: keys.forceActiveFocus()
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
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "sunset-wifi"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            // Pinned top-right under the bar; slides below toasts.
            anchors {
                top: parent.top
                right: parent.right
                topMargin: root.topInset + root.toastOffset
                rightMargin: 0
            }
            implicitWidth: Math.min(340, parent.width - 24)
            implicitHeight: col.implicitHeight + 28
            width: implicitWidth
            height: implicitHeight
            color: root.cPanel
            border.width: 1
            border.color: root.cBorderStrong
            radius: root.cRadius
            transformOrigin: Item.TopRight
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
                    easing.type: Easing.OutCubic
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

                Keys.onEscapePressed: {
                    // A failed join leaves the field open on purpose (the
                    // password was wrong); Esc still closes the card.
                    root.close();
                }
                Keys.onPressed: event => {
                    // The password field owns the keyboard while it has focus
                    // — Space and the arrows belong to the caret.
                    const f = win.activeFocusItem;
                    if (f && f.objectName === "pwEdit")
                        return;
                    if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                        root.moveKb(1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                        root.moveKb(-1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.activateNet(WifiService.networks[root.kbIndex]);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_R) {
                        root.rescan();
                        event.accepted = true;
                    }
                }

                Column {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    // ---- header: rescan + title + radio switch ----
                    Item {
                        width: parent.width
                        height: 22

                        Rectangle {
                            id: scanBtn
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 22
                            radius: root.cRadius
                            color: scanMouse.containsMouse ? root.cRow : "transparent"
                            opacity: WifiService.enabled ? 1.0 : 0.4

                            Image {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                fillMode: Image.PreserveAspectFit
                                source: "file://" + Theme.iconDir + "refresh.svg"
                                opacity: scanMouse.containsMouse ? 0.65 : 1.0

                                RotationAnimation on rotation {
                                    running: WifiService.scanning && !Theme.reduceMotion
                                    from: 0
                                    to: 360
                                    duration: 1200
                                    loops: Animation.Infinite
                                }
                            }
                            MouseArea {
                                id: scanMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.rescan()
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "WI-FI"
                            font.family: root.cFont
                            font.pixelSize: 11
                            font.bold: true
                            color: root.cAccent
                        }

                        Rectangle {
                            id: radioSwitch
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 18
                            radius: 9
                            color: WifiService.enabled ? root.cAccent : root.cRow
                            border.width: 1
                            border.color: WifiService.enabled ? root.cAccent : root.cBorderStrong

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.animFast
                                }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: WifiService.enabled ? parent.width - width - 3 : 3
                                width: 12
                                height: 12
                                radius: 6
                                color: WifiService.enabled ? root.cOnAccent : root.cDim

                                Behavior on x {
                                    NumberAnimation {
                                        duration: Theme.animFast
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: WifiService.toggleRadio()
                            }
                        }
                    }

                    // ---- status + one-line feedback ----
                    Column {
                        width: parent.width
                        spacing: 2
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                            text: root.statusText
                            font.family: root.cFont
                            font.pixelSize: 10
                            color: root.cMuted
                        }
                        Text {
                            width: parent.width
                            visible: WifiService.msg !== ""
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: WifiService.msg
                            font.family: root.cFont
                            font.pixelSize: 10
                            // Errors have no token of their own; the accent is
                            // the palette's only alert colour.
                            color: WifiService.lastError !== "" ? root.cAccent : root.cDim
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.cBorder
                    }

                    // ---- network list ----
                    ListView {
                        id: netList
                        width: parent.width
                        height: Math.min(contentHeight, 240)
                        visible: WifiService.enabled && WifiService.networks.length > 0
                        model: WifiService.networks
                        clip: true
                        interactive: contentHeight > height
                        currentIndex: root.kbIndex

                        ScrollBar.vertical: ScrollBar {
                            contentItem: Rectangle {
                                implicitWidth: 8
                                color: root.cBorderStrong
                                radius: root.cRadius
                            }
                        }

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool kb: index === root.kbIndex
                            // Leave the scrollbar's gutter clear, or a long
                            // list slides the signal% under it.
                            width: ListView.view.width - 10
                            height: 38
                            radius: root.cRadius
                            color: netHover.hovered ? root.cRow : "transparent"
                            // Accent outline = live network, or the keyboard
                            // cursor when it is not the live one.
                            border.width: 1
                            border.color: modelData.active ? root.cAccent : (kb ? root.cAccent : "transparent")

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Text {
                                    width: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: WifiService.signalGlyph(modelData.signal)
                                    font.family: root.cFont
                                    font.pixelSize: 14
                                    color: modelData.active ? root.cAccent : root.cDim
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 20 - 96 - 20
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: (modelData.security ? WifiService.glyphLock + " " : "") + modelData.ssid
                                        font.family: root.cFont
                                        font.pixelSize: 12
                                        color: netHover.hovered ? root.cAccentHover : root.cText
                                    }
                                    Text {
                                        width: parent.width
                                        visible: modelData.active || modelData.saved
                                        elide: Text.ElideRight
                                        text: modelData.active ? "connected" : "saved"
                                        font.family: root.cFont
                                        font.pixelSize: 10
                                        color: root.cMuted
                                    }
                                }
                                Text {
                                    width: 96
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.signal + "%"
                                    font.family: root.cFont
                                    font.pixelSize: 10
                                    color: modelData.active ? root.cAccent : root.cMuted
                                }
                            }

                            HoverHandler {
                                id: netHover
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        root.selectNet(modelData.ssid);
                                        return;
                                    }
                                    root.kbIndex = index;
                                    root.activateNet(modelData);
                                }
                            }
                        }
                    }

                    // ---- off / empty states ----
                    Text {
                        width: parent.width
                        visible: !WifiService.enabled
                        horizontalAlignment: Text.AlignHCenter
                        text: "Wi-Fi is off"
                        font.family: root.cFont
                        font.pixelSize: 11
                        color: root.cMuted
                        topPadding: 6
                        bottomPadding: 6
                    }
                    Text {
                        width: parent.width
                        visible: WifiService.enabled && WifiService.networks.length === 0
                        horizontalAlignment: Text.AlignHCenter
                        text: "No networks found — rescan"
                        font.family: root.cFont
                        font.pixelSize: 11
                        color: root.cMuted
                        topPadding: 6
                        bottomPadding: 6
                    }

                    // ---- options for the picked network ----
                    Column {
                        width: parent.width
                        spacing: 6
                        visible: root.selectedSsid !== ""

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.selectedSsid + " \u2014 options"
                            font.family: root.cFont
                            font.pixelSize: 10
                            font.bold: true
                            color: root.cMuted
                        }
                        Row {
                            width: parent.width
                            spacing: 6
                            RowBtn {
                                label: "Connect"
                                cols: 3
                                onClicked: {
                                    const net = root.netBySsid(root.selectedSsid);
                                    if (net && net.active)
                                        WifiService.activate(net.profile !== "" ? net.profile : net.ssid);
                                    else
                                        root.activateNet(net);
                                }
                            }
                            RowBtn {
                                label: "Disconnect"
                                cols: 3
                                onClicked: {
                                    const net = root.netBySsid(root.selectedSsid);
                                    if (net)
                                        WifiService.disconnect(net.profile !== "" ? net.profile : net.ssid);
                                }
                            }
                            RowBtn {
                                label: "Forget"
                                cols: 3
                                onClicked: root.forgetNet(root.netBySsid(root.selectedSsid))
                            }
                        }
                    }

                    // ---- password entry ----
                    Column {
                        width: parent.width
                        spacing: 6
                        visible: root.pendingSsid !== ""

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: "Password for " + root.pendingSsid
                            font.family: root.cFont
                            font.pixelSize: 10
                            font.bold: true
                            color: root.cMuted
                        }
                        Row {
                            width: parent.width
                            spacing: 6
                            TextField {
                                id: pwInput
                                objectName: "pwEdit"
                                width: parent.width - 76
                                placeholderText: "Password\u2026"
                                echoMode: TextInput.Password
                                font.family: root.cFont
                                font.pixelSize: 12
                                color: root.cText
                                placeholderTextColor: root.cDim
                                background: Rectangle {
                                    color: root.cBg
                                    border.width: 1
                                    border.color: pwInput.activeFocus ? root.cAccent : root.cBorderStrong
                                    radius: root.cRadius
                                }
                                onAccepted: root.join()
                            }
                            RowBtn {
                                label: "Join"
                                cols: 1
                                width: 70
                                h: 30
                                onClicked: root.join()
                            }
                        }
                    }

                    // ---- footer ----
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.cBorder
                        visible: root.selectedSsid !== "" || root.pendingSsid !== ""
                    }
                    Row {
                        width: parent.width
                        spacing: 6
                        RowBtn {
                            label: "Rescan"
                            cols: 2
                            ghost: true
                            h: 28
                            onClicked: root.rescan()
                        }
                        RowBtn {
                            // GNOME owns what a card cannot do: VPNs, hidden
                            // networks, a wired profile, connection secrets.
                            label: "Network Settings"
                            cols: 2
                            ghost: true
                            h: 28
                            onClicked: {
                                Quickshell.execDetached([root.repoDir + "/scripts/gnome-settings.sh", "network"]);
                                root.close();
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "tap to connect \u00B7 right-click for options \u00B7 \u2191\u2193 move \u00B7 R rescan"
                        font.family: root.cFont
                        font.pixelSize: 9
                        color: root.cDim
                    }
                }
            }
        }
    }

    // No return-type annotation: QML has no type for a plain JS object, and
    // declaring one makes it coerce the result to void (see AGENTS.md).
    function netBySsid(ssid) {
        const nets = WifiService.networks;
        for (let i = 0; i < nets.length; ++i) {
            if (nets[i].ssid === ssid)
                return nets[i];
        }
        return null;
    }

    // One button, two skins: filled rows (options block, password Join) and
    // ghost footer rows (Rescan / Network Settings). Declared at the Scope
    // root because an inline `component` inside a Row is only visible to that
    // Row's own subtree — the options and password rows are siblings.
    component RowBtn: Rectangle {
        // injected props (inline component scope is isolated)
        property color cAccentHover: root.cAccentHover
        property color cBorderStrong: root.cBorderStrong
        property string cFont: root.cFont
        property color cMuted: root.cMuted
        property int cRadius: root.cRadius
        property color cRow: root.cRow
        property color cText: root.cText
        id: rBtn
        property string label: ""
        property int cols: 1
        property int gap: 6
        property int h: 30
        property bool ghost: false
        signal clicked
        width: parent ? (parent.width - (cols - 1) * gap) / cols : 100
        height: rBtn.h
        radius: cRadius
        color: ghost ? (btnHover.hovered ? cRow : "transparent") : cRow
        border.width: ghost ? 0 : 1
        border.color: cBorderStrong
        Text {
            anchors.centerIn: parent
            text: rBtn.label
            font.family: rBtn.cFont
            font.pixelSize: 11
            font.bold: !rBtn.ghost
            color: btnHover.hovered ? rBtn.cAccentHover : (rBtn.ghost ? rBtn.cMuted : rBtn.cText)
        }
        HoverHandler {
            id: btnHover
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: rBtn.clicked()
        }
    }

    IpcHandler {
        target: "wifi"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.open();
        }
        function close(): void {
            root.close();
        }
        // Same path as the header button (a bind can trigger a rescan without
        // building the card open just to press it).
        function rescan(): void {
            root.rescan();
        }
    }
}