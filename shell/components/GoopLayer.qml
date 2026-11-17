pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Hyprstack.Blobs
import "../utils/vendor/goopui/core.js" as Upstream

// GoopRenderer for Qt Quick. The body and original circle commands are drawn
// into one source-over field, then use upstream's Gaussian kernel and threshold.
Item {
    id: root
    property var body: ({cx:0,cy:0,w:0,h:0})
    property var circles: []
    property var bodyShape: null
    property rect panelRect: Qt.rect(0,0,1,1)
    property rect fieldRect: Qt.rect(0,0,1,1)
    property color paintColor: "white"
    property real cornerRadius: 0
    property real blur: 5
    property real contrast: 20
    property real threshold: 0.4
    property bool cutoutHost: false
    property bool live: true
    property GoopFrameMask frameMask: null
    readonly property bool joinsFrame: frameMask?.active ?? false
    readonly property real dpr: Math.max(1, Screen.devicePixelRatio)
    readonly property int downscale: Upstream.GoopCore.fieldScale(blur*dpr)
    readonly property size fieldSize: Qt.size(Math.max(1,Math.ceil(width*dpr/downscale)),
        Math.max(1,Math.ceil(height*dpr/downscale)))
    readonly property var taps: Upstream.GoopCore.gaussianTaps(Math.max(.01,blur*dpr/downscale))
    property int circleCapacity: 128
    readonly property alias maskTexture: verticalTexture

    x: fieldRect.x
    y: fieldRect.y
    width: Math.max(1,fieldRect.width)
    height: Math.max(1,fieldRect.height)
    enabled: false

    // Qt expects a valid provider for every declared sampler, even when the
    // shader's frame branch is disabled (previews and workspace indicators).
    Rectangle { id: emptyField; width: 1; height: 1; color: "transparent" }
    ShaderEffectSource {
        id: emptyTexture
        sourceItem: root.live ? emptyField : null
        textureSize: Qt.size(1,1)
        visible: true
        hideSource: true
    }

    Item {
        id: scene
        anchors.fill: parent
        visible: true

        ShaderEffect {
            anchors.fill: parent
            visible: root.joinsFrame
            property var frameSource: root.frameMask?.rawTexture ?? emptyTexture
            property rect fieldRect: root.fieldRect
            property vector2d frameViewport: Qt.vector2d(root.frameMask?.width ?? 1,root.frameMask?.height ?? 1)
            fragmentShader: "qrc:/shaders/goop-frame.frag.qsb"
            vertexShader: "qrc:/shaders/goop.vert.qsb"
        }

        Rectangle {
            width: Math.max(0,root.panelRect.width)
            height: Math.max(0,root.panelRect.height)
            x: root.body.cx-root.fieldRect.x-width/2
            y: root.body.cy-root.fieldRect.y-height/2
            radius: root.cornerRadius
            color: "white"
            antialiasing: true
            visible: !root.bodyShape && root.body.w>0 && root.body.h>0
            transform: Scale {
                origin.x: root.panelRect.width/2
                origin.y: root.panelRect.height/2
                xScale: root.body.w/Math.max(1,root.panelRect.width)
                yScale: root.body.h/Math.max(1,root.panelRect.height)
            }
        }

        GoopBody {
            x: root.body.cx-root.body.w/2-root.fieldRect.x
            y: root.body.cy-root.body.h/2-root.fieldRect.y
            width: root.body.w
            height: root.body.h
            radiusX: root.bodyShape?.rx ?? 0
            radiusY: root.bodyShape?.ry ?? 0
            lean: root.bodyShape?.lean ?? 0
            side: root.bodyShape?.side ?? "bottom"
            joinFrame: root.joinsFrame
            visible: !!root.bodyShape && width>0 && height>0
        }

        Repeater {
            // Stable pool: changing circle data never recreates a delegate.
            model: root.circleCapacity
            Rectangle {
                id: circle
                required property int index
                readonly property var blob: root.circles[index]
                width: 20
                height: 20
                radius: 10
                color: "white"
                antialiasing: true
                x: (blob?.x ?? 0)-root.fieldRect.x-10
                y: (blob?.y ?? 0)-root.fieldRect.y-10
                opacity: blob?.opacity ?? 1
                visible: (blob?.r ?? 0)>0
                transform: Scale {
                    origin.x: 10
                    origin.y: 10
                    xScale: (circle.blob?.r ?? 0)/10*(circle.blob?.sx ?? 1)
                    yScale: (circle.blob?.r ?? 0)/10*(circle.blob?.sy ?? 1)
                }
            }
        }
    }

    ShaderEffectSource {
        id: sceneTexture
        objectName: "goopSceneTexture"
        sourceItem: root.live ? scene : null
        textureSize: root.fieldSize
        visible: true
        smooth: true
        hideSource: true
    }

    GoopBlurPass {
        id: horizontal
        input: sceneTexture
        fieldSize: root.fieldSize
        sigma: root.blur*root.dpr/root.downscale
        blurDirection: Qt.vector2d(1/root.fieldSize.width,0)
    }

    ShaderEffectSource {
        id: horizontalTexture
        objectName: "goopHorizontalTexture"
        sourceItem: root.live ? horizontal : null
        textureSize: root.fieldSize
        format: ShaderEffectSource.RGBA16F
        visible: true
        smooth: true
        hideSource: true
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
        objectName: "goopVerticalTexture"
        sourceItem: root.live ? vertical : null
        textureSize: root.fieldSize
        format: ShaderEffectSource.RGBA16F
        visible: true
        smooth: true
        hideSource: true
    }

    ShaderEffect {
        id: edgeOutput
        objectName: "goopThreshold"
        anchors.fill: parent
        property var source: verticalTexture
        property vector2d textureExtent: Qt.vector2d(root.fieldSize.width,root.fieldSize.height)
        property real contrast: root.contrast
        property real threshold: root.threshold
        property color paintColor: root.paintColor
        property rect fieldRect: root.fieldRect
        property rect hostRect: Qt.rect(root.body.cx-root.body.w/2,root.body.cy-root.body.h/2,root.body.w,root.body.h)
        property real hostRadius: Math.min(root.cornerRadius,root.body.w/2,root.body.h/2)
        property bool cutoutHost: root.cutoutHost
        property bool joinsFrame: root.joinsFrame
        property var frameSource: root.frameMask?.rawTexture ?? emptyTexture
        property var frameBaseline: root.frameMask?.blurredTexture ?? emptyTexture
        property vector2d frameViewport: Qt.vector2d(root.frameMask?.width ?? 1,root.frameMask?.height ?? 1)
        property vector2d frameExtent: Qt.vector2d(root.frameMask?.fieldSize.width ?? 1,root.frameMask?.fieldSize.height ?? 1)
        fragmentShader: "qrc:/shaders/goop-edge.frag.qsb"
        vertexShader: "qrc:/shaders/goop.vert.qsb"
    }

    readonly property var diagnostics: ({field:fieldRect,size:fieldSize,
        body:body,circles:circles.length,opacity:opacity,visible:visible,
        geometry:[x,y,width,height],edgeGeometry:[edgeOutput.width,edgeOutput.height,edgeOutput.visible],
        vGeometry:[vertical.width,vertical.height,vertical.visible],taps:taps.count,centerWeight:taps.w0,
        hStatus:horizontal.status,hLog:horizontal.log,vStatus:vertical.status,vLog:vertical.log,
        edgeStatus:edgeOutput.status,edgeLog:edgeOutput.log})

}
