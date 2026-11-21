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

    readonly property list<MenuItem> titlePresets: [
        MenuItem { text: Tr.tr("Low battery"); value: Tr.mark("Low battery") },
        MenuItem { text: Tr.tr("Did you see the previous message?"); value: Tr.mark("Did you see the previous message?") },
        MenuItem { text: Tr.tr("Critical battery level"); value: Tr.mark("Critical battery level") },
        MenuItem { text: Tr.tr("Battery warning"); value: Tr.mark("Battery warning") }
    ]

    readonly property list<MenuItem> messagePresets: [
        MenuItem { text: Tr.tr("You might want to plug in a charger"); value: Tr.mark("You might want to plug in a charger") },
        MenuItem { text: Tr.tr("You should probably plug in a charger <b>now</b>"); value: Tr.mark("You should probably plug in a charger <b>now</b>") },
        MenuItem { text: Tr.tr("PLUG THE CHARGER RIGHT NOW!!"); value: Tr.mark("PLUG THE CHARGER RIGHT NOW!!") },
        MenuItem { text: Tr.tr("Battery level is low"); value: Tr.mark("Battery level is low") }
    ]

    readonly property list<MenuItem> iconPresets: [
        MenuItem { text: "battery_android_frame_2"; icon: "battery_android_frame_2"; value: "battery_android_frame_2" },
        MenuItem { text: "battery_android_frame_1"; icon: "battery_android_frame_1"; value: "battery_android_frame_1" },
        MenuItem { text: "battery_android_alert"; icon: "battery_android_alert"; value: "battery_android_alert" },
        MenuItem { text: "battery_full"; icon: "battery_full"; value: "battery_full" },
        MenuItem { text: "battery_charging_full"; icon: "battery_charging_full"; value: "battery_charging_full" },
        MenuItem { text: "battery_alert"; icon: "battery_alert"; value: "battery_alert" },
        MenuItem { text: "battery_saver"; icon: "battery_saver"; value: "battery_saver" }
    ]

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
                    value: Tr.trMarked(root.warnLevels.at(entry.index)?.title ?? entry.modelData.title ?? "")
                    placeholderText: Tr.tr("Battery warning")
                    menuItems: root.titlePresets
                    onEditingFinished: v => {
                        const stored = root.warnLevels.at(entry.index)?.title ?? entry.modelData.title ?? "";
                        // Blur or re-typing the visible text must not overwrite the marker
                        if (v === Tr.trMarked(stored))
                            return;
                        root.warnLevels.at(entry.index).title = v;
                    }
                    onMenuSelected: item => root.warnLevels.at(entry.index).title = item.value
                }

                TextFieldRow {
                    label: Tr.tr("Message")
                    subtext: Tr.tr("Body of the notification")
                    value: Tr.trMarked(root.warnLevels.at(entry.index)?.message ?? entry.modelData.message ?? "")
                    placeholderText: Tr.tr("Battery level is low")
                    menuItems: root.messagePresets
                    onEditingFinished: v => {
                        const stored = root.warnLevels.at(entry.index)?.message ?? entry.modelData.message ?? "";
                        if (v === Tr.trMarked(stored))
                            return;
                        root.warnLevels.at(entry.index).message = v;
                    }
                    onMenuSelected: item => root.warnLevels.at(entry.index).message = item.value
                }

                TextFieldRow {
                    label: Tr.tr("Icon")
                    subtext: Tr.tr("Material icon name")
                    value: root.warnLevels.at(entry.index)?.icon ?? entry.modelData.icon ?? ""
                    leadingIcon: value
                    menuItems: root.iconPresets
                    onEditingFinished: v => root.warnLevels.at(entry.index).icon = v
                    onMenuSelected: item => root.warnLevels.at(entry.index).icon = item.value
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
