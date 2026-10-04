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
//   library -> ~/Pictures/Wallpapers, top level, newest-first, exts
//              jpg/jpeg/png/webp/avif (FolderListModel, Time sort, reversed).
//   current -> .state/current_wallpaper basename, watched live via
//              FileView (external sets via menu/scroll re-highlight).
//   thumbs  -> magick <src>[0] -auto-orient -thumbnail 384x216 <cache>
//              in ~/.cache/niri-wallpaper/thumbs (<basename>.jpg),
//              original on failure (server parity, incl. lazy gen).
//   set     -> scripts/wallpaper.sh <abs path> via WallpaperService
//              (same slow magick backdrop pipeline; busy disables Set).
//   delete  -> scripts/manage-wallpaper.sh delete <path> (trash,
//              recoverable; deleting the current one auto-sets a successor).
//   rename  -> scripts/manage-wallpaper.sh rename <path> <name>
//              (inline editor: F2 / Rename button, Enter commits).
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
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
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

    property bool isOpen: false
    // Deferred gallery: the Repeater below instantiates one delegate per
    // image file (each with an async Image + magick regen Process).
    // Building all of them at shell startup — while the window is
    // invisible — burns seconds of CPU on weak iGPUs for a popup the
    // user may never open. Gate the model on first open; the
    // FolderListModel scan itself (cheap stat) still runs at startup so
    // the count is ready when the picker opens.
    property bool everOpened: false
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
    // Rename editor + post-op selection anchors.
    property bool renaming: false
    property string lastDeleted: ""
    // After a delete, hold the grid position (clamped) instead of jumping
    // to the current wallpaper. After a rename, jump to the new file.
    property int pendingIndex: -1
    property string pendingPath: ""
    // Preview fallback phase: 0 = full image, 1 = cached thumb.
    // Reset to 0 on every select(); onStatusChanged flips 0 -> 1 once.
    // selFullUrl prefers the FolderListModel fileURL role but falls back to
    // file:// + filePath (proven via isSel/current highlight) so an empty
    // fileURL role (Null status, no Error) can never leave the pane black.
    property int previewPhase: 0
    readonly property string selFullUrl: selUrl !== "" ? selUrl : (selPath !== "" ? ("file://" + selPath) : "")
    // Double-encoded: the thumb FILE on disk is literally
    // encodeURIComponent(fileName)+".jpg" (genProc below writes that
    // literal name, so spaced names contain a real "%20" on disk).
    // A single-encoded file:// URL would decode "%20" back to a space
    // and miss the file; encoding twice addresses the literal name
    // while leaving normal names byte-identical (no % present).
    readonly property string selThumbUrl: selName !== "" ? ("file://" + thumbDir + "/" + encodeURIComponent(encodeURIComponent(selName) + ".jpg")) : ""
    // Session set of source paths whose magick thumb regen already
    // failed (exit != 0, e.g. corrupt source). Delegates check it
    // before spawning genProc, so a dead file costs one magick run
    // per session, never a respawn storm. The full-image fallback
    // still runs once per delegate instance; when it also fails the
    // cell becomes an honest placeholder (imgDead) instead of gray.
    property var genFailed: new Set()
    // ---- keyboard nav state ----
    property int selIndex: -1
    readonly property int gridCols: 4
    readonly property int pageStep: 8 // 2 rows of 4 cols
    property int toolFocus: -1 // -1 = grid, 0..4 = toolbar button

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
        sortField: FolderListModel.Time
        sortReversed: true
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
        // Post-op anchors first: renamed file, or held grid position.
        if (pendingPath !== "") {
            for (let k = 0; k < folder.count; ++k) {
                if (folder.get(k, "filePath") === pendingPath) {
                    pendingPath = "";
                    pendingIndex = -1;
                    select(k, true);
                    ensureVisible(k);
                    return;
                }
            }
            // Model hasn't caught up yet — retry on the next count change.
            return;
        }
        if (pendingIndex >= 0) {
            const held = Math.min(pendingIndex, folder.count - 1);
            pendingIndex = -1;
            select(held, true);
            ensureVisible(held);
            return;
        }
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
        ensureVisible(idx);
    }

    function select(i: int, quiet: bool): void {
        if (i < 0 || i >= folder.count)
            return;
        // FolderListModel roles can be briefly undefined while the model
        // resolves (startup sort); coalesce so preview never goes blank.
        // Reset preview fallback first so the new selection starts at full.
        previewPhase = 0;
        selIndex = i;
        selPath = folder.get(i, "filePath") ?? "";
        selUrl = folder.get(i, "fileURL") ?? "";
        selName = folder.get(i, "fileName") ?? "";
    }

    function moveSel(delta: int): void {
        if (folder.count === 0)
            return;
        const base = selIndex >= 0 ? selIndex : 0;
        let idx = base + delta;
        if (idx < 0)
            idx = 0;
        if (idx >= folder.count)
            idx = folder.count - 1;
        toolFocus = -1;
        select(idx, false);
        ensureVisible(idx);
    }

    function goFirst(): void {
        if (folder.count === 0)
            return;
        toolFocus = -1;
        select(0, false);
        ensureVisible(0);
    }

    function goLast(): void {
        if (folder.count === 0)
            return;
        toolFocus = -1;
        select(folder.count - 1, false);
        ensureVisible(folder.count - 1);
    }

    function ensureVisible(i: int): void {
        if (!gridFlick || i < 0 || i >= folder.count)
            return;
        // Thumb geometry must match the delegate below (h 88, rowSpacing 8).
        const rowH = 88 + 8;
        const row = Math.floor(i / gridCols);
        const rowY = row * rowH;
        const rowBottom = rowY + 88;
        if (rowY < gridFlick.contentY) {
            gridFlick.contentY = Math.max(0, rowY);
        } else if (rowBottom > gridFlick.contentY + gridFlick.height) {
            const maxY = Math.max(0, gridFlick.contentHeight - gridFlick.height);
            gridFlick.contentY = Math.min(maxY, rowBottom - gridFlick.height);
        }
    }

    function toggleAuto(): void {
        if (root.autoOn) {
            stopProc.running = true;
        } else {
            Quickshell.execDetached([WallpaperService.autoScript]);
            say("\u2713 Auto-wallpaper started");
            statusTimer.restart();
            statusProc.refresh();
        }
    }

    function triggerTool(i: int): void {
        if (i === 0)
            step("prev");
        else if (i === 1)
            step("random");
        else if (i === 2)
            step("next");
        else if (i === 3)
            toggleAuto();
        else if (i === 4)
            close();
    }

    function setWallpaper(path: string): void {
        if (!path || WallpaperService.busy)
            return;
        cancelRename();
        say("Setting wallpaper\u2026");
        WallpaperService.setWallpaper(path);
    }

    function deleteSelection(): void {
        if (!selPath || WallpaperService.busy)
            return;
        cancelRename();
        pendingPath = "";
        pendingIndex = selIndex >= 0 ? selIndex : 0;
        pendingTimer.restart();
        lastDeleted = selName;
        say("Deleting\u2026");
        WallpaperService.deleteWallpaper(selPath);
    }

    function startRename(): void {
        if (!selPath || WallpaperService.busy)
            return;
        renaming = true;
        renameField.text = selName;
        renameField.forceActiveFocus();
        renameField.selectAll();
    }

    function cancelRename(): void {
        renaming = false;
    }

    function commitRename(): void {
        if (!renaming)
            return;
        const raw = renameField.text.trim();
        if (raw === "") {
            renaming = false;
            say("Empty name \u2014 rename cancelled");
            return;
        }
        // Mirror the script: bare basename, old extension kept when missing.
        let nn = raw.slice(raw.lastIndexOf("/") + 1);
        const dot = selName.lastIndexOf(".");
        const ext = dot >= 0 ? selName.slice(dot) : "";
        if (nn.indexOf(".") < 0)
            nn += ext;
        renaming = false;
        pendingIndex = -1;
        pendingPath = wallDir + "/" + nn;
        pendingTimer.restart();
        say("Renaming\u2026");
        WallpaperService.renameWallpaper(selPath, raw);
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

    // Safety: if the FolderListModel watcher misses a delete/rename,
    // drop the anchors after 3s instead of freezing the selection.
    Timer {
        id: pendingTimer
        interval: 3000
        repeat: false
        onTriggered: {
            root.pendingPath = "";
            root.pendingIndex = -1;
            root.ensureSelection();
        }
    }

    // Reflect service results in the footer line.
    Connections {
        target: WallpaperService
        function onBusyChanged(): void {
            if (WallpaperService.busy)
                return;
            if (WallpaperService.lastError !== "") {
                root.say("\u2717 " + WallpaperService.lastError);
            } else if (root.msg === "Setting wallpaper\u2026") {
                currentFile.reload();
                root.say("\u2713 Wallpaper set: " + root.currentBase);
            } else if (root.msg === "Deleting\u2026") {
                currentFile.reload();
                root.say("\u2713 Deleted (trashed): " + root.lastDeleted);
                root.lastDeleted = "";
            } else if (root.msg === "Renaming\u2026") {
                currentFile.reload();
                root.say("\u2713 Renamed");
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
            root.everOpened = true;
            toolFocus = -1;
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
            color: root.cPanel
            border.width: 1
            border.color: root.cBorderStrong
            radius: root.cRadius
            // Micro-animation: subtle entrance (opacity 150ms OutCubic +
            // scale 0.96->1 180ms OutBack overshoot 1.2 + y -6->0).
            // Close stays instant (visible flips with isOpen, <200ms).
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

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true
                // Full keyboard nav: arrows move grid, Home/End first/last,
                // PageUp/PageDown ±pageStep, Enter/Space sets, Tab cycles the
                // toolbar (Shift+Tab backwards), Alt+1..5 fires toolbar
                // directly, Esc closes. Arrows always return focus to grid.
                Keys.onPressed: (event) => {
                    // While renaming, the TextField owns all keys except
                    // Esc (cancel). Enter commits via onAccepted.
                    if (root.renaming) {
                        if (event.key === Qt.Key_Escape) {
                            event.accepted = true;
                            root.cancelRename();
                        }
                        return;
                    }
                    if ((event.modifiers & Qt.AltModifier) !== 0) {
                        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5) {
                            event.accepted = true;
                            root.toolFocus = event.key - Qt.Key_1;
                            root.triggerTool(root.toolFocus);
                            return;
                        }
                    }
                    if (event.key === Qt.Key_Left) {
                        event.accepted = true;
                        root.moveSel(-1);
                    } else if (event.key === Qt.Key_Right) {
                        event.accepted = true;
                        root.moveSel(1);
                    } else if (event.key === Qt.Key_Up) {
                        event.accepted = true;
                        root.moveSel(-root.gridCols);
                    } else if (event.key === Qt.Key_Down) {
                        event.accepted = true;
                        root.moveSel(root.gridCols);
                    } else if (event.key === Qt.Key_Home) {
                        event.accepted = true;
                        root.goFirst();
                    } else if (event.key === Qt.Key_End) {
                        event.accepted = true;
                        root.goLast();
                    } else if (event.key === Qt.Key_PageUp) {
                        event.accepted = true;
                        root.moveSel(-root.pageStep);
                    } else if (event.key === Qt.Key_PageDown) {
                        event.accepted = true;
                        root.moveSel(root.pageStep);
                    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                        event.accepted = true;
                        const backward = (event.key === Qt.Key_Backtab) || ((event.modifiers & Qt.ShiftModifier) !== 0);
                        if (backward) {
                            if (root.toolFocus <= -1)
                                root.toolFocus = 4;
                            else if (root.toolFocus === 0)
                                root.toolFocus = -1;
                            else
                                root.toolFocus = root.toolFocus - 1;
                        } else {
                            if (root.toolFocus >= 4)
                                root.toolFocus = -1;
                            else
                                root.toolFocus = root.toolFocus + 1;
                        }
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        event.accepted = true;
                        if (root.toolFocus >= 0)
                            root.triggerTool(root.toolFocus);
                        else
                            root.setWallpaper(root.selPath);
                    } else if (event.key === Qt.Key_Delete) {
                        event.accepted = true;
                        root.deleteSelection();
                    } else if (event.key === Qt.Key_F2) {
                        event.accepted = true;
                        root.startRename();
                    } else if (event.key === Qt.Key_Escape) {
                        event.accepted = true;
                        root.close();
                    }
                }

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
                            font.family: root.cFontFamily
                            font.pixelSize: 14
                            font.bold: true
                            color: root.cAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            width: parent.width - parent.spacing - 110
                            elide: Text.ElideRight
                            text: folder.count + " wallpapers \u00B7 current: " + (root.currentBase !== "" ? root.currentBase : "\u2014")
                            font.family: root.cFontFamily
                            font.pixelSize: 11
                            color: root.cMuted
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
                        color: root.cBg
                        border.width: 1
                        border.color: root.cBorderStrong
                        radius: root.cRadius
                        clip: true
                        // Filename placeholder behind the image: visible while
                        // resolving and when both full + thumb fail, so the
                        // pane is never bare black.
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideMiddle
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            text: previewImg.status === Image.Loading ? ((root.selName !== "" ? root.selName : "\u2014") + " \u2014 loading\u2026") : (root.selName !== "" ? root.selName : "\u2014")
                            font.family: root.cFontFamily
                            font.pixelSize: 11
                            color: root.cMuted
                        }
                        Image {
                            id: previewImg
                            anchors.fill: parent
                            source: root.previewPhase === 1 ? root.selThumbUrl : (root.selFullUrl !== "" ? root.selFullUrl : root.selThumbUrl)
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            onStatusChanged: {
                                if (status === Image.Error && root.previewPhase === 0 && root.selThumbUrl !== "")
                                    root.previewPhase = 1;
                                else if (status === Image.Error && root.previewPhase === 1)
                                    console.warn("sunset/WallpaperPicker preview failed for " + (root.selName !== "" ? root.selName : "?") + " full=" + root.selFullUrl + " thumb=" + root.selThumbUrl);
                            }
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 34
                            color: root.cBg
                            opacity: 0.85
                            radius: root.cRadius
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.right: actionRow.left
                            anchors.rightMargin: 8
                            anchors.bottom: parent.bottom
                            height: 34
                            leftPadding: 8
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: root.selName !== "" ? root.selName : "\u2014"
                            font.family: root.cFontFamily
                            font.pixelSize: 11
                            color: root.cText
                        }
                        Row {
                            id: actionRow
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 5
                            spacing: 8
                            // Secondary action: rename the selected file
                            // (inline editor below the toolbar).
                            Rectangle {
                                id: renBtn
                                width: 84
                                height: 24
                                color: root.cRow
                                border.width: 1
                                border.color: root.cBorderStrong
                                radius: root.cRadius
                                opacity: (WallpaperService.busy || root.selPath === "") ? 0.5 : 1
                                transformOrigin: Item.Center
                                scale: renMouse.pressed ? 0.98 : 1.0
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 100
                                        easing.type: Easing.OutQuad
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "Rename"
                                    font.family: root.cFontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: renHover.hovered ? root.cAccentHover : root.cText
                                }
                                HoverHandler {
                                    id: renHover
                                }
                                MouseArea {
                                    id: renMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.startRename()
                                }
                            }
                            // Secondary action: trash the selected file
                            // (recoverable via system trash; Del key too).
                            Rectangle {
                                id: delBtn
                                width: 84
                                height: 24
                                color: root.cRow
                                border.width: 1
                                border.color: root.cBorderStrong
                                radius: root.cRadius
                                opacity: (WallpaperService.busy || root.selPath === "") ? 0.5 : 1
                                transformOrigin: Item.Center
                                scale: delMouse.pressed ? 0.98 : 1.0
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 100
                                        easing.type: Easing.OutQuad
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "Delete"
                                    font.family: root.cFontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: delHover.hovered ? root.cAccentHover : root.cText
                                }
                                HoverHandler {
                                    id: delHover
                                }
                                MouseArea {
                                    id: delMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.deleteSelection()
                                }
                            }
                            // Primary action: apply the selected file.
                            Rectangle {
                                id: setBtn
                                width: 130
                                height: 24
                                color: setHover.hovered && !WallpaperService.busy ? root.cAccentHover : root.cAccent
                                radius: root.cRadius
                                opacity: WallpaperService.busy ? 0.5 : 1
                                transformOrigin: Item.Center
                                scale: setMouse.pressed ? 0.98 : 1.0
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 100
                                        easing.type: Easing.OutQuad
                                    }
                                }
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 120
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: WallpaperService.busy ? "Setting\u2026" : "Set wallpaper"
                                    font.family: root.cFontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: root.cBg
                                }
                                HoverHandler {
                                    id: setHover
                                }
                                MouseArea {
                                    id: setMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.setWallpaper(root.selPath)
                                }
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
                            cAccent: root.cAccent
                            cAccentHover: root.cAccentHover
                            cBorderStrong: root.cBorderStrong
                            cFontFamily: root.cFontFamily
                            cRadius: root.cRadius
                            cRow: root.cRow
                            cText: root.cText
                            cols: 5
                            gap: 8
                            label: "󰁈 Prev"
                            focused: root.toolFocus === 0
                            onClicked: root.step("prev")
                        }
                        SunsetBtn {
                            cAccent: root.cAccent
                            cAccentHover: root.cAccentHover
                            cBorderStrong: root.cBorderStrong
                            cFontFamily: root.cFontFamily
                            cRadius: root.cRadius
                            cRow: root.cRow
                            cText: root.cText
                            cols: 5
                            gap: 8
                            label: "󰁒 Random"
                            focused: root.toolFocus === 1
                            onClicked: root.step("random")
                        }
                        SunsetBtn {
                            cAccent: root.cAccent
                            cAccentHover: root.cAccentHover
                            cBorderStrong: root.cBorderStrong
                            cFontFamily: root.cFontFamily
                            cRadius: root.cRadius
                            cRow: root.cRow
                            cText: root.cText
                            cols: 5
                            gap: 8
                            label: "󰁔 Next"
                            focused: root.toolFocus === 2
                            onClicked: root.step("next")
                        }
                        SunsetBtn {
                            cAccent: root.cAccent
                            cAccentHover: root.cAccentHover
                            cBorderStrong: root.cBorderStrong
                            cFontFamily: root.cFontFamily
                            cRadius: root.cRadius
                            cRow: root.cRow
                            cText: root.cText
                            cols: 5
                            gap: 8
                            label: root.autoOn ? "Auto: On" : "Auto: Off"
                            hot: root.autoOn
                            focused: root.toolFocus === 3
                            onClicked: root.toggleAuto()
                        }
                        SunsetBtn {
                            cAccent: root.cAccent
                            cAccentHover: root.cAccentHover
                            cBorderStrong: root.cBorderStrong
                            cFontFamily: root.cFontFamily
                            cRadius: root.cRadius
                            cRow: root.cRow
                            cText: root.cText
                            cols: 5
                            gap: 8
                            label: "Close"
                            focused: root.toolFocus === 4
                            onClicked: root.close()
                        }
                    }
                    // ---- rename editor (F2 / Rename button) ----
                    Rectangle {
                        visible: root.renaming
                        width: parent.width
                        height: visible ? 36 : 0
                        color: root.cBg
                        border.width: 1
                        border.color: root.cAccent
                        radius: root.cRadius
                        clip: true
                        Row {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 8
                            Text {
                                text: "Rename:"
                                font.family: root.cFontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: root.cAccent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            TextField {
                                id: renameField
                                width: parent.width - 220
                                height: 24
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: root.cFontFamily
                                font.pixelSize: 11
                                color: root.cText
                                placeholderText: "new file name"
                                placeholderTextColor: root.cMuted
                                background: Rectangle {
                                    color: root.cRow
                                    border.width: 1
                                    border.color: root.cBorder
                                    radius: root.cRadius
                                }
                                onAccepted: root.commitRename()
                            }
                            Text {
                                text: "Enter \u2713 \u00B7 Esc \u2715"
                                font.family: root.cFontFamily
                                font.pixelSize: 10
                                color: root.cMuted
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    Item {
                        width: parent.width
                        height: 8
                    }

                    // ---- grid ----
                    Flickable {
                        id: gridFlick
                        width: parent.width
                        height: 210
                        readonly property real gutter: 12
                        contentWidth: width - gutter
                        contentHeight: thumbGrid.implicitHeight
                        clip: true
                        // Mouse wheel scrolls the grid (vertical flick).
                        interactive: true
                        flickableDirection: Flickable.VerticalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {
                            contentItem: Rectangle {
                                implicitWidth: 8
                                color: root.cBorderStrong
                                radius: root.cRadius
                            }
                        }
                        Grid {
                            id: thumbGrid
                            width: gridFlick.width - gridFlick.gutter
                            columns: 4
                            columnSpacing: 8
                            rowSpacing: 8
                            Repeater {
                                // Deferred until first open (see everOpened):
                                // avoids instantiating ~100+ image delegates
                                // at shell startup for a hidden window.
                                model: root.everOpened ? folder : null
                                delegate: Rectangle {
                                    // FolderListModel roles.
                                    property string fPath: model.filePath ?? ""
                                    property string fUrl: model.fileURL ?? ""
                                    property string fName: model.fileName ?? ""
                                    // Double-encoded (see selThumbUrl): the disk file
                                    // is literally encodeURIComponent(fName)+".jpg".
                                    property string thumbUrl: "file://" + root.thumbDir + "/" + encodeURIComponent(encodeURIComponent(fName) + ".jpg")
                                    // 0 = thumb, 1 = thumb regenerating, 2 = full fallback.
                                    property int phase: 0
                                    // Terminal: thumb missing/unreadable AND
                                    // magick regen failed AND full fallback
                                    // failed. Image hidden, dim scrim +
                                    // filename shown instead of flat gray.
                                    // File stays in the grid so the user can
                                    // see and delete it.
                                    property bool imgDead: false
                                    readonly property bool isSel: root.selPath === fPath && fPath !== ""
                                    readonly property bool isCur: root.currentBase === fName && fName !== ""
                                    width: (thumbGrid.width - 3 * thumbGrid.columnSpacing) / 4
                                    height: 88
                                    color: root.cBg
                                    // Visible focus ring: selected gets a 2px
                                    // accent border; when the grid holds
                                    // keyboard focus it glows accentHover.
                                    border.width: isSel ? 2 : 1
                                    border.color: isSel ? (root.toolFocus === -1 && keys.activeFocus ? root.cAccentHover : root.cAccent) : (tHover.hovered ? root.cAccent : root.cBorder)
                                    radius: root.cRadius
                                    clip: true

                                    // Filename behind the thumb: visible while
                                    // loading and when thumb + full both fail
                                    // (corrupt file), so a dead file is
                                    // labeled, never a flat gray box.
                                    Text {
                                        anchors.centerIn: parent
                                        width: parent.width - 8
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideMiddle
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        text: fName
                                        font.family: root.cFontFamily
                                        font.pixelSize: 9
                                        color: root.cMuted
                                    }
                                    Image {
                                        id: thumb
                                        anchors.fill: parent
                                        // Hidden once permanently unreadable:
                                        // a failed/partial Image can still
                                        // paint gray over the filename Text.
                                        visible: !imgDead
                                        source: phase === 2 ? fUrl : thumbUrl
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        onStatusChanged: {
                                            if (status === Image.Error && phase === 0) {
                                                if (fPath === "") {
                                                    // Roles not resolved yet (FolderListModel
                                                    // startup sort): stay on the thumb. fName
                                                    // resolving updates thumbUrl, which reloads
                                                    // the Image automatically — jumping to the
                                                    // full-res fallback here would pin this cell
                                                    // to a multi-MB load and skip its thumbnail.
                                                } else if (root.genFailed.has(fPath)) {
                                                    // Magick already failed
                                                    // for this source this
                                                    // session: never respawn
                                                    // genProc, straight to
                                                    // the one full fallback.
                                                    phase = 2;
                                                } else {
                                                    phase = 1;
                                                    genProc.running = true;
                                                }
                                            } else if (status === Image.Error && phase === 1) {
                                                phase = 2;
                                            } else if (status === Image.Error && phase === 2) {
                                                imgDead = true;
                                                console.warn("sunset/WallpaperPicker unreadable image, placeholder for " + (fName !== "" ? fName : "?"));
                                            }
                                        }
                                    }
                                    // Magick thumbnail cache (server parity).
                                    // Disk name is encodeURIComponent(fName)+".jpg";
                                    // thumbUrl double-encodes it so file:// addresses
                                    // the literal on-disk name (spaced names hit cache).
                                    Process {
                                        id: genProc
                                        command: ["magick", fPath + "[0]", "-auto-orient", "-thumbnail", "384x216", root.thumbDir + "/" + encodeURIComponent(fName) + ".jpg"]
                                        running: false
                                        stderr: StdioCollector {
                                            onStreamFinished: {
                                                if (text.trim() !== "")
                                                    console.warn("sunset/WallpaperPicker thumb gen failed for " + fName + ": " + text.trim().split("\n").pop());
                                            }
                                        }
                                        onExited: exitCode => {
                                            if (exitCode === 0) {
                                                // Healed (e.g. stale partial
                                                // thumb replaced): clear the
                                                // session mark, then retry.
                                                if (root.genFailed.has(fPath))
                                                    root.genFailed.delete(fPath);
                                                // Bust the failed load, then retry the thumb.
                                                thumb.source = "";
                                                thumb.source = thumbUrl;
                                            } else {
                                                // magick missing/failed (incl.
                                                // corrupt source): remember
                                                // it so this session never
                                                // spawns genProc for this
                                                // file again; fall straight
                                                // back to the full image.
                                                root.genFailed.add(fPath);
                                                phase = 2;
                                            }
                                        }
                                    }
                                    // Honest placeholder, painted above the (hidden)
                                    // Image so a failed/partial decode can never
                                    // cover the filename: dim scrim + centered
                                    // 9px muted wrapped name, same styling as
                                    // the loading Text behind the thumb.
                                    Rectangle {
                                        visible: imgDead
                                        anchors.fill: parent
                                        color: root.cRow
                                    }
                                    Text {
                                        visible: imgDead
                                        anchors.centerIn: parent
                                        width: parent.width - 8
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideMiddle
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        text: fName
                                        font.family: root.cFontFamily
                                        font.pixelSize: 9
                                        color: root.cMuted
                                    }
                                    Rectangle {
                                        visible: isCur
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: 4
                                        width: 20
                                        height: 16
                                        color: root.cAccent
                                        radius: root.cRadius
                                        Text {
                                            anchors.centerIn: parent
                                            text: "\u2713"
                                            font.family: root.cFontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                            color: root.cBg
                                        }
                                    }
                                    HoverHandler {
                                        id: tHover
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton
                                        // Single click previews only; hover
                                        // never steals the preview selection.
                                        onClicked: {
                                            const i = index;
                                            root.toolFocus = -1;
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
                        font.family: root.cFontFamily
                        font.pixelSize: 11
                        color: root.cMuted
                        elide: Text.ElideRight
                        topPadding: 8
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        text: "←→↑↓ move · Home/End first/last · PgUp/PgDn ±8 · Enter set · Del delete · F2 rename · click preview · 2-click set · Tab toolbar · Alt+1..5 actions · Esc close"
                        font.family: root.cFontFamily
                        font.pixelSize: 10
                        color: root.cMuted
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
        // injected props (inline component scope is isolated)
        property color cAccent: root.cAccent
        property color cAccentHover: root.cAccentHover
        property color cBorderStrong: root.cBorderStrong
        property string cFontFamily: root.cFontFamily
        property int cRadius: 0
        property color cRow: root.cRow
        property color cText: root.cText
        id: sBtn
        property string label: ""
        property bool hot: false
        property bool focused: false
        property int cols: 1
        property real gap: 8
        signal clicked
        width: parent ? (parent.width - (cols - 1) * gap) / cols : 100
        height: 32
        color: cRow
        border.width: focused ? 2 : 1
        border.color: focused ? cAccentHover : (hot ? cAccent : cBorderStrong)
        radius: cRadius
        transformOrigin: Item.Center
        scale: sMouse.pressed ? 0.98 : 1.0
        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutQuad
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
        Text {
            anchors.centerIn: parent
            text: sBtn.label
            font.family: cFontFamily
            font.pixelSize: 12
            font.bold: true
            color: hot ? cAccent : ((sHover.hovered || sBtn.focused) ? cAccentHover : cText)
        }
        HoverHandler {
            id: sHover
        }
        MouseArea {
            id: sMouse
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
        function dbg(): void {
            dbgProc.running = true;
        }
    }

    Process {
        id: dbgProc
        running: false
        command: ["sh", "-c", `OUT=/tmp/opencode/wpdbg.txt
{
  echo "t=$(date +%T) count=${folder.count} selIndex=${root.selIndex} busy=${WallpaperService.busy} everOpened=${root.everOpened}"
  echo "selPath=[${root.selPath}]"
  ls -l -- "${root.selPath}"
  ${repoDir}/scripts/manage-wallpaper.sh delete "${root.selPath}"
  echo "script rc=$?"
  ls -l -- "${root.selPath}"
} > $OUT 2>&1`]
    }
}
