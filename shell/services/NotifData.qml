pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import qs.services
import qs.utils
import "NotificationStore.js" as Store

QtObject {
    id: notif

    property bool popup
    property bool closed
    property bool retiring: false
    property bool read
    property bool isTransient
    property bool fromPreviousGeneration
    property string historyId: "notification-" + Date.now() + "-" + Math.random().toString(36).slice(2)
    property var locks: new Set()

    property date time: new Date()
    property int ageMins: 0
    readonly property string timeStr: {
        if (ageMins < 1)
            return Tr.tr("now");

        const h = Math.floor(ageMins / 60);
        const d = Math.floor(h / 24);

        if (d > 0)
            return Tr.trCtx("%1d", "abbreviated notification age, days").arg(d);
        if (h > 0)
            return Tr.trCtx("%1h", "abbreviated notification age, hours").arg(h);
        return Tr.trCtx("%1m", "abbreviated notification age, minutes").arg(ageMins);
    }

    property Notification notification
    property string notificationId
    property string summary
    property string body
    property string appIcon
    property string appName
    property string image
    property bool screenshot
    property string screenshotPath
    property string desktopEntry
    property var hints // Hints are not persisted across restarts
    property real expireTimeout: GlobalConfig.notifs.defaultExpireTimeout
    property int urgency: NotificationUrgency.Normal
    property bool resident
    property bool hasActionIcons
    property list<var> liveActions
    readonly property list<var> actions: {
        const live = liveActions.filter(a => a.identifier !== "default");
        if (!screenshot)
            return live;
        // Screenshot actions belong to the shell, so they work even after the
        // sending process or notification server has restarted.
        return [
            {identifier: "open", text: Tr.tr("Open"), invoke: () => notif.imageAction("open")},
            {identifier: "copy", text: Tr.tr("Copy"), invoke: () => notif.imageAction("copy")},
            {identifier: "save", text: Tr.tr("Save"), invoke: () => notif.imageAction("save")},
            {identifier: "reveal", text: Tr.tr("Show in folder"), invoke: () => notif.imageAction("reveal")}
        ];
    }

    onReadChanged: Notifs.scheduleSave()
    onImageChanged: Notifs.scheduleSave()
    onScreenshotPathChanged: Notifs.scheduleSave()
    onClosedChanged: Notifs.scheduleSave()
    onPopupChanged: {
        if (!popup && isTransient && notification)
            notification.expire();
    }

    function imageAction(action: string): void {
        if (actionProcess.running)
            return;
        read = true;
        actionProcess.command = ["python3", Notifs.imageHelper, "action", action, screenshotPath, image];
        actionProcess.running = true;
    }

    function restoreHistory(properties: var): void {
        time = properties.time;
        read = properties.read;
        historyId = properties.historyId;
        if (properties.image)
            image = properties.image;
        if (properties.screenshotPath)
            screenshotPath = properties.screenshotPath;
        screenshot = properties.screenshot || screenshot;
        updateTimeStr();
    }

    function activate(): bool {
        read = true;
        popup = false;
        if (screenshot) {
            imageAction("open");
            return true;
        }
        const action = liveActions.find(a => a.identifier === "default");
        if (action) {
            action.invoke();
            return true;
        }
        const entry = DesktopEntries.applications.values.find(e => e.id === desktopEntry || e.id === desktopEntry + ".desktop");
        if (entry) {
            ThemeSync.launchEntry(entry);
            return true;
        }
        return false;
    }

    function updated(): void {
        time = new Date();
        updateTimeStr();
        read = ShellState.anySidebarOpen();
        popup = Notifs.shouldShowPopup();
        Notifs.touch(notif);
    }

    readonly property Process actionProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.error)
                        Notifs.lastError = result.error;
                    else if (result.action === "save")
                        notif.screenshotPath = result.path;
                } catch (err) {
                    Notifs.lastError = "Unable to use screenshot: " + err;
                }
            }
        }
    }

    readonly property Process cacheProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.path)
                        notif.image = result.path;
                } catch (_) {
                    // The source may have been removed by its application.
                }
            }
        }
    }

    readonly property bool hasFullscreen: {
        const monitor = Hypr.focusedMonitor;
        const specialName = monitor?.lastIpcObject.specialWorkspace?.name;
        if (specialName) {
            const specialWs = Hypr.workspaces.values.find(ws => ws.name === specialName);
            return specialWs?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
        }
        return monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
    }

    readonly property Timer timer: Timer {
        running: notif.popup && notif.expireTimeout !== 0
        interval: notif.expireTimeout > 0 ? notif.expireTimeout : notif.hasFullscreen ? GlobalConfig.notifs.fullscreenExpireTimeout : GlobalConfig.notifs.defaultExpireTimeout
        onTriggered: {
            if (notif.expireTimeout === 0)
                return;
            // Always expire if the active workspace has a fullscreen window
            if (GlobalConfig.notifs.expire || notif.hasFullscreen || notif.isTransient)
                notif.popup = false;
        }
    }

    readonly property LazyLoader dummyImageLoader: LazyLoader {
        active: false

        // qmllint disable uncreatable-type
        PanelWindow {
            // qmllint enable uncreatable-type
            implicitWidth: cacheImage.width
            implicitHeight: cacheImage.height
            color: "transparent"
            mask: Region {}

            Image {
                id: cacheImage

                function tryCache(): void {
                    if (status !== Image.Ready || width < 1 || height < 1)
                        return;

                    const cacheKey = notif.appName + notif.summary + notif.notificationId + notif.image;
                    let h1 = 0xdeadbeef, h2 = 0x41c6ce57, ch;
                    for (let i = 0; i < cacheKey.length; i++) {
                        ch = cacheKey.charCodeAt(i);
                        h1 = Math.imul(h1 ^ ch, 2654435761);
                        h2 = Math.imul(h2 ^ ch, 1597334677);
                    }
                    h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507);
                    h1 ^= Math.imul(h2 ^ (h2 >>> 13), 3266489909);
                    h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507);
                    h2 ^= Math.imul(h1 ^ (h1 >>> 13), 3266489909);
                    const hash = (h2 >>> 0).toString(16).padStart(8, 0) + (h1 >>> 0).toString(16).padStart(8, 0);

                    const cache = `${Paths.notifimagecache}/${hash}.png`;
                    CUtils.saveItem(this, Qt.resolvedUrl(cache), () => {
                        notif.image = cache;
                        notif.dummyImageLoader.active = false;
                    });
                }

                width: Math.max(1, notif.screenshot ? implicitWidth : Math.min(1280, implicitWidth))
                height: Math.max(1, width * implicitHeight / Math.max(1, implicitWidth))
                source: Paths.fileUrl(notif.image)
                fillMode: Image.PreserveAspectFit
                cache: false
                asynchronous: true
                opacity: 0

                onStatusChanged: tryCache()
                onWidthChanged: tryCache()
                onHeightChanged: tryCache()
            }
        }
    }

    readonly property Connections conn: Connections {
        function onClosed(reason: int): void {
            notif.notification = null;
            notif.liveActions = [];
            notif.popup = false;
            if (reason !== NotificationCloseReason.Expired || notif.isTransient)
                notif.close();
            else
                Notifs.scheduleSave();
        }

        function onSummaryChanged(): void {
            notif.summary = notif.notification.summary;
            notif.updated();
        }

        function onBodyChanged(): void {
            notif.body = notif.notification.body;
            notif.updated();
        }

        function onAppIconChanged(): void {
            notif.appIcon = notif.notification.appIcon;
        }

        function onAppNameChanged(): void {
            notif.appName = notif.notification.appName;
        }

        function onImageChanged(): void {
            notif.image = notif.notification.image;
            notif.maybeTriggerDummyImageLoader();
        }

        function onExpireTimeoutChanged(): void {
            notif.expireTimeout = notif.notification.expireTimeout;
        }

        function onUrgencyChanged(): void {
            notif.urgency = notif.notification.urgency;
        }

        function onResidentChanged(): void {
            notif.resident = notif.notification.resident;
        }

        function onHasActionIconsChanged(): void {
            notif.hasActionIcons = notif.notification.hasActionIcons;
        }

        function onActionsChanged(): void {
            // qmllint disable unresolved-type
            notif.liveActions = notif.notification.actions.map(a => ({
                        // qmllint enable unresolved-type
                        identifier: a.identifier,
                        text: a.text,
                        invoke: () => a.invoke()
                    }));
        }

        function onHintsChanged(): void {
            notif.hints = notif.notification.hints;
            notif.maybeTriggerDummyImageLoader();
        }

        function onTransientChanged(): void {
            notif.isTransient = notif.notification.transient;
            Notifs.scheduleSave();
        }

        target: notif.notification
    }

    function updateTimeStr(): void {
        const diff = Date.now() - time.getTime();
        ageMins = Math.max(0, Math.floor(diff / 60000));
    }

    function maybeTriggerDummyImageLoader(): void {
        if (!notification)
            return;
        const path = Store.imagePath(notification);
        screenshot = Store.isScreenshot(notification, path);
        if (screenshot && path)
            screenshotPath = path;
        if (path && !path.startsWith(Paths.notifimagecache + "/")) {
            // Local screenshots are copied byte-for-byte, retaining resolution.
            image = path;
            if (!cacheProcess.running) {
                cacheProcess.command = ["python3", Notifs.imageHelper, "cache", path];
                cacheProcess.running = true;
            }
        } else if (image && !image.startsWith("image://icon/") && !image.startsWith(Paths.notifimagecache)) {
            dummyImageLoader.active = true;
        }
    }

    function lock(item: Item): void {
        locks.add(item);
    }

    function unlock(item: Item): void {
        locks.delete(item);
        if (closed)
            close();
    }

    function close(): void {
        if (retiring)
            return;
        closed = true;
        popup = false;
        if (notification) {
            const remote = notification;
            notification = null;
            remote.dismiss();
        }
        if (locks.size === 0) {
            retiring = true;
            if (Notifs.list.includes(this))
                Notifs.list = Notifs.list.filter(n => n !== this);
            destroy();
        }
    }

    Component.onCompleted: {
        updateTimeStr();
        if (!notification)
            return;

        notificationId = notification.id;
        summary = notification.summary;
        body = notification.body;
        appIcon = notification.appIcon;
        appName = notification.appName;
        desktopEntry = notification.desktopEntry;
        isTransient = notification.transient;
        image = notification.image;
        maybeTriggerDummyImageLoader();
        expireTimeout = notification.expireTimeout;
        hints = notification.hints;
        urgency = notification.urgency;
        resident = notification.resident;
        hasActionIcons = notification.hasActionIcons;
        // qmllint disable unresolved-type
        liveActions = notification.actions.map(a => ({
                    // qmllint enable unresolved-type
                    identifier: a.identifier,
                    text: a.text,
                    invoke: () => a.invoke()
                }));
    }
}
