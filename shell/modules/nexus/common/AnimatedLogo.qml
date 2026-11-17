import QtQuick
import Hyprstack.Config
import qs.components

Logo {
    id: root
    property bool skipIntroAnimation: false
    signal animationCompleted
    opacity: skipIntroAnimation ? 1 : 0
    scale: skipIntroAnimation ? 1 : 0.92
    ParallelAnimation {
        running: !root.skipIntroAnimation
        onFinished: root.animationCompleted()
        StyledAnim {
            target: root; property: "opacity"; to: 1
            defaultDuration: 240
            presetDuration: Tokens.anim.durations.expressiveDefaultEffects
            presetEasing: Tokens.anim.expressiveDefaultEffects
        }
        StyledAnim { target: root; property: "scale"; to: 1; defaultDuration: 320; defaultEasing: Easing.OutCubic }
    }
}
