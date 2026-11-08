pragma Singleton

import QtQuick
import Quickshell
import Hyprstack
import qs.components
import qs.services

Singleton {
    property ShellRoot shellRoot

    // What the search box should start with when the launcher next opens,
    // so a keybind can land directly in one of its modes.
    property string launcherPrefill

    // Whether any screen has a menu up. The shell holds the input then, so
    // the key that closes windows belongs to the shell and not to the
    // compositor.
    readonly property bool menuOpen: components.instances.some(c => c.rootWindow?.menuOpen ?? false)

    // prefill is deliberately untyped: a declared string turns a missing
    // argument into the word "undefined" rather than leaving it empty.
    function setLauncher(state: ScreenState, open: bool, prefill): void {
        if (!state)
            return;
        launcherPrefill = open ? (prefill ?? "") : "";
        Overview.close(false);
        for (const other of states.instances)
            if (other !== state)
                other.launcher = false;
        if (open) {
            state.dashboard = state.sidebar = state.session = false;
            const components = componentsFor(state.modelData);
            if (components?.interactionWrapper)
                components.interactionWrapper.dashboardHoverBlocked = true;
            components?.panels?.popouts.close();
        }
        state.launcher = open;
    }

    function closeDrawers(): void {
        for (const state of states.instances) {
            state.launcher = state.dashboard = state.sidebar = state.session = false;
            componentsFor(state.modelData)?.panels?.popouts.close();
        }
    }

    function setNotificationCenter(state: ScreenState, open: bool): void {
        if (!state)
            return;
        for (const other of states.instances)
            other.sidebar = false;
        if (open) {
            state.launcher = state.dashboard = state.session = false;
            const components = componentsFor(state.modelData);
            components?.panels?.popouts.close();
            state.sidebar = true;
            Notifs.markAllRead();
        }
    }

    function anySidebarOpen(): bool {
        return states.instances.some(s => s.sidebar);
    }

    function forScreen(screen: ShellScreen): ScreenState {
        for (const s of states.instances)
            if (s.modelData === screen)
                return s;
        return null;
    }

    function forActive(): ScreenState {
        const mon = Hypr.focusedMonitor;
        for (const s of states.instances)
            if (Hypr.monitorFor(s.modelData) === mon)
                return s;
        return null;
    }

    function componentsFor(screen: ShellScreen): Components {
        for (const c of components.instances)
            if (c.modelData === screen)
                return c;
        return null;
    }

    function componentsForActive(): Components {
        const mon = Hypr.focusedMonitor;
        for (const c of components.instances)
            if (Hypr.monitorFor(c.modelData) === mon)
                return c;
        return null;
    }

    Variants {
        id: states

        model: Screens.screens

        ScreenState {}
    }

    Variants {
        id: components

        model: Screens.screens

        Components {}
    }

    component Components: QtObject {
        required property ShellScreen modelData

        property var background
        property var rootWindow
        property var interactionWrapper
        property var bar
        property var panels
        property var overview

        function find(name: string, rootItem: Item): var {
            return CUtils.findChild(rootItem ?? rootWindow?.contentItem, name);
        }

        function findAll(name: string, rootItem: Item): var {
            return CUtils.findChildren(rootItem ?? rootWindow?.contentItem, name);
        }

        function findMatching(pattern: string, rootItem: Item): var {
            return CUtils.findChildrenMatching(rootItem ?? rootWindow?.contentItem, pattern);
        }
    }

    component ComponentRef: QtObject {
        required property ShellScreen screen
        required property string slot
        required property var component

        readonly property QtObject target: ShellState.componentsFor(screen)

        onTargetChanged: {
            if (target)
                target[slot] = component;
        }
        Component.onDestruction: {
            if (target && target[slot] === component)
                target[slot] = null;
        }
    }
}
