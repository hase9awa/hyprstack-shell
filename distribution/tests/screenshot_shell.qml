// UI fixture for test_screenshots.py. Runs only on its private display and bus.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Hyprstack
import qs.services
import qs.modules.areapicker as Capture
import qs.modules.notifications as Popups
import qs.modules.sidebar as History
import qs.components

ShellRoot {
    id: root
    settings.watchFiles: false
    readonly property ScreenState screenState: ShellState.forScreen(Quickshell.screens[0])

    Component.onCompleted: { AnimationClock.activate(); Dialogs; Notifs; }
    Capture.AreaPicker { id: picker }
    History.Props { id: historyProps }

    FloatingWindow {
        id: underlay
        title: "Screenshot test underlay"
        implicitWidth: 900
        implicitHeight: 600
        color: "#234567"
        visible: true
        Text { anchors.centerIn: parent; text: "Screenshot test"; color: "white" }
    }

    PanelWindow {
        id: popupWindow
        anchors.top: true
        anchors.right: true
        implicitWidth: 420
        implicitHeight: popup.implicitHeight
        visible: (Notifs.popups.length > 0) && !(root.screenState?.sidebar ?? false)
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "test-screenshot-popup"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        Loader {
            id: popup
            width: parent.width
            active: Notifs.popups.length > 0
            sourceComponent: Popups.Notification {
                objectName: "testScreenshotPopup"
                implicitWidth: popupWindow.implicitWidth
                modelData: Notifs.popups[0] ?? null
                expanded: false
            }
        }
    }

    PanelWindow {
        id: historyWindow
        anchors.top: true
        anchors.left: true
        implicitWidth: 500
        implicitHeight: history.implicitHeight
        visible: (root.screenState?.sidebar ?? false) && Notifs.notClosed.length > 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "test-screenshot-history"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        Loader {
            id: history
            width: parent.width
            active: Notifs.notClosed.length > 0
            sourceComponent: History.Notif {
                modelData: Notifs.notClosed[0] ?? null
                props: historyProps
                expanded: true
                screenState: root.screenState
            }
        }
    }

    function findItem(item: var, name: string): var {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) {
            const found = findItem(child, name);
            if (found) return found;
        }
        return null;
    }

    IpcHandler {
        target: "screenshotTest"
        function status(): string {
            return JSON.stringify({loaded: Notifs.loaded, error: Notifs.lastError,
                underlay: underlay.visible, dialogs: Dialogs.dialogs.filter(d => d.visible).map(d => d.name),
                notifications: Notifs.notClosed.map(n => ({id:n.historyId, screenshot:n.screenshot,
                    path:n.screenshotPath, image:n.image, popup:n.popup}))});
        }
        function history(): void { ShellState.setNotificationCenter(root.screenState, true); }
        function rect(name: string): string {
            for (const win of [...Dialogs.dialogs, popupWindow, historyWindow]) {
                if (!win.visible) continue;
                const item = root.findItem(win.contentItem, name);
                if (!item) continue;
                const pos = item.mapToItem(null, item.width / 2, item.height / 2);
                return JSON.stringify({x:pos.x, y:pos.y, namespace:win === popupWindow
                    ? "test-screenshot-popup" : win === historyWindow
                    ? "test-screenshot-history" : "hyprstack-" + win.name});
            }
            return "null";
        }
    }
}
