pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import qs.components.misc
import qs.services
import qs.utils
import "NotificationStore.js" as Store

Singleton {
    id: root

    property list<NotifData> list: []
    readonly property list<NotifData> notClosed: list.filter(n => !n.closed && !n.isTransient)
    readonly property list<NotifData> popups: list.filter(n => n.popup && !n.closed)
    readonly property int unreadCount: notClosed.filter(n => !n.read).length
    readonly property string imageHelper: Paths.toLocalFile(Qt.resolvedUrl("../assets/notification_tools.py"))
    property string lastError
    property alias dnd: props.dnd

    property bool loaded

    // The area picker owns the preview; notification history can request it
    // even when the sending process and original capture are long gone.
    signal screenshotRequested(path: string)

    function scheduleSave(): void {
        if (loaded)
            saveTimer.restart();
    }

    function saveNow(block: bool): void {
        if (!loaded)
            return;
        saveTimer.stop();
        storage.blockWrites = block;
        storage.setText(JSON.stringify({version: 1, dnd: root.dnd,
            notifications: root.notClosed.map(n => Store.serialize(n))}));
        storage.blockWrites = false;
    }

    Component.onDestruction: saveNow(true)

    function touch(notif: NotifData): void {
        if (list.includes(notif))
            list = [notif, ...list.filter(n => n !== notif)];
        scheduleSave();
    }

    function markAllRead(): void {
        for (const notif of list) {
            notif.read = true;
            notif.popup = false;
        }
        scheduleSave();
    }

    function clearAll(): void {
        const removed = list.slice();
        // Publish one model change instead of rebuilding every group for
        // every dismissed item in a large notification history.
        list = [];
        for (const notif of removed)
            notif.close();
        scheduleSave();
    }

    function clearGroup(appName: string): void {
        const removed = list.filter(n => n.appName === appName);
        list = list.filter(n => n.appName !== appName);
        for (const notif of removed)
            notif.close();
        scheduleSave();
    }

    function trimHistory(): void {
        for (const notif of notClosed.slice(500))
            notif.close();
    }

    function hasFullscreen(): bool {
        for (const monitor of Hypr.monitors.values) {
            if (Hypr.hasFullscreen(monitor?.activeWorkspace))
                return true;
        }
        return false;
    }

    function shouldShowPopup(): bool {
        if (props.dnd || ShellState.anySidebarOpen())
            return false;
        if (GlobalConfig.notifs.fullscreen === NotifsFullscreen.Off && hasFullscreen())
            return false;
        return true;
    }

    onDndChanged: {
        scheduleSave();
        if (dnd)
            for (const notif of popups)
                notif.popup = false;
        if (!loaded)
            return;
        if (!GlobalConfig.utilities.toasts.dndChanged)
            return;

        if (dnd)
            Toaster.toast(Tr.tr("Do not disturb enabled"), Tr.tr("Popup notifications are now disabled"), "do_not_disturb_on");
        else
            Toaster.toast(Tr.tr("Do not disturb disabled"), Tr.tr("Popup notifications are now enabled"), "do_not_disturb_off");
    }

    onListChanged: {
        scheduleSave();
    }

    Timer {
        interval: 60000
        running: root.notClosed.length > 0 && (ShellState.anySidebarOpen() || root.popups.length > 0)
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            for (const notif of root.notClosed) notif.updateTimeStr();
        }
    }

    Timer {
        id: saveTimer

        interval: 250
        onTriggered: {
            root.saveNow(false);
            cacheCleanup.restart();
        }
    }

    PersistentProperties {
        id: props

        property bool dnd

        reloadableId: "notifs"
    }

    NotificationServer {
        id: server

        keepOnReload: true
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true;
            const saved = notif.lastGeneration ? root.list.find(n => !n.notification
                && n.notificationId === String(notif.id) && n.appName === notif.appName) : null;

            const comp = notifComp.createObject(root, {
                popup: !notif.lastGeneration && root.shouldShowPopup(),
                read: ShellState.anySidebarOpen(),
                fromPreviousGeneration: notif.lastGeneration,
                notification: notif
            });
            // File loading and server replay can finish in either order.
            if (saved) {
                comp.restoreHistory(Store.restore([Store.serialize(saved)]).notifications[0]);
                saved.close();
            }
            root.list = [comp, ...root.list];
            root.trimHistory();
            if (comp.isTransient && !comp.popup)
                Qt.callLater(() => { if (comp.notification) comp.notification.expire(); });
        }
    }

    FileView {
        id: storage

        printErrors: false
        atomicWrites: true
        path: `${Paths.state}/notifs.json`
        onSaveFailed: err => root.lastError = "Unable to save notification history: " + err
        onLoaded: {
            try {
                const data = Store.restore(JSON.parse(text()));
                props.dnd = data.dnd;
                const restored = [];
                for (const properties of data.notifications) {
                    // Reloaded live notifications retain their DBus actions.
                    // IDs from a new server generation must never be matched.
                    const live = root.list.find(n => n.fromPreviousGeneration
                        && n.notificationId === properties.notificationId && n.appName === properties.appName);
                    if (live) {
                        live.restoreHistory(properties);
                    } else {
                        restored.push(notifComp.createObject(root, properties));
                    }
                }
                root.list = [...root.list, ...restored].sort((a, b) => b.time - a.time);
            } catch (err) {
                // A bad history file must not prevent new notifications.
                root.lastError = "Unable to restore notification history: " + err;
            }
            root.loaded = true;
            root.trimHistory();
            if (ShellState.anySidebarOpen())
                root.markAllRead();
            cacheCleanup.start();
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.loaded = true;
                root.scheduleSave();
            } else {
                root.lastError = "Unable to read notification history";
                root.loaded = true;
            }
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "clearNotifs"
        description: "Clear all notifications"
        onPressed: {
            root.clearAll();
        }
    }

    IpcHandler {
        function flush(): void { root.saveNow(true); }

        function clear(): void {
            root.clearAll();
        }

        function open(): void { ShellState.setNotificationCenter(ShellState.forActive(), true); }
        function close(): void { ShellState.setNotificationCenter(ShellState.forActive(), false); }
        function toggle(): void {
            const state = ShellState.forActive();
            if (state)
                ShellState.setNotificationCenter(state, !state.sidebar);
        }

        function unread(): int { return root.unreadCount; }

        function isDndEnabled(): bool {
            return props.dnd;
        }

        function toggleDnd(): void {
            props.dnd = !props.dnd;
        }

        function enableDnd(): void {
            props.dnd = true;
        }

        function disableDnd(): void {
            props.dnd = false;
        }

        target: "notifs"
    }

    Component {
        id: notifComp

        NotifData {}
    }

    Timer {
        id: cacheCleanup
        interval: 10000
        onTriggered: if (!prune.running) prune.running = true
    }

    Process {
        id: prune
        command: ["python3", root.imageHelper, "prune"]
    }
}
