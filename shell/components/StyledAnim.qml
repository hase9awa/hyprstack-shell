import QtQuick
import Hyprstack.Config

Anim {
    id: root

    // Preserve hand-tuned timing in the default preset; new presets use the
    // common motion roles, including zero-duration reduced motion.
    property int defaultDuration: 200
    property int defaultEasing: Easing.Linear
    property int presetDuration: Tokens.anim.durations.expressiveFastSpatial
    property var presetEasing: Tokens.anim.expressiveFastSpatial
    readonly property bool useDefault: !["goop", "fluent", "snappy", "cinematic", "reduced"]
        .includes(GlobalConfig.appearance.anim.shellPreset)
    readonly property NumberAnimation original: NumberAnimation { easing.type: root.defaultEasing }

    duration: useDefault ? defaultDuration : presetDuration
    easing: bounded && GlobalConfig.appearance.anim.shellPreset === "goop"
        ? Tokens.anim.expressiveDefaultEffects : useDefault ? original.easing : presetEasing
}
