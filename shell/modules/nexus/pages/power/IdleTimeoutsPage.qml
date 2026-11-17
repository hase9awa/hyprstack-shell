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

    readonly property var timeouts: GlobalConfig.general.idle.timeouts

    // Idle actions are stored as a string for the shell's own dispatchers and
    // as an argument list for session commands; both normalise to one key.
    function actionKey(action: var): string {
        if (action === undefined || action === null || action === "")
            return "";
        if (typeof action === "string")
            return action;
        return String(action);
    }

    // Strings reach Hyprland dispatchers, lists run through the session manager
    function writeAction(index: int, key: string, prop: string): void {
        const node = root.timeouts.at(index);
        if (!node)
            return;
        const shellStrings = ["", "lock", "unlock", "dpms off", "dpms on"];
        node[prop] = shellStrings.includes(key) ? key : [key];
    }

    readonly property list<MenuItem> idleActionItems: [
        MenuItem {
            text: Tr.tr("Lock screen")
            icon: "lock"
            value: "lock"
        },
        MenuItem {
            text: Tr.tr("Turn off the display")
            icon: "visibility_off"
            value: "dpms off"
        },
        MenuItem {
            text: Tr.tr("Suspend")
            icon: "bedtime"
            value: "suspend"
        },
        MenuItem {
            text: Tr.tr("Hibernate")
            icon: "downloading"
            value: "hibernate"
        },
        MenuItem {
            text: Tr.tr("Log out")
            icon: "logout"
            value: "logout"
        },
        MenuItem {
            text: Tr.tr("Power off")
            icon: "power_settings_new"
            value: "poweroff"
        },
        MenuItem {
            text: Tr.tr("Reboot")
            icon: "cached"
            value: "reboot"
        },
        MenuItem {
            text: Tr.tr("Do nothing")
            icon: "block"
            value: ""
        }
    ]

    readonly property list<MenuItem> returnActionItems: [
        MenuItem {
            text: Tr.tr("Turn on the display")
            icon: "visibility"
            value: "dpms on"
        },
        MenuItem {
            text: Tr.tr("Unlock")
            icon: "lock_open"
            value: "unlock"
        },
        MenuItem {
            text: Tr.tr("Do nothing")
            icon: "block"
            value: ""
        }
    ]

    title: Tr.tr("Sleep timeouts")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledText {
            Layout.fillWidth: true
            text: Tr.tr("Each timeout runs its action after the screen has been idle for the given time.")
            wrapMode: Text.WordWrap
            color: Colours.palette.m3onSurfaceVariant
        }

        Repeater {
            model: root.timeouts.values

            ColumnLayout {
                id: entry

                required property var modelData
                required property int index

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    first: entry.index === 0
                    text: Tr.tr("After %1 seconds").arg(root.timeouts.at(entry.index)?.timeout ?? entry.modelData.timeout)
                }

                StepperRow {
                    first: true
                    label: Tr.tr("Timeout")
                    subtext: Tr.tr("Seconds of inactivity before the action")
                    value: root.timeouts.at(entry.index)?.timeout ?? entry.modelData.timeout
                    from: 5
                    to: 86400
                    stepSize: 5
                    onMoved: v => root.timeouts.at(entry.index).timeout = Math.round(v)
                }

                SelectRow {
                    label: Tr.tr("When idle")
                    subtext: Tr.tr("Action after the timeout")
                    menuItems: root.idleActionItems
                    active: root.idleActionItems.find(i => i.value === root.actionKey(root.timeouts.at(entry.index)?.idleAction)) ?? null
                    fallbackText: root.actionKey(root.timeouts.at(entry.index)?.idleAction) || Tr.tr("Custom")
                    onSelected: item => root.writeAction(entry.index, item.value, "idleAction")
                }

                SelectRow {
                    label: Tr.tr("When returning")
                    subtext: Tr.tr("Action when the session becomes active")
                    menuItems: root.returnActionItems
                    active: root.returnActionItems.find(i => i.value === root.actionKey(root.timeouts.at(entry.index)?.returnAction)) ?? null
                    fallbackText: root.actionKey(root.timeouts.at(entry.index)?.returnAction) || Tr.tr("Custom")
                    onSelected: item => root.writeAction(entry.index, item.value, "returnAction")
                }

                ToggleRow {
                    text: Tr.trCtx("Enabled", "toggle label")
                    checked: root.timeouts.at(entry.index)?.enabled ?? entry.modelData.enabled ?? true
                    onToggled: root.timeouts.at(entry.index).enabled = checked
                }

                ToggleRow {
                    text: Tr.tr("Respect inhibitors")
                    subtext: Tr.tr("Honour requests from apps to stay awake")
                    checked: root.timeouts.at(entry.index)?.respectInhibitors ?? entry.modelData.respectInhibitors ?? true
                    onToggled: root.timeouts.at(entry.index).respectInhibitors = checked
                }

                ToggleRow {
                    text: Tr.tr("Inhibit while audio plays")
                    checked: root.timeouts.at(entry.index)?.inhibitWhenAudio ?? entry.modelData.inhibitWhenAudio ?? false
                    onToggled: root.timeouts.at(entry.index).inhibitWhenAudio = checked
                }

                ToggleRow {
                    text: Tr.tr("Inhibit while charging")
                    checked: root.timeouts.at(entry.index)?.inhibitWhenCharging ?? entry.modelData.inhibitWhenCharging ?? false
                    onToggled: root.timeouts.at(entry.index).inhibitWhenCharging = checked
                }

                RowButton {
                    last: true
                    icon: "delete"
                    text: Tr.tr("Remove timeout")
                    onClicked: root.timeouts.remove(entry.index)
                }
            }
        }

        RowButton {
            first: true
            last: true
            icon: "add"
            text: Tr.tr("Add timeout")
            onClicked: root.timeouts.insert({
                timeout: 60,
                idleAction: "lock"
            })
        }
    }
}
