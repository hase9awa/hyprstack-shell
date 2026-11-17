pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates
import Quickshell
import Hyprstack.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root
    objectName: "dashboardTabs"

    required property ScreenState screenState
    required property var tabs

    readonly property alias count: bar.count

    function syncCurrentIndex(): void {
        if (bar.count !== tabs.length || bar.count === 0)
            return;
        const index = Math.max(0, Math.min(screenState.dashboardTab, bar.count - 1));
        screenState.dashboardTab = index;
        if (bar.currentIndex !== index)
            bar.setCurrentIndex(index);
    }

    implicitHeight: bar.implicitHeight + bar.anchors.topMargin + indicator.implicitHeight + indicator.anchors.topMargin + separator.implicitHeight

    TabBar {
        id: bar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Tokens.sizes.dashboard.tabIndicatorSpacing

        currentIndex: root.screenState.dashboardTab
        onCurrentIndexChanged: Qt.callLater(root.syncCurrentIndex)
        onCountChanged: {
            // Container indices change while translated buttons are replaced.
            // Only user actions should change the saved selection.
            Qt.callLater(root.syncCurrentIndex);
        }

        implicitHeight: contentHeight
        background: null
        contentItem: ListView {
            model: bar.contentModel
            currentIndex: bar.currentIndex
            orientation: ListView.Horizontal
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            clip: true
        }

        Repeater {
            model: ScriptModel {
                values: root.tabs
            }

            delegate: Tab {
                required property var modelData
                required property int index
                objectName: "dashboardTab_" + index

                iconName: modelData.iconName
                text: modelData.text
            }
        }
    }

    Item {
        id: indicator
        property real position: bar.currentIndex
        property real trailingPosition: bar.currentIndex
        readonly property bool gooey: GlobalConfig.appearance.anim.shellPreset === "goop"
        readonly property real trailWidth: gooey ? Math.abs(position - trailingPosition)
            * bar.availableWidth / Math.max(1, bar.count) : 0

        anchors.top: bar.bottom
        anchors.topMargin: 5 * Tokens.scale

        implicitWidth: {
            const tab = bar.currentItem;
            if (tab)
                return tab.implicitWidth + trailWidth;
            const width = bar.availableWidth / Math.max(1, bar.count);
            return width + trailWidth;
        }
        implicitHeight: 3 * Tokens.scale

        x: {
            const tab = bar.currentItem;
            const width = bar.availableWidth / Math.max(1, bar.count);
            const tabWidth = tab?.implicitWidth ?? width;
            return width * (gooey ? Math.min(position, trailingPosition) : position) + (width - tabWidth) / 2;
        }

        clip: true

        StyledRect {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: parent.implicitHeight * 2

            color: Colours.palette.m3primary
            radius: Tokens.rounding.full
        }

        Behavior on position {
            Anim {
                type: Anim.Standard
                duration: Tokens.anim.durations.expressiveFastSpatial
            }
        }

        Behavior on trailingPosition {
            Anim {
                duration: indicator.gooey ? Tokens.anim.durations.expressiveSlowSpatial : 0
                type: Anim.SlowSpatial
            }
        }

        Behavior on implicitWidth {
            Anim {}
        }
    }

    StyledRect {
        id: separator

        anchors.top: indicator.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        implicitHeight: 1 * Tokens.scale
        color: Colours.palette.m3outlineVariant
    }

    component Tab: TabButton {
        id: tab

        required property string iconName
        readonly property bool current: TabBar.tabBar.currentItem === this

        width: bar.availableWidth / Math.max(1, bar.count)
        implicitWidth: implicitContentWidth
        implicitHeight: implicitContentHeight
        background: null
        onClicked: root.screenState.dashboardTab = TabBar.index
        Keys.onLeftPressed: root.screenState.dashboardTab = Math.max(0, root.screenState.dashboardTab - 1)
        Keys.onRightPressed: root.screenState.dashboardTab = Math.min(bar.count - 1, root.screenState.dashboardTab + 1)

        contentItem: CustomMouseArea {
            id: mouse

            function onWheel(event: WheelEvent): void {
                if (event.angleDelta.y < 0)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, bar.count - 1);
                else if (event.angleDelta.y > 0)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
            }

            implicitWidth: Math.max(icon.width, label.width)
            implicitHeight: icon.height + label.height

            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onPressed: root.screenState.dashboardTab = tab.TabBar.index

            StateLayer {
                id: stateLayer

                anchors.fill: undefined
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: parent.height + Tokens.sizes.dashboard.tabIndicatorSpacing * 2

                radius: Tokens.rounding.medium
                color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurface
                onClicked: root.screenState.dashboardTab = tab.TabBar.index
            }

            MaterialIcon {
                id: icon

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: label.top

                text: tab.iconName
                color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                fill: tab.current ? 1 : 0
                fontStyle: Tokens.font.icon.medium

                Behavior on fill {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            StyledText {
                id: label

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom

                text: tab.text
                color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
