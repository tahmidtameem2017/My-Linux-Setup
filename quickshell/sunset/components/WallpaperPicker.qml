// WallpaperPicker.qml — visual wallpaper gallery popup.
//
// Replaces: waybar/wallpaper/wallpaper.html + wallpaper-server.py +
//           launcher waybar/scripts/wallpaper-gallery.sh + Brave profile
//           ~/.cache/niri-wallpaper (old app-id brave-localhost__-Default,
//           window 760x560, backend on localhost). The Brave profile, the
//           wallpaper-server.py daemon and the localhost backend are all
//           deleted by this migration; nothing else needs them.
//           (components/WallpaperMenu.qml stays: it is the thin 8-row script
//           menu, a different frontend over the same scripts.)
//
// Backend parity (from wallpaper-server.py):
//   library -> ~/Pictures/Wallpapers, top level, sorted, exts
//              jpg/jpeg/png/webp/avif (FolderListModel, Name sort).
//   current -> .state/current_wallpaper basename, watched live via
//              FileView (external sets via menu/scroll re-highlight).
//   thumbs  -> magick <src>[0] -auto-orient -thumbnail 384x216 <cache>
//              in ~/.cache/niri-wallpaper/thumbs (<basename>.jpg),
//              original on failure (server parity, incl. lazy gen).
//   set     -> scripts/wallpaper.sh <abs path> via WallpaperService
//              (same slow magick backdrop pipeline; busy disables Set).
//   action  -> random|next|prev via scripts/change-wallpaper-simple.sh.
//   auto    -> start spawns scripts/auto-wallpaper.sh detached,
//              stop runs it with --stop, status via --status (server parity).
// Image ids are model indexes, never client paths (server parity).
//
// Shell contract (landed sunset pattern, cf. ClipboardPopup/Launcher):
//   - exclusiveKeyboardFocus == WlrLayershell.keyboardFocus Exclusive.
//   - Esc closes; click previews, double-click sets; outside-click closes;
//     Bar re-click toggles via IPC.
//   - Card width 760 (old 760x560 window); height is content-driven.
//   - niri layer-rule doc (shell owner adds, do NOT edit rules.kdl here):
//       layer-rule { match namespace="sunset-wallpaper-picker" }
//     Verify: `niri msg layers`
// IPC: `qs -c sunset ipc call wallpaper toggle` (also: open, close, refresh)

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    property bool isOpen: false
    // Task term "exclusiveKeyboardFocus" == the Exclusive layer-shell
    // keyboard focus set on the PanelWindow below.
    readonly property bool exclusiveKeyboardFocus: true

    function open(): void {
        isOpen = true;
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
    function refresh(): void {
        currentFile.reload();
        WallpaperService.refreshCurrent();
        WallpaperService.daemonStatusRefresh();
        statusProc.refresh();
    }

    // ---- paths ----
    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string repoDir: Quickshell.env("NIRI_SETUP_HOME") ?? (homeDir + "/niri-setup")
    readonly property string wallDir: homeDir + "/Pictures/Wallpapers"
    readonly property string thumbDir: (Quickshell.env("NIRI_WALLPAPER_DIR") ?? (homeDir + "/.cache/niri-wallpaper")) + "/thumbs"
    readonly property string stepScript: repoDir + "/scripts/change-wallpaper-simple.sh"
    readonly property var imgFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.avif", "*.JPG", "*.JPEG", "*.PNG", "*.WEBP", "*.AVIF"]

    // ---- state ----
    property string currentAbs: "" // from FileView below (trimmed)
    property string currentBase: ""
    property string selPath: ""
    property string selUrl: ""
    property string selName: ""
    property string msg: ""
    property bool autoOn: false

    function baseName(p: string): string {
        const i = p.lastIndexOf("/");
        return i >= 0 ? p.slice(i + 1) : p;
    }
    function say(t: string): void {
        msg = t;
    }

    FolderListModel {
        id: folder
        folder: "file://" + root.wallDir
        nameFilters: root.imgFilters
        showDirs: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
        onCountChanged: root.ensureSelection()
    }

    // Watches the same state file scripts/wallpaper.sh writes, so sets made
    // elsewhere (menu, scroll binds, daemon) re-highlight live.
    FileView {
        id: currentFile
        path: WallpaperService.stateFile
        watchChanges: true
        onLoaded: {
            const t = text().trim();
            root.currentAbs = t;
            root.currentBase = root.baseName(t);
            root.ensureSelection();
        }
        onLoadFailed: {
            root.currentAbs = "";
            root.currentBase = "";
        }
        onFileChanged: reload()
    }

    function ensureSelection(): void {
        if (folder.count === 0)
            return;
        // Keep a valid selection; prefer the current wallpaper.
        let idx = -1;
        if (currentAbs !== "") {
            for (let i = 0; i < folder.count; ++i) {
                if (folder.get(i, "filePath") === currentAbs) {
                    idx = i;
                    break;
                }
            }
        }
        if (idx < 0 && selPath !== "") {
            for (let j = 0; j < folder.count; ++j) {
                if (folder.get(j, "filePath") === selPath) {
                    idx = j;
                    break;
                }
            }
        }
        if (idx < 0)
            idx = 0;
        select(idx, true);
    }

    function select(i: int, quiet: bool): void {
        if (i < 0 || i >= folder.count)
            return;
        selPath = folder.get(i, "filePath");
        selUrl = folder.get(i, "fileURL");
        selName = folder.get(i, "fileName");
    }

    function setWallpaper(path: string): void {
        if (!path || WallpaperService.busy)
            return;
        say("Setting wallpaper\u2026");
        WallpaperService.setWallpaper(path);
    }

    function step(op: string): void {
        stepProc.op = op;
        stepProc.running = true;
    }

    Process {
        id: stepProc
        property string op: ""
        command: [root.stepScript, op]
        running: false
        onExited: {
            currentFile.reload();
            WallpaperService.refreshCurrent();
            say("\u2713 " + op + ": " + root.currentBase);
        }
    }

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.thumbDir]
        running: false
    }

    // ---- auto-wallpaper daemon ----
    Process {
        id: statusProc
        command: [WallpaperService.autoScript, "--status"]
        running: false
        stdout: StdioCollector {
            id: statusOut
            onStreamFinished: {
                const first = text.trim().split("\n")[0] ?? "";
                root.autoOn = first.toLowerCase().indexOf("running") !== -1;
            }
        }
        function refresh(): void {
            if (!running)
                running = true;
        }
    }
    Process {
        id: stopProc
        command: [WallpaperService.autoScript, "--stop"]
        running: false
        onExited: {
            statusProc.refresh();
            say("\u2713 Auto-wallpaper stopped");
        }
    }
    Timer {
        id: statusTimer
        interval: 5000
        running: root.isOpen
        repeat: true
        onTriggered: statusProc.refresh()
    }

    // Reflect service results in the footer line.
    Connections {
        target: WallpaperService
        function onBusyChanged(): void {
            if (!WallpaperService.busy && WallpaperService.lastError === "" && root.msg === "Setting wallpaper\u2026") {
                currentFile.reload();
                root.say("\u2713 Wallpaper set: " + root.currentBase);
            } else if (!WallpaperService.busy && WallpaperService.lastError !== "") {
                root.say("\u2717 " + WallpaperService.lastError);
            }
        }
    }

    Component.onCompleted: {
        mkdirProc.running = true;
        currentFile.reload();
        statusProc.refresh();
    }

    onIsOpenChanged: {
        if (isOpen) {
            currentFile.reload();
            statusProc.refresh();
        }
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
        WlrLayershell.namespace: "sunset-wallpaper-picker"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            // Old Brave window was 760 wide; height is content-driven.
            implicitWidth: Math.min(760, parent.width - 32)
            implicitHeight: Math.min(col.implicitHeight + 24, parent.height - 48)
            width: implicitWidth
            height: implicitHeight
            color: Theme.panel
            border.width: 1
            border.color: Theme.borderStrong
            radius: Theme.radius

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.close()

                Column {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 14
                    anchors.bottomMargin: 10
                    spacing: 0

                    // ---- header ----
                    Row {
                        width: parent.width
                        spacing: 10
                        Text {
                            text: "WALLPAPERS"
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: true
                            color: Theme.accent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            width: parent.width - parent.spacing - 110
                            elide: Text.ElideRight
                            text: folder.count + " wallpapers \u00B7 current: " + (root.currentBase !== "" ? root.currentBase : "\u2014")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.muted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Item {
                        width: parent.width
                        height: 8
                    }

                    // ---- preview ----
                    Rectangle {
                        width: parent.width
                        height: 190
                        color: Theme.bg
                        border.width: 1
                        border.color: Theme.borderStrong
                        radius: Theme.radius
                        Image {
                            anchors.fill: parent
                            source: root.selUrl
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 34
                            color: Theme.bg
                            opacity: 0.85
                            radius: Theme.radius
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.right: setBtn.left
                            anchors.bottom: parent.bottom
                            height: 34
                            leftPadding: 8
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: root.selName !== "" ? root.selName : "\u2014"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.text
                        }
                        Rectangle {
                            id: setBtn
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 5
                            width: 130
                            height: 24
                            color: setHover.hovered && !WallpaperService.busy ? Theme.accentHover : Theme.accent
                            radius: Theme.radius
                            opacity: WallpaperService.busy ? 0.5 : 1
                            Text {
                                anchors.centerIn: parent
                                text: WallpaperService.busy ? "Setting\u2026" : "Set wallpaper"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                color: Theme.bg
                            }
                            HoverHandler {
                                id: setHover
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.setWallpaper(root.selPath)
                            }
                        }
                    }
                    Item {
                        width: parent.width
                        height: 10
                    }

                    // ---- toolbar ----
                    Row {
                        width: parent.width
                        spacing: 8
                        SunsetBtn {
                            cols: 5
                            gap: 8
                            label: "󰁈 Prev"
                            onClicked: root.step("prev")
                        }
                        SunsetBtn {
                            cols: 5
                            gap: 8
                            label: "󰁒 Random"
                            onClicked: root.step("random")
                        }
                        SunsetBtn {
                            cols: 5
                            gap: 8
                            label: "󰁔 Next"
                            onClicked: root.step("next")
                        }
                        SunsetBtn {
                            cols: 5
                            gap: 8
                            label: root.autoOn ? "Auto: On" : "Auto: Off"
                            hot: root.autoOn
                            onClicked: {
                                if (root.autoOn) {
                                    stopProc.running = true;
                                } else {
                                    Quickshell.execDetached([WallpaperService.autoScript]);
                                    root.say("\u2713 Auto-wallpaper started");
                                    statusTimer.restart();
                                    statusProc.refresh();
                                }
                            }
                        }
                        SunsetBtn {
                            cols: 5
                            gap: 8
                            label: "Close"
                            onClicked: root.close()
                        }
                    }
                    Item {
                        width: parent.width
                        height: 8
                    }

                    // ---- grid ----
                    Flickable {
                        width: parent.width
                        height: 210
                        contentWidth: width
                        contentHeight: thumbGrid.implicitHeight
                        clip: true
                        ScrollBar.vertical: ScrollBar {
                            contentItem: Rectangle {
                                implicitWidth: 8
                                color: Theme.borderStrong
                                radius: Theme.radius
                            }
                        }
                        Grid {
                            id: thumbGrid
                            width: parent.width
                            columns: 4
                            columnSpacing: 8
                            rowSpacing: 8
                            Repeater {
                                model: folder
                                delegate: Rectangle {
                                    // FolderListModel roles.
                                    property string fPath: model.filePath ?? ""
                                    property string fUrl: model.fileURL ?? ""
                                    property string fName: model.fileName ?? ""
                                    property string thumbUrl: "file://" + root.thumbDir + "/" + encodeURIComponent(fName) + ".jpg"
                                    // 0 = thumb, 1 = thumb regenerating, 2 = full fallback.
                                    property int phase: 0
                                    readonly property bool isSel: root.selPath === fPath && fPath !== ""
                                    readonly property bool isCur: root.currentBase === fName && fName !== ""
                                    width: (thumbGrid.width - 3 * thumbGrid.columnSpacing) / 4
                                    height: 88
                                    color: Theme.bg
                                    border.width: 1
                                    border.color: isSel ? Theme.accent : (tHover.hovered ? Theme.accent : Theme.border)
                                    radius: Theme.radius

                                    Image {
                                        id: thumb
                                        anchors.fill: parent
                                        source: phase === 2 ? fUrl : thumbUrl
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        onStatusChanged: {
                                            if (status === Image.Error && phase === 0) {
                                                phase = 1;
                                                genProc.running = true;
                                            } else if (status === Image.Error && phase === 1) {
                                                phase = 2;
                                            }
                                        }
                                    }
                                    // Magick thumbnail cache (server parity).
                                    Process {
                                        id: genProc
                                        command: ["magick", fPath + "[0]", "-auto-orient", "-thumbnail", "384x216", root.thumbDir + "/" + fName + ".jpg"]
                                        running: false
                                        onExited: {
                                            // Bust the failed load, then retry the thumb.
                                            thumb.source = "";
                                            thumb.source = thumbUrl;
                                        }
                                    }
                                    Rectangle {
                                        visible: isCur
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: 4
                                        width: 20
                                        height: 16
                                        color: Theme.accent
                                        radius: Theme.radius
                                        Text {
                                            anchors.centerIn: parent
                                            text: "\u2713"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                            color: Theme.bg
                                        }
                                    }
                                    HoverHandler {
                                        id: tHover
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton
                                        onClicked: {
                                            const i = index;
                                            root.select(i, false);
                                        }
                                        onDoubleClicked: {
                                            const i = index;
                                            root.select(i, false);
                                            root.setWallpaper(fPath);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: root.msg !== "" ? root.msg : (WallpaperService.busy ? "Setting wallpaper\u2026" : "")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.muted
                        elide: Text.ElideRight
                        topPadding: 8
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "click: preview \u00B7 double-click: set \u00B7 Esc: close"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.muted
                        topPadding: 2
                    }
                }
            }
        }

        onVisibleChanged: {
            if (visible)
                keys.forceActiveFocus();
        }
    }

    component SunsetBtn: Rectangle {
        id: sBtn
        property string label: ""
        property bool hot: false
        property int cols: 1
        property real gap: 8
        signal clicked
        width: parent ? (parent.width - (cols - 1) * gap) / cols : 100
        height: 32
        color: Theme.row
        border.width: 1
        border.color: hot ? Theme.accent : Theme.borderStrong
        radius: Theme.radius
        Text {
            anchors.centerIn: parent
            text: sBtn.label
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.bold: true
            color: hot ? Theme.accent : (sHover.hovered ? Theme.accentHover : Theme.text)
        }
        HoverHandler {
            id: sHover
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: sBtn.clicked()
        }
    }

    IpcHandler {
        target: "wallpaper"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.open();
        }
        function close(): void {
            root.close();
        }
        function refresh(): void {
            root.refresh();
        }
    }
}
