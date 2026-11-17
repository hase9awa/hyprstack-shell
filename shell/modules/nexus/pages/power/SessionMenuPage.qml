pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    function splitCommand(text: string): var {
        return text.split(/\s+/).filter(part => part.length > 0);
    }

    title: Tr.tr("Session menu")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // General
        SectionHeader {
            first: true
            text: Tr.tr("General")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Enabled", "toggle label")
            subtext: Tr.tr("Show the session menu in the drawer")
            checked: Config.session.enabled
            onToggled: GlobalConfig.session.enabled = checked
        }

        StepperRow {
            label: Tr.tr("Drag threshold")
            subtext: Tr.tr("Distance to drag before the menu opens (pixels)")
            value: Config.session.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.session.dragThreshold = Math.round(v)
        }

        ToggleRow {
            last: true
            text: Tr.tr("Vim keybinds")
            subtext: Tr.tr("Navigate the menu with hjkl")
            checked: Config.session.vimKeybinds
            onToggled: GlobalConfig.session.vimKeybinds = checked
        }

        // Commands
        SectionHeader {
            text: Tr.tr("Commands")
        }

        TextFieldRow {
            first: true
            label: Tr.tr("Logout command")
            subtext: Tr.tr("Command and arguments, separated by spaces")
            value: Config.session.commands.logout.join(" ")
            onEditingFinished: v => GlobalConfig.session.commands.logout = root.splitCommand(v)
        }

        TextFieldRow {
            label: Tr.tr("Shutdown command")
            subtext: Tr.tr("Command and arguments, separated by spaces")
            value: Config.session.commands.shutdown.join(" ")
            onEditingFinished: v => GlobalConfig.session.commands.shutdown = root.splitCommand(v)
        }

        TextFieldRow {
            label: Tr.tr("Hibernate command")
            subtext: Tr.tr("Command and arguments, separated by spaces")
            value: Config.session.commands.hibernate.join(" ")
            onEditingFinished: v => GlobalConfig.session.commands.hibernate = root.splitCommand(v)
        }

        TextFieldRow {
            last: true
            label: Tr.tr("Reboot command")
            subtext: Tr.tr("Command and arguments, separated by spaces")
            value: Config.session.commands.reboot.join(" ")
            onEditingFinished: v => GlobalConfig.session.commands.reboot = root.splitCommand(v)
        }

        // Icons
        SectionHeader {
            text: Tr.tr("Icons")
        }

        TextFieldRow {
            first: true
            label: Tr.tr("Logout icon")
            subtext: Tr.tr("Material icon name")
            value: Config.session.icons.logout
            onEditingFinished: v => GlobalConfig.session.icons.logout = v
        }

        TextFieldRow {
            label: Tr.tr("Shutdown icon")
            subtext: Tr.tr("Material icon name")
            value: Config.session.icons.shutdown
            onEditingFinished: v => GlobalConfig.session.icons.shutdown = v
        }

        TextFieldRow {
            label: Tr.tr("Hibernate icon")
            subtext: Tr.tr("Material icon name")
            value: Config.session.icons.hibernate
            onEditingFinished: v => GlobalConfig.session.icons.hibernate = v
        }

        TextFieldRow {
            last: true
            label: Tr.tr("Reboot icon")
            subtext: Tr.tr("Material icon name")
            value: Config.session.icons.reboot
            onEditingFinished: v => GlobalConfig.session.icons.reboot = v
        }
    }
}
