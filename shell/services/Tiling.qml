pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services
import qs.utils

Singleton {
    id: root

    property bool desktopFrame: true
    property bool gaps: true
    property int gapsIn: 5
    property int gapsOut: 10
    property int focusBorderWidth: 1
    property string focusBorderColor: "primary"
    readonly property var baseBorderColorRoles: ["primary", "secondary", "tertiary", "error", "success", "onSurface", "outline",
        ...Array.from({length: 16}, (_, i) => `term${i}`)]
    readonly property var borderColorChoices: [
        {role: "primary", label: "Theme accent"},
        ...(ThemeSchemes.currentVariant?.borderColours ?? [
            {role: "secondary", label: "Secondary"}, {role: "tertiary", label: "Tertiary"},
            ...Array.from({length: 6}, (_, i) => ({role: `term${i + 1}`, label: `ANSI ${i + 1}`}))]),
        {role: "onSurface", label: "Text"}
    ]
    readonly property var borderColorRoles: borderColorChoices.map(choice => choice.role)
    property int windowRounding: 15
    property bool focusOnHover: true
    property bool edgeScroll: true
    property bool autoscroll: true
    property bool loaded: false
    property var hoverState: ({visible: false})

    function configureHover(screen: string, geometry: string): void {
        if (Hypr.usingLua)
            Hypr.extras.message(`eval if hl.plugin.hyprbars and hl.plugin.hyprbars.tiling_hover then hl.plugin.hyprbars.tiling_hover("shell",${JSON.stringify(screen)},${JSON.stringify(geometry)}) end`);
    }

    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "hyprstack_tiling_hover") {
                try { root.hoverState = JSON.parse(event.data); }
                catch (error) { console.warn(`Unable to read tiling hint: ${error}`); }
            }
        }
    }

    function validBorderRole(role: var): bool {
        return typeof role === "string" && (baseBorderColorRoles.includes(role) || /^palette_[A-Za-z][A-Za-z0-9_]{0,95}$/.test(role));
    }

    function set(option: string, value: var): void {
        if (!loaded) return;
        if (option === "desktopFrame") desktopFrame = !!value;
        else if (option === "gaps") gaps = !!value;
        else if (option === "gapsIn") gapsIn = Math.max(0, Math.min(100, Math.round(value)));
        else if (option === "gapsOut") gapsOut = Math.max(0, Math.min(100, Math.round(value)));
        else if (option === "focusBorderWidth") focusBorderWidth = Math.max(0, Math.min(10, Math.round(value)));
        else if (option === "focusBorderColor") focusBorderColor = validBorderRole(value) ? value : "primary";
        else if (option === "windowRounding") windowRounding = Math.max(0, Math.min(60, Math.round(value)));
        else if (option === "focusOnHover") focusOnHover = !!value;
        else if (option === "edgeScroll") edgeScroll = !!value;
        else if (option === "autoscroll") autoscroll = !!value;
        else return;
        storage.setText(JSON.stringify({desktopFrame: desktopFrame, gaps: gaps, gapsIn: gapsIn,
            gapsOut: gapsOut, focusBorderWidth: focusBorderWidth, focusBorderColor: focusBorderColor,
            windowRounding: windowRounding, focusOnHover: focusOnHover, edgeScroll: edgeScroll, autoscroll: autoscroll}));
        apply();
    }

    function apply(): void {
        if (loaded && Hypr.usingLua)
            Hypr.extras.message(`eval if hyprstack_layouts then hyprstack_layouts.tiling({gaps=${gaps},gapsIn=${gapsIn},gapsOut=${gapsOut},focusBorderWidth=${focusBorderWidth},focusBorderColor=${JSON.stringify(focusBorderColor)},windowRounding=${windowRounding},focusOnHover=${focusOnHover},edgeScroll=${edgeScroll},autoscroll=${autoscroll}}) end`);
    }

    FileView {
        id: storage
        path: `${Paths.config}/tiling.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.desktopFrame = data.desktopFrame !== false;
                root.gaps = data.gaps !== false;
                root.gapsIn = Math.max(0, Math.min(100, Math.round(data.gapsIn ?? 5)));
                root.gapsOut = Math.max(0, Math.min(100, Math.round(data.gapsOut ?? 10)));
                root.focusBorderWidth = Math.max(0, Math.min(10, Math.round(data.focusBorderWidth ?? 1)));
                root.focusBorderColor = root.validBorderRole(data.focusBorderColor) ? data.focusBorderColor : "primary";
                root.windowRounding = Math.max(0, Math.min(60, Math.round(data.windowRounding ?? 15)));
                root.focusOnHover = data.focusOnHover !== false;
                root.edgeScroll = data.edgeScroll !== false;
                root.autoscroll = data.autoscroll !== false;
            } catch (error) {
                console.warn(`Unable to load tiling appearance: ${error}`);
            }
            root.loaded = true;
            root.apply();
        }
        onLoadFailed: { root.loaded = true; root.apply(); }
    }

    Connections {
        target: Hypr
        function onConfigReloaded(): void { root.apply(); }
    }
}
