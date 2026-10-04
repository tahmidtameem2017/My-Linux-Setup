// PdfPreview.qml — paged PDF view for PreviewPane.qml, using QtQuick.Pdf.
//
// Deliberately its own file: QtQuick.Pdf is a plugin, and a static import
// that fails to load would take the whole launcher's QML down. Loaded through
// a Loader, a missing plugin is only Loader.Error + the metadata fallback.
//
// Wheel flips pages (multi-page only), so a PDF is browsable while the search
// input keeps keyboard focus. The page image is rasterized at the pane's
// width in device pixels, never full 4K, and the document is released when
// the Loader goes inactive.
//
// THE WHITE PAGE IS LOAD-BEARING, and it is not a theme token.
// A PDF that never paints a page background renders as transparent, so its
// black text lands straight on the launcher's dark card and the document
// looks empty. Measured with `pdftocairo -transp`, corner alpha of page 1:
//
//   201 Tut-4 Exp Norm Spring2526.pdf   corner alpha 0  -> invisible
//   Biology The Study of Life.pdf       corner alpha 0  -> invisible
//   Ch03.pdf                            corner alpha 1  -> fine on its own
//
// So the failure is per-file, not per-pane, and no palette change fixes it.
// The paper below is sized to the page's own point aspect so PdfPageImage
// lands exactly on top of it (both use PreserveAspectFit). It supplies ONLY
// the paper the file omits — the document's fonts, colours and layout are
// whatever the file says, untouched. A file that does paint its own
// background simply covers this rect.
//
// Trap: pagePointSize() must not be called before the document reports a
// page, or it warns on a null page. Gate on pageCount instead.

import QtQuick
import QtQuick.Pdf
import qs.services

Item {
    id: root

    property url source: ""
    property int page: 0
    readonly property int pageCount: doc.pageCount
    readonly property string errorText: doc.status === PdfDocument.Error
        ? (doc.error || "Cannot render this PDF") : ""

    // --- vim-style page motions ------------------------------------------
    // Ctrl+F / Ctrl+D forward, Ctrl+B / Ctrl+U back, Ctrl+Home / Ctrl+End to
    // the ends. The launcher routes these in (it owns the keyboard), and the
    // footer buttons call the same functions.
    //
    // Ctrl+D / Ctrl+U collapse onto Ctrl+F / Ctrl+B on purpose: vim's D/U are
    // HALF-page scrolls, and a paginated document has no sub-page scroll
    // unit — a fractional page position would round to the next page at
    // exactly the midpoint, i.e. they would be the same key wearing a
    // different name. Mapping both keeps muscle memory working.
    readonly property bool canPrev: root.page > 0
    readonly property bool canNext: root.pageCount > 0 && root.page < root.pageCount - 1

    function goTo(p: int): void {
        if (root.pageCount <= 0)
            return;
        root.page = Math.max(0, Math.min(p, root.pageCount - 1));
    }

    function step(delta: int): void {
        root.goTo(root.page + delta);
    }

    function nextPage(): void {
        root.step(1);
    }

    function prevPage(): void {
        root.step(-1);
    }

    function firstPage(): void {
        root.goTo(0);
    }

    function lastPage(): void {
        root.goTo(root.pageCount - 1);
    }

    PdfDocument {
        id: doc
        source: root.source
    }

    // Page aspect (width / height) in points, 0 until the document has a
    // page. Letter is only a fallback so the first layout pass has a sane
    // box; a loaded document always overrides it.
    readonly property real pageAspect: {
        if (doc.pageCount <= 0)
            return 0;
        const s = doc.pagePointSize(root.page);
        return (s.width > 0 && s.height > 0) ? s.width / s.height : 0.7727;
    }

    // The paper. Deliberately white and deliberately NOT a Theme token: this
    // is the document's own surface, not our chrome. Themed here it would be
    // the one preview that ignored the palette for a good reason.
    Rectangle {
        anchors.centerIn: parent
        width: Math.max(1, Math.min(parent.width, parent.height * root.pageAspect))
        height: root.pageAspect > 0 ? width / root.pageAspect : parent.height
        visible: root.errorText === "" && root.pageCount > 0
        color: "#ffffff"
        // Hairline only, so the white sheet reads as an object against the
        // dark card instead of bleeding into it.
        border.width: 1
        border.color: "#00000030"
    }

    PdfPageImage {
        id: pageImage
        anchors.fill: parent
        document: doc
        currentFrame: root.page
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.max(1, Math.round(width * (Screen.devicePixelRatio || 1)))
    }

    Text {
        anchors.centerIn: parent
        visible: doc.status === PdfDocument.Loading
        text: "Loading PDF…"
        font.family: "JetBrainsMono Nerd Font"
        font.pointSize: 10
        color: Theme.muted
    }

    Text {
        anchors.centerIn: parent
        width: Math.min(parent.width, 260)
        visible: root.errorText !== ""
        text: root.errorText
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        font.family: "JetBrainsMono Nerd Font"
        font.pointSize: 9
        color: Theme.muted
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            if (root.pageCount <= 1)
                return;
            if (event.angleDelta.y < 0)
                root.nextPage();
            else if (event.angleDelta.y > 0)
                root.prevPage();
        }
    }
}