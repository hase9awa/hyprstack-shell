pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

Singleton {
    id: root

    property bool opened
    property var windows: []
    property var history: []
    property int index
    property ShellScreen screen
    readonly property var selected: windows[index] ?? null
    readonly property var candidates: Hypr.toplevels.values.filter(w => {
        const client = Hypr.clientData(w);
        return client?.mapped && (!client.workspace?.name.startsWith("special:") || Hypr.isMinimized(w));
    })

    function remember(): void {
        const id = Hypr.activeToplevel?.lastIpcObject.stableId;
        if (id) history = [id, ...history.filter(value => value !== id)].slice(0, 200);
    }

    function step(direction: int): void {
        if (!Hypr.stacking) return;
        if (!opened) {
            windows = candidates.slice().sort((a, b) => {
                const rank = w => {
                    const known = history.indexOf(w.lastIpcObject.stableId);
                    return known >= 0 ? known : 200 + (w.lastIpcObject.focusHistoryID < 0 ? 10000 : w.lastIpcObject.focusHistoryID);
                };
                return rank(a) - rank(b);
            });
            if (!windows.length) { close(); return; }
            screen = Screens.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Screens.screens[0];
            index = windows.indexOf(Hypr.activeToplevel);
            if (index < 0) index = direction > 0 ? -1 : 0;
            opened = true;
        }
        index = (index + direction + windows.length) % windows.length;
    }

    function close(): void {
        opened = false;
        windows = [];
        if (Hypr.usingLua)
            Hypr.extras.message("eval if hyprstack_layouts then hyprstack_layouts.end_switcher() end");
    }

    function accept(): void {
        const window = selected;
        close();
        if (window?.lastIpcObject.mapped) Hypr.windowAction("activate", window);
    }

    onCandidatesChanged: {
        if (!opened) return;
        const current = selected;
        windows = windows.filter(w => candidates.includes(w));
        if (!windows.length) { close(); return; }
        const next = windows.indexOf(current);
        index = next >= 0 ? next : Math.min(index, windows.length - 1);
    }

    Component.onCompleted: remember()
    Connections {
        target: Hypr
        function onActiveToplevelChanged(): void {
            root.remember();
            if (root.opened) root.close();
        }
        function onStackingChanged(): void { root.close(); }
        function onConfigReloaded(): void { root.close(); }
    }
}
