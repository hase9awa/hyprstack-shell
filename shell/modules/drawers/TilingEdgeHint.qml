pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Hyprstack.Blobs
import Hyprstack.Config
import qs.components
import qs.services
import qs.modules.bar as Bar

Item {
    id: root
    objectName: "tilingEdgeHint"

    required property ShellScreen screen
    required property var win
    required property Panels panels
    required property Bar.BarWrapper bar
    required property BlobGroup group

    readonly property var monitor: Hypr.monitorFor(screen)?.lastIpcObject
    readonly property real originX: monitor?.x ?? 0
    readonly property real originY: monitor?.y ?? 0
    readonly property real uiScale: Tokens.scale
    readonly property real halo: Math.max(Tokens.rounding.extraLarge, win.contentItem.Config.border.smoothing * uiScale)
    readonly property var nativeState: Tiling.hoverState
    readonly property bool shown: nativeState.visible && nativeState.monitor === screen.name
    property var placement: ({side: "right", box: {x: 0, y: 0, width: 34, height: 52}})
    readonly property var box: placement.box
    readonly property bool horizontal: placement.side === "left" || placement.side === "right"
    readonly property real join: 8 * uiScale
    property real offsetScale: shown ? 0 : 1

    onNativeStateChanged: if (nativeState.visible && nativeState.monitor === screen.name) placement = nativeState
    visible: offsetScale < 1
    anchors.fill: parent

    Behavior on offsetScale {
        enabled: !root.nativeState.instant
        Anim { bounded: true }
    }

    readonly property string registration: JSON.stringify(geometry())
    onRegistrationChanged: Qt.callLater(sync)
    Component.onCompleted: sync()

    function sync(): void { Tiling.configureHover(screen.name, registration); }

    // Reserve real drawer bounds and closed hover sensors alike. The hint
    // cannot claim the edge used to reveal sound and brightness controls.
    function geometry(): var {
        const blocked = [];
        const edge = win.borderThickness;
        function add(x, y, width, height) {
            if (width > 0 && height > 0)
                blocked.push({x: originX + x, y: originY + y, width, height});
        }
        function panel(item, active) {
            if (!active || !item || item.width <= 0 || item.height <= 0) return;
            const px = item.x, py = item.y;
            const p = item.mapToItem(win.contentItem, 0, 0);
            add(p.x - halo, p.y - halo, item.width + 2 * halo, item.height + 2 * halo);
        }
        add(0, 0, win.width, bar.topInset);
        add(0, win.height - bar.bottomInset, win.width, bar.bottomInset);

        if (win.contentItem.Config.osd.enabled) {
            const count = 1 + Number(win.contentItem.Config.osd.enableBrightness)
                + Number(win.contentItem.Config.osd.enableMicrophone && (!win.contentItem.Config.osd.enableBrightness || !win.screenState.session));
            const osdHeight = Math.max(panels.osd.height, count * Tokens.sizes.osd.sliderHeight
                + (count - 1) * Tokens.spacing.medium + 2 * Tokens.padding.large);
            const centre = panels.osdWrapper.mapToItem(win.contentItem, 0, panels.osdWrapper.height / 2).y;
            const depth = panels.osd.shouldBeActive || panels.osd.visible
                ? Math.max(panels.osd.width, Tokens.sizes.osd.sliderWidth + 2 * Tokens.padding.large) + halo : Math.max(edge, 3 * uiScale);
            const onLeft = win.contentItem.Config.osd.side === OsdSide.Left;
            add(onLeft ? 0 : win.width - depth, centre - osdHeight / 2 - halo, depth, osdHeight + 2 * halo);
        }
        panel(panels.sidebar, panels.sidebar.visible || win.screenState.sidebar);
        panel(panels.sessionWrapper, panels.session.visible || win.screenState.session);
        panel(panels.utilities, panels.utilities.visible || win.screenState.utilities);
        panel(panels.notifications, panels.notifications.visible);
        panel(panels.dashboard, panels.dashboard.visible);
        panel(panels.launcher, panels.launcher.visible);
        panel(panels.popoutsWrapper, panels.popouts.offsetScale < 1 || panels.popouts.hasCurrent || panels.popouts.isDetached);
        return {area: {x: originX + edge, y: originY + bar.topInset, width: win.width - 2 * edge,
            height: win.height - bar.topInset - bar.bottomInset}, blocked,
            depth: 34 * uiScale, length: 52 * uiScale, padding: Math.max(12 * uiScale, halo)};
    }

    Connections {
        target: Hypr
        function onConfigReloaded(): void { Qt.callLater(root.sync); }
    }

    // BlobRect tracks its own geometry for the SDF uniforms and deformation.
    // Move the shape itself rather than a moving ancestor, as PanelBg does.
    BlobRect {
        group: root.visible ? root.group : null
        x: body.x - (root.placement.side === "left" ? root.join : 0)
        y: body.y - (root.placement.side === "top" ? root.join : 0)
        width: body.width + (root.horizontal ? root.join : 0)
        height: body.height + (root.horizontal ? 0 : root.join)
        radius: Tokens.rounding.extraLarge
        deformScale: (0.15 * Config.appearance.deformScale) / 10000
    }

    Item {
        id: body
        x: root.box.x - root.originX + (root.placement.side === "left" ? -(width + root.join) * root.offsetScale
            : root.placement.side === "right" ? (width + root.join) * root.offsetScale : 0)
        y: root.box.y - root.originY + (root.placement.side === "top" ? -(height + root.join) * root.offsetScale
            : root.placement.side === "bottom" ? (height + root.join) * root.offsetScale : 0)
        width: root.box.width
        height: root.box.height

        MaterialIcon {
            anchors.centerIn: parent
            text: root.placement.side === "left" ? "chevron_left" : root.placement.side === "right" ? "chevron_right"
                : root.placement.side === "top" ? "keyboard_arrow_up" : "keyboard_arrow_down"
            color: root.shown && root.nativeState.hovered ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.medium
            opacity: Math.max(0, 1 - root.offsetScale)
        }
    }
}
