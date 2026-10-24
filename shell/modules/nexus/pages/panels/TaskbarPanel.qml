pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQml.Models
import Quickshell
import Hyprstack.Config
import Hyprstack.I18n
import qs.modules.nexus.common
import qs.components.controls

PageBase {
    id: root

    title: Tr.tr("Taskbar")
    isSubPage: true

    property string selectedScreen: ""
    property int screenRevision: 0
    readonly property var targetConfig: selectedScreen ? GlobalConfig.forScreen(selectedScreen) : GlobalConfig
    readonly property list<MenuItem> screenChoices: {
        screenRevision;
        const result = [allScreens];
        for (let i = 0; i < screenItems.count; ++i) {
            const choice = screenItems.objectAt(i);
            if (choice) result.push(choice);
        }
        return result;
    }
    readonly property var componentChoices: [
        {id: "logo", label: Tr.tr("Logo")},
        {id: "workspaces", label: Tr.tr("Workspaces")},
        {id: "activeWindow", label: Tr.tr("Active window")},
        {id: "tray", label: Tr.tr("Tray")},
        {id: "clock", label: Tr.tr("Clock")},
        {id: "statusIcons", label: Tr.tr("Status icons")},
        {id: "vpn", label: Tr.tr("VPN")},
        {id: "power", label: Tr.tr("Power button")}
    ]

    readonly property MenuItem allScreens: MenuItem { text: Tr.tr("All screens"); icon: "desktop_windows"; value: "" }
    readonly property QtObject screenModel: Instantiator {
        id: screenItems
        model: Quickshell.screens
        delegate: MenuItem {
            required property var modelData
            text: modelData.name
            icon: "monitor"
            value: modelData.name
        }
        onObjectAdded: root.screenRevision++
        onObjectRemoved: (index, object) => {
            root.screenRevision++;
            if (root.selectedScreen === object.value) root.selectedScreen = "";
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Behaviour
        SectionHeader {
            first: true
            text: Tr.tr("Behaviour")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Persistent")
            subtext: Tr.tr("Keep the bar visible at all times")
            checked: Config.bar.persistent
            onToggled: GlobalConfig.bar.persistent = checked
        }

        ToggleRow {
            text: Tr.tr("Show on hover")
            subtext: Tr.tr("Reveal the bar when the cursor reaches the screen edge")
            checked: Config.bar.showOnHover
            onToggled: GlobalConfig.bar.showOnHover = checked
        }

        StepperRow {
            last: true
            label: Tr.tr("Drag threshold")
            subtext: Tr.tr("Pixels dragged before the bar reveals")
            value: Config.bar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.bar.dragThreshold = v
        }

        // Components
        SectionHeader { text: Tr.tr("Element visibility") }

        SelectRow {
            first: true
            objectName: "taskbarScreenSelector"
            label: Tr.tr("Screen")
            subtext: Tr.tr("Choose a screen to hide individual panel elements")
            menuItems: root.screenChoices
            active: root.screenChoices.find(item => item.value === root.selectedScreen) ?? allScreens
            onSelected: item => root.selectedScreen = item.value
        }

        Repeater {
            model: root.componentChoices
            delegate: ToggleRow {
                required property var modelData
                objectName: "taskbarElement_" + modelData.id
                text: modelData.label
                checked: root.targetConfig.bar.entries.values.find(entry => entry.id === modelData.id)?.enabled ?? false
                onToggled: {
                    const entries = root.targetConfig.bar.entries;
                    const entry = entries.values.find(entry => entry.id === modelData.id);
                    if (entry) entry.enabled = checked;
                    else {
                        const beforePower = modelData.id === "vpn" ? entries.values.findIndex(item => item.id === "power") : -1;
                        entries.insert({id: modelData.id, enabled: checked}, beforePower);
                    }
                }
            }
        }

        ToggleRow {
            objectName: "taskbarElement_notifications"
            text: Tr.tr("Notification centre")
            checked: root.targetConfig.bar.showNotifications
            onToggled: root.targetConfig.bar.showNotifications = checked
        }

        ToggleRow {
            last: true
            objectName: "taskbarElement_tasks"
            text: Tr.tr("Applications in stacking mode")
            checked: root.targetConfig.bar.showTasks
            onToggled: root.targetConfig.bar.showTasks = checked
        }

        SectionHeader {
            text: Tr.tr("Components")
        }

        NavRow {
            first: true
            icon: "workspaces"
            text: Tr.tr("Workspaces")
            subtext: Tr.tr("Indicators, window icons")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            icon: "web_asset"
            text: Tr.tr("Active window")
            subtext: Tr.tr("Title display, popout")
            onClicked: root.nState.openSubPage(7)
        }

        NavRow {
            icon: "widgets"
            text: Tr.tr("Tray")
            subtext: Tr.tr("System tray icons")
            onClicked: root.nState.openSubPage(8)
        }

        NavRow {
            icon: "signal_cellular_alt"
            text: Tr.tr("Status icons")
            subtext: Tr.tr("Visible indicators")
            onClicked: root.nState.openSubPage(9)
        }

        NavRow {
            last: true
            icon: "schedule"
            text: Tr.tr("Clock")
            subtext: Tr.tr("Date, icon, background")
            onClicked: root.nState.openSubPage(10)
        }

        // Scroll actions
        SectionHeader {
            text: Tr.tr("Scroll actions")
        }

        ToggleRow {
            first: true
            last: true
            text: Tr.tr("Workspaces")
            subtext: Tr.tr("Scroll over the workspace indicator to switch workspaces")
            checked: Config.bar.scrollActions.workspaces
            onToggled: GlobalConfig.bar.scrollActions.workspaces = checked
        }

    }
}
