pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Hyprstack.Config
import qs.modules.bar as Bar

Region {
    id: root

    required property Bar.BarWrapper bar
    required property Panels panels
    required property var win

    readonly property real borderThickness: win.borderThickness
    readonly property real clampedThickness: bar.atBottom ? 0 : Math.max(2, (win.contentItem.Config.border.minThickness * win.contentItem.Tokens.scale), win.borderThickness)

    x: clampedThickness + win.dragMaskPadding
    y: Math.max(clampedThickness, bar.topInset) + win.dragMaskPadding
    width: win.width - clampedThickness * 2 - win.dragMaskPadding * 2
    height: win.height - Math.max(clampedThickness, bar.topInset) - Math.max(clampedThickness, bar.bottomInset) - win.dragMaskPadding * 2
    intersection: Intersection.Xor

    Region {
        // A small, deliberate quick-settings corner. The rest of the top edge
        // belongs to the maximized application, including its tab hitboxes.
        x: root.win.width - width
        y: 0
        width: root.bar.atBottom && root.win.contentItem.Config.utilities.enabled ? 8 : 0
        height: width
        intersection: Intersection.Subtract
    }

    R {
        panel: root.panels.dashboard
        x: root.panels.x + panel.x + (panel.width - root.panels.dashboard.interactionWidth) / 2
        width: root.panels.dashboard.interactionWidth
        y: root.panels.dashboard.atBottom ? root.win.height - height : 0
        height: root.panels.dashboard.interactionHeight * Math.max(0, 1 - root.panels.dashboard.offsetScale)
            + (root.panels.dashboard.atBottom ? root.bar.bottomInset : root.bar.topInset)
    }

    R {
        panel: root.panels.launcher
        y: root.win.height - height
        height: panel.height * (1 - root.panels.launcher.offsetScale) + root.bar.bottomInset
    }

    R {
        id: sessionRegion

        panel: root.panels.sessionWrapper
        x: root.win.width - width
        width: panel.width * (1 - root.panels.session.offsetScale) + root.borderThickness + sidebarRegion.width
    }

    R {
        id: sidebarRegion

        panel: root.panels.sidebar
        x: root.bar.atBottom ? root.panels.x + panel.x : root.win.width - width
        width: root.bar.atBottom ? (panel.visible ? panel.width + root.borderThickness : 0)
            : panel.width * (1 - root.panels.sidebar.offsetScale) + root.borderThickness
        height: root.bar.atBottom ? Math.max(0, Math.min(panel.height, root.win.height - root.bar.bottomInset - y)) : panel.height
    }

    R {
        panel: root.panels.osdWrapper
        x: root.win.width - width
        // Stacking has no frame. Keep the closed OSD's edge reachable while
        // leaving the top hot corner and bottom taskbar to their own menus.
        y: Math.max(8, root.panels.y + panel.y)
        height: Math.max(0, Math.min(panel.height, root.win.height - root.bar.bottomInset - y))
        width: Math.max(root.bar.atBottom && root.win.contentItem.Config.osd.enabled ? 3 : 0,
            panel.width * (1 - root.panels.osd.offsetScale) + root.borderThickness + sessionRegion.width)
    }

    R {
        panel: root.panels.notifications
        y: 0
        height: panel.height + root.bar.topInset
    }

    R {
        panel: root.panels.utilities
        y: root.panels.utilities.followSidebar ? root.panels.y + panel.y
            : root.panels.utilities.atBottom ? root.win.height - height : 0
        height: panel.height * (root.panels.utilities.followSidebar ? 1 : (1 - root.panels.utilities.offsetScale))
            + (root.panels.utilities.atBottom ? root.bar.bottomInset : root.bar.topInset)
    }

    R {
        panel: root.panels.popoutsWrapper
    }

    component R: Region {
        required property Item panel

        x: root.panels.x + panel.x
        y: root.panels.y + panel.y
        width: panel.width
        height: panel.height
        intersection: Intersection.Subtract
    }
}
