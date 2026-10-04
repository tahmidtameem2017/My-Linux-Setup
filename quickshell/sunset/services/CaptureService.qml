pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// CaptureService.qml — pin state for the bar camera icon. The camera pill
// appears in the bar (right of the centered clock) only while pinned;
// right-clicking it (or the Close row of the capture menu) unpins it.
Singleton {
    id: root

    property bool pinned: false

    function pin(): void { root.pinned = true; }
    function unpin(): void { root.pinned = false; }
}
