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

    // hypr-vars.lua owns the gesture finger counts too, and gestures.lua
    // registers its defaults on every config load, so these are both the
    // fallback for an untouched gesture setting and the baseline the shell
    // unsets from.
    property int varsGestureScrollFingers: 3
    property int varsGestureWorkspaceFingers: 3
    property int varsGestureOverviewFingers: 4

    // hypr-vars.lua can also carry the enabled flags gestures.lua and
    // layouts.lua consult, so they are both what an untouched toggle shows
    // and what the shell publishes back to the module when the toggle moves.
    property bool varsGestureScrollEnabled: true
    property bool varsGestureWorkspaceEnabled: true

    // The three managed gestures, mirroring gestures.lua. A duplicate
    // fingers/direction registration is rejected, so every change unsets the
    // old registration before adding the new one, and unset ignores the
    // action, which is how the function-action overview gesture is removed.
    readonly property var gestureDefs: [
        {
            key: "scroll",
            enabledProp: "touchpadGestureScroll",
            fingersProp: "touchpadGestureScrollFingers",
            varsProp: "varsGestureScrollFingers",
            varsLua: "gestureFingers",
            flagLua: "gestureScrollEnabled",
            binds: [{ direction: "horizontal", lua: '"scroll_move"', keyword: "scroll_move" }]
        },
        {
            key: "workspace",
            enabledProp: "touchpadGestureWorkspace",
            fingersProp: "touchpadGestureWorkspaceFingers",
            varsProp: "varsGestureWorkspaceFingers",
            varsLua: "workspaceSwipeFingers",
            flagLua: "gestureWorkspaceEnabled",
            binds: [{ direction: "vertical", lua: '"workspace"', keyword: "workspace" }]
        },
        {
            key: "overview",
            enabledProp: "touchpadGestureOverview",
            fingersProp: "touchpadGestureOverviewFingers",
            varsProp: "varsGestureOverviewFingers",
            varsLua: "gestureFingersMore",
            binds: [
                {
                    direction: "up",
                    lua: 'function() hl.dispatch(hl.dsp.global("hyprstack:overviewOpen")) end',
                    keyword: "dispatcher, global, hyprstack:overviewOpen"
                },
                {
                    direction: "down",
                    lua: 'function() hl.dispatch(hl.dsp.global("hyprstack:overviewAccept")) end',
                    keyword: "dispatcher, global, hyprstack:overviewAccept"
                }
            ]
        }
    ]

    // What is registered in the compositor right now.
    property var registeredGestures: ({})
    property string lastAppliedMode: ""

    // The last finger counts the shell assigned to the Lua variables
    // module. Invariant: the module holds the hypr-vars.lua value whenever
    // the shell does not own the gesture as enabled, so layouts.lua always
    // re-registers exactly what the reconcile records.
    property var moduleCounts: ({})
    // The last enabled flags the shell assigned to the module for the two
    // gestures layouts.lua guards with them.
    property var moduleFlags: ({})

    // What the compositor config registers for a gesture the shell does not
    // own: the vars finger counts, with scroll and workspace on in
    // scrolling mode only when the hypr-vars.lua flag allows them
    // (layouts.lua unsets them in stacking mode).
    function baselineGestureState(def): var {
        return { enabled: root.gestureAvailable(def) && root.fileGestureFlag(def), fingers: root[def.varsProp] };
    }

    function fileGestureFlag(def): bool {
        return def.key === "scroll" ? root.varsGestureScrollEnabled
            : def.key === "workspace" ? root.varsGestureWorkspaceEnabled : true;
    }

    // Enabled state from the settings alone, before the stacking clamp:
    // shell-owned once the toggle moved, otherwise the hypr-vars.lua flag
    // (overview has no flag and defaults to on).
    function gestureFileEnabled(def): bool {
        return root.shownBool(root.cfg[def.enabledProp], null, root.fileGestureFlag(def));
    }

    // Bookkeeping for a layout-mode transition, applied synchronously at
    // signal time: layouts.lua applies its scroll/workspace changes before
    // the shell observes the switch, and only touches those two gestures,
    // so the record is updated without sending anything and the overview
    // entry is left alone. A round-trip that coalesces before the deferred
    // timer still runs this once per leg.
    function reconcileLayoutGestures(): void {
        const registered = root.registeredGestures;
        const scrolling = Hypr.layoutMode === "scrolling";
        for (const def of gestureDefs) {
            if (def.key === "overview")
                continue;
            // layouts.lua adds on scrolling entry only when the module flag
            // is true and removes on stacking entry, so the flag predicts
            // exactly what it just did.
            registered[def.key] = { enabled: scrolling && root.moduleFlags[def.key], fingers: root[def.varsProp] };
        }
        root.lastAppliedMode = Hypr.layoutMode;
    }

    // Full baseline: gestures.lua re-registers the vars defaults for all
    // three gestures on every config load (re-executing variables.lua, so
    // the module returns to the file values), so startup and reloads
    // rebuild the whole record and reset the module counts.
    function reconcileGestures(): void {
        const registered = {};
        const counts = {};
        for (const def of gestureDefs) {
            registered[def.key] = root.baselineGestureState(def);
            counts[def.key] = root[def.varsProp];
        }
        root.registeredGestures = registered;
        root.moduleCounts = counts;
        // The reload re-executed variables.lua, so the module flags are the
        // file flags again.
        root.moduleFlags = { scroll: root.varsGestureScrollEnabled, workspace: root.varsGestureWorkspaceEnabled };
        root.lastAppliedMode = Hypr.layoutMode;
    }

    // layouts.lua unsets the scroll and workspace gestures in stacking
    // mode, so only the mode-independent overview gesture is available
    // there.
    function gestureAvailable(def): bool {
        return def.key === "overview" || Hypr.layoutMode === "scrolling";
    }

    function gestureState(def): var {
        return {
            enabled: root.gestureAvailable(def) && root.gestureFileEnabled(def),
            fingers: root.cfg[def.fingersProp] !== 0 ? root.cfg[def.fingersProp] : root[def.varsProp]
        };
    }

    function gestureUnset(fingers: int, bind): string {
        return Hypr.usingLua ? `eval hl.gesture({ fingers = ${fingers}, direction = "${bind.direction}", action = "unset" })`
            : `keyword gesture ${fingers}, ${bind.direction}, unset`;
    }

    function gestureAdd(fingers: int, bind): string {
        return Hypr.usingLua ? `eval hl.gesture({ fingers = ${fingers}, direction = "${bind.direction}", action = ${bind.lua} })`
            : `keyword gesture ${fingers}, ${bind.direction}, ${bind.keyword}`;
    }

    // Only the gestures whose effective state changed are re-registered, so
    // an untouched settings page sends nothing. All changes go out as one
    // ordered batch: a duplicate add is rejected, so the unset must precede
    // the add, and independent sockets would not guarantee that order.
    function applyGestures(): void {
        if (root.lastAppliedMode !== Hypr.layoutMode)
            root.reconcileLayoutGestures();
        const registered = root.registeredGestures;
        const messages = [];
        const varsUpdates = [];
        for (const def of root.gestureDefs) {
            const want = root.gestureState(def);
            const have = registered[def.key];
            if (Hypr.usingLua) {
                // layouts.lua skips the add/unset of a gesture whose flag is
                // false, so publish the unclamped enabled state (a user who
                // disabled a gesture wants it off in scrolling mode too) and
                // keep layouts.lua from unsetting a registration the shell
                // already removed, which pops a runtime error notification.
                if (def.flagLua !== undefined) {
                    const flag = root.gestureFileEnabled(def);
                    if (root.moduleFlags[def.key] !== flag) {
                        varsUpdates.push(`eval require("variables").${def.flagLua} = ${flag ? "true" : "false"}`);
                        root.moduleFlags[def.key] = flag;
                    }
                }
                // Enforce the module invariant for every gesture, whether
                // or not its registration changed: an enabled gesture
                // publishes the count the shell applies, a disabled one
                // (by the user or by stacking mode) the hypr-vars.lua
                // value, so layouts.lua never re-registers a stale count.
                const moduleCount = want.enabled ? want.fingers : root[def.varsProp];
                if (root.moduleCounts[def.key] !== moduleCount) {
                    varsUpdates.push(`eval require("variables").${def.varsLua} = ${moduleCount}`);
                    root.moduleCounts[def.key] = moduleCount;
                }
            }
            if (!have || (have.enabled === want.enabled && have.fingers === want.fingers))
                continue;
            if (have.enabled) {
                for (const bind of def.binds)
                    messages.push(root.gestureUnset(have.fingers, bind));
            }
            if (want.enabled) {
                for (const bind of def.binds)
                    messages.push(root.gestureAdd(want.fingers, bind));
            }
            registered[def.key] = want;
        }
        // The variables reset must go out even when the gesture messages
        // are empty: a forced-off gesture whose only diff is the finger
        // count still has to publish the file value to the Lua module,
        // otherwise layouts.lua re-registers a stale count on return.
        if (messages.length === 0 && varsUpdates.length === 0)
            return;
        root.registeredGestures = registered;
        Hypr.extras.batchMessage(varsUpdates.concat(messages));
    }

    // Cursor themes are icon folders holding a cursors subfolder, found in the
    // same places libXcursor looks. A stored theme whose package is gone stays
    // in the list so the settings never silently drop the choice.
    property var cursorThemes: []

    function cursorThemeRoots(): var {
        const roots = [];
        const add = path => {
            if (path !== "" && !roots.includes(path))
                roots.push(path);
        };
        for (const path of (Quickshell.env("XCURSOR_PATH") || "").split(":"))
            add(path);
        const home = Quickshell.env("HOME") || "";
        add(`${home}/.icons`);
        add(`${Quickshell.env("XDG_DATA_HOME") || `${home}/.local/share`}/icons`);
        for (const dir of (Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share").split(":"))
            add(`${dir}/icons`);
        return roots;
    }

    function refreshCursorThemes(): void {
        if (!themeScan.running)
            themeScan.running = true;
    }

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
    readonly property var gestureStamp: [cfg.touchpadGestureScroll, cfg.touchpadGestureScrollFingers,
        cfg.touchpadGestureWorkspace, cfg.touchpadGestureWorkspaceFingers, cfg.touchpadGestureOverview,
        cfg.touchpadGestureOverviewFingers, varsGestureScrollFingers, varsGestureWorkspaceFingers,
        varsGestureOverviewFingers, varsGestureScrollEnabled, varsGestureWorkspaceEnabled,
        Hypr.layoutMode]

    onInputStampChanged: inputTimer.restart()
    onCursorStampChanged: cursorTimer.restart()
    onGestureStampChanged: gestureTimer.restart()

    Component.onCompleted: {
        // The first read is blocking, so the cursor is applied with the real
        // hypr-vars.lua values rather than with the defaults.
        const vars = varsFile.text();
        if (vars !== "")
            parseVars(vars);
        root.reconcileGestures();
        inputTimer.restart();
        cursorTimer.restart();
        gestureTimer.restart();
        refreshCursorThemes();
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
        id: gestureTimer

        interval: 0
        onTriggered: root.applyGestures()
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
            // gestures.lua re-registers the vars defaults, so the baseline
            // is restored before the shell's own state is applied on top.
            root.reconcileGestures();
            gestureTimer.restart();
        }
        function onLayoutModeChanged(): void {
            // Synchronous, not via the stamp/timer: a round-trip that
            // coalesces before the timer fires still runs this twice, once
            // per leg, matching what layouts.lua already applied.
            root.reconcileLayoutGestures();
            gestureTimer.restart();
        }
        function onUsingLuaChanged(): void { inputTimer.restart(); }
    }

    // hypr-vars.lua is Lua the shell must not execute, so the cursor and
    // gesture keys are read out of it directly.
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
        const scrollFingers = /gestureFingers\s*=\s*(\d+)/.exec(contents);
        const workspaceFingers = /workspaceSwipeFingers\s*=\s*(\d+)/.exec(contents);
        const overviewFingers = /gestureFingersMore\s*=\s*(\d+)/.exec(contents);
        const scrollEnabled = /gestureScrollEnabled\s*=\s*(true|false)/.exec(contents);
        const workspaceEnabled = /gestureWorkspaceEnabled\s*=\s*(true|false)/.exec(contents);
        root.varsCursorTheme = theme && theme[1] !== "" ? theme[1] : "Adwaita";
        root.varsCursorSize = size ? Number(size[1]) : 24;
        root.varsGestureScrollFingers = scrollFingers ? Number(scrollFingers[1]) : 3;
        root.varsGestureWorkspaceFingers = workspaceFingers ? Number(workspaceFingers[1]) : 3;
        root.varsGestureOverviewFingers = overviewFingers ? Number(overviewFingers[1]) : 4;
        root.varsGestureScrollEnabled = scrollEnabled ? scrollEnabled[1] === "true" : true;
        root.varsGestureWorkspaceEnabled = workspaceEnabled ? workspaceEnabled[1] === "true" : true;
    }

    // A theme is a directory with a cursors subfolder. The loop skips roots
    // that do not exist, so find only ever reports what is installed.
    Process {
        id: themeScan

        command: ["sh", "-c", 'for d in "$@"; do if [ -d "$d" ]; then find "$d" -maxdepth 2 -type d -name cursors 2>/dev/null; fi; done', "theme-scan", ...root.cursorThemeRoots()]
        stdout: StdioCollector {
            onStreamFinished: {
                const themes = [];
                for (const line of text.split("\n")) {
                    const path = line.trim();
                    if (!path.endsWith("/cursors"))
                        continue;
                    const name = path.split("/").slice(-2)[0];
                    if (name !== "" && !themes.includes(name))
                        themes.push(name);
                }
                themes.sort();
                if (root.cfg.cursorTheme !== "" && !themes.includes(root.cfg.cursorTheme))
                    themes.push(root.cfg.cursorTheme);
                root.cursorThemes = themes;
            }
        }
    }
}
