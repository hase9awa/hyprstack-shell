pragma ComponentBehavior: Bound

import QtQuick
import Hyprstack
import Hyprstack.Config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState
    required property bool atBottom
    property real slideDistance: height + 5
    property bool readyToOpen: true
    property bool contentPrepared: false
    property bool retainContent: false
    readonly property Props props: Props {}

    readonly property bool shouldBeActive: screenState.sidebar && Config.sidebar.enabled
    property real offsetScale: shouldBeActive && readyToOpen ? 0 : 1

    visible: offsetScale < 1
    clip: true
    anchors.rightMargin: atBottom ? 0 : (-implicitWidth - 5) * offsetScale
    implicitWidth: Tokens.sizes.sidebar.width
    opacity: 1 - offsetScale

    onShouldBeActiveChanged: {
        if (shouldBeActive)
            Notifs.markAllRead();
        if (shouldBeActive && visible)
            Qt.callLater(() => root.forceActiveFocus());
    }
    onVisibleChanged: if (visible && shouldBeActive) Qt.callLater(() => root.forceActiveFocus())

    Keys.onEscapePressed: root.screenState.sidebar = false

    Behavior on offsetScale {
        NumberAnimation {
            duration: Tokens.anim.durations.expressiveDefaultSpatial * 0.6
            easing.type: Easing.InOutSine
        }
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: Tokens.padding.large
        anchors.margins: CUtils.clamp(anchors.leftMargin - (Config.border.thickness * Tokens.scale), 0, anchors.leftMargin)
        anchors.bottomMargin: 0

        asynchronous: true
        active: Config.sidebar.enabled && (root.shouldBeActive || root.visible || root.retainContent)
        onActiveChanged: if (!active) root.contentPrepared = false
        onLoaded: Qt.callLater(() => {
            if (content.status === Loader.Ready) {
                root.retainContent = true;
                root.contentPrepared = true;
            }
        })

        sourceComponent: Content {
            implicitWidth: Tokens.sizes.sidebar.width - content.anchors.leftMargin - content.anchors.margins
            props: root.props
            screenState: root.screenState
        }
    }
}
