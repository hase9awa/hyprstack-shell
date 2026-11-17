pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Hyprstack.Blobs
import Hyprstack.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.bar

StyledWindow {
    id: root

    readonly property alias bar: bar
    readonly property alias interactionWrapper: interactions

    // A menu the shell has opened in front of the windows, which it holds the
    // input for while it is up. The key that closes windows closes the menu
    // first, the way a click outside it does.
    readonly property bool menuOpen: focusGrab.active || panels.popouts.isDetached

    readonly property ScreenState screenState: ShellState.forScreen(screen)

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property bool hasSpecialWorkspace: (monitor?.lastIpcObject.specialWorkspace?.name.length ?? 0) > 0
    readonly property bool hasFullscreenOnNormalWs: Hypr.hasFullscreen(monitor?.activeWorkspace)
    readonly property bool hasFullscreen: {
        if (hasSpecialWorkspace) {
            const specialName = monitor?.lastIpcObject.specialWorkspace?.name;
            if (!specialName)
                return false;
            const specialWs = Hypr.workspaces.values.find(ws => ws.name === specialName);
            return Hypr.hasFullscreen(specialWs);
        }
        return hasFullscreenOnNormalWs;
    }

    property real fsTransitionProg: hasFullscreen ? 1 : 0
    readonly property real sdfBorderOffset: 2 * fsTransitionProg // SDFs joins are not exact, so offset by 2px to ensure nothing shows
    readonly property real borderThickness: (Tiling.desktopFrame ? (contentItem.Config.border.thickness * contentItem.Tokens.scale) : 0) * (1 - fsTransitionProg) * (1 - Hypr.stackingProgress)
    readonly property real borderRounding: (Tiling.desktopFrame ? (contentItem.Config.border.rounding * contentItem.Tokens.scale) : 0) * (1 - fsTransitionProg) * (1 - Hypr.stackingProgress)
    readonly property real shadowOpacity: Effects.shadowOpacity * (1 - fsTransitionProg)
    readonly property real borderLayoutThickness: hasFullscreen ? 0 : borderThickness
    readonly property real tileFrameRadius: !Hypr.stacking && !Tiling.gaps && Tiling.desktopFrame && !hasFullscreen
        ? (contentItem.Config.border.rounding * contentItem.Tokens.scale) : 0

    function syncTileFrame(): void {
        if (Hypr.usingLua && screen)
            Hypr.extras.message(`eval if hl.plugin.hyprbars and hl.plugin.hyprbars.tile_frame then hl.plugin.hyprbars.tile_frame(${JSON.stringify(screen.name)},${tileFrameRadius}) end`);
    }
    onTileFrameRadiusChanged: syncTileFrame()
    onScreenChanged: syncTileFrame()
    Component.onCompleted: syncTileFrame()

    Connections {
        target: Hypr
        function onConfigReloaded(): void { Qt.callLater(root.syncTileFrame); }
        function onUsingLuaChanged(): void { root.syncTileFrame(); }
    }

    property color surfaceColour: Colours.tPalette.m3surface

    readonly property int dragMaskPadding: {
        if (Hypr.stacking || !Tiling.desktopFrame)
            return 0;
        if (focusGrab.active || panels.popouts.isDetached)
            return 0;

        if (monitor?.lastIpcObject.specialWorkspace?.name || monitor?.activeWorkspace?.toplevels.values.length > 0)
            return 0;

        const thresholds = [];
        for (const panel of ["dashboard", "launcher", "session", "sidebar"])
            if (contentItem.Config[panel].enabled)
                thresholds.push(contentItem.Config[panel].dragThreshold);
        return Math.max(...thresholds);
    }

    onHasFullscreenChanged: {
        screenState.launcher = false;
        screenState.session = false;
        screenState.dashboard = false;
        panels.popouts.close();
    }

    name: "drawers"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: (fsTransitionProg > 0 && contentItem.Config.general.showOverFullscreen) || (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: screenState.sidebar || screenState.launcher || screenState.session
        ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: hasFullscreen && !(contentItem.Config.general.showOverFullscreen && focusGrab.active)
        ? emptyRegion : regions

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Behavior on fsTransitionProg {
        Anim {}
    }

    Behavior on surfaceColour {
        CAnim {}
    }

    Region {
        id: emptyRegion

        x: panels.x + panels.notifications.x
        y: panels.y + panels.notifications.y
        width: panels.notifications.width
        height: panels.notifications.height

        Region {
            x: root.contentItem.Config.osd.side === OsdSide.Left ? 0 : root.width - width
            y: panels.y + panels.osdWrapper.y
            width: panels.osdWrapper.width * (1 - panels.osd.offsetScale) + root.borderThickness
            height: panels.osd.height
        }
    }

    Regions {
        id: regions

        bar: bar
        panels: panels
        win: root
    }

    HyprlandFocusGrab {
        id: focusGrab

        active: {
            const s = root.screenState;
            const conf = root.contentItem.Config;
            if ((s.launcher && conf.launcher.enabled) || (s.session && conf.session.enabled) || (s.sidebar && conf.sidebar.enabled))
                return true;
            if ((Hypr.stacking || !conf.dashboard.showOnHover) && s.dashboard && conf.dashboard.enabled)
                return true;
            if (panels.popouts.currentName.startsWith("traymenu") && (panels.popouts.current as StackView)?.depth > 1)
                return true;
            return false;
        }
        windows: [root]
        onCleared: {
            root.screenState.launcher = false;
            root.screenState.session = false;
            root.screenState.sidebar = false;
            root.screenState.dashboard = false;
            panels.popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    StyledRect {
        anchors.fill: parent
        opacity: (root.screenState.session && Config.session.enabled) || panels.popouts.detachedMode !== "" ? 0.5 : 0
        color: Colours.palette.m3scrim

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    Item {
        id: backgroundLayer
        anchors.fill: parent
        opacity: root.surfaceColour.a

        BlobGroup {
            id: blobGroup

            color: root.surfaceColour
            smoothing: (root.contentItem.Config.border.smoothing * root.contentItem.Tokens.scale)
            shadowColor: Effects.uiShadowsEnabled
                ? Qt.alpha(Colours.palette.m3shadow, Math.max(0, root.shadowOpacity)) : "transparent"
            shadowSize: Effects.uiShadowsEnabled ? Effects.shadowSize * root.contentItem.Tokens.scale : 0
            shadowOffset: 2 * root.contentItem.Tokens.scale
        }

        DesktopFrame { group: blobGroup }

        Item {
            id: frameDensity
            anchors.fill: parent
            visible: liquidFrame.active

            BlobGroup {
                id: densityGroup
                color: "white"
                smoothing: blobGroup.smoothing
            }

            DesktopFrame { group: densityGroup }
        }

        GoopFrameMask {
            id: liquidFrame
            anchors.fill: parent
            frameItem: frameDensity
            active: GlobalConfig.appearance.anim.shellPreset === "goop"
                && GlobalConfig.appearance.anim.durations.scale>0 && !GameMode.enabled
            innerRect: Qt.rect(root.borderThickness-root.sdfBorderOffset,
                bar.topInset-root.sdfBorderOffset,
                root.width-2*(root.borderThickness-root.sdfBorderOffset),
                root.height-bar.topInset-bar.bottomInset+2*root.sdfBorderOffset)
        }

        PanelBg {
            id: dashBg
            objectName: "dashboardBackground"

            panel: panels.dashboard
            anchorEdge: panels.dashboard.atBottom ? "bottom" : "top"
            contentKey: root.screenState.dashboardTab.toString()
            deformAmount: 0.1
        }

        PanelBg {
            id: launcherBg

            panel: panels.launcher
            anchorEdge: "bottom"
            deformAmount: 0.1
        }

        PanelBg {
            id: sessionBg

            panel: panels.sessionWrapper
            motionPanel: panels.session
            anchorEdge: "right"
            deformAmount: 0.2
            x: panels.x + panels.sessionWrapper.x + panels.session.x
            implicitWidth: panels.session.width
        }

        PanelBg {
            id: sidebarBg
            objectName: "notificationCenterBackground"

            panel: panels.sidebar
            anchorEdge: bar.atBottom ? "bottom" : "right"
            // A single surface keeps the notification list and controls joined.
            deformAmount: panels.utilities.followSidebar ? 0 : 0.03
            implicitHeight: panels.utilities.followSidebar
                ? panel.height + panels.utilities.height
                : panel.height * (1 / rawDeformMatrix.m22) + 2
        }

        PanelBg {
            id: osdBg

            panel: panels.osdWrapper
            motionPanel: panels.osd
            anchorEdge: panels.osd.onLeft === true ? "left" : "right"
            deformAmount: 0.25
            x: panels.x + panels.osdWrapper.x + panels.osd.x
            implicitWidth: panels.osd.width
        }

        PanelBg {
            id: notifsBg

            panel: panels.notifications
            anchorEdge: "right"
        }

        PanelBg {
            id: utilsBg

            panel: panels.utilities
            anchorEdge: panels.utilities.atBottom ? "bottom" : "top"
            maskSurfaceOverride: panels.utilities.followSidebar && !panels.utilities.keepStandaloneOpen
                ? sidebarBg.liquid : null
            visible: (!panels.utilities.followSidebar || panels.utilities.keepStandaloneOpen)
                && panel.visible && panel.width > 0 && panel.height > 0
            deformAmount: panels.utilities.followSidebar ? 0 : 0.15
        }

        PanelBg {
            id: popoutBg
            objectName: "popoutBackground"

            // Keep the animated popout background joined to the horizontal bar.
            property real extraDepth: GlobalConfig.appearance.anim.shellPreset === "goop"
                ? 0 : panels.popouts.isDetached ? 0 : 0.2
            contentKey: panels.popouts.currentName + ":" + panels.popouts.detachedMode + ":" + panels.popouts.trayRevision
            stableField: true
            splashOnContentChange: !panels.popouts.isDetached
            keepFrameJoin: !panels.popouts.isDetached

            panel: panels.popoutsWrapper
            motionPanel: panels.popouts
            deformAmount: panels.popouts.isDetached ? 0.05 : panels.popouts.hasCurrent ? 0.15 : 0.1
            x: panels.x + panels.popoutsWrapper.x + panels.popouts.x
            y: panels.y + panels.popoutsWrapper.y + panels.popouts.y - (bar.atBottom ? 0 : panels.popouts.height * extraDepth)
            implicitWidth: panels.popouts.width
            implicitHeight: panels.popouts.height * (1 + extraDepth)

            Behavior on extraDepth {
                Anim {}
            }
        }
    }

    TilingEdgeHint {
        screen: root.screen
        win: root
        panels: panels
        bar: bar
        group: blobGroup
    }

    Interactions {
        id: interactions

        screen: root.screen
        popouts: panels.popouts
        screenState: root.screenState
        panels: panels
        bar: bar
        borderThickness: root.borderLayoutThickness
        fullscreen: root.hasFullscreen

        Panels {
            id: panels

            screen: root.screen
            screenState: root.screenState
            bar: bar
            borderThickness: root.borderThickness

            // Spring deformation belongs to the background surface. Keep
            // text, icons, previews and their hit targets at their normal size.
        }

        BarWrapper {
            id: bar

            screen: root.screen
            screenState: root.screenState
            popouts: panels.popouts

            fullscreen: root.hasFullscreen
        }
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "rootWindow"
        component: root
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "interactionWrapper"
        component: interactions
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "bar"
        component: bar
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "panels"
        component: panels
    }

    component DesktopFrame: BlobInvertedRect {
        anchors.fill: parent
        anchors.margins: -50 // Extend the outside of the frame past the viewport.
        radius: root.borderRounding
        borderLeft: root.borderThickness - anchors.margins - root.sdfBorderOffset
        borderRight: root.borderThickness - anchors.margins - root.sdfBorderOffset
        borderTop: bar.topInset - anchors.margins - root.sdfBorderOffset
        borderBottom: bar.bottomInset - anchors.margins - root.sdfBorderOffset
    }

    component PanelBg: BlobRect {
        id: backgroundShape
        required property Item panel
        property Item motionPanel: panel
        property string anchorEdge: bar.atBottom ? "bottom" : "top"
        property real deformAmount: 0.15
        property string contentKey
        property bool keepFrameJoin: true
        property bool stableField: false
        property bool splashOnContentChange: false
        property var maskSurfaceOverride: null
        readonly property alias liquid: liquidPanel
        readonly property real baseRadius: Tokens.rounding.extraLarge

        GoopSurface {
            id: liquidPanel
            anchors.fill: parent
            hoverTarget: backgroundShape.motionPanel
            controlsContentMotion: true
            escapeParent: backgroundLayer
            frameMask: liquidFrame
            keepFrameJoin: backgroundShape.keepFrameJoin
            stableField: backgroundShape.stableField
            splashOnContentChange: backgroundShape.splashOnContentChange
            contentMaskSurface: backgroundShape.maskSurfaceOverride ?? liquidPanel
            paintColor: Qt.rgba(root.surfaceColour.r, root.surfaceColour.g, root.surfaceColour.b, 1)
            cornerRadius: backgroundShape.baseRadius
            externalProgress: liquidPanel.goopy ? 1 : backgroundShape.motionPanel.offsetScale !== undefined
                ? 1 - backgroundShape.motionPanel.offsetScale : -1
            contentKey: backgroundShape.contentKey
            anchorEdge: backgroundShape.anchorEdge
            panelOpen: backgroundShape.visible
                && (backgroundShape.motionPanel.shouldBeActive
                    ?? (backgroundShape.motionPanel.hasCurrent !== undefined
                        ? backgroundShape.motionPanel.hasCurrent || backgroundShape.motionPanel.isDetached
                        : backgroundShape.motionPanel.visible))
        }

        Binding {
            target: backgroundShape.motionPanel
            property: "flowOpacity"
            when: liquidPanel.goopy
            value: liquidPanel.contentOpacity
            restoreMode: Binding.RestoreBindingOrValue
        }

        visible: panel.visible && panel.width > 0 && panel.height > 0
        group: visible && !liquidPanel.goopy ? blobGroup : null
        x: panels.x + panel.x
        y: panels.y + panel.y
        implicitWidth: panel.width
        implicitHeight: panel.height
        radius: baseRadius
        deformScale: Hypr.stacking || GlobalConfig.appearance.anim.shellPreset === "goop"
            ? 0 : (deformAmount * Config.appearance.deformScale) / 10000
    }
}
