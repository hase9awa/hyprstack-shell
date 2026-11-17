pragma ComponentBehavior: Bound

import QtQuick
import "../utils/vendor/goopui/core.js" as Upstream

// The paired Gaussian kernel from goopUI's renderer, shared by the panel
// field and the stationary desktop-frame field.
ShaderEffect {
    id: root
    required property var input
    required property size fieldSize
    required property vector2d blurDirection
    property real sigma: 5
    readonly property var taps: Upstream.GoopCore.gaussianTaps(Math.max(.01,sigma))
    anchors.fill: parent
    visible: true
    property var source: input
    property vector2d direction: blurDirection
    property vector2d textureExtent: Qt.vector2d(fieldSize.width,fieldSize.height)
    property real centerWeight: taps.w0
    property int tapCount: taps.count
    property matrix4x4 kernel0: kernel(0)
    property matrix4x4 kernel1: kernel(4)
    property matrix4x4 kernel2: kernel(8)
    property matrix4x4 kernel3: kernel(12)
    property matrix4x4 kernel4: kernel(16)
    property matrix4x4 kernel5: kernel(20)
    property matrix4x4 kernel6: kernel(24)
    property matrix4x4 kernel7: kernel(28)
    fragmentShader: "qrc:/shaders/goop-blur.frag.qsb"
    vertexShader: "qrc:/shaders/goop.vert.qsb"

    function kernel(first: int): matrix4x4 {
        const t=taps.taps;
        function v(index) { return t[index] ?? 0; }
        const i=first*2;
        return Qt.matrix4x4(v(i),v(i+2),v(i+4),v(i+6),
            v(i+1),v(i+3),v(i+5),v(i+7),0,0,0,0,0,0,0,0);
    }
}
