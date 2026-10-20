pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Hyprstack.I18n
import Hyprstack.Services
import qs.components.misc
import qs.utils
import "KeyboardLayouts.js" as KeyboardLayouts

Singleton {
    id: root

    readonly property var toplevels: Hyprland.toplevels
    readonly property var workspaces: Hyprland.workspaces
    readonly property var monitors: Hyprland.monitors
    readonly property bool usingLua: Hyprland.usingLua

    readonly property HyprlandToplevel activeToplevel: {
        const t = Hyprland.activeToplevel;
        return t?.workspace?.name.startsWith("special:") || Hyprland.focusedWorkspace?.toplevels.values.length > 0 ? t : null;
    }
    readonly property HyprlandWorkspace focusedWorkspace: Hyprland.focusedWorkspace
    readonly property HyprlandMonitor focusedMonitor: Hyprland.focusedMonitor
    readonly property int activeWsId: focusedWorkspace?.id ?? 1

    readonly property HyprKeyboard keyboard: extras.devices.keyboards.find(kb => kb.main) ?? extras.devices.keyboards[0] ?? null
    readonly property bool capsLock: keyboard?.capsLock ?? false
    readonly property bool numLock: keyboard?.numLock ?? false
    readonly property string defaultKbLayout: keyboard?.layout.split(",")[0].trim() || "??"
    readonly property string kbLayoutFull: keyboard?.activeKeymap ?? Tr.trCtx("Unknown", "keyboard layout")
    readonly property string kbLayout: KeyboardLayouts.code(keyboard, kbMap)
    readonly property string xkbRulesPath: Quickshell.env("HYPRSTACK_XKB_RULES_PATH") || "/usr/share/X11/xkb/rules/base.lst"
    readonly property string xkbRulesDir: xkbRulesPath.slice(0, xkbRulesPath.lastIndexOf("/"))
    property var kbMap: new Map()

    readonly property alias extras: extras
    readonly property alias options: extras.options
    readonly property alias devices: extras.devices

    property string lastSpecialWorkspace: ""
    property string layoutMode: "scrolling"
    readonly property bool stacking: layoutMode === "stacking"
    property real stackingProgress: stacking ? 1 : 0
    property var windowStates: ({})
    property bool perMonitorWorkspaces: false
    property int workspaceCount: 10
    property var workspaceBases: ({})
    property bool secondaryOnSpecial: false

    signal configReloaded

    Behavior on stackingProgress {
        NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
    }

    function windowState(toplevel: HyprlandToplevel): var {
        return windowStates[toplevel?.lastIpcObject.address] ?? {};
    }

    function isMinimized(toplevel: HyprlandToplevel): bool {
        return !!windowState(toplevel).minimized;
    }

    function isMaximized(toplevel: HyprlandToplevel): bool {
        return !!windowState(toplevel).maximized || toplevel?.lastIpcObject.fullscreen === 1;
    }

    function setTaskTargets(monitor: string, targets: var): void {
        if (usingLua)
            extras.message(`eval hyprstack_layouts.set_task_targets(${JSON.stringify(monitor)}, require("utils.json").decode(${JSON.stringify(JSON.stringify(targets))}))`);
    }

    function taskWindows(screen: ShellScreen): list<HyprlandToplevel> {
        const monitor = monitorFor(screen);
        return toplevels.values.filter(t => {
            const ipc = t?.lastIpcObject;
            if (!ipc?.mapped || !ipc.class)
                return false;
            const hidden = windowState(t).minimized;
            if (hidden)
                return hidden.monitor === screen.name;
            return !t.workspace?.name.startsWith("special:") && ipc.monitor === monitor?.id;
        });
    }

    function windowAction(action: string, toplevel: HyprlandToplevel): void {
        const ipc = toplevel?.lastIpcObject;
        if (usingLua && ipc?.address && ipc?.stableId)
            extras.message(`eval hyprstack_layouts.action(${JSON.stringify(action)}, ${JSON.stringify(ipc.address)}, ${JSON.stringify(ipc.stableId)})`);
    }

    function dispatch(request: string): void {
        Hyprland.dispatch(request);
    }

    function workspaceBase(monitor: HyprlandMonitor): int {
        if (!perMonitorWorkspaces || !monitor)
            return 0;
        return workspaceBases[monitor.name] ?? Math.floor(((monitor.activeWorkspace?.id ?? 1) - 1) / workspaceCount) * workspaceCount;
    }

    function setSecondaryOnSpecial(enabled: bool): void {
        if (usingLua && perMonitorWorkspaces)
            extras.message(`eval hyprstack_layouts.configure_workspaces({secondary_on_special=${enabled}})`);
    }

    function workspaceNumber(id: int, monitor: HyprlandMonitor): int {
        return perMonitorWorkspaces ? id - workspaceBase(monitor) : id;
    }

    function focusWorkspace(ws: var, monitor: HyprlandMonitor): void {
        const output = monitor ?? focusedMonitor;
        if (usingLua && perMonitorWorkspaces && Number(ws) > 0) {
            extras.message(`eval hyprstack_layouts.focus(${workspaceNumber(Number(ws), output)}, ${JSON.stringify(output.name)})`);
        } else {
            dispatch(usingLua ? `hl.dsp.focus({ workspace = "${ws}" })` : `workspace ${ws}`);
        }
    }

    function stepWorkspace(direction: int, monitor: HyprlandMonitor): void {
        if (usingLua && perMonitorWorkspaces) {
            extras.message(`eval hyprstack_layouts.step(${direction}, ${JSON.stringify(monitor.name)})`);
        } else if (direction > 0 || monitor.activeWorkspace?.id > 1) {
            focusWorkspace(`r${direction > 0 ? "+" : "-"}1`, monitor);
        }
    }

    function toggleSpecial(name: string): void {
        if (usingLua && name === "hyprstack-secondary") {
            extras.message("eval hyprstack_layouts.toggle_special()");
            return;
        }
        dispatch(usingLua ? `hl.dsp.workspace.toggle_special("${name}")` : `togglespecialworkspace ${name}`);
    }

    function cycleSpecialWorkspace(direction: string): void {
        const openSpecials = workspaces.values.filter(w => w.name.startsWith("special:") && !w.name.startsWith("special:hyprstack-minimized-") && w.lastIpcObject.windows > 0);

        if (openSpecials.length === 0)
            return;

        const activeSpecial = focusedMonitor.lastIpcObject.specialWorkspace.name ?? "";

        if (!activeSpecial) {
            if (lastSpecialWorkspace) {
                const workspace = workspaces.values.find(w => w.name === lastSpecialWorkspace);
                if (workspace && workspace.lastIpcObject.windows > 0) {
                    focusWorkspace(lastSpecialWorkspace);
                    return;
                }
            }
            focusWorkspace(openSpecials[0].name);
            return;
        }

        const currentIndex = openSpecials.findIndex(w => w.name === activeSpecial);
        let nextIndex = 0;

        if (currentIndex !== -1) {
            if (direction === "next")
                nextIndex = (currentIndex + 1) % openSpecials.length;
            else
                nextIndex = (currentIndex - 1 + openSpecials.length) % openSpecials.length;
        }

        focusWorkspace(openSpecials[nextIndex].name);
    }

    function monitorNames(): list<string> {
        return monitors.values.map(e => e.name);
    }

    function monitorFor(screen: ShellScreen): HyprlandMonitor {
        // Reading the model keeps callers reactive when a screen arrives before
        // its compositor monitor object during hotplug.
        return screen ? monitors.values.find(m => m.name === screen.name) ?? null : null;
    }

    function activeToplevelFor(screen: ShellScreen): HyprlandToplevel {
        const monitor = monitorFor(screen);
        const window = activeToplevel;
        return monitor && window?.lastIpcObject.monitor === monitor.id && !isMinimized(window) ? window : null;
    }

    function trimWsName(name: string): string {
        return name.startsWith("special:") ? name.slice("special:".length) : name;
    }

    function toplevelsForWs(ws: int, ignoredTags = []): list<HyprlandToplevel> {
        return toplevels.values.filter(t => t.workspace && t.workspace.id === ws && !isToplevelIgnored(t, ignoredTags));
    }

    function isToplevelIgnored(toplevel: HyprlandToplevel, ignoredTags = []): bool {
        const ipc = toplevel?.lastIpcObject;
        if (!ipc?.class || !ipc.mapped)
            return true;

        return ipc.tags?.some(tag => ignoredTags.includes(tag.replace(/\*$/, ""))) ?? false;
    }

    function reloadDynamicConfs(): void {
        if (usingLua) {
            extras.batchMessage(['eval hl.bind("Caps_Lock", hl.dsp.global("hyprstack:refreshDevices"), { locked = true, non_consuming = true, ignore_mods = true, release = true })', 'eval hl.bind("Num_Lock", hl.dsp.global("hyprstack:refreshDevices"), { locked = true, non_consuming = true, ignore_mods = true, release = true })']);
        } else {
            extras.batchMessage(["keyword bindlni ,Caps_Lock,global,hyprstack:refreshDevices", "keyword bindlni ,Num_Lock,global,hyprstack:refreshDevices"]);
        }
    }

    function refreshToplevels(): void {
        Hyprland.refreshToplevels();
        // Quickshell drops refresh requests while its previous query is in flight.
        // Read once more after the event burst so an older reply cannot leave the
        // bar visible over a window that has just entered native fullscreen.
        trailingToplevelRefresh.restart();
    }

    Timer {
        id: trailingToplevelRefresh
        interval: 60
        onTriggered: Hyprland.refreshToplevels()
    }

    onUsingLuaChanged: reloadDynamicConfs()
    Component.onCompleted: reloadDynamicConfs()

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n.endsWith("v2"))
                return;

            if (n === "configreloaded") {
                root.configReloaded();
                root.reloadDynamicConfs();
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
                root.refreshToplevels();
            } else if (["workspace", "moveworkspace", "activespecial", "focusedmon"].includes(n)) {
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
            } else if (["openwindow", "closewindow", "movewindow"].includes(n)) {
                root.refreshToplevels();
                Hyprland.refreshWorkspaces();
            } else if (n.includes("mon")) {
                Hyprland.refreshMonitors();
            } else if (n.includes("workspace")) {
                Hyprland.refreshWorkspaces();
            } else if (n.includes("window") || n.includes("group") || ["pin", "fullscreen", "changefloatingmode", "minimize"].includes(n)) {
                root.refreshToplevels();
            }
        }

        target: Hyprland
    }

    Connections {
        function onLastIpcObjectChanged(): void {
            const specialName = root.focusedMonitor.lastIpcObject.specialWorkspace.name;

            if (specialName && specialName.startsWith("special:")) {
                root.lastSpecialWorkspace = specialName;
            }
        }

        target: root.focusedMonitor
    }

    FileView {
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/hyprstack-layouts-${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.windowStates = JSON.parse(text()).windows ?? {}
    }

    FileView {
        path: `${Paths.config}/layouts.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const state = JSON.parse(text());
            root.layoutMode = (state.mode ?? state.default_mode) === "stacking" ? "stacking" : "scrolling";
        }
    }

    FileView {
        path: `${Paths.config}/workspaces.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const state = JSON.parse(text());
            root.perMonitorWorkspaces = state.per_monitor === true;
            root.workspaceCount = Math.max(1, state.count ?? 10);
            root.workspaceBases = state.monitor_bases ?? {};
            root.secondaryOnSpecial = state.secondary_on_special === true;
        }
    }

    FileView {
        id: kbLayoutFile

        path: root.xkbRulesPath
        onLoaded: root.kbMap = KeyboardLayouts.parseRules(text())
    }

    IpcHandler {
        function refreshDevices(): void {
            extras.refreshDevices();
        }

        function cycleSpecialWorkspace(direction: string): void {
            root.cycleSpecialWorkspace(direction);
        }

        function listSpecialWorkspaces(): string {
            return root.workspaces.values.filter(w => w.name.startsWith("special:") && w.lastIpcObject.windows > 0).map(w => w.name).join("\n");
        }

        function toggleLayoutAll(): void {
            extras.message("eval hyprstack_layouts.toggle()");
        }

        target: "hypr"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "refreshDevices"
        description: "Reload devices"
        onPressed: extras.refreshDevices()
        onReleased: extras.refreshDevices()
    }

    HyprExtras {
        id: extras

        usingLua: Hyprland.usingLua
    }
}
