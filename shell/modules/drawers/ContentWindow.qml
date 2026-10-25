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

    readonly property ScreenState screenState: ShellState.forScreen(screen)

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property bool hasSpecialWorkspace: (monitor?.lastIpcObject.specialWorkspace?.name.length ?? 0) > 0
    readonly property bool hasFullscreenOnNormalWs: monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false
    readonly property bool hasFullscreen: {
        if (hasSpecialWorkspace) {
            const specialName = monitor?.lastIpcObject.specialWorkspace?.name;
            if (!specialName)
                return false;
            const specialWs = Hypr.workspaces.values.find(ws => ws.name === specialName);
            return specialWs?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
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
            x: root.width - width
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

        BlobInvertedRect {
            anchors.fill: parent
            anchors.margins: -50 // Make border thicker to smooth out bulge from closed drawers
            group: blobGroup
            radius: root.borderRounding
            borderLeft: root.borderThickness - anchors.margins - root.sdfBorderOffset
            borderRight: root.borderThickness - anchors.margins - root.sdfBorderOffset
            borderTop: bar.topInset - anchors.margins - root.sdfBorderOffset
            borderBottom: bar.bottomInset - anchors.margins - root.sdfBorderOffset
        }

        PanelBg {
            id: dashBg
            objectName: "dashboardBackground"

            panel: panels.dashboard
            deformAmount: 0.1
        }

        PanelBg {
            id: launcherBg

            panel: panels.launcher
            deformAmount: 0.1
        }

        PanelBg {
            id: sessionBg

            panel: panels.sessionWrapper
            deformAmount: 0.2
            x: panels.x + panels.sessionWrapper.x + panels.session.x
            implicitWidth: panels.session.width
        }

        PanelBg {
            id: sidebarBg
            objectName: "notificationCenterBackground"

            panel: panels.sidebar
            // A single surface keeps the notification list and controls joined.
            deformAmount: panels.utilities.followSidebar ? 0 : 0.03
            implicitHeight: panels.utilities.followSidebar
                ? panel.height + panels.utilities.height
                : panel.height * (1 / rawDeformMatrix.m22) + 2
        }

        PanelBg {
            id: osdBg

            panel: panels.osdWrapper
            deformAmount: 0.25
            x: panels.x + panels.osdWrapper.x + panels.osd.x
            implicitWidth: panels.osd.width
        }

        PanelBg {
            id: notifsBg

            panel: panels.notifications
        }

        PanelBg {
            id: utilsBg

            panel: panels.utilities
            visible: (!panels.utilities.followSidebar || panels.utilities.keepStandaloneOpen)
                && panel.visible && panel.width > 0 && panel.height > 0
            deformAmount: panels.utilities.followSidebar ? 0 : 0.15
        }

        PanelBg {
            id: popoutBg
            objectName: "popoutBackground"

            // Keep the animated popout background joined to the horizontal bar.
            property real extraDepth: panels.popouts.isDetached ? 0 : 0.2

            panel: panels.popoutsWrapper
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

            utilities.deformMatrix: utilities.followSidebar ? sidebarBg.rawDeformMatrix : utilsBg.rawDeformMatrix

            dashboard.transform: Matrix4x4 {
                matrix: dashBg.deformMatrix
            }
            launcher.transform: Matrix4x4 {
                matrix: launcherBg.deformMatrix
            }
            session.transform: Matrix4x4 {
                matrix: sessionBg.deformMatrix
            }
            sidebar.transform: Matrix4x4 {
                matrix: sidebarBg.deformMatrix
            }
            osd.transform: Matrix4x4 {
                matrix: osdBg.deformMatrix
            }
            notifications.transform: Matrix4x4 {
                matrix: notifsBg.deformMatrix
            }
            utilities.transform: Matrix4x4 {
                matrix: panels.utilities.followSidebar ? sidebarBg.deformMatrix : utilsBg.deformMatrix
            }
            popouts.transform: Matrix4x4 {
                matrix: popoutBg.deformMatrix
            }
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

    component PanelBg: BlobRect {
        required property Item panel
        property real deformAmount: 0.15

        visible: panel.visible && panel.width > 0 && panel.height > 0
        group: visible ? blobGroup : null
        x: panels.x + panel.x
        y: panels.y + panel.y
        implicitWidth: panel.width
        implicitHeight: panel.height
        radius: Tokens.rounding.extraLarge
        deformScale: Hypr.stacking ? 0 : (deformAmount * Config.appearance.deformScale) / 10000
    }
}
