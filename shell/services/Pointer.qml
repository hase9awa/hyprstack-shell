pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack
import Hyprstack.Config
import qs.services

Singleton {
    id: root

    readonly property var cfg: GlobalConfig.pointer

    // hypr-vars.lua still owns the cursor until the shell is told otherwise, so
    // its values are both what an untouched cursor control shows and what
    // setcursor falls back to when only one of the two has been changed.
    property string varsCursorTheme: "Adwaita"
    property int varsCursorSize: 24
    readonly property string cursorTheme: cfg.cursorTheme !== "" ? cfg.cursorTheme : varsCursorTheme
    readonly property int cursorSize: cfg.cursorSize > 0 ? cfg.cursorSize : varsCursorSize
    readonly property bool cursorManaged: cfg.cursorTheme !== "" || cfg.cursorSize > 0

    // What a control shows: the shell's own value once the user moved it,
    // otherwise whatever the compositor uses right now.
    function shownBool(explicit: int, live, fallback: bool): bool {
        if (explicit === PointerTriState.On)
            return true;
        if (explicit === PointerTriState.Off)
            return false;
        return typeof live === "boolean" ? live : fallback;
    }

    function shownReal(explicit: real, sentinel: real, live, fallback: real): real {
        if (explicit !== sentinel && typeof explicit === "number")
            return explicit;
        return typeof live === "number" ? live : fallback;
    }

    function shownInt(explicit: int, sentinel: int, live, fallback: int): int {
        if (explicit !== sentinel)
            return explicit;
        return typeof live === "number" ? Math.round(live) : fallback;
    }

    // Only the settings the user has touched are sent to the compositor.
    function optionValues(): var {
        const values = {};
        if (cfg.sensitivity !== -2)
            values["input:sensitivity"] = cfg.sensitivity;
        if (cfg.accelProfile !== "")
            values["input:accel_profile"] = cfg.accelProfile;
        if (cfg.naturalScroll !== PointerTriState.Inherit)
            values["input:natural_scroll"] = cfg.naturalScroll === PointerTriState.On;
        if (cfg.scrollFactor !== -1)
            values["input:scroll_factor"] = cfg.scrollFactor;
        if (cfg.leftHanded !== PointerTriState.Inherit)
            values["input:left_handed"] = cfg.leftHanded === PointerTriState.On;
        if (cfg.followMouse !== -1)
            values["input:follow_mouse"] = cfg.followMouse;
        if (cfg.touchpadNaturalScroll !== PointerTriState.Inherit)
            values["input:touchpad:natural_scroll"] = cfg.touchpadNaturalScroll === PointerTriState.On;
        if (cfg.touchpadTapToClick !== PointerTriState.Inherit)
            values["input:touchpad:tap-to-click"] = cfg.touchpadTapToClick === PointerTriState.On;
        if (cfg.touchpadDisableWhileTyping !== PointerTriState.Inherit)
            values["input:touchpad:disable_while_typing"] = cfg.touchpadDisableWhileTyping === PointerTriState.On;
        if (cfg.touchpadScrollFactor !== -1)
            values["input:touchpad:scroll_factor"] = cfg.touchpadScrollFactor;
        if (cfg.cursorHideTimeout !== -1)
            values["cursor:inactive_timeout"] = cfg.cursorHideTimeout;
        return values;
    }

    // The Lua config spells the dashed keys with underscores.
    function luaApply(values: var): string {
        const table = {};
        for (const key of Object.keys(values)) {
            const parts = key.split(":");
            let node = table;
            for (let i = 0; i < parts.length - 1; ++i) {
                if (!(parts[i] in node))
                    node[parts[i]] = {};
                node = node[parts[i]];
            }
            node[parts[parts.length - 1].replace(/-/g, "_")] = values[key];
        }
        return `eval hl.config(${root.luaTable(table)})`;
    }

    function luaTable(table: var): string {
        const fields = [];
        for (const key of Object.keys(table)) {
            const value = table[key];
            fields.push(`${key} = ${typeof value === "object" ? root.luaTable(value) : root.luaValue(value)}`);
        }
        return `{ ${fields.join(", ")} }`;
    }

    function luaValue(value): string {
        if (typeof value === "string")
            return JSON.stringify(value);
        if (typeof value === "boolean")
            return value ? "true" : "false";
        return String(value);
    }

    function keywordValue(value): string {
        if (typeof value === "boolean")
            return value ? "true" : "false";
        return String(value);
    }

    function applyInputs(): void {
        const values = root.optionValues();
        if (Object.keys(values).length === 0)
            return;

        if (Hypr.usingLua) {
            Hypr.extras.message(root.luaApply(values));
        } else {
            const options = {};
            for (const [key, value] of Object.entries(values))
                options[key] = root.keywordValue(value);
            Hypr.extras.applyOptions(options);
            return;
        }

        // An evaluated config change emits no event, so the live values the
        // settings page shows are refreshed by hand.
        refreshTimer.restart();
    }

    // The compositor reads the cursor from the environment while loading the
    // config, so a change goes through setcursor now and reaches launched apps
    // with the next reload (see hyprland/env.lua).
    function applyCursor(): void {
        if (root.cursorManaged)
            Hypr.extras.message(`setcursor ${root.cursorTheme} ${root.cursorSize}`);
    }

    // Every touched setting feeds a stamp, so moving any control re-applies.
    readonly property var inputStamp: [cfg.sensitivity, cfg.accelProfile, cfg.naturalScroll, cfg.scrollFactor,
        cfg.leftHanded, cfg.followMouse, cfg.touchpadNaturalScroll, cfg.touchpadTapToClick,
        cfg.touchpadDisableWhileTyping, cfg.touchpadScrollFactor, cfg.cursorHideTimeout]
    readonly property var cursorStamp: [cfg.cursorTheme, cfg.cursorSize]

    onInputStampChanged: inputTimer.restart()
    onCursorStampChanged: cursorTimer.restart()

    Component.onCompleted: {
        // The first read is blocking, so the cursor is applied with the real
        // hypr-vars.lua values rather than with the defaults.
        const vars = varsFile.text();
        if (vars !== "")
            parseVars(vars);
        inputTimer.restart();
        cursorTimer.restart();
    }

    Timer {
        id: inputTimer

        interval: 0
        onTriggered: root.applyInputs()
    }

    Timer {
        id: cursorTimer

        interval: 0
        onTriggered: root.applyCursor()
    }

    Timer {
        id: refreshTimer

        interval: 250
        onTriggered: Hypr.extras.refreshOptions()
    }

    Connections {
        target: Hypr

        function onConfigReloaded(): void {
            inputTimer.restart();
            cursorTimer.restart();
        }
        function onUsingLuaChanged(): void { inputTimer.restart(); }
    }

    // hypr-vars.lua is Lua the shell must not execute, so its two cursor keys
    // are read out of it directly.
    FileView {
        id: varsFile

        path: `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/hyprstack/hypr-vars.lua`
        preload: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseVars(text())
    }

    function parseVars(contents: string): void {
        const theme = /cursorTheme\s*=\s*["']([^"']*)["']/.exec(contents);
        const size = /cursorSize\s*=\s*(\d+)/.exec(contents);
        root.varsCursorTheme = theme && theme[1] !== "" ? theme[1] : "Adwaita";
        root.varsCursorSize = size ? Number(size[1]) : 24;
    }
}
