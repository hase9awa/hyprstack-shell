pragma Singleton

import QtQuick
import Quickshell
import Hyprstack.Config

Singleton {
    id: root

    readonly property var shellPresets: ["default", "goop", "fluent", "snappy", "cinematic", "reduced"]
    readonly property var windowPresets: ["default", "spring", "glide", "snappy", "cinematic", "reduced"]
    readonly property string shellPreset: shellPresets.includes(GlobalConfig.appearance.anim.shellPreset)
        ? GlobalConfig.appearance.anim.shellPreset : "default"
    readonly property string windowPreset: windowPresets.includes(GlobalConfig.appearance.anim.windowPreset)
        ? GlobalConfig.appearance.anim.windowPreset : "default"

    function apply(): void {
        if (Hypr.usingLua)
            Hypr.extras.message(`eval require("hyprland.animations").apply(${JSON.stringify(windowPreset)}, ${JSON.stringify(shellPreset)}, ${GameMode.enabled})`);
    }

    onShellPresetChanged: applyTimer.restart()
    onWindowPresetChanged: applyTimer.restart()
    Component.onCompleted: applyTimer.restart()

    Timer {
        id: applyTimer
        interval: 0
        onTriggered: root.apply()
    }

    Connections {
        target: Hypr
        function onConfigReloaded(): void { applyTimer.restart(); }
        function onUsingLuaChanged(): void { applyTimer.restart(); }
    }

    Connections {
        target: GameMode
        function onEnabledChanged(): void { applyTimer.restart(); }
    }
}
