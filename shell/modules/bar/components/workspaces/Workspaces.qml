pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Hyprstack
import Hyprstack.Components
import Hyprstack.Config
import qs.components
import qs.services
import "../../../../utils/scripts/panel-layout.js" as PanelLayout

StyledClippingRect {
    id: root

    required property ShellScreen screen
    required property bool fullscreen

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property bool onSpecial: (monitor?.lastIpcObject.specialWorkspace?.name ?? "").length > 0
    readonly property int activeWsId: monitor?.activeWorkspace?.id ?? 1
    readonly property int activeWsIdx: workspaceIndex(activeWsId)
    readonly property int shown: Hypr.perMonitorWorkspaces ? Hypr.workspaceCount : Math.max(1, Config.bar.workspaces.shown)

    readonly property var wsIds: {
        const allMonitors = !Hypr.perMonitorWorkspaces && !Config.bar.workspaces.perMonitor;
        const ignoredTags = GlobalConfig.bar.workspaces.ignoredTags;
        const occupied = Hypr.workspaces.values.filter(w => w.id > 0 && (allMonitors || w.monitor === root.monitor)
            && w.toplevels.values.some(t => !Hypr.isToplevelIgnored(t, ignoredTags))).map(w => w.id);
        return PanelLayout.workspaceIds(groupOffset, shown, activeWsId, occupied, Config.bar.workspaces.showUnoccupied);
    }

    readonly property var workspaces: {
        workspaces.itemsDirty;
        return wsIds.map(id => workspaces.itemAtIndex(workspaceIndex(id)));
    }

    readonly property int groupOffset: {
        if (Hypr.perMonitorWorkspaces)
            return Hypr.workspaceBase(root.monitor);
        return Math.floor((activeWsId - 1) / shown) * shown;
    }

    property real blur: onSpecial ? 1 : 0

    function workspaceIndex(id: int): int {
        if (!Config.bar.workspaces.showUnoccupied)
            return wsIds.indexOf(id);

        let index = id - 1;
        while (index < 0)
            index += shown;
        return index % shown;
    }

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: workspaces.layoutHeight + workspaces.anchors.margins * 2

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    Item {
        anchors.fill: parent
        scale: root.onSpecial ? 0.8 : 1
        opacity: root.onSpecial ? 0.5 : 1
        visible: !root.fullscreen

        layer.enabled: root.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: root.blur
            blurMax: 32
        }

        Loader {
            asynchronous: true
            opacity: Config.bar.workspaces.occupiedBg ? 1 : 0
            active: opacity > 0

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall

            sourceComponent: OccupiedBg {
                workspaces: root.workspaces
                wsSpacing: workspaces.spacing
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        LazyListView {
            id: workspaces

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.extraSmall
            implicitHeight: contentHeight

            spacing: Tokens.spacing.extraSmall
            removeDuration: Tokens.anim.durations.expressiveDefaultEffects

            model: ScriptModel {
                values: root.wsIds
            }

            delegate: Workspace {
                activeWsId: root.activeWsId
                ws: modelData
                monitor: root.monitor

                displayType: Config.bar.workspaces.displayType
                showWindows: Config.bar.workspaces.showWindows
                iconRules: GlobalConfig.bar.workspaces.workspaceIcons
                activeLabel: Config.bar.workspaces.activeLabel
                occupiedLabel: Config.bar.workspaces.occupiedLabel
                label: Config.bar.workspaces.label
            }
        }

        Loader {
            asynchronous: true
            active: false // Empty workspaces inside the displayed range remain visible.

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall

            sourceComponent: GapMarkers {
                workspaces: root.workspaces
                wsSpacing: workspaces.spacing
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Loader {
            asynchronous: true
            anchors.left: workspaces.left
            anchors.right: workspaces.right
            z: -1
            active: Config.bar.workspaces.activeIndicator

            sourceComponent: ActiveIndicator {
                activeWs: {
                    workspaces.itemsDirty;
                    return workspaces.itemAtIndex(root.activeWsIdx) as Workspace;
                }
                mask: workspaces
            }
        }

        MouseArea {
            anchors.fill: workspaces
            onClicked: event => {
                const ws = (workspaces.itemAt(event.x, event.y) as Workspace)?.ws;
                if (!ws)
                    return;
                Hypr.focusWorkspace(ws, root.monitor);
            }
        }

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: specialWs

        anchors.fill: parent

        asynchronous: true
        active: opacity > 0
        opacity: root.onSpecial ? 1 : 0

        sourceComponent: Item {
            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3scrim, Colours.light ? 0 : 0.2)
            }

            SpecialWorkspaces {
                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall
                monitor: root.monitor

                scale: 0.5
                Component.onCompleted: scale = Qt.binding(() => root.onSpecial ? 1 : 0.5)

                Behavior on scale {
                    Anim {}
                }
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Behavior on blur {
        Anim {
            type: Anim.StandardSmall
        }
    }

    Behavior on implicitHeight {
        Anim {}
    }
}
