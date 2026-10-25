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
    readonly property real targetOffsetScale: content.isDetached || content.hasCurrent ? 0 : 1
    property real offsetScale: targetOffsetScale

    // Where the popout settles once it finishes opening. Hover tests use this
    // instead of the animated geometry, which is both cheaper and keeps the
    // popout open when the pointer reaches its place before the animation does.
    readonly property real targetWidth: content.nonAnimWidth
    readonly property real targetHeight: Math.max(0, content.nonAnimHeight * (1 - targetOffsetScale))
    readonly property real targetX: {
        if (content.isDetached)
            return (parent.width - targetWidth) / 2;
        return Math.max(0, Math.min(content.currentCenter - borderThickness - targetWidth / 2,
            parent.width - targetWidth));
    }
    readonly property real targetY: content.isDetached ? (parent.height - targetHeight) / 2
        : atBottom ? parent.height - targetHeight : 0

    // The settled place together with the one still covered on screen. The
    // input region follows this so a popout keeps taking clicks until it has
    // finished shrinking away.
    readonly property rect reserved: {
        const left = Math.min(x, targetX);
        const top = Math.min(y, targetY);
        return Qt.rect(left, top, Math.max(x + width, targetX + targetWidth) - left,
            Math.max(y + height, targetY + targetHeight) - top);
    }

    visible: width > 0 && height > 0
    clip: true

    HoverHandler { id: hover }

    implicitWidth: content.implicitWidth
    implicitHeight: Math.max(0, content.implicitHeight * (1 - offsetScale))

    // A detached panel keeps growing from the centre, so it follows its
    // animated size rather than the settled one.
    x: content.isDetached ? (parent.width - width) / 2 : targetX
    y: content.isDetached ? (parent.height - height) / 2 : atBottom ? parent.height - height : 0

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
