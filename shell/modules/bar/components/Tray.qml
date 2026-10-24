pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.SystemTray
import Hyprstack.Config
import qs.components
import qs.services

StyledRect {
    id: root

    readonly property alias layout: layout
    readonly property alias items: items
    readonly property alias expandIcon: expandIcon

    readonly property int padding: Config.bar.tray.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property int spacing: Config.bar.tray.background ? Tokens.spacing.medium : Tokens.spacing.extraSmall

    property bool expanded

    function redundant(item: var): bool {
        const id = item.id.toLowerCase();
        const status = Config.bar.statusIcons.values;
        if (/^(nm-applet|networkmanager(-applet)?)$/.test(id))
            return status.some(entry => entry.id === "network" && entry.enabled);
        if (/^(blueman(-applet|-tray)?)$/.test(id))
            return status.some(entry => entry.id === "bluetooth" && entry.enabled);
        return false;
    }

    readonly property real nonAnimWidth: {
        if (items.count === 0)
            return 0;
        if (!Config.bar.tray.compact)
            return layout.implicitWidth + padding * 2;
        if (expanded)
            return expandIcon.implicitWidth + layout.implicitWidth + spacing + padding;
        return expandIcon.implicitWidth;
    }

    clip: true
    visible: width > 0

    implicitWidth: nonAnimWidth
    implicitHeight: Tokens.sizes.bar.innerWidth

    color: "transparent"
    radius: Tokens.rounding.full

    GroupBackground {
        color: Qt.alpha(Colours.tPalette.m3surfaceContainer, (Config.bar.tray.background && root.items.count > 0) ? Colours.tPalette.m3surfaceContainer.a : 0)
    }

    Item {
        id: contentClip

        // Reveal the stationary icon row beside the button without overlapping it.
        x: root.padding
        width: Math.max(0, root.width - root.padding - (Config.bar.tray.compact ? expandIcon.width + root.spacing : root.padding))
        height: parent.height
        clip: true
        enabled: root.expanded || !Config.bar.tray.compact

        Row {
            id: layout

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            spacing: Tokens.spacing.small

            opacity: root.expanded || !Config.bar.tray.compact ? 1 : 0

            add: Transition {
                Anim {
                    properties: "scale"
                    from: 0
                    to: 1
                    easing: Tokens.anim.standardDecel
                }
            }

            move: Transition {
                Anim {
                    properties: "scale"
                    to: 1
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    properties: "x,y"
                }
            }

            Repeater {
                id: items

                model: ScriptModel {
                    values: SystemTray.items.values.filter(i => i.status !== Status.Passive && !GlobalConfig.bar.tray.hiddenIcons.includes(i.id) && !root.redundant(i))
                }

                TrayItem {}
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    MouseArea {
        id: expandIcon

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right

        implicitWidth: root.implicitHeight
        implicitHeight: root.implicitHeight
        visible: Config.bar.tray.compact && items.count > 0
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor

        onClicked: root.expanded = !root.expanded

        Shape {
            id: chevron

            anchors.centerIn: parent
            anchors.alignWhenCentered: false
            width: 24 * Tokens.scale
            height: width
            preferredRendererType: Shape.CurveRenderer
            rotation: root.expanded ? 180 : 0

            ShapePath {
                strokeWidth: 2 * root.Tokens.scale
                strokeColor: Colours.palette.m3onSurfaceVariant
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: chevron.width * 0.625
                startY: chevron.height * 0.25

                PathLine {
                    x: chevron.width * 0.375
                    y: chevron.height * 0.5
                }
                PathLine {
                    x: chevron.width * 0.625
                    y: chevron.height * 0.75
                }

                Behavior on strokeColor {
                    CAnim {}
                }
            }

            Behavior on rotation {
                Anim {
                    type: Anim.Standard
                }
            }
        }
    }

    Behavior on implicitWidth {
        Anim {
            type: Anim.Standard
        }
    }
}
