pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// NotificationService.qml — canonical notification data layer.
// NotificationServer + DND + history (20, dunst `history_length` parity).
//
// SOLE-OWNER NOTE: org.freedesktop.Notifications can have exactly one
// owner. components/Toasts.qml (landed earlier, other builder owns it)
// currently embeds its OWN NotificationServer + `silent` + history(20) +
// IpcHandler target "notifications". Running two servers means the second
// fails to claim the bus (harmless warning, first wins) — but history/DND
// would split. MIGRATION PATH: Toasts builder should drop its embedded
// server/IPC and bind to this service instead:
//   model: NotificationService.serverNotifications
//   visible: !NotificationService.dnd && ...
//   onLeftClick: NotificationService.dismiss(...)
// This file intentionally has NO IpcHandler (Toasts owns target
// "notifications" until that merge) and NO colors (Theme.* lives in UI).
Singleton {
    id: root

    // DND flag. When true, data is still tracked + kept in history;
    // UI layer hides toasts (same contract as Toasts.silent).
    property bool dnd: false

    // Plain-data history (dunst `history_length 20` + `sticky_history yes`).
    // Newest first, capped at 20, survives dismiss/expire.
    property var history: []
    readonly property int historyLimit: 20
    // Dunst `notification_limit 5`: max toasts on screen at once (for UI).
    readonly property int visibleLimit: 5
    readonly property int unreadCount: server.trackedNotifications.values.length

    // Expose the ObjectModel for UI binding after migration.
    readonly property var serverNotifications: server.trackedNotifications

    function pushHistory(n: Notification) {
        const entry = {
            "app": n.appName,
            "summary": n.summary,
            "body": n.body,
            "urgency": n.urgency.toString(),
            "time": Date.now()
        };
        history = [entry].concat(history).slice(0, historyLimit);
    }

    function toggleDnd() {
        dnd = !dnd;
    }

    // Alias so Toasts migration is a rename, not a rewrite.
    function toggleSilent() {
        toggleDnd();
    }

    function dismiss(n: Notification) {
        if (n)
            n.dismiss();
    }

    function dismissAll() {
        const vals = server.trackedNotifications.values;
        for (let i = 0; i < vals.length; ++i)
            vals[i].dismiss();
    }

    function clearAll() {
        dismissAll();
    }

    function clearHistory() {
        history = [];
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

        onNotification: n => {
            n.tracked = true;
            root.pushHistory(n);
            // Enforce on-screen cap: dismiss oldest non-critical beyond limit.
            // Critical stays sticky (dunst timeout 0 parity; UI owns timers).
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
}
