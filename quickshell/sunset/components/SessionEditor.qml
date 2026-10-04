// SessionEditor.qml — GUI editor for saved workspace sessions.
// Profiles live in ~/.local/share/niri-setup/sessions/*.json (see
// scripts/session.sh). This popup lists, applies, creates, renames,
// deletes, and edits them — workspaces with app-command rows — without
// touching any config file. Applying opens the profile's apps on the
// CURRENT workspace (groups become columns left-to-right, the view never
// moves) via `session.sh apply` (same engine as Launcher Sessions rows).
//
// Shell contract (like sibling popups): Scope {isOpen + open/close/
// toggle} + Overlay PanelWindow namespace "sunset-sessions" + Exclusive
// keyboard focus while open (text fields need keys) + IpcHandler target
// "sessions" (`qs -c sunset ipc call sessions toggle`).
// Theme tokens only, sharp rects, no blur. All file IO goes through
// session.sh (show/save/remove/list); JSON travels base64 to dodge shell
// quoting entirely. No polling: processes run on open/user action only.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    readonly property string script: "/home/me/niri-setup/scripts/session.sh"
    readonly property string sessDir: Theme.homeDir + "/.local/share/niri-setup/sessions"

    property bool isOpen: false
    property var profiles: []
    property string selected: ""
    // Editable model: {name, workspaces: [{name, apps: [str]}]}.
    property var doc: ({ "name": "", "workspaces": [] })
    property bool dirty: false
    property string status: "Pick a session on the left."

    function open(): void {
        refreshList();
        isOpen = true;
        focusTimer.restart();
    }

    function close(): void {
        isOpen = false;
    }

    function toggle(): void {
        if (isOpen)
            close();
        else
            open();
    }

    function markDirty(msg: string): void {
        root.dirty = true;
        if (msg !== undefined && msg !== "")
            root.status = msg;
    }

    // ---- backend IO (session.sh only) ----
    function refreshList(): void {
        if (!listProc.running)
            listProc.running = true;
    }

    function load(name: string): void {
        if (!name)
            return;
        root.selected = name;
        root.dirty = false;
        loadName = name;
        if (!loadProc.running)
            loadProc.running = true;
    }

    property string loadName: ""
    property string saveB64: ""
    property string saveName: ""
    property string removeName: ""

    function applySelected(): void {
        if (root.selected !== "")
            Quickshell.execDetached([root.script, "apply", root.selected]);
    }

    function newProfile(): void {
        const base = "session";
        let n = base, i = 2;
        while (root.profiles.indexOf(n) !== -1) {
            n = base + i;
            i++;
        }
        root.doc = { "name": n, "workspaces": [{ "name": "main", "apps": [""] }] };
        root.selected = "";
        root.dirty = true;
        root.status = "New session — edit, then Save.";
    }

    function saveDoc(): void {
        const d = root.doc;
        if (!d || !d.name || !/^[A-Za-z0-9_-]+$/.test(d.name)) {
            root.status = "Name must be letters/digits/-/_ (no spaces).";
            return;
        }
        // Drop empty app rows before saving.
        const clean = { "name": d.name, "workspaces": [] };
        for (let i = 0; i < d.workspaces.length; ++i) {
            const w = d.workspaces[i];
            const apps = [];
            for (let a = 0; a < w.apps.length; ++a)
                if (String(w.apps[a]).trim() !== "")
                    apps.push(String(w.apps[a]).trim());
            clean.workspaces.push({ "name": String(w.name || ("ws" + (i + 1))), "apps": apps });
        }
        if (clean.workspaces.length === 0) {
            root.status = "Add at least one workspace.";
            return;
        }
        root.saveName = d.name;
        root.saveB64 = Qt.btoa(unescape(encodeURIComponent(JSON.stringify(clean, null, 2))));
        if (!saveProc.running)
            saveProc.running = true;
    }

    function deleteSelected(): void {
        if (root.selected === "")
            return;
        root.removeName = root.selected;
        if (!removeProc.running)
            removeProc.running = true;
    }

    function captureCurrent(): void {
        root.captureName = "captured";
        if (!captureProc.running)
            captureProc.running = true;
    }

    property string captureName: ""

    function touchDoc(): void {
        // Reassign so Repeaters re-evaluate (plain JS mutation).
        const d = { "name": root.doc.name, "workspaces": [] };
        for (let i = 0; i < root.doc.workspaces.length; ++i) {
            const w = root.doc.workspaces[i];
            d.workspaces.push({ "name": w.name, "apps": w.apps.slice() });
        }
        root.doc = d;
    }

    Process {
        id: listProc
        command: [root.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const lines = String(text).split("\n");
                for (let i = 0; i < lines.length; ++i) {
                    const n = lines[i].trim();
                    if (n !== "")
                        out.push(n);
                }
                root.profiles = out;
                if (root.selected === "" && out.length > 0 && !root.dirty)
                    root.load(out[0]);
            }
        }
    }

    Process {
        id: loadProc
        command: ["bash", "-c", "cat \"" + root.sessDir + "/" + root.loadName + ".json\""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(String(text));
                    if (d && d.name && d.workspaces) {
                        root.doc = d;
                        root.dirty = false;
                        root.status = "Editing '" + d.name + "'.";
                    } else {
                        root.status = "Could not parse " + root.loadName + ".json.";
                    }
                } catch (e) {
                    root.status = "Could not parse " + root.loadName + ".json.";
                }
            }
        }
    }

    Process {
        id: saveProc
        command: [root.script, "save", root.saveName, root.saveB64]
        stdout: StdioCollector {
            onStreamFinished: {
                const ok = String(text).indexOf("[OK]") !== -1;
                if (ok) {
                    // Renamed save: drop the stale file.
                    if (root.selected !== "" && root.selected !== root.saveName)
                        Quickshell.execDetached([root.script, "remove", root.selected]);
                    root.selected = root.saveName;
                    root.dirty = false;
                    root.status = "Saved '" + root.saveName + "'.";
                    root.refreshList();
                } else {
                    root.status = "Save failed: " + String(text).trim();
                }
            }
        }
    }

    Process {
        id: removeProc
        command: [root.script, "remove", root.removeName]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.selected === root.removeName) {
                    root.selected = "";
                    root.doc = { "name": "", "workspaces": [] };
                    root.dirty = false;
                }
                root.status = String(text).trim();
                root.refreshList();
            }
        }
    }

    Process {
        id: captureProc
        command: [root.script, "capture", root.captureName]
        stdout: StdioCollector {
            onStreamFinished: {
                root.status = String(text).trim() + " — fix up app commands, then Save.";
                root.refreshList();
            }
        }
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
        WlrLayershell.namespace: "sunset-sessions"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(760, parent.width - 48)
            height: Math.min(560, parent.height - 48)
            radius: Theme.radius
            color: Theme.bg
            border.width: 2
            border.color: Theme.borderStrong
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

            MouseArea {
                anchors.fill: parent
                onClicked: (mouse) => mouse.accepted = true
            }

            Column {
                id: col
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text {
                    text: "Workspace Sessions" + (root.dirty ? " •" : "")
                    font.family: Theme.fontFamily
                    font.pointSize: 13
                    font.bold: true
                    color: Theme.text
                }

                Row {
                    width: parent.width
                    height: parent.height - 96
                    spacing: 12

                    // ---- left: profile list ----
                    Column {
                        id: leftCol
                        width: 200
                        height: parent.height
                        spacing: 6

                        Repeater {
                            model: root.profiles
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: leftCol.width
                                height: 32
                                radius: 0
                                color: root.selected === modelData ? Theme.accent : (profMouse.containsMouse ? Theme.row : "transparent")
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    text: modelData
                                    font.family: Theme.fontFamily
                                    font.pointSize: 11
                                    font.bold: root.selected === modelData
                                    color: root.selected === modelData ? Theme.bg : Theme.text
                                }
                                MouseArea {
                                    id: profMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.load(modelData)
                                    onDoubleClicked: {
                                        root.load(modelData);
                                        root.applySelected();
                                    }
                                }
                            }
                        }

                        Row {
                            spacing: 6
                            EdBtn {
                                label: "Apply"
                                onFired: root.applySelected()
                            }
                            EdBtn {
                                label: "New"
                                onFired: root.newProfile()
                            }
                        }
                        Row {
                            spacing: 6
                            EdBtn {
                                label: "Delete"
                                danger: true
                                onFired: root.deleteSelected()
                            }
                            EdBtn {
                                label: "Capture"
                                onFired: root.captureCurrent()
                            }
                        }
                        Text {
                            width: leftCol.width
                            text: "Double-click applies."
                            font.family: Theme.fontFamily
                            font.pointSize: 9
                            color: Theme.dim
                            wrapMode: Text.WordWrap
                        }
                    }

                    // ---- right: editor ----
                    Column {
                        id: rightCol
                        width: parent.width - leftCol.width - 12
                        height: parent.height
                        spacing: 8

                        Row {
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Name"
                                font.family: Theme.fontFamily
                                font.pointSize: 11
                                color: Theme.muted
                            }
                            EdField {
                                width: 200
                                text: root.doc.name || ""
                                onEdited: (v) => {
                                    root.doc.name = v;
                                    root.markDirty("");
                                }
                            }
                            EdBtn {
                                label: "Save"
                                accent: true
                                onFired: root.saveDoc()
                            }
                        }

                        Flickable {
                            id: wsFlick
                            width: parent.width
                            height: parent.height - 90
                            contentHeight: wsCol.implicitHeight
                            clip: true
                            Column {
                                id: wsCol
                                width: wsFlick.width
                                spacing: 10
                                Repeater {
                                    model: root.doc.workspaces || []
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        property int wi: index
                                        width: wsCol.width
                                        height: wsInner.implicitHeight + 16
                                        radius: 0
                                        color: Theme.panel
                                        border.width: 1
                                        border.color: Theme.border
                                        Column {
                                            id: wsInner
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 8
                                            spacing: 6
                                            Row {
                                                spacing: 8
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "WS " + (wi + 1)
                                                    font.family: Theme.fontFamily
                                                    font.pointSize: 11
                                                    font.bold: true
                                                    color: Theme.accent
                                                }
                                                EdField {
                                                    width: 160
                                                    text: modelData.name || ""
                                                    onEdited: (v) => {
                                                        root.doc.workspaces[wi].name = v;
                                                        root.markDirty("");
                                                    }
                                                }
                                                Item {
                                                    width: 8
                                                    height: 1
                                                }
                                                EdBtn {
                                                    label: "− ws"
                                                    danger: true
                                                    onFired: {
                                                        root.doc.workspaces.splice(wi, 1);
                                                        root.touchDoc();
                                                        root.markDirty("Workspace removed — Save to keep.");
                                                    }
                                                }
                                            }
                                            Repeater {
                                                model: modelData.apps || []
                                                delegate: Row {
                                                    required property var modelData
                                                    required property int index
                                                    property string appVal: modelData
                                                    property int ai: index
                                                    property int wj: wi
                                                    spacing: 6
                                                    EdField {
                                                        width: wsInner.width - 70
                                                        text: appVal || ""
                                                        placeholder: "command, e.g. brave --new-window"
                                                        onEdited: (v) => {
                                                            root.doc.workspaces[wj].apps[ai] = v;
                                                            root.markDirty("");
                                                        }
                                                    }
                                                    EdBtn {
                                                        label: "×"
                                                        danger: true
                                                        onFired: {
                                                            root.doc.workspaces[wj].apps.splice(ai, 1);
                                                            root.touchDoc();
                                                            root.markDirty("");
                                                        }
                                                    }
                                                }
                                            }
                                            EdBtn {
                                                label: "+ app"
                                                onFired: {
                                                    root.doc.workspaces[wi].apps.push("");
                                                    root.touchDoc();
                                                    root.markDirty("");
                                                }
                                            }
                                        }
                                    }
                                }
                                EdBtn {
                                    label: "+ workspace"
                                    onFired: {
                                        root.doc.workspaces.push({ "name": "ws" + (root.doc.workspaces.length + 1), "apps": [""] });
                                        root.touchDoc();
                                        root.markDirty("");
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    id: statusLine
                    width: parent.width
                    text: root.status
                    font.family: Theme.fontFamily
                    font.pointSize: 10
                    color: Theme.muted
                    elide: Text.ElideRight
                }
            }

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.close()
            }
        }
    }

    // ---- inline atoms (popups convention: no per-file hex, Theme only) ----
    component EdBtn: Rectangle {
        id: btn
        signal fired()
        property string label: ""
        property bool accent: false
        property bool danger: false
        implicitWidth: Math.max(64, btnLabel.implicitWidth + 20)
        implicitHeight: 28
        radius: 0
        color: btn.accent ? Theme.accent : (btnArea.containsMouse ? Theme.row : Theme.panel)
        border.width: 1
        border.color: btn.danger ? Theme.danger : Theme.borderStrong
        Text {
            id: btnLabel
            anchors.centerIn: parent
            text: btn.label
            font.family: Theme.fontFamily
            font.pointSize: 10
            font.bold: btn.accent
            color: btn.accent ? Theme.onAccent : (btn.danger ? Theme.danger : Theme.text)
        }
        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.fired()
        }
        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
    }

    component EdField: Rectangle {
        id: field
        signal edited(string value)
        property alias text: input.text
        property string placeholder: ""
        implicitHeight: 28
        radius: 0
        color: Theme.row
        border.width: 1
        border.color: input.activeFocus ? Theme.accent : Theme.border
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            font.family: Theme.fontFamily
            font.pointSize: 10
            color: Theme.text
            selectionColor: Theme.accent
            selectedTextColor: Theme.bg
            onEditingFinished: field.edited(text)
        }
        Text {
            anchors.fill: input
            verticalAlignment: Text.AlignVCenter
            text: field.placeholder
            font.family: Theme.fontFamily
            font.pointSize: 10
            color: Theme.dim
            visible: input.text === "" && field.placeholder !== ""
        }
        Behavior on border.color {
            ColorAnimation {
                duration: 120
            }
        }
    }

    IpcHandler {
        target: "sessions"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }
    }
}
