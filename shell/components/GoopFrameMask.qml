pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "../utils/vendor/goopui/core.js" as Upstream

// One stationary frame field per monitor. Drawers sample it into their own
// liquid field; its filtered baseline prevents repainting the existing frame.
Item {
    id: root
    required property Item frameItem
    property bool active: false
    property rect innerRect
    property real blur: Upstream.GoopCore.qtFilterParams.blur
    readonly property real dpr: Math.max(1,Screen.devicePixelRatio)
    readonly property int downscale: Upstream.GoopCore.fieldScale(blur*dpr)
    readonly property size fieldSize: Qt.size(Math.max(1,Math.ceil(width*dpr/downscale)),
        Math.max(1,Math.ceil(height*dpr/downscale)))
    readonly property alias rawTexture: rawTexture
    readonly property alias blurredTexture: verticalTexture

    enabled: false
    visible: active

    ShaderEffectSource {
        id: rawTexture
        sourceItem: root.active ? root.frameItem : null
        textureSize: Qt.size(Math.max(1,Math.ceil(root.width*root.dpr)),Math.max(1,Math.ceil(root.height*root.dpr)))
        hideSource: true
        visible: true
        smooth: true
    }

    GoopBlurPass {
        id: horizontal
        input: rawTexture
        fieldSize: root.fieldSize
        sigma: root.blur*root.dpr/root.downscale
        blurDirection: Qt.vector2d(1/root.fieldSize.width,0)
    }

    ShaderEffectSource {
        id: horizontalTexture
        sourceItem: root.active ? horizontal : null
        textureSize: root.fieldSize
        format: ShaderEffectSource.RGBA16F
        hideSource: true
        visible: true
        smooth: true
    }

    GoopBlurPass {
        id: vertical
        input: horizontalTexture
        fieldSize: root.fieldSize
        sigma: root.blur*root.dpr/root.downscale
        blurDirection: Qt.vector2d(0,1/root.fieldSize.height)
    }

    ShaderEffectSource {
        id: verticalTexture
        sourceItem: root.active ? vertical : null
        textureSize: root.fieldSize
        format: ShaderEffectSource.RGBA16F
        hideSource: true
        visible: true
        smooth: true
    }
}
