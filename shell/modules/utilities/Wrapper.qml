pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Hyprstack
import Hyprstack.Config
import qs.components
import qs.modules.sidebar as Sidebar
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property ScreenState screenState
    required property Sidebar.Wrapper sidebar
    required property BarPopouts.Wrapper popouts
    property bool atBottom: true
    property matrix4x4 deformMatrix

    readonly property PersistentProperties props: PersistentProperties {
        property bool recordingListExpanded: false
        property string recordingConfirmDelete
        property string recordingMode

        reloadableId: "utilities"
    }
    readonly property bool shouldBeActive: Config.utilities.enabled
        && (screenState.sidebar || (screenState.utilities && !(screenState.session && Config.session.enabled)))
    readonly property real totalPadding: content.anchors.margins + CUtils.clamp(content.anchors.margins - (Config.border.thickness * Tokens.scale), 0, content.anchors.margins)
    readonly property real nonAnimHeight: ((content.item as Content)?.nonAnimHeight ?? 0) + totalPadding
    readonly property bool followSidebar: Config.utilities.enabled
        && (sidebar.shouldBeActive || sidebar.visible)
    // Keep an already open corner panel in place while the sidebar slides in.
    property bool keepStandaloneOpen: false
    readonly property bool movesWithSidebar: followSidebar && !keepStandaloneOpen
    property bool contentPrepared: false
    property bool retainContent: false
    property real detachedOffsetScale: shouldBeActive ? 0 : 1
    readonly property real offsetScale: movesWithSidebar ? sidebar.offsetScale : detachedOffsetScale

    onFollowSidebarChanged: keepStandaloneOpen = followSidebar && !sidebar.atBottom && screenState.utilities
    onShouldBeActiveChanged: if (!shouldBeActive) keepStandaloneOpen = false

    visible: offsetScale < 1
    implicitHeight: content.implicitHeight + totalPadding
    implicitWidth: followSidebar ? sidebar.width : Tokens.sizes.utilities.width
    anchors.rightMargin: movesWithSidebar ? sidebar.anchors.rightMargin : 0
    opacity: 1 - offsetScale

    Behavior on detachedOffsetScale {
        enabled: !root.movesWithSidebar
        Anim {}
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Tokens.padding.large

        asynchronous: true
        active: Config.utilities.enabled && (root.shouldBeActive || root.visible || root.retainContent)
        onActiveChanged: if (!active) root.contentPrepared = false
        onLoaded: Qt.callLater(() => {
            if (content.status === Loader.Ready) {
                if (root.followSidebar)
                    root.retainContent = true;
                root.contentPrepared = true;
            }
        })

        sourceComponent: Content {
            implicitWidth: root.implicitWidth - root.totalPadding
            props: root.props
            screenState: root.screenState
            showStandaloneCards: root.visible && !root.screenState.sidebar && !root.sidebar.visible
            popouts: root.popouts
            deformMatrix: root.deformMatrix
        }
    }
}
