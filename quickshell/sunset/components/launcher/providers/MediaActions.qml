// MediaActions.qml — static media/volume action rows for the Launcher.
// NOT a provider: no search(), no latestRows, no resultsChanged — just
// QtObject with rows() + activate(row). (Launcher closes BEFORE calling
// activate, so activate only acts.)
// Service APIs used (verified in-repo):
//   MediaService.toggle() / .next() / .previous()
//     (quickshell/sunset/services/MediaService.qml lines 53-66)
//   AudioService.toggleMute() (quickshell/sunset/services/AudioService.qml
//     line 51)
// Rows: {kind:"media", name, detail, icon:null, score:100,
//   section:"Media", data:{op}} with op in
//   "toggle"|"next"|"previous"|"mute". icon is null per contract (the
//   existing play/pause/volume-muted.svg glyphs are deliberately not
//   claimed: these rows are state toggles, not state indicators).
// No colors/fonts, no UI.

import QtQuick
import qs.services

QtObject {
    id: root

    function rows(): var {
        return [
            {
                "kind": "media",
                "name": "Play / Pause",
                "detail": "Toggle playback (Enter)",
                "icon": null,
                "score": 100,
                "section": "Media",
                "data": { "op": "toggle" }
            },
            {
                "kind": "media",
                "name": "Next track",
                "detail": "Skip to next track (Enter)",
                "icon": null,
                "score": 100,
                "section": "Media",
                "data": { "op": "next" }
            },
            {
                "kind": "media",
                "name": "Previous track",
                "detail": "Go to previous track (Enter)",
                "icon": null,
                "score": 100,
                "section": "Media",
                "data": { "op": "previous" }
            },
            {
                "kind": "media",
                "name": "Mute / Unmute",
                "detail": "Toggle mute (Enter)",
                "icon": null,
                "score": 100,
                "section": "Media",
                "data": { "op": "mute" }
            }
        ];
    }

    function activate(row: var): void {
        if (!row || !row.data || !row.data.op)
            return;
        const op = row.data.op;
        if (op === "toggle")
            MediaService.toggle();
        else if (op === "next")
            MediaService.next();
        else if (op === "previous")
            MediaService.previous();
        else if (op === "mute")
            AudioService.toggleMute();
    }
}
