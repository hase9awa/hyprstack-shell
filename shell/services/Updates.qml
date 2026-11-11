pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import qs.services
import qs.utils

Singleton {
    id: root

    property var report: ({})
    property string action
    property string lastNotifiedVersion
    property bool noticeLoaded
    readonly property string phase: report.phase ?? "idle"
    readonly property bool busy: operation.running || ["checking", "downloading", "building", "starting", "waiting", "installing"].includes(phase)
    readonly property bool available: report.available ?? false
    readonly property bool ready: report.ready ?? false
    readonly property bool canInstall: report.can_install ?? false
    readonly property string latestVersion: report.latest_version ?? ""
    readonly property string error: report.error ?? ""
    readonly property string helper: `${Quickshell.env("HYPRSTACK_DATA_DIR") || Paths.data}/updater/updates.py`

    function receive(text: string): void {
        try {
            const data = JSON.parse(text);
            if ((data.updated_at ?? 0) < (report.updated_at ?? 0))
                return;
            report = data;
            notifyUpdate();
        } catch (error) {
            report = Object.assign({}, report, {phase: "error", error: Tr.tr("Unable to read the updater response")});
        }
    }

    function refresh(): void {
        if (!status.running)
            status.running = true;
    }

    function run(action: string): void {
        if (busy)
            return;
        root.action = action;
        operation.running = true;
    }

    function automaticCheck(): void {
        if (GlobalConfig.services.checkUpdates && !busy
                && Date.now() / 1000 - (report.checked_at ?? 0) >= 6 * 60 * 60)
            run("check");
    }

    function notifyUpdate(): void {
        if (!noticeLoaded || !available || !latestVersion || lastNotifiedVersion === latestVersion
                || !GlobalConfig.services.updateNotifications || Notifs.dnd)
            return;
        Toaster.toast(Tr.tr("Hyprstack update available"),
            Tr.tr("Version %1 is available. Open Settings → Updates to install it.").arg(latestVersion),
            "system_update", Toast.Info, 7000);
        lastNotifiedVersion = latestVersion;
        notice.setText(JSON.stringify({version: lastNotifiedVersion}));
    }

    Component.onCompleted: refresh()

    IpcHandler {
        target: "updates"
        function status(): string {
            return JSON.stringify(Object.assign({}, root.report, {current_version: CUtils.version,
                busy: root.busy, phase: root.phase, available: root.available, ready: root.ready}));
        }
        function check(): void { root.run("check"); }
    }

    Connections {
        target: GlobalConfig.services
        function onCheckUpdatesChanged(): void { if (GlobalConfig.services.checkUpdates) root.automaticCheck(); }
        function onUpdateNotificationsChanged(): void { root.notifyUpdate(); }
    }

    Connections {
        target: Notifs
        function onDndChanged(): void { root.notifyUpdate(); }
    }

    FileView {
        id: notice
        path: `${Paths.state}/updates/notice.json`
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try { root.lastNotifiedVersion = JSON.parse(text()).version ?? ""; } catch (error) {}
            root.noticeLoaded = true;
            root.notifyUpdate();
        }
        onLoadFailed: {
            root.noticeLoaded = true;
            root.notifyUpdate();
        }
    }

    Timer {
        interval: 45000
        running: true
        onTriggered: root.automaticCheck()
    }

    Timer {
        interval: 6 * 60 * 60 * 1000
        running: GlobalConfig.services.checkUpdates
        repeat: true
        onTriggered: root.automaticCheck()
    }

    Timer {
        interval: 2000
        running: root.busy
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: status
        command: ["python3", root.helper, "--current-version", CUtils.version, "status"]
        stdout: StdioCollector { onStreamFinished: root.receive(text) }
    }

    Process {
        id: operation
        command: ["python3", root.helper, "--current-version", CUtils.version, root.action]
        stdout: StdioCollector { onStreamFinished: root.receive(text) }
        onExited: (exitCode, exitStatus) => {
            if (exitStatus !== 0)
                root.report = Object.assign({}, root.report, {phase: "error", error: Tr.tr("The updater stopped unexpectedly")});
            root.refresh();
        }
    }
}
