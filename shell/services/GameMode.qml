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

    property alias enabled: props.enabled
    // Whether the current state was switched on by an auto rule (not manually)
    property bool autoActive: false
    // Set while the auto logic flips `enabled` so toasts and autoActive stay untouched
    property bool autoChange: false

    // True while an auto-enable rule matches the focused window
    readonly property bool ruleActive: {
        const conf = GlobalConfig.utilities.gameMode;
        if (conf.autoFullscreen && Hypr.hasFullscreen(Hypr.focusedWorkspace))
            return true;
        const cls = (Hypr.clientData(Hypr.activeToplevel)?.class ?? "").toLowerCase();
        if (!cls)
            return false;
        const rules = conf.rules;
        for (let i = 0; i < rules.count; i++) {
            const pattern = rules.at(i).pattern.trim().toLowerCase();
            if (pattern && cls.includes(pattern))
                return true;
        }
        return false;
    }

    function setDynamicConfs(): void {
        const conf = GlobalConfig.utilities.gameMode;
        const opts = {};
        if (conf.animations)
            opts["animations:enabled"] = 0;
        if (conf.shadows)
            opts["decoration:shadow:enabled"] = 0;
        if (conf.blur)
            opts["decoration:blur:enabled"] = 0;
        if (conf.wobble)
            opts["decoration:wobble:enabled"] = 0;
        if (conf.glow)
            opts["decoration:glow:enabled"] = 0;
        if (conf.motionBlur)
            opts["decoration:motion_blur:enabled"] = 0;
        if (conf.gaps) {
            opts["general:gaps_in"] = 0;
            opts["general:gaps_out"] = 0;
            opts["general:border_size"] = 1;
        }
        if (conf.rounding)
            opts["decoration:rounding"] = 0;
        if (conf.tearing)
            opts["general:allow_tearing"] = 1;
        Hypr.extras.applyOptions(opts);
    }

    // Re-applies the option set after the settings changed while the mode is on
    function apply(): void {
        if (enabled)
            Hypr.extras.message("reload");
    }

    onEnabledChanged: {
        // Manual toggles (IPC, quick toggle card) must not be undone by rules later
        if (!autoChange)
            autoActive = false;
        if (enabled) {
            setDynamicConfs();
            const toastOn = autoChange ? GlobalConfig.utilities.gameMode.autoToast : GlobalConfig.utilities.toasts.gameModeChanged;
            if (toastOn)
                Toaster.toast(Tr.tr("Game mode enabled"), Tr.tr("Disabled Hyprland animations, blur, gaps and shadows"), "gamepad");
        } else {
            Hypr.extras.message("reload");
            const toastOn = autoChange ? GlobalConfig.utilities.gameMode.autoToast : GlobalConfig.utilities.toasts.gameModeChanged;
            if (toastOn)
                Toaster.toast(Tr.tr("Game mode disabled"), Tr.tr("Hyprland settings restored"), "gamepad");
        }
    }

    onRuleActiveChanged: {
        if (ruleActive && !enabled) {
            autoChange = true;
            autoActive = true;
            enabled = true;
            autoChange = false;
        } else if (!ruleActive && autoActive) {
            autoChange = true;
            autoActive = false;
            enabled = false;
            autoChange = false;
        }
    }

    PersistentProperties {
        id: props

        property bool enabled: Hypr.options["animations:enabled"] === 0 // qmllint disable missing-property

        reloadableId: "gameMode"
    }

    Connections {
        function onConfigReloaded(): void {
            if (props.enabled)
                root.setDynamicConfs();
        }

        target: Hypr
    }

    IpcHandler {
        function isEnabled(): bool {
            return props.enabled;
        }

        function toggle(): void {
            props.enabled = !props.enabled;
        }

        function enable(): void {
            props.enabled = true;
        }

        function disable(): void {
            props.enabled = false;
        }

        target: "gameMode"
    }
}
