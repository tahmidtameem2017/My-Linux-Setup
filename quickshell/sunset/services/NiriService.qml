pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// NiriService.qml — pure-QML niri IPC (no qml-niri plugin).
// Pattern: DankMaterialShell / ii-niri, self-contained.
//
// Protocol (niri wiki IPC + niri_ipc docs):
//   - socket path from $NIRI_SOCKET.
//   - write one JSON Request per line, read one JSON Reply/Event per line.
//   - requests used here: "EventStream" | "Workspaces" | "Windows" | "Outputs"
//   - replies look like {"Ok":{"Workspaces":[...]}} / {"Ok":{"Handled":{}}}
//   - events look like {"WorkspacesChanged":{"workspaces":[...]}},
//     {"WorkspaceActivated":{"id":N,"focused":bool}}, {"WindowsChanged":...},
//     {"WindowOpenedOrChanged":{"window":{...}}}, {"WindowClosed":{"id":N}},
//     {"WindowFocusChanged":{"id":N|null}}, etc.
//   - two sockets because EventStream occupies its socket forever;
//     queries + actions go on the second socket.
//   - EventStream replays full state up-front (WorkspacesChanged +
//     WindowsChanged), so no separate fetch is strictly needed — but we
//     still query on (re)connect to cover niri restarts / missed frames.
//
// is_focused vs is_active (multi-output):
//   - is_focused: exactly ONE workspace across ALL outputs (keyboard focus).
//     Bar highlight must use this.
//   - is_active: ONE workspace PER output (visible on that output).
//     Multi-monitor bars must filter by output + is_active, not is_focused.
//   - output may be null when no outputs are connected; treat as "".
Singleton {
    id: root

    readonly property string socketPath: Quickshell.env("NIRI_SOCKET") ?? ""
    readonly property bool connected: eventSocket.connected
    property bool queryReady: false

    // Live state. Sorted by idx ascending for bar rendering.
    property var workspaces: []
    property var windows: []
    // Outputs reply is a map: { "HDMI-A-1": {...logical...}, ... }
    property var outputs: ({})

    property string focusedWorkspaceId: ""
    property int focusedWorkspaceIdx: 1
    property string focusedOutput: ""

    // Derived from windows where is_focused == true. Fallback = Desktop.
    property string activeWindowTitle: "Desktop"
    property string activeWindowAppId: ""
    property int activeWindowId: -1

    // Internal query correlation (niri answers in request order).
    property var _pendingQueries: []
    property bool _streamHandshakeDone: false

    // --- derived helpers (Bar builders use these) ---

    function focusedWorkspace() {
        for (let i = 0; i < workspaces.length; ++i) {
            if (String(workspaces[i].id) === focusedWorkspaceId)
                return workspaces[i];
        }
        return null;
    }

    function workspacesForOutput(outputName) {
        const name = outputName ?? "";
        const out = [];
        for (let i = 0; i < workspaces.length; ++i) {
            const wsOut = workspaces[i].output ?? "";
            if (wsOut === name)
                out.push(workspaces[i]);
        }
        return out;
    }

    function activeWorkspaceForOutput(outputName) {
        const list = workspacesForOutput(outputName);
        for (let i = 0; i < list.length; ++i) {
            if (list[i].is_active)
                return list[i];
        }
        return null;
    }

    // --- actions (via `niri msg action`, fire-and-forget) ---

    function focusWorkspaceById(id) {
        // Ids are u64 (large); indices are u8 (small) so a bare number is
        // unambiguous to niri, but prefer the explicit Id reference shape
        // via JSON to avoid index/id confusion. We still go through the
        // `niri msg action` CLI as required by the migration contract.
        Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", "--reference", "id", String(id)]);
    }

    function focusWorkspaceByIndex(idx) {
        Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(idx)]);
    }

    function focusWindow(id) {
        Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(id)]);
    }

    function refresh() {
        if (!querySocket.connected)
            return;
        requestQuery("Workspaces");
        requestQuery("Windows");
        requestQuery("Outputs");
    }

    function requestQuery(name) {
        _pendingQueries.push(name);
        querySocket.write(JSON.stringify(name) + "\n");
        querySocket.flush();
    }

    // --- sockets ---

    Socket {
        id: eventSocket
        path: root.socketPath
        connected: root.socketPath !== ""

        onConnectedChanged: {
            if (connected) {
                root._streamHandshakeDone = false;
                // JSON string request, one line.
                eventSocket.write(JSON.stringify("EventStream") + "\n");
                eventSocket.flush();
            }
        }

        parser: SplitParser {
            onRead: line => {
                const text = String(line).trim();
                if (text === "")
                    return;
                let msg = null;
                try {
                    msg = JSON.parse(text);
                } catch (e) {
                    console.warn("sunset/NiriService: bad event line: " + text);
                    return;
                }
                if (!root._streamHandshakeDone) {
                    // First reply is {"Ok":{"Handled":{}}}; swallow it.
                    if (msg.Ok !== undefined && msg.Ok.Handled !== undefined) {
                        root._streamHandshakeDone = true;
                        // State replay follows; also seed via queries.
                        root.refresh();
                        return;
                    }
                    root._streamHandshakeDone = true;
                }
                root._handleEvent(msg);
            }
        }

        onError: error => {
            console.warn("sunset/NiriService event socket error: " + error);
        }
    }

    Socket {
        id: querySocket
        path: root.socketPath
        connected: root.socketPath !== ""

        onConnectedChanged: {
            if (connected) {
                root.queryReady = true;
                // Small delay lets the event stream handshake win first.
                refreshTimer.restart();
            } else {
                root.queryReady = false;
            }
        }

        parser: SplitParser {
            onRead: line => {
                const text = String(line).trim();
                if (text === "")
                    return;
                let msg = null;
                try {
                    msg = JSON.parse(text);
                } catch (e) {
                    console.warn("sunset/NiriService: bad query line: " + text);
                    return;
                }
                const expected = root._pendingQueries.length > 0 ? root._pendingQueries.shift() : "";
                root._handleQueryReply(expected, msg);
            }
        }

        onError: error => {
            console.warn("sunset/NiriService query socket error: " + error);
        }
    }

    Timer {
        id: refreshTimer
        interval: 250
        repeat: false
        onTriggered: root.refresh()
    }

    // Reconnect nudge: if NIRI_SOCKET appears late (niri restart),
    // flipping `connected` re-triggers onConnectedChanged.
    Timer {
        id: reconnectTimer
        interval: 5000
        repeat: true
        running: root.socketPath !== "" && !eventSocket.connected
        onTriggered: {
            eventSocket.connected = false;
            querySocket.connected = false;
            eventSocket.connected = true;
            querySocket.connected = true;
        }
    }

    // --- event handling ---

    function _handleEvent(event) {
        const keys = Object.keys(event);
        if (keys.length === 0)
            return;
        const type = keys[0];
        const data = event[type];
        switch (type) {
        case "WorkspacesChanged":
            _setWorkspaces(data.workspaces ?? []);
            break;
        case "WorkspaceActivated":
            _onWorkspaceActivated(data);
            break;
        case "WorkspaceActiveWindowChanged":
            _onWorkspaceActiveWindowChanged(data);
            break;
        case "WindowsChanged":
            _setWindows(data.windows ?? []);
            break;
        case "WindowOpenedOrChanged":
            if (data.window)
                _upsertWindow(data.window);
            break;
        case "WindowClosed":
            _removeWindow(data.id);
            break;
        case "WindowFocusChanged":
            _onWindowFocusChanged(data.id);
            break;
        case "OutputsChanged":
            // Newer niri sends full outputs map here.
            if (data.outputs !== undefined)
                outputs = data.outputs;
            else
                refresh();
            break;
        case "OverviewOpenedOrClosed":
        case "ConfigLoaded":
        case "KeyboardLayoutsChanged":
        case "KeyboardLayoutSwitched":
            // Tracked by other builders if needed; ignore here.
            break;
        default:
            // Forward-compatible: niri adds variants; ignore unknowns.
            break;
        }
    }

    function _handleQueryReply(expected, msg) {
        if (msg.Err !== undefined) {
            console.warn("sunset/NiriService query " + expected + " failed: " + JSON.stringify(msg.Err));
            return;
        }
        const ok = msg.Ok;
        if (ok === undefined)
            return;
        if (ok.Workspaces !== undefined) {
            _setWorkspaces(ok.Workspaces);
        } else if (ok.Windows !== undefined) {
            _setWindows(ok.Windows);
        } else if (ok.Outputs !== undefined) {
            outputs = ok.Outputs;
        } else if (ok.Handled !== undefined) {
            // Action ack; nothing to do.
        }
    }

    // --- state updaters ---

    function _sortedWorkspaces(list) {
        return list.slice().sort((a, b) => (a.idx ?? 0) - (b.idx ?? 0));
    }

    function _setWorkspaces(list) {
        workspaces = _sortedWorkspaces(list);
        // Recompute focused (single across outputs) + focused output.
        for (let i = 0; i < workspaces.length; ++i) {
            if (workspaces[i].is_focused) {
                focusedWorkspaceId = String(workspaces[i].id);
                focusedWorkspaceIdx = workspaces[i].idx ?? 1;
                focusedOutput = workspaces[i].output ?? "";
                break;
            }
        }
        _updateActiveWindow();
    }

    function _setWindows(list) {
        // Keep array order stable; bar sorts by workspace if needed.
        windows = list.slice();
        _updateActiveWindow();
    }

    function _upsertWindow(win) {
        let found = false;
        const next = windows.slice();
        for (let i = 0; i < next.length; ++i) {
            if (next[i].id === win.id) {
                next[i] = win;
                found = true;
                break;
            }
        }
        if (!found)
            next.push(win);
        windows = next;
        _updateActiveWindow();
    }

    function _removeWindow(id) {
        windows = windows.filter(w => w.id !== id);
        _updateActiveWindow();
    }

    function _onWorkspaceActivated(data) {
        // data: {id, focused}. Update is_focused globally when focused,
        // and is_active only for workspaces on the same output.
        const target = workspaces.find(w => String(w.id) === String(data.id));
        const targetOutput = target ? (target.output ?? "") : null;
        const next = workspaces.map(w => {
            const copy = Object.assign({}, w);
            if (data.focused)
                copy.is_focused = String(w.id) === String(data.id);
            if (targetOutput !== null && (w.output ?? "") === targetOutput)
                copy.is_active = String(w.id) === String(data.id);
            return copy;
        });
        workspaces = _sortedWorkspaces(next);
        if (data.focused && target) {
            focusedWorkspaceId = String(target.id);
            focusedWorkspaceIdx = target.idx ?? 1;
            focusedOutput = target.output ?? "";
        }
    }

    function _onWorkspaceActiveWindowChanged(data) {
        const next = workspaces.map(w => {
            if (String(w.id) !== String(data.workspace_id))
                return w;
            const copy = Object.assign({}, w);
            copy.active_window_id = data.active_window_id;
            return copy;
        });
        workspaces = next;
    }

    function _onWindowFocusChanged(id) {
        const next = windows.map(w => {
            const copy = Object.assign({}, w);
            copy.is_focused = id !== null && id !== undefined && w.id === id;
            return copy;
        });
        windows = next;
        _updateActiveWindow();
    }

    function _updateActiveWindow() {
        for (let i = 0; i < windows.length; ++i) {
            if (windows[i].is_focused) {
                activeWindowTitle = windows[i].title ?? "Desktop";
                activeWindowAppId = windows[i].app_id ?? "";
                activeWindowId = windows[i].id ?? -1;
                return;
            }
        }
        // No focused window (e.g. empty workspace): fall back to the
        // focused workspace's active_window_id if present.
        const fw = focusedWorkspace();
        if (fw && fw.active_window_id !== undefined && fw.active_window_id !== null) {
            for (let j = 0; j < windows.length; ++j) {
                if (windows[j].id === fw.active_window_id) {
                    activeWindowTitle = windows[j].title ?? "Desktop";
                    activeWindowAppId = windows[j].app_id ?? "";
                    activeWindowId = windows[j].id ?? -1;
                    return;
                }
            }
        }
        activeWindowTitle = "Desktop";
        activeWindowAppId = "";
        activeWindowId = -1;
    }

    Component.onCompleted: {
        if (socketPath === "")
            console.warn("sunset/NiriService: $NIRI_SOCKET is empty (not under niri?)");
    }
}
