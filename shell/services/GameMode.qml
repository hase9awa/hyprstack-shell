pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import qs.services

Singleton {
    id: root

    readonly property var preferences: GlobalConfig.utilities.gameMode
    readonly property bool ruleMatches: {
        if (!preferences.autoFullscreen && preferences.rules.count === 0)
            return false;
        const client = Hypr.clientData(Hypr.activeToplevel);
        if (preferences.autoFullscreen && client?.fullscreen >= 2)
            return true;
        const windowClass = (client?.class ?? "").toLowerCase();
        return windowClass !== "" && preferences.rules.values.some(rule => {
            const pattern = rule.pattern.trim().toLowerCase();
            return pattern !== "" && windowClass.includes(pattern);
        });
    }
    readonly property bool enabled: manual.enabled || (ruleMatches && !autoSuppressed)
    property bool autoSuppressed: false
    property bool manualChange: false
    property bool ready: false

    readonly property bool animationsSuppressed: enabled && preferences.animations
    readonly property bool blurSuppressed: enabled && preferences.blur
    readonly property bool tearingEnabled: enabled && preferences.tearing
    readonly property var decorationOverrides: ({
        blur: blurSuppressed,
        shadows: enabled && preferences.shadows,
        wobble: enabled && preferences.wobble,
        motionBlur: enabled && preferences.motionBlur
    })
    readonly property var tilingOverrides: ({
        gaps: enabled && preferences.gaps,
        rounding: enabled && preferences.rounding
    })

    // Keep the legacy compositor path for sessions using a non-Lua config.
    readonly property var legacyOverrides: {
        const options = {};
        if (Hypr.usingLua || !enabled)
            return options;
        if (animationsSuppressed)
            options["animations:enabled"] = 0;
        if (decorationOverrides.shadows)
            options["decoration:shadow:enabled"] = 0;
        if (blurSuppressed)
            options["decoration:blur:enabled"] = 0;
        if (decorationOverrides.wobble)
            options["decoration:wobble:enabled"] = 0;
        if (decorationOverrides.motionBlur)
            options["decoration:motion_blur:enabled"] = 0;
        if (tilingOverrides.gaps) {
            options["general:gaps_in"] = 0;
            options["general:gaps_out"] = 0;
            options["general:border_size"] = 1;
        }
        if (tilingOverrides.rounding)
            options["decoration:rounding"] = 0;
        if (tearingEnabled)
            options["general:allow_tearing"] = 1;
        return options;
    }
    property var appliedLegacyOverrides: ({})

    function updateCompositor(reloaded: bool): void {
        if (Hypr.usingLua) {
            Hypr.extras.message("eval if hyprstack_layouts then hyprstack_layouts.game_tearing(" + tearingEnabled + ") end");
            return;
        }

        const options = legacyOverrides;
        const restore = !reloaded && Object.keys(appliedLegacyOverrides).some(key => !(key in options));
        appliedLegacyOverrides = options;
        if (restore)
            Hypr.extras.message("reload");
        else
            Hypr.extras.applyOptions(options);
    }

    function setEnabled(value: bool): void {
        manualChange = true;
        if (value) {
            manual.enabled = true;
            autoSuppressed = false;
        } else {
            autoSuppressed = ruleMatches;
            manual.enabled = false;
        }
        manualChange = false;
    }

    function toggle(): void {
        setEnabled(!enabled);
    }

    onRuleMatchesChanged: {
        if (!ruleMatches)
            autoSuppressed = false;
    }
    onTearingEnabledChanged: compositorTimer.restart()
    onLegacyOverridesChanged: compositorTimer.restart()
    onEnabledChanged: {
        const notify = manualChange ? GlobalConfig.utilities.toasts.gameModeChanged : preferences.autoToast;
        if (!ready || !notify)
            return;

        if (enabled)
            Toaster.toast(Tr.tr("Game mode enabled"), "", "gamepad");
        else
            Toaster.toast(Tr.tr("Game mode disabled"), Tr.tr("Hyprland settings restored"), "gamepad");
    }

    Component.onCompleted: {
        ready = true;
        compositorTimer.restart();
    }

    Timer {
        id: compositorTimer
        interval: 0
        onTriggered: root.updateCompositor(false)
    }

    PersistentProperties {
        id: manual

        property bool enabled: false
        reloadableId: "gameMode"
    }

    Connections {
        target: Hypr
        function onConfigReloaded(): void { root.updateCompositor(true); }
        function onUsingLuaChanged(): void { compositorTimer.restart(); }
    }

    IpcHandler {
        target: "gameMode"
        function isEnabled(): bool { return root.enabled; }
        function toggle(): void { root.toggle(); }
        function enable(): void { root.setEnabled(true); }
        function disable(): void { root.setEnabled(false); }
    }
}
