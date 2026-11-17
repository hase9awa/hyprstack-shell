pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var warnLevels: GlobalConfig.general.battery.warnLevels

    title: Tr.tr("Battery warnings")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Hibernation guard
        SectionHeader {
            first: true
            text: Tr.tr("Critical level")
        }

        StepperRow {
            first: true
            last: true
            label: Tr.tr("Critical battery level")
            subtext: Tr.tr("Hibernates the system five seconds after the battery falls to this level")
            value: GlobalConfig.general.battery.criticalLevel
            from: 0
            to: 100
            stepSize: 1
            onMoved: v => GlobalConfig.general.battery.criticalLevel = Math.round(v)
        }

        // Warning levels
        SectionHeader {
            text: Tr.tr("Warning levels")
        }

        Repeater {
            model: root.warnLevels.values

            ColumnLayout {
                id: entry

                required property var modelData
                required property int index

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    first: entry.index === 0
                    text: Tr.tr("At %1% charge").arg(root.warnLevels.at(entry.index)?.level ?? entry.modelData.level)
                }

                StepperRow {
                    first: true
                    label: Tr.tr("Level")
                    subtext: Tr.tr("Battery percentage that triggers the warning")
                    value: root.warnLevels.at(entry.index)?.level ?? entry.modelData.level
                    from: 1
                    to: 100
                    stepSize: 1
                    onMoved: v => root.warnLevels.at(entry.index).level = Math.round(v)
                }

                TextFieldRow {
                    label: Tr.tr("Title")
                    subtext: Tr.tr("First line of the notification")
                    value: root.warnLevels.at(entry.index)?.title ?? entry.modelData.title ?? ""
                    onEditingFinished: v => root.warnLevels.at(entry.index).title = v
                }

                TextFieldRow {
                    label: Tr.tr("Message")
                    subtext: Tr.tr("Body of the notification")
                    value: root.warnLevels.at(entry.index)?.message ?? entry.modelData.message ?? ""
                    onEditingFinished: v => root.warnLevels.at(entry.index).message = v
                }

                TextFieldRow {
                    label: Tr.tr("Icon")
                    subtext: Tr.tr("Material icon name")
                    value: root.warnLevels.at(entry.index)?.icon ?? entry.modelData.icon ?? ""
                    onEditingFinished: v => root.warnLevels.at(entry.index).icon = v
                }

                ToggleRow {
                    text: Tr.tr("Critical")
                    subtext: Tr.tr("Show the warning as an error")
                    checked: root.warnLevels.at(entry.index)?.critical ?? entry.modelData.critical ?? false
                    onToggled: root.warnLevels.at(entry.index).critical = checked
                }

                RowButton {
                    last: true
                    icon: "delete"
                    text: Tr.tr("Remove level")
                    onClicked: root.warnLevels.remove(entry.index)
                }
            }
        }

        RowButton {
            first: true
            last: true
            icon: "add"
            text: Tr.tr("Add level")
            onClicked: root.warnLevels.insert({
                level: 15,
                icon: "battery_android_frame_2"
            })
        }
    }
}
