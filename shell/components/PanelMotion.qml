import QtQuick
import Hyprstack.Config

Scale {
    required property Item target
    required property real progress
    property bool fromBottom: false
    property bool deform: true

    // A small volume-preserving stretch follows the drawer's travel. Identity
    // at either endpoint keeps the settled text and input geometry pixel crisp.
    readonly property real stretch: deform && GlobalConfig.appearance.anim.shellPreset === "goop"
        ? Math.sin(Math.PI * Math.max(0, Math.min(1, progress))) * 0.035 : 0
    origin.x: target.width / 2
    origin.y: fromBottom ? target.height : 0
    xScale: 1 - stretch
    yScale: 1 / xScale
}
