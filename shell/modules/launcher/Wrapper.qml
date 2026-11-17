pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Hyprstack.Config
import qs.components
import qs.modules.launcher.services

Item {
    id: root
    property real flowOpacity: 1
    property bool flowClipped: false
    readonly property real visualOffsetScale: flowClipped ? 0 : offsetScale

    required property ShellScreen screen
    required property ScreenState screenState
    required property var panels

    readonly property bool shouldBeActive: screenState.launcher && Config.launcher.enabled
    property bool contentPrepared: false
    property bool retainContent: false
    property bool preparingGraphics: false
    property double lastClosedAt: Date.now()

    function prepareContent(): void {
        if (contentPrepared || preparingGraphics || content.status !== Loader.Ready)
            return;
        preparingGraphics = true;
        if (!content.item.grabToImage(() => {
            root.preparingGraphics = false;
            root.contentPrepared = content.status === Loader.Ready;
        })) {
            preparingGraphics = false;
            contentPrepared = true;
        }
    }

    readonly property real maxHeight: {
        let max = panels.height + Tokens.padding.extraLarge;
        if (screenState.dashboard)
            max -= panels.dashboard.nonAnimHeight;
        return max;
    }

    property real offsetScale: shouldBeActive && contentPrepared ? 0 : 1

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            implicitHeight = Qt.binding(() => content.implicitHeight);
            if (Math.abs(Date.now() - lastClosedAt) > 2000) {
                contentPrepared = false;
                Qt.callLater(prepareContent);
            }
        } else {
            lastClosedAt = Date.now();
            implicitHeight = implicitHeight; // Break binding during close anim
        }
    }

    visible: offsetScale < 1
    anchors.bottomMargin: (-implicitHeight - 5) * visualOffsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 630 // Hard coded fallback for first open
    opacity: flowClipped ? 1 : (1 - offsetScale) * flowOpacity

    Component.onCompleted: Qt.callLater(() => Apps) // Load apps on init
    onVisibleChanged: if (visible && shouldBeActive) Qt.callLater(() => content.item?.focusSearch())

    Behavior on offsetScale {
        Anim { bounded: true }
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        asynchronous: true
        active: Config.launcher.enabled && (root.shouldBeActive || root.visible || root.retainContent)
        onActiveChanged: if (!active) root.contentPrepared = false
        onLoaded: Qt.callLater(() => {
            if (content.status === Loader.Ready) {
                root.retainContent = true;
                root.prepareContent();
            }
        })

        sourceComponent: Content {
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight
        }
    }
}
