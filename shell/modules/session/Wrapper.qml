pragma ComponentBehavior: Bound

import QtQuick
import Hyprstack.Config
import qs.components

Item {
    id: root
    property real flowOpacity: 1
    property bool flowClipped: false
    readonly property real visualOffsetScale: flowClipped ? 0 : offsetScale

    required property ScreenState screenState
    required property bool sidebarVisible
    readonly property real nonAnimWidth: content.implicitWidth

    readonly property bool shouldBeActive: screenState.session && Config.session.enabled
    property real offsetScale: shouldBeActive ? 0 : 1
    property real sidebarOffset: sidebarVisible ? 14 : 0

    visible: offsetScale < 1
    anchors.rightMargin: (-implicitWidth - 5 - sidebarOffset) * visualOffsetScale
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight || 510 // Hard coded fallback for first open
    opacity: flowClipped ? 1 : (1 - offsetScale) * flowOpacity

    Behavior on offsetScale {
        Anim { bounded: true }
    }

    Loader {
        id: content

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left

        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            screenState: root.screenState
        }
    }
}
