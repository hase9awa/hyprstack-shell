pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import qs.utils

Singleton {
    id: root

    readonly property bool busy: process.running || debounce.running
    property bool pending
    property var errors: []
    property var skipped: []
    property var launchEnvironment: ({})
    readonly property var options: {
        const config = GlobalConfig.appearance.themeSync;
        return {enabled: config.enabled, gtk: config.gtk, qt: config.qt, java: config.java,
            system: config.system, terminals: config.terminals, liveReload: config.liveReload,
            kitty: config.kitty, foot: config.foot, alacritty: config.alacritty, wezterm: config.wezterm,
            ghostty: config.ghostty, konsole: config.konsole, xfce4Terminal: config.xfce4Terminal,
            gnomeTerminal: config.gnomeTerminal, tilix: config.tilix, xterm: config.xterm};
    }
    property string payload

    function requestSync(): void {
        debounce.restart();
    }

    function exec(command, workingDirectory = ""): void {
        // Quickshell launches children with its startup environment, even after
        // qputenv(). Supply the current overrides explicitly for every launch.
        Quickshell.execDetached({command: command, workingDirectory: workingDirectory,
            environment: root.launchEnvironment});
    }

    function launchEntry(entry: DesktopEntry): void {
        const command = entry.runInTerminal
            ? [...GlobalConfig.general.apps.terminal, `${Quickshell.shellDir}/assets/wrap_term_launch.sh`, ...entry.command]
            : entry.command;
        exec(command, entry.workingDirectory);
    }

    onOptionsChanged: requestSync()

    IpcHandler {
        function apply(): void { root.requestSync(); }

        function status(): string {
            return JSON.stringify({enabled: root.options.enabled, busy: root.busy,
                errors: root.errors, skipped: root.skipped});
        }

        target: "themeSync"
    }

    FileView {
        path: `${Paths.state}/scheme.json`
        watchChanges: true
        onFileChanged: { reload(); root.requestSync(); }
        onLoaded: root.requestSync()
    }

    Timer {
        id: debounce

        interval: 200
        onTriggered: {
            if (process.running) {
                root.pending = true;
                return;
            }
            root.pending = false;
            root.payload = JSON.stringify(root.options);
            process.stdinEnabled = true;
            process.running = true;
        }
    }

    Process {
        id: process

        command: ["python3", Paths.toLocalFile(Qt.resolvedUrl("../assets/theme_sync.py")), "--settings-stdin"]
        onStarted: {
            write(root.payload);
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const report = JSON.parse(text);
                    root.errors = report.errors ?? [];
                    root.skipped = report.skipped ?? [];
                    root.launchEnvironment = Object.assign({}, root.launchEnvironment, report.environment ?? {});
                    CUtils.setThemeEnvironment(report.environment ?? {});
                } catch (error) {
                    root.errors = [Tr.tr("Unable to synchronize application colours: %1").arg(error)];
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if ((exitCode !== 0 || exitStatus !== 0) && !root.errors.length)
                root.errors = [Tr.tr("Unable to synchronize application colours")];
            if (root.pending)
                root.requestSync();
        }
    }
}
