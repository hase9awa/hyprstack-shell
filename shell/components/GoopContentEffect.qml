pragma ComponentBehavior: Bound

import QtQuick

// Sample the same threshold field as the fluid surface, in window space.
// Content stays at its settled position and is revealed by the actual fluid.
ShaderEffect {
    property var source
    required property var maskSource
    required property rect contentRect
    property vector2d sourceScale: Qt.vector2d(1,1)
    required property rect fieldRect
    required property vector2d maskExtent
    property real contrast: 20
    property real threshold: .4
    fragmentShader: "qrc:/shaders/goop-content.frag.qsb"
    vertexShader: "qrc:/shaders/goop.vert.qsb"
}
