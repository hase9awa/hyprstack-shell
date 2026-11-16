pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    // OSD side, values must match config::OsdSide (Left, Right)
    readonly property list<MenuItem> osdSideItems: [
        MenuItem {
            text: Tr.tr("Left")
            value: OsdSide.Left
            icon: "chevron_left"
        },
        MenuItem {
            text: Tr.tr("Right")
            value: OsdSide.Right
            icon: "chevron_right"
        }
    ]

    title: Tr.tr("Sound and brightness")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: Tr.tr("General")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Enabled", "toggle label")
            checked: Config.osd.enabled
            onToggled: GlobalConfig.osd.enabled = checked
        }

        ToggleRow {
            text: Tr.tr("Show on hover")
            subtext: Tr.tr("Reveal when the cursor reaches the screen edge")
            checked: Config.osd.showOnHover
            onToggled: GlobalConfig.osd.showOnHover = checked
        }

        SelectRow {
            label: Tr.tr("Orientation")
            subtext: Tr.tr("Screen edge the indicator appears on")
            menuItems: root.osdSideItems
            active: root.osdSideItems.find(i => i.value === Config.osd.side)
            onSelected: item => GlobalConfig.osd.side = item.value
        }

        StepperRow {
            last: true
            label: Tr.tr("Hide delay")
            // TRANSLATORS: ms is the millisecond unit, leave it untranslated
            subtext: Tr.tr("Time before the indicator hides (ms)")
            value: Config.osd.hideDelay
            from: 0
            to: 10000
            stepSize: 100
            onMoved: v => GlobalConfig.osd.hideDelay = Math.round(v)
        }

        SectionHeader {
            text: Tr.tr("Sliders")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Show brightness slider")
            subtext: Tr.tr("Brightness control in the indicator")
            checked: Config.osd.enableBrightness
            onToggled: GlobalConfig.osd.enableBrightness = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Show microphone slider")
            subtext: Tr.tr("Input volume control in the indicator")
            checked: Config.osd.enableMicrophone
            onToggled: GlobalConfig.osd.enableMicrophone = checked
        }
    }
}
