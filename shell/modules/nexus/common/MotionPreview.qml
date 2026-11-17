pragma ComponentBehavior: Bound

import QtQuick
import Hyprstack.Config
import Hyprstack.Blobs
import qs.components
import qs.services

StyledRect {
    id: root

    property bool windows: false
    required property string preset
    property real shellProgress: 1
    property real windowProgress: 1
    readonly property real progress: windows ? windowProgress : shellProgress
    readonly property var windowCurves: ({
        default: [0.25, 0.1, 0.25, 1, 1, 1], spring: [0.22, 1.25, 0.32, 1, 1, 1],
        glide: [0.16, 1, 0.3, 1, 1, 1], snappy: [0.22, 1, 0.36, 1, 1, 1],
        cinematic: [0.76, 0, 0.24, 1, 1, 1], reduced: [0, 0, 1, 1, 1, 1]
    })
    readonly property var windowDurations: ({default: 400, spring: 480, glide: 380, snappy: 200, cinematic: 600, reduced: 0})

    function replay(): void {
        sequence.stop();
        shellProgress = windowProgress = 1;
        sequence.start();
    }

    onPresetChanged: Qt.callLater(replay)
    Component.onCompleted: Qt.callLater(replay)

    implicitHeight: 164 * Tokens.scale
    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainerLow
    clip: true

    Rectangle {
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        radius: Tokens.rounding.medium
        color: Colours.tPalette.m3surfaceContainer

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 7 * Tokens.scale
            radius: height / 2
            color: Colours.tPalette.m3surfaceContainerHighest
        }
    }

    Item { id: previewGoo; anchors.fill: parent }

    StyledRect {
        id: panel
        readonly property real amount: Math.max(0, Math.min(1, root.progress))
        width: Math.min(root.width * 0.62, 280 * Tokens.scale)
        height: root.height * 0.57
        x: (root.width - width) / 2 + (root.windows && root.preset === "glide" ? (1 - root.progress) * root.width * 0.25 : 0)
        y: (root.height - height) / 2 + (root.windows ? 0 : (1 - root.progress) * root.height * 0.55)
        scale: root.windows ? (root.preset === "cinematic" ? 0.82 : root.preset === "spring" ? 0.88
            : root.preset === "snappy" ? 0.97 : 0.94) + (root.preset === "cinematic" ? 0.18
            : root.preset === "spring" ? 0.12 : root.preset === "snappy" ? 0.03 : 0.06) * root.progress : 1
        opacity: (!root.windows && root.preset === "goop") || (root.windows && root.preset !== "reduced") ? 1 : amount
        visible: root.progress > 0
        radius: Tokens.rounding.large
        color: !root.windows && root.preset === "goop" ? "transparent" : Colours.palette.m3primaryContainer

        GoopSurface {
            id: liquidPreview
            anchors.fill: parent
            paintColor: Colours.palette.m3primaryContainer
            escapeParent: previewGoo
            cornerRadius: panel.radius
            anchorEdge: "bottom"
            externalProgress: root.windows ? 1 : root.progress
            panelOpen: !root.windows && root.progress > 0
        }

        Row {
            visible: root.windows
            x: Tokens.padding.medium
            y: Tokens.padding.small
            spacing: 4 * Tokens.scale
            Repeater {
                model: 3
                Rectangle {
                    width: 5 * Tokens.scale
                    height: width
                    radius: width / 2
                    color: Colours.palette.m3onPrimaryContainer
                    opacity: 0.45
                }
            }
        }

        Column {
            anchors.centerIn: parent
            opacity: !root.windows && root.preset === "goop" ? liquidPreview.contentOpacity : 1
            width: (parent?.width ?? 0) * 0.65
            spacing: 7 * Tokens.scale
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    width: (parent?.width ?? 0) * (index === 2 ? 0.6 : 1)
                    height: 5 * Tokens.scale
                    radius: height / 2
                    color: Colours.palette.m3onPrimaryContainer
                    opacity: index === 0 ? 0.7 : 0.25
                }
            }
        }
    }

    // One cycle on selection/replay; the preview never runs in an idle loop.
    SequentialAnimation {
        id: sequence
        ParallelAnimation {
            Anim {
                bounded: true
                target: root
                property: "shellProgress"
                to: 0
                duration: root.windows ? 0 : Tokens.anim.durations.expressiveFastEffects
                easing: Tokens.anim.standardAccel
            }
            NumberAnimation {
                target: root
                property: "windowProgress"
                to: 0
                duration: root.windows ? (root.windowDurations[root.preset] ?? 400) * 0.65 : 0
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.4, 0, 1, 1, 1, 1]
            }
        }
        PauseAnimation { duration: 100 }
        ParallelAnimation {
            Anim {
                bounded: true
                target: root
                property: "shellProgress"
                to: 1
                duration: root.windows ? 0 : Tokens.anim.durations.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: root
                property: "windowProgress"
                to: 1
                duration: root.windows ? root.windowDurations[root.preset] ?? 400 : 0
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.windowCurves[root.preset] ?? root.windowCurves.default
            }
        }

    }
}
