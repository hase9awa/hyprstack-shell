import QtQuick
import QtQuick.Controls
import Quickshell
import Hyprstack.Config
import qs.components
import qs.components.controls
import qs.modules.bar as Bar
import qs.modules.bar.popouts as BarPopouts

CustomMouseArea {
    id: root

    required property ShellScreen screen
    required property BarPopouts.Wrapper popouts
    required property ScreenState screenState
    required property Panels panels
    required property Bar.BarWrapper bar
    required property real borderThickness
    required property bool fullscreen

    property point dragStart
    property point pointerPosition: Qt.point(mouseX, mouseY)
    property bool dashboardShortcutActive
    property bool dashboardHoverBlocked
    property bool dashboardTabHoverHeld
    property bool osdShortcutActive
    property bool utilitiesShortcutActive

    function withinPanelHeight(panel: Item, x: real, y: real): bool {
        const start = panel.mapToItem(root, 0, 0);
        const end = panel.mapToItem(root, panel.width, panel.height);
        return y >= Math.min(start.y, end.y) - (Config.border.rounding * Tokens.scale) && y <= Math.max(start.y, end.y) + (Config.border.rounding * Tokens.scale);
    }

    function withinPanelWidth(panel: Item, x: real, y: real): bool {
        const start = panel.mapToItem(root, 0, 0);
        const end = panel.mapToItem(root, panel.width, panel.height);
        return x >= Math.min(start.x, end.x) - (Config.border.rounding * Tokens.scale) && x <= Math.max(start.x, end.x) + (Config.border.rounding * Tokens.scale);
    }

    function inBar(x: real, y: real, includeHidden = false): bool {
        const thickness = includeHidden ? bar.clampedThickness : bar.height;
        return bar.atBottom ? y >= height - thickness : y <= thickness;
    }

    function inRightPanel(panel: Item, x: real, y: real): bool {
        return x >= Math.min(width - Math.max(3, (Config.border.minThickness * Tokens.scale)), panels.x + panel.x) && withinPanelHeight(panel, x, y);
    }

    function inTopPanel(panel: Item, x: real, y: real): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y < Math.max(2, (Config.border.minThickness * Tokens.scale), panelHeight > 0 ? panels.y + panelHeight : 0) && withinPanelWidth(panel, x, y);
    }

    function inBottomPanel(panel: Item, x: real, y: real, isCorner = false): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y > height - Math.max(2, (Config.border.minThickness * Tokens.scale), panelHeight > 0 ? bar.bottomInset + panelHeight : 0) - (isCorner ? (Config.border.rounding * Tokens.scale) : 0) && withinPanelWidth(panel, x, y);
    }

    function inDashboard(x: real, y: real): bool {
        return panels.dashboard.atBottom ? inBottomPanel(panels.dashboard, x, y) : inTopPanel(panels.dashboard, x, y);
    }

    function inDashboardInteraction(x: real, y: real): bool {
        const panel = panels.dashboard;
        const extraWidth = (panel.interactionWidth - panel.width) / 2;
        const start = panel.mapToItem(root, -extraWidth, 0);
        const end = panel.mapToItem(root, panel.width + extraWidth, 0);
        const panelHeight = panel.interactionHeight * (1 - panel.offsetScale);
        return x >= Math.min(start.x, end.x) - Config.border.rounding * Tokens.scale
            && x <= Math.max(start.x, end.x) + Config.border.rounding * Tokens.scale
            && (panel.atBottom ? y > height - bar.bottomInset - panelHeight
                : y < panels.y + panelHeight);
    }

    function releaseDashboardHover(): void {
        dashboardTabHoverHeld = false;
        panels.dashboard.hoverHeight = 0;
        panels.dashboard.hoverWidth = 0;
    }

    function inUtilities(x: real, y: real): bool {
        if (bar.atBottom && !screenState.utilities && !screenState.sidebar)
            return x >= width - 8 && y < 8;
        return panels.utilities.atBottom ? inBottomPanel(panels.utilities, x, y, true) : inTopPanel(panels.utilities, x, y);
    }

    function onWheel(event: WheelEvent): void {
        if (fullscreen)
            return;
        if (inBar(event.x, event.y)) {
            bar.handleWheel(event.x, event.angleDelta);
        }
    }

    anchors.fill: parent
    acceptedButtons: fullscreen ? Qt.NoButton : Qt.AllButtons
    hoverEnabled: true

    onPressed: event => dragStart = Qt.point(event.x, event.y)
    onContainsMouseChanged: {
        if (!containsMouse)
            popoutLeaveTimer.restart();
    }

    // Passive hover also sees pointer events handled by child controls. Their
    // enter/leave events must not repeatedly close and recreate the drawers.
    HoverHandler {
        id: surfaceHover
        onHoveredChanged: if (!hovered) { utilitiesCornerTimer.stop(); popoutLeaveTimer.restart(); bar.resumePopoutHover(); }
        onPointChanged: if (hovered) root.updatePointer(point.position.x, point.position.y)
    }

    onPositionChanged: event => updatePointer(event.x, event.y)

    function updatePointer(x: real, y: real): void {
        if (dashboardTabHoverHeld && ((!panels.dashboard.resizing && inDashboard(x, y)) || !inDashboardInteraction(x, y)))
            releaseDashboardHover();
        pointerPosition = Qt.point(x, y);
        if (popouts.isDetached)
            return;

        const dragX = x - dragStart.x;
        const dragY = y - dragStart.y;

        if (fullscreen) {
            root.panels.osd.hovered = inRightPanel(panels.osdWrapper, x, y);
            return;
        }

        // Show bar in non-exclusive mode on hover
        if (!screenState.bar && Config.bar.showOnHover && inBar(x, y, true))
            bar.isHovered = true;

        // Show/hide bar on drag
        if (pressed && inBar(dragStart.x, dragStart.y, true)) {
            const inward = dragY * (bar.atBottom ? -1 : 1);
            if (inward > Config.bar.dragThreshold)
                screenState.bar = true;
            else if (inward < -Config.bar.dragThreshold)
                screenState.bar = false;
        }

        if (panels.sidebar.offsetScale === 1) {
            // Show osd on hover
            const showOsd = inRightPanel(panels.osdWrapper, x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                screenState.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            const showSidebar = pressed && dragStart.x > Math.min(width - (Config.border.minThickness * Tokens.scale), panels.x + panels.sidebar.x);

            // Show sidebar on hover (top-right corner, bounded by notification panel height)
            if (Config.sidebar.showOnHover) {
                const sidebarTriggerY = Math.max(Config.sidebar.minHoverThreshold, panels.y + panels.notifications.y + panels.notifications.height);
                const showSidebarHover = x > Math.min(width - (Config.border.minThickness * Tokens.scale), panels.x + panels.sidebar.x) && y <= sidebarTriggerY;
                if (showSidebarHover && !screenState.sidebar)
                    screenState.sidebar = true;
            }

            // Show/hide session on drag
            if (pressed && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    screenState.session = true;
                else if (dragX > Config.session.dragThreshold)
                    screenState.session = false;

                // Show sidebar on drag if in session area and session is nearly fully visible
                if (showSidebar && panels.session.offsetScale <= 0 && dragX < -Config.sidebar.dragThreshold)
                    screenState.sidebar = true;
            } else if (showSidebar && dragX < -Config.sidebar.dragThreshold) {
                // Show sidebar on drag if not in session area
                screenState.sidebar = true;
            }
        } else {
            const outOfSidebar = x < width - panels.sidebar.width * (1 - panels.sidebar.offsetScale);
            // Show osd on hover
            const showOsd = outOfSidebar && inRightPanel(panels.osdWrapper, x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                screenState.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            // Show/hide session on drag
            if (pressed && outOfSidebar && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    screenState.session = true;
                else if (dragX > Config.session.dragThreshold)
                    screenState.session = false;
            }

            // Show/hide sidebar on hover
            if (Config.sidebar.showOnHover && !pressed) {
                const sidebarTriggerY = Math.max(Config.sidebar.minHoverThreshold, panels.y + panels.notifications.y + panels.notifications.height);
                const showSidebarHover = x > Math.min(width - (Config.border.minThickness * Tokens.scale), panels.x + panels.sidebar.x) && y <= sidebarTriggerY;
                if (showSidebarHover && !screenState.sidebar) {
                    screenState.sidebar = true;
                } else {
                    const inSidebarArea = inRightPanel(panels.sidebar, x, y) || inRightPanel(panels.sessionWrapper, x, y);
                    if (!inSidebarArea)
                        screenState.sidebar = false;
                }
            }

            // Hide sidebar on drag
            if (pressed && inRightPanel(panels.sidebar, dragStart.x, 0) && dragX > Config.sidebar.dragThreshold)
                screenState.sidebar = false;
        }

        // Show launcher on hover, or show/hide on drag if hover is disabled
        if (Config.launcher.showOnHover) {
            if (!screenState.launcher && inBottomPanel(panels.launcher, x, y))
                screenState.launcher = true;
        } else if (pressed && inBottomPanel(panels.launcher, dragStart.x, dragStart.y) && withinPanelWidth(panels.launcher, x, y)) {
            if (dragY < -Config.launcher.dragThreshold)
                screenState.launcher = true;
            else if (dragY > Config.launcher.dragThreshold)
                screenState.launcher = false;
        }

        // Show dashboard on hover
        // Closing with the keyboard must finish before a shrinking panel can
        // hand visibility back to its hover sensor under a stationary pointer.
        if (dashboardHoverBlocked && panels.dashboard.offsetScale === 1 && !inDashboard(x, y))
            dashboardHoverBlocked = false;
        const showDashboard = !dashboardHoverBlocked && !bar.atBottom && Config.dashboard.showOnHover
            && !(panels.dashboard.atBottom && screenState.launcher)
            && (inDashboard(x, y) || (dashboardTabHoverHeld && inDashboardInteraction(x, y)));

        // Always update visibility based on hover if not in shortcut mode
        if (!dashboardShortcutActive) {
            screenState.dashboard = showDashboard;
        } else if (showDashboard) {
            // If hovering over dashboard area while in shortcut mode, transition to hover control
            dashboardShortcutActive = false;
        }

        // Show/hide dashboard on drag (for touchscreen devices)
        if (!bar.atBottom && pressed && inDashboard(dragStart.x, dragStart.y) && withinPanelWidth(panels.dashboard, x, y)) {
            const inward = dragY * (panels.dashboard.atBottom ? -1 : 1);
            if (inward > Config.dashboard.dragThreshold)
                screenState.dashboard = true;
            else if (inward < -Config.dashboard.dragThreshold)
                screenState.dashboard = false;
        }

        // Show utilities on hover
        const attachedUtilities = screenState.sidebar || panels.sidebar.visible;
        const atUtilitiesCorner = !attachedUtilities && bar.atBottom && x >= width - 8 && y < 8;
        if (atUtilitiesCorner && !screenState.utilities) {
            if (!utilitiesCornerTimer.running)
                utilitiesCornerTimer.start();
        } else {
            utilitiesCornerTimer.stop();
        }
        const showUtilities = (!bar.atBottom || screenState.utilities || screenState.sidebar) && inUtilities(x, y);

        // Always update visibility based on hover if not in shortcut mode
        if (!attachedUtilities && !utilitiesShortcutActive) {
            screenState.utilities = showUtilities;
        } else if (!attachedUtilities && showUtilities) {
            // If hovering over utilities area while in shortcut mode, transition to hover control
            utilitiesShortcutActive = false;
        }

        // Show popouts on hover
        if (inBar(x, y) && !screenState.dashboard) {
            bar.checkPopout(x, y);
        } else if (!panels.popoutsWrapper.hovered && (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1)
            && !(withinPanelWidth(panels.popoutsWrapper, x, y) && withinPanelHeight(panels.popoutsWrapper, x, y))) {
            popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    Timer {
        id: utilitiesCornerTimer
        interval: 180
        onTriggered: {
            const point = root.pointerPosition;
            if (root.bar.atBottom && point.x >= root.width - 8 && point.y < 8 && !root.fullscreen)
                root.screenState.utilities = true;
        }
    }

    Timer {
        id: popoutLeaveTimer
        interval: 160
        onTriggered: {
            if (root.containsMouse || surfaceHover.hovered)
                return;
            if (!root.osdShortcutActive) {
                root.screenState.osd = false;
                root.panels.osd.hovered = false;
            }
            if (!root.dashboardShortcutActive)
                root.screenState.dashboard = false;
            if (!root.utilitiesShortcutActive)
                root.screenState.utilities = false;
            if (root.Config.bar.showOnHover)
                root.bar.isHovered = false;
            if (root.Config.sidebar.showOnHover)
                root.screenState.sidebar = false;
            if (!root.panels.popoutsWrapper.hovered
                && (!root.popouts.currentName.startsWith("traymenu") || ((root.popouts.current as StackView)?.depth ?? 0) <= 1)) {
                root.popouts.hasCurrent = false;
                root.bar.closeTray();
            }
        }
    }

    // Monitor individual visibility changes
    Connections {
        function onLauncherChanged() {
            if (root.screenState.launcher && root.panels.dashboard.atBottom)
                root.screenState.dashboard = false;
            // If launcher is hidden, clear shortcut flags for dashboard and OSD
            if (!root.screenState.launcher) {
                root.dashboardShortcutActive = false;
                root.osdShortcutActive = false;
                root.utilitiesShortcutActive = false;

                // Also hide dashboard and OSD if they're not being hovered
                const inDashboardArea = root.inDashboard(root.pointerPosition.x, root.pointerPosition.y);
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.pointerPosition.x, root.pointerPosition.y);

                if (!inDashboardArea) {
                    root.screenState.dashboard = false;
                }
                if (!inOsdArea) {
                    root.screenState.osd = false;
                    root.panels.osd.hovered = false;
                }
            }
        }

        function onDashboardChanged() {
            if (root.screenState.dashboard) {
                // Dashboard became visible, immediately check if this should be shortcut mode
                const inDashboardArea = root.inDashboard(root.pointerPosition.x, root.pointerPosition.y);
                if (root.bar.atBottom || !inDashboardArea) {
                    root.dashboardShortcutActive = true;
                }
            } else {
                // Dashboard hidden, clear shortcut flag
                root.dashboardShortcutActive = false;
                root.releaseDashboardHover();
            }
        }

        function onDashboardTabChanged() {
            if (root.screenState.dashboard
                && root.inDashboard(root.pointerPosition.x, root.pointerPosition.y)) {
                root.panels.dashboard.hoverHeight = Math.max(root.panels.dashboard.hoverHeight, root.panels.dashboard.height);
                root.panels.dashboard.hoverWidth = Math.max(root.panels.dashboard.hoverWidth, root.panels.dashboard.width);
                root.dashboardTabHoverHeld = true;
            }
        }

        function onOsdChanged() {
            if (root.screenState.osd) {
                // OSD became visible, immediately check if this should be shortcut mode
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.pointerPosition.x, root.pointerPosition.y);
                if (!inOsdArea) {
                    root.osdShortcutActive = true;
                }
            } else {
                // OSD hidden, clear shortcut flag
                root.osdShortcutActive = false;
            }
        }

        function onUtilitiesChanged() {
            if (root.screenState.utilities) {
                // Utilities became visible, immediately check if this should be shortcut mode
                const inUtilitiesArea = root.inUtilities(root.pointerPosition.x, root.pointerPosition.y);
                if (!inUtilitiesArea) {
                    root.utilitiesShortcutActive = true;
                }
            } else {
                // Utilities hidden, clear shortcut flag
                root.utilitiesShortcutActive = false;
            }
        }

        target: root.screenState
    }

    Connections {
        target: root.bar

        function onAtBottomChanged() {
            root.dashboardShortcutActive = false;
            root.screenState.dashboard = false;
            root.utilitiesShortcutActive = false;
            root.screenState.utilities = false;
        }
    }
}
