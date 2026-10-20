pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Workspaces")
    isSubPage: true

    readonly property list<MenuItem> iconModes: [
        MenuItem { text: Tr.tr("Application colours"); icon: "palette"; value: "original" },
        MenuItem { text: Tr.tr("Tinted application icons"); icon: "format_color_fill"; value: "tinted" },
        MenuItem { text: Tr.tr("Standard symbols"); icon: "apps"; value: "symbols" }
    ]
    readonly property list<MenuItem> indicatorModes: [
        MenuItem { text: Tr.tr("Shapes"); icon: "shapes"; value: BarWorkspaceDisplay.Shapes },
        MenuItem { text: Tr.tr("Numbers / labels"); icon: "123"; value: BarWorkspaceDisplay.Text },
        MenuItem { text: Tr.tr("Workspace icons"); icon: "grid_view"; value: BarWorkspaceDisplay.Icons }
    ]

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StepperRow {
            first: true
            // TRANSLATORS: the number of workspaces shown on the bar
            label: Tr.trCtx("Shown", "bar workspaces")
            subtext: Tr.tr("Number of workspaces displayed")
            value: Config.bar.workspaces.shown
            from: 1
            to: 20
            stepSize: 1
            onMoved: v => GlobalConfig.bar.workspaces.shown = v
        }

        ToggleRow {
            text: Tr.trCtx("Active indicator", "bar workspaces")
            checked: Config.bar.workspaces.activeIndicator
            onToggled: GlobalConfig.bar.workspaces.activeIndicator = checked
        }

        ToggleRow {
            text: Tr.trCtx("Active trail", "bar workspaces")
            checked: Config.bar.workspaces.activeTrail
            onToggled: GlobalConfig.bar.workspaces.activeTrail = checked
        }

        ToggleRow {
            text: Tr.trCtx("Occupied background", "bar workspaces")
            checked: Config.bar.workspaces.occupiedBg
            onToggled: GlobalConfig.bar.workspaces.occupiedBg = checked
        }

        ToggleRow {
            text: Tr.trCtx("Show unoccupied", "bar workspaces")
            subtext: Tr.tr("When disabled, hide only empty workspaces after the last occupied or active workspace")
            checked: Config.bar.workspaces.showUnoccupied
            onToggled: GlobalConfig.bar.workspaces.showUnoccupied = checked
        }

        ToggleRow {
            text: Tr.trCtx("Per monitor", "bar workspaces")
            subtext: Tr.tr("Hide workspaces not on the current monitor")
            checked: Config.bar.workspaces.perMonitor
            onToggled: GlobalConfig.bar.workspaces.perMonitor = checked
        }

        ToggleRow {
            objectName: "workspaceSecondaryOnSpecial"
            text: Tr.tr("Second monitor overlay with Super+S")
            subtext: Tr.tr("Works with the second monitor switched off. Super+1–0 selects its workspace; press Super+S again to close the overlay.")
            enabled: Hypr.usingLua && Hypr.perMonitorWorkspaces
            checked: Hypr.secondaryOnSpecial
            onToggled: Hypr.setSecondaryOnSpecial(checked)
        }

        ToggleRow {
            text: Tr.trCtx("Show windows", "bar workspaces")
            subtext: Tr.tr("Show icons of open windows on each workspace")
            checked: Config.bar.workspaces.showWindows
            onToggled: GlobalConfig.bar.workspaces.showWindows = checked
        }

        ToggleRow {
            text: Tr.trCtx("Windows on special workspaces", "bar workspaces")
            checked: Config.bar.workspaces.showWindowsOnSpecialWorkspaces
            onToggled: GlobalConfig.bar.workspaces.showWindowsOnSpecialWorkspaces = checked
        }

        StepperRow {
            last: true
            // TRANSLATORS: maximum number of window icons shown per workspace
            label: Tr.trCtx("Max window icons", "bar workspaces")
            value: Config.bar.workspaces.maxWindowIcons
            from: 0
            to: 20
            stepSize: 1
            onMoved: v => GlobalConfig.bar.workspaces.maxWindowIcons = v
        }

        SectionHeader { text: Tr.tr("Icon appearance") }

        SelectRow {
            first: true
            objectName: "workspaceIndicatorStyle"
            updateActiveOnSelection: false
            label: Tr.tr("Workspace indicator")
            menuItems: root.indicatorModes
            active: root.indicatorModes.find(i => i.value === Config.bar.workspaces.displayType)
            onSelected: item => GlobalConfig.bar.workspaces.displayType = item.value
        }

        SelectRow {
            objectName: "workspaceIconStyle"
            updateActiveOnSelection: false
            label: Tr.tr("Window icons")
            menuItems: root.iconModes
            active: root.iconModes.find(i => i.value === WorkspaceIcons.mode)
            onSelected: item => WorkspaceIcons.set("mode", item.value)
        }

        StepperRow {
            objectName: "workspaceIconSize"
            label: Tr.tr("Window icon size")
            value: WorkspaceIcons.size
            from: 12
            to: 32
            onMoved: v => WorkspaceIcons.set("size", v)
        }

        PaletteRow {
            objectName: "workspaceActiveIconColour"
            label: Tr.tr("Active icon colour")
            subtext: Tr.tr("Tinted icons and symbols; choose a colour from the current scheme")
            value: WorkspaceIcons.activeSelection
            palette: Colours.palette
            choices: WorkspaceIcons.colourChoices
            choicePrefix: "workspaceActiveIconColour_"
            onSelected: role => {
                if (role.startsWith("#")) WorkspaceIcons.set("activeColour", role);
                else WorkspaceIcons.set("activeColourRole", role);
            }
        }

        PaletteRow {
            last: true
            objectName: "workspaceInactiveIconColour"
            label: Tr.tr("Inactive icon colour")
            subtext: Tr.tr("Tinted icons and symbols; choose a colour from the current scheme")
            value: WorkspaceIcons.inactiveSelection
            palette: Colours.palette
            choices: WorkspaceIcons.colourChoices
            choicePrefix: "workspaceInactiveIconColour_"
            onSelected: role => {
                if (role.startsWith("#")) WorkspaceIcons.set("inactiveColour", role);
                else WorkspaceIcons.set("inactiveColourRole", role);
            }
        }
    }
}
