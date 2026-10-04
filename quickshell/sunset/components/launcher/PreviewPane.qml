// PreviewPane.qml — Quick Look pane for the launcher (Ctrl+Space on a file row).
//
// One pane, five native renderers, chosen by extension + one stat (directories
// have no extension):
//   image/gif  QtQuick Image / AnimatedImage
//   pdf        PdfPreview.qml (QtQuick.Pdf, isolated behind a Loader)
//   text       head -c 64 KiB, plain monospace
//   dir        ls -1Ap listing
//   meta       icon + mime + size + mtime card
// Anything the native side cannot draw honestly — audio, video, office docs,
// fonts — classifies as "sushi" and Launcher.qml routes it to the external
// Sushi window (hybrid preview). This pane then only shows the metadata card
// with a hint when Sushi is missing, so Ctrl+Space never dies silently.
//
// Traps:
//   * Rich QML modules live in their OWN files behind a Loader. A static
//     QtQuick.Pdf import that failed to load would take the whole launcher
//     down with it; a Loader failure leaves loader.status Error and the pane
//     falls back to metadata.
//   * Every Process is argv-driven (no sh -c interpolation): fd hands us
//     absolute paths that may contain spaces, '#', quotes.
//   * Text is PlainText. A file containing "<img ...>" must not be
//     interpreted as rich text.
//   * Image.cache is off: Qt otherwise retains every previewed image's
//     pixmap for the life of the shell.
//   * The stat result (not the extension) decides directories; a folder
//     called "assets.png" must list, not render as an image.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services

Item {
    id: root

    property string path: ""
    property bool sushiAvailable: true

    readonly property string fileName: {
        if (root.path === "")
            return "";
        const slash = root.path.lastIndexOf("/");
        return slash >= 0 ? root.path.slice(slash + 1) : root.path;
    }

    function extOf(p: string): string {
        const slash = p.lastIndexOf("/");
        const name = slash >= 0 ? p.slice(slash + 1) : p;
        const dot = name.lastIndexOf(".");
        return dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
    }

    function fileUrl(p: string): url {
        if (p === "")
            return "";
        const segs = String(p).split("/");
        for (let i = 0; i < segs.length; ++i)
            segs[i] = encodeURIComponent(segs[i]);
        return "file://" + segs.join("/");
    }

    // Public classifier used by Launcher.qml to decide native pane vs Sushi.
    function classifyPath(p: string): string {
        const e = root.extOf(p);
        if (root.imageExts.indexOf(e) !== -1)
            return e === "gif" ? "gif" : "image";
        if (e === "pdf")
            return "pdf";
        if (root.textExts.indexOf(e) !== -1)
            return "text";
        if (root.sushiExts.indexOf(e) !== -1)
            return "sushi";
        return "meta";
    }

    readonly property var imageExts: ["jpg", "jpeg", "png", "webp", "gif", "bmp", "svg", "heic", "heif", "avif", "tif", "tiff", "ico"]
    readonly property var textExts: ["txt", "md", "markdown", "rst", "log", "conf", "cfg", "ini", "toml", "yaml", "yml", "json", "kdl", "xml", "csv", "tsv", "sh", "bash", "zsh", "fish", "py", "js", "ts", "jsx", "tsx", "qml", "c", "h", "hpp", "cpp", "cc", "rs", "go", "java", "kt", "lua", "sql", "css", "scss", "html", "htm", "desktop", "service", "env", "gitignore", "editorconfig", "nix", "diff", "patch"]
    // Audio/video/office/font: Sushi renders these properly (player, doc
    // layout, font specimen); the native pane would have to fake them.
    readonly property var sushiExts: ["mp3", "flac", "wav", "ogg", "opus", "m4a", "aac", "wma", "aiff", "mka", "mp4", "mkv", "webm", "avi", "mov", "m4v", "mpg", "mpeg", "wmv", "flv", "doc", "docx", "odt", "rtf", "epub", "xls", "xlsx", "ods", "ppt", "pptx", "odp", "ttf", "otf", "woff", "woff2"]

    readonly property url sourceUrl: root.fileUrl(root.path)

    // ---- async facts ----------------------------------------------------
    property string statType: ""
    property real sizeBytes: -1
    property real mtime: 0
    property string statFailed: ""
    property string mimeType: ""
    property string textBody: ""
    property bool textTruncated: false
    property string dirBody: ""
    property int dirCount: 0
    property string pdfError: ""
    property bool imageFailed: false
    property string dirStartedFor: ""

    readonly property string kind: {
        if (root.path === "")
            return "";
        if (root.statFailed !== "")
            return "missing";
        if (root.statType === "")
            return "loading";
        if (root.statType === "directory")
            return "dir";
        return root.classifyPath(root.path);
    }

    readonly property string sizeLabel: root.humanSize(root.sizeBytes)

    readonly property bool showMeta: root.kind === "meta" || root.kind === "missing"
        || (root.kind === "sushi" && !root.sushiAvailable)
        || root.imageFailed || (root.kind === "pdf" && root.pdfError !== "")
        || root.pdfDocError !== ""

    // A corrupt/encrypted PDF fails inside the loaded viewer, not the Loader.
    readonly property string pdfDocError: pdfLoader.item ? pdfLoader.item.errorText : ""

    // ---- PDF paging (drives the footer buttons) -------------------------
    // The viewer's own state, not a copy: buttons and key handling must not
    // be able to disagree about which page is showing.
    readonly property var pdf: pdfLoader.item
    readonly property bool pdfPaged: root.pdf && root.pdf.pageCount > 1
    readonly property bool canPrevPage: !!(root.pdf && root.pdf.canPrev)
    readonly property bool canNextPage: !!(root.pdf && root.pdf.canNext)

    // Buttons only when there is something to page through; a 1-page PDF
    // keeps the plain "Page 1 / 1 · size" footer it always had.
    readonly property bool showPageButtons: root.kind === "pdf"
        && root.pdfPaged && root.pdfError === "" && root.pdfDocError === ""

    function nextPage(): void {
        if (root.pdf)
            root.pdf.nextPage();
    }

    function prevPage(): void {
        if (root.pdf)
            root.pdf.prevPage();
    }

    readonly property string subtitle: {
        switch (root.kind) {
        case "missing": return "File not found";
        case "loading": return "Loading…";
        case "image": return root.extOf(root.path).toUpperCase() + " image";
        case "gif": return "GIF image";
        case "pdf": return "PDF document";
        case "text": return root.extOf(root.path).toUpperCase() + " file";
        case "dir": return "Folder";
        case "sushi": return root.sushiAvailable ? "Opening system preview…" : (root.mimeType || "No preview available");
        default: return root.mimeType || "No preview available";
        }
    }

    readonly property string footerText: {
        switch (root.kind) {
        case "image":
        case "gif":
            return root.sizeLabel;
        case "text":
            return root.textTruncated ? root.sizeLabel + "  ·  showing first 64 KB" : root.sizeLabel;
        case "dir":
            return root.dirCount + (root.dirCount === 1 ? " item" : " items");
        case "pdf": {
            const it = pdfLoader.item;
            if (it && it.pageCount > 0) {
                let s = "Page " + (it.page + 1) + " / " + it.pageCount;
                if (root.sizeLabel !== "")
                    s += "  ·  " + root.sizeLabel;
                // Only on multi-page: on a 1-page PDF the keys do nothing,
                // and advertising them there is noise.
                if (root.showPageButtons)
                    s += "  ·  ^F/^B pages";
                return s;
            }
            return root.sizeLabel;
        }
        default:
            return "";
        }
    }

    function humanSize(bytes: real): string {
        if (!(bytes >= 0))
            return "";
        if (bytes < 1024)
            return bytes + " B";
        const kb = bytes / 1024;
        if (kb < 1024)
            return (kb < 10 ? kb.toFixed(1) : Math.round(kb)) + " KB";
        const mb = kb / 1024;
        if (mb < 1024)
            return (mb < 10 ? mb.toFixed(1) : Math.round(mb)) + " MB";
        return (mb / 1024).toFixed(2) + " GB";
    }

    function restart(proc, argv): void {
        proc.command = argv;
        proc.running = false;
        proc.running = true;
    }

    function refresh(): void {
        root.statType = "";
        root.sizeBytes = -1;
        root.mtime = 0;
        root.statFailed = "";
        root.mimeType = "";
        root.textBody = "";
        root.textTruncated = false;
        root.dirBody = "";
        root.dirCount = 0;
        root.pdfError = "";
        root.imageFailed = false;
        root.dirStartedFor = "";
        if (root.path === "")
            return;
        root.restart(statProc, ["stat", "-c", "%F|%s|%Y", root.path]);
        const guess = root.classifyPath(root.path);
        if (guess === "text")
            root.restart(textProc, ["head", "-c", "65536", root.path]);
        if (guess === "sushi" || guess === "meta")
            root.restart(mimeProc, ["file", "-b", "--mime-type", root.path]);
    }

    onPathChanged: root.refresh()

    // ---- metadata / stat -------------------------------------------------
    Process {
        id: statProc
        command: ["true"]
        stdout: StdioCollector {
            id: statOut
            onStreamFinished: {
                const parts = statOut.text.trim().split("|");
                if (parts.length >= 3) {
                    root.statType = parts[0];
                    root.sizeBytes = Number(parts[1]);
                    root.mtime = Number(parts[2]);
                }
                if (root.statType === "directory" && root.dirStartedFor !== root.path) {
                    root.dirStartedFor = root.path;
                    root.restart(dirProc, ["ls", "-1Ap", root.path]);
                }
            }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                root.statFailed = root.path;
        }
    }

    Process {
        id: textProc
        command: ["true"]
        stdout: StdioCollector {
            id: textOut
            onStreamFinished: {
                root.textBody = textOut.text;
                root.textTruncated = root.sizeBytes > 65536;
            }
        }
    }

    Process {
        id: dirProc
        command: ["true"]
        stdout: StdioCollector {
            id: dirOut
            onStreamFinished: {
                root.dirBody = dirOut.text;
                let n = 0;
                const lines = dirOut.text.split("\n");
                for (let i = 0; i < lines.length; ++i)
                    if (lines[i].trim() !== "")
                        n++;
                root.dirCount = n;
            }
        }
    }

    Process {
        id: mimeProc
        command: ["true"]
        stdout: StdioCollector {
            id: mimeOut
            onStreamFinished: root.mimeType = mimeOut.text.trim()
        }
    }

    // ---- chrome ----------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        radius: 12 // launcher card parity
        color: Theme.withAlpha(Theme.bg, 0.95)
        border.width: 2
        border.color: Theme.accent
        clip: true

        // Swallow clicks so a click on the preview never reaches the
        // click-outside-to-close plane behind the launcher group.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            Column {
                width: parent.width
                spacing: 0
                Text {
                    width: parent.width
                    text: root.fileName
                    font.family: "JetBrainsMono Nerd Font"
                    font.pointSize: 11
                    font.bold: true
                    color: Theme.text
                    elide: Text.ElideMiddle
                }
                Text {
                    width: parent.width
                    text: root.subtitle
                    font.family: "JetBrainsMono Nerd Font"
                    font.pointSize: 9
                    color: Theme.muted
                    elide: Text.ElideRight
                }
            }

            Item {
                id: body
                width: parent.width
                // y already carries the header + first spacing; subtract the
                // trailing spacing so header/body/footer tile the pane.
                height: parent.height - y - footer.height - parent.spacing
                clip: true

                Text {
                    anchors.centerIn: parent
                    visible: root.kind === "loading"
                    text: "Loading…"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pointSize: 10
                    color: Theme.muted
                }

                Image {
                    id: imageView
                    anchors.fill: parent
                    visible: root.kind === "image"
                    source: root.kind === "image" ? root.sourceUrl : ""
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: Math.max(1, Math.round(width * (Screen.devicePixelRatio || 1)))
                    onStatusChanged: if (status === Image.Error)
                        root.imageFailed = true
                }

                AnimatedImage {
                    anchors.fill: parent
                    visible: root.kind === "gif"
                    source: root.kind === "gif" ? root.sourceUrl : ""
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectFit
                    onStatusChanged: if (status === Image.Error)
                        root.imageFailed = true
                }

                Loader {
                    id: pdfLoader
                    anchors.fill: parent
                    active: root.kind === "pdf"
                    source: Qt.resolvedUrl("PdfPreview.qml")
                    onLoaded: if (item) {
                        item.source = root.sourceUrl;
                        item.page = 0;
                    }
                    onStatusChanged: if (status === Loader.Error)
                        root.pdfError = "PDF preview unavailable"
                }

                Flickable {
                    anchors.fill: parent
                    visible: root.kind === "text"
                    clip: true
                    contentWidth: width
                    contentHeight: textView.implicitHeight
                    Text {
                        id: textView
                        width: parent.width
                        text: root.textBody
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.family: "JetBrainsMono Nerd Font"
                        font.pointSize: 9
                        color: Theme.text
                    }
                }

                Flickable {
                    anchors.fill: parent
                    visible: root.kind === "dir"
                    clip: true
                    contentWidth: width
                    contentHeight: dirView.implicitHeight
                    Text {
                        id: dirView
                        width: parent.width
                        text: root.dirBody
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.family: "JetBrainsMono Nerd Font"
                        font.pointSize: 9
                        color: Theme.text
                    }
                }

                // Metadata card: unknown types, missing files, unrenderable
                // images/PDFs, and the sushi-missing fallback.
                Column {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, 300)
                    spacing: 8
                    visible: root.showMeta

                    IconImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 64
                        height: 64
                        source: "file://" + Theme.iconDir + "logo.svg"
                    }
                    Text {
                        width: parent.width
                        text: root.fileName
                        font.family: "JetBrainsMono Nerd Font"
                        font.pointSize: 11
                        font.bold: true
                        color: Theme.text
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                    }
                    Text {
                        width: parent.width
                        text: root.kind === "missing"
                            ? "The file is gone — refresh the search."
                            : (root.kind === "sushi" && !root.sushiAvailable
                                ? "Install sushi for rich previews (audio, video, documents)."
                                : "Enter opens it in the default app.")
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.family: "JetBrainsMono Nerd Font"
                        font.pointSize: 9
                        color: Theme.muted
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // Footer: the page indicator is the natural home for paging
            // controls, so ‹ › sit either side of the same "Page 3 / 97"
            // string rather than floating over the artwork.
            Item {
                id: footer
                width: parent.width
                height: visible ? Math.max(18, Math.max(footerText.implicitHeight, pageNav.height)) : 0
                visible: footerText.text !== "" || root.showPageButtons

                Text {
                    id: footerText
                    anchors.left: parent.left
                    anchors.right: pageNav.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.footerText
                    font.family: "JetBrainsMono Nerd Font"
                    font.pointSize: 9
                    color: Theme.muted
                    elide: Text.ElideRight
                }

                Row {
                    id: pageNav
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    visible: root.showPageButtons

                    component PageBtn: Rectangle {
                        id: btn
                        required property string glyph
                        required property bool usable
                        signal clicked()
                        width: 20
                        height: 18
                        radius: 4
                        color: mouse.containsMouse && btn.usable ? Theme.withAlpha(Theme.accent, 0.18) : "transparent"
                        opacity: btn.usable ? 1.0 : 0.3

                        Text {
                            anchors.centerIn: parent
                            text: btn.glyph
                            font.family: "JetBrainsMono Nerd Font"
                            font.pointSize: 11
                            color: mouse.containsMouse ? Theme.accent : Theme.muted
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: btn.usable
                            cursorShape: Qt.PointingHandCursor
                            onClicked: btn.clicked()
                        }
                    }

                    PageBtn {
                        glyph: "‹"
                        usable: root.canPrevPage
                        onClicked: root.prevPage()
                    }
                    PageBtn {
                        glyph: "›"
                        usable: root.canNextPage
                        onClicked: root.nextPage()
                    }
                }
            }
        }
    }
}
