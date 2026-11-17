pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.filedialog

Item {
    id: root

    required property ScreenState screenState
    required property FileDialog facePicker

    readonly property var dashboardTabs: {
        const allTabs = [
            {
                component: dashComponent,
                iconName: "dashboard",
                text: Tr.tr("Dashboard"),
                enabled: Config.dashboard.showDashboard
            },
            {
                component: mediaComponent,
                iconName: "queue_music",
                text: Tr.tr("Media"),
                enabled: Config.dashboard.showMedia
            },
            {
                component: performanceComponent,
                iconName: "speed",
                text: Tr.tr("Performance"),
                enabled: Config.dashboard.showPerformance
            },
            {
                component: weatherComponent,
                iconName: "cloud",
                text: Tr.tr("Weather"),
                enabled: Config.dashboard.showWeather
            }
        ];
        return allTabs.filter(tab => tab.enabled);
    }

    readonly property real nonAnimWidth: view.implicitWidth + viewWrapper.anchors.margins * 2
    readonly property real nonAnimHeight: tabs.implicitHeight + tabs.anchors.topMargin + view.implicitHeight + viewWrapper.anchors.margins * 2
    readonly property bool readyToOpen: dashboardTabs.length === 0
        || (view.currentItem?.status === Loader.Ready && view.implicitWidth > 0 && view.implicitHeight > 0)

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    Tabs {
        id: tabs

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: CUtils.clamp(anchors.margins - (Config.border.thickness * Tokens.scale), 0, anchors.margins)
        anchors.margins: Tokens.padding.large

        screenState: root.screenState
        tabs: root.dashboardTabs
    }

    ClippingRectangle {
        id: viewWrapper

        anchors.top: tabs.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large

        radius: Tokens.rounding.large
        color: "transparent"

        Flickable {
            id: view

            readonly property int currentIndex: root.screenState.dashboardTab
            readonly property Item currentItem: {
                repeater.count; // Trigger update on count change
                repeater.revision; // Delegates can finish after count changes.
                return repeater.itemAt(currentIndex);
            }

            anchors.fill: parent

            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            implicitWidth: currentItem?.implicitWidth ?? 0
            implicitHeight: currentItem?.implicitHeight ?? 0

            contentX: currentItem?.x ?? 0
            contentWidth: row.implicitWidth
            contentHeight: row.implicitHeight

            onContentXChanged: {
                if (!moving || !currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 2)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 2)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
            }

            onDragEnded: {
                if (!currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 10)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 10)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
                contentX = Qt.binding(() => currentItem?.x ?? 0);
            }

            Row {
                id: row
                spacing: Tokens.spacing.small

                Repeater {
                    id: repeater

                    property int revision: 0
                    function refreshItems(): void { revision++; }
                    onItemAdded: Qt.callLater(refreshItems)
                    onItemRemoved: Qt.callLater(refreshItems)

                    model: ScriptModel {
                        values: root.dashboardTabs
                    }

                    delegate: Loader {
                        id: paneLoader

                        required property int index
                        required property var modelData

                        asynchronous: true

                        // Four cached panes keep their positions while sliding.
                        // Visibility below suspends services outside the viewport.
                        sourceComponent: modelData.component

                        // Preserve adjacent tabs' geometry for swiping, but let
                        // their services and animations sleep outside the viewport.
                        Binding {
                            target: paneLoader.item
                            property: "visible"
                            when: !!paneLoader.item
                            value: paneLoader.x + paneLoader.width > view.contentX
                                && paneLoader.x < view.contentX + view.width
                        }
                    }
                }
            }

            Component {
                id: dashComponent

                Dash {
                    screenState: root.screenState
                    facePicker: root.facePicker
                }
            }

            Component {
                id: mediaComponent

                Media {
                    screenState: root.screenState
                }
            }

            Component {
                id: performanceComponent

                Performance {}
            }

            Component {
                id: weatherComponent

                WeatherTab {}
            }

            Behavior on contentX {
                Anim {
                    type: Anim.Standard
                    duration: Tokens.anim.durations.expressiveFastSpatial
                }
            }
        }
    }

    Behavior on implicitWidth {
        enabled: root.visible && root.readyToOpen
        Anim {
            bounded: true
            type: Anim.Standard
            duration: Tokens.anim.durations.expressiveFastSpatial
        }
    }

    Behavior on implicitHeight {
        enabled: root.visible && root.readyToOpen
        Anim {
            bounded: true
            type: Anim.Standard
            duration: Tokens.anim.durations.expressiveFastSpatial
        }
    }
}
