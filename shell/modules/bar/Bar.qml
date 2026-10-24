pragma ComponentBehavior: Bound

import "popouts" as BarPopouts
import "components"
import "components/workspaces"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Hyprstack.Config
import qs.components
import qs.services
import "../../utils/scripts/panel-layout.js" as PanelLayout

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    readonly property int hPadding: Hypr.stacking ? 12 * Tokens.scale : Tokens.padding.large
    readonly property real spacing: Tokens.spacing.medium
    readonly property var rowEntries: layout.children.filter(c => c.entryId && c.visible)
    readonly property var entryItems: centeredTitle.visible ? [...rowEntries, centeredTitle] : rowEntries
    readonly property real titleWidth: {
        let left = hPadding, right = hPadding;
        const firstSpacer = rowEntries.findIndex(c => c.entryId === "spacer");
        for (let i = 0; i < rowEntries.length; ++i) {
            const item = rowEntries[i];
            if (item.entryId === "spacer") continue;
            if ((firstSpacer < 0 && ["logo", "workspaces"].includes(item.entryId)) || i < firstSpacer)
                left += item.width + spacing;
            else
                right += item.width + spacing;
        }
        return PanelLayout.centeredWidth(width, left, right, spacing);
    }
    readonly property real sideWidth: entryItems.filter(c => !["logo", "spacer", "workspaces", "activeWindow"].includes(c.entryId))
        .reduce((width, item) => width + item.width + spacing, hPadding)

    function entryAt(x: real): Item {
        for (const item of entryItems) {
            if (item.entryId === "spacer") continue;
            const position = item.mapToItem(root, 0, 0);
            if (x >= position.x && x < position.x + item.width)
                return item;
        }
        return null;
    }

    function closeTray(): void {
        if (!Config.bar.tray.compact)
            return;

        for (let i = 0; i < repeater.count; i++) {
            const tray = (repeater.itemAt(i) as EntryWrapper)?.item as Tray;
            if (tray)
                tray.expanded = false;
        }
    }

    function checkPopout(x: real): void {
        if (tasks.visible && tasks.contains(mapToItem(tasks, x, height / 2))) {
            closeTray();
            return;
        }
        const ch = entryAt(x) as EntryWrapper;

        if (ch?.entryId !== "tray")
            closeTray();

        if (!ch) {
            popouts.hasCurrent = false;
            return;
        }

        const id = ch.entryId;
        if (id === "statusIcons" && Config.bar.popouts.statusIcons) {
            const items = (ch.item as StatusIcons).items;
            const icon = items.childAt(mapToItem(items, x, height / 2).x, items.height / 2);
            if (icon) {
                popouts.currentName = icon.name;
                popouts.currentCenter = Qt.binding(() => icon.mapToItem(root, icon.width / 2, 0).x);
                popouts.hasCurrent = true;
            } else {
                popouts.hasCurrent = false;
            }
        } else if (id === "tray" && Config.bar.popouts.tray) {
            const tray = ch.item as Tray;
            if (!Config.bar.tray.compact || (tray.expanded && !tray.expandIcon.contains(mapToItem(tray.expandIcon, x, height / 2)))) {
                const item = tray.layout.childAt(mapToItem(tray.layout, x, height / 2).x, tray.layout.height / 2);
                let index = -1;
                for (let i = 0; i < tray.items.count; i++) {
                    if (tray.items.itemAt(i) === item) {
                        index = i;
                        break;
                    }
                }
                const trayItem = tray.items.itemAt(index);
                if (trayItem) {
                    popouts.currentName = `traymenu${index}`;
                    popouts.currentCenter = Qt.binding(() => trayItem.mapToItem(root, trayItem.width / 2, 0).x);
                    popouts.hasCurrent = true;
                } else {
                    popouts.hasCurrent = false;
                }
            } else {
                popouts.hasCurrent = false;
                tray.expanded = true;
            }
        } else if (id === "activeWindow" && Config.bar.popouts.activeWindow && Config.bar.activeWindow.showOnHover) {
            popouts.currentName = id.toLowerCase();
            popouts.currentCenter = (ch.item as Item).mapToItem(root, (ch.item as Item).width / 2, 0).x ?? 0;
            popouts.hasCurrent = true;
        } else {
            popouts.hasCurrent = false;
        }
    }

    function handleWheel(x: real, angleDelta: point): void {
        const ch = entryAt(x) as EntryWrapper;
        if (!Hypr.stacking && ch?.entryId === "workspaces" && Config.bar.scrollActions.workspaces) {
            // Workspace scroll
            const mon = Hypr.monitorFor(screen);
            const specialWs = mon?.lastIpcObject.specialWorkspace.name;
            if (specialWs?.length > 0)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.workspace.toggle_special("${specialWs.slice(8)}")` : `togglespecialworkspace ${specialWs.slice(8)}`);
            else if (angleDelta.y !== 0)
                Hypr.stepWorkspace(angleDelta.y > 0 ? -1 : 1, mon);
        }
    }

    RowLayout {
        id: layout
        anchors.fill: parent
        spacing: root.spacing

        Repeater {
            id: repeater

            model: ScriptModel {
                values: {
                    const entries = root.Config.bar.entries.values.filter(e => e.enabled
                        && !["notifications", "activeWindow"].includes(e.id) && (!Hypr.stacking || e.id !== "workspaces"));
                    // Also covers configurations saved before this entry existed.
                    const power = entries.findIndex(e => e.id === "power");
                    if (root.Config.sidebar.enabled && root.Config.bar.showNotifications)
                        entries.splice(power < 0 ? entries.length : power, 0, {id: "notifications", enabled: true});
                    return entries;
                }
            }

            DelegateChooser {
                role: "id"

                DelegateChoice {
                    roleValue: "spacer"
                    delegate: EntryWrapper {
                        Layout.fillWidth: true
                    }
                }
                DelegateChoice {
                    roleValue: "logo"
                    delegate: EntryWrapper {
                        OsIcon {
                            objectName: "taskbarLogo"
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "workspaces"
                    delegate: EntryWrapper {
                        Item {
                            implicitWidth: workspaces.implicitHeight
                            implicitHeight: workspaces.implicitWidth
                            Workspaces {
                                id: workspaces
                                objectName: "taskbarWorkspaces"
                                screen: root.screen
                                fullscreen: root.fullscreen
                                visible: !Hypr.stacking
                                y: implicitWidth
                                rotation: -90
                                transformOrigin: Item.TopLeft
                            }
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "tray"
                    delegate: EntryWrapper {
                        Tray {
                            objectName: "taskbarTray"
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "clock"
                    delegate: EntryWrapper {
                        Clock {
                            objectName: "taskbarClock"
                            screenState: root.screenState
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "statusIcons"
                    delegate: EntryWrapper {
                        StatusIcons {
                            objectName: "taskbarStatusIcons"
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "vpn"
                    delegate: EntryWrapper {
                        VpnToggle {
                            objectName: "taskbarVpnToggle"
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "notifications"
                    delegate: EntryWrapper {
                        NotificationCenterButton {
                            objectName: "taskbarNotificationCenterButton"
                            screenState: root.screenState
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "power"
                    delegate: EntryWrapper {
                        Power {
                            objectName: "taskbarPowerButton"
                            screenState: root.screenState
                        }
                    }
                }
            }
        }
    }

    EntryWrapper {
        id: centeredTitle
        objectName: "taskbarCenteredTitle"
        modelData: ({id: "activeWindow"})
        index: -1
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        visible: !Hypr.stacking && root.titleWidth > 0
            && root.Config.bar.entries.values.some(e => e.id === "activeWindow" && e.enabled)

        ActiveWindow {
            objectName: "taskbarActiveWindow"
            bar: root
            monitor: Brightness.getMonitorForScreen(root.screen)
        }
    }

    Tasks {
        id: tasks
        objectName: "taskbarTasks"
        anchors.centerIn: parent
        screen: root.screen
        popouts: root.popouts
        maxWidth: Math.max(0, root.width - 2 * Math.max(root.sideWidth, root.hPadding + 40 * Tokens.scale) - 24 * Tokens.scale)
        visible: Hypr.stacking && Config.bar.showTasks && maxWidth > 0
    }

    component EntryWrapper: Item {
        required property var modelData
        required property int index
        default property Item item
        readonly property string entryId: modelData.id

        Layout.leftMargin: index === 0 ? root.hPadding : 0
        Layout.rightMargin: index === repeater.count - 1 ? root.hPadding : 0
        Layout.alignment: Qt.AlignVCenter

        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0

        children: item
    }
}
