pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.modules.bar.popouts // Need to import this module so the Wrapper type is the same as others

Item {
    id: root

    required property ShellScreen screen
    required property real borderThickness
    required property bool atBottom

    readonly property alias content: content
    readonly property bool hovered: hover.hovered
    property real offsetScale: content.isDetached || content.hasCurrent ? 0 : 1

    visible: width > 0 && height > 0
    clip: true

    HoverHandler { id: hover }

    implicitWidth: content.implicitWidth
    implicitHeight: Math.max(0, content.implicitHeight * (1 - offsetScale))

    x: {
        if (content.isDetached)
            return Math.round((parent.width - width) / 2);
        return Math.max(0, Math.min(content.currentCenter - borderThickness - content.nonAnimWidth / 2,
            parent.width - content.nonAnimWidth));
    }
    y: content.isDetached ? Math.round((parent.height - height) / 2) : atBottom ? parent.height - height : 0

    Behavior on offsetScale {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    Behavior on x {
        enabled: root.offsetScale === 0 && !content.isDetached
        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Wrapper {
        id: content

        screen: root.screen
        offsetScale: root.offsetScale

        anchors.horizontalCenter: parent.horizontalCenter
        y: root.atBottom ? root.height - height + (height + 5) * root.offsetScale
            : (-height - 5) * root.offsetScale
    }
}
