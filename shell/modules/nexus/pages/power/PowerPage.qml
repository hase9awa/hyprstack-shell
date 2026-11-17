pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Hyprstack.Config
import Hyprstack.I18n
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    // Ordered to match UPower PowerProfile (PowerSaver, Balanced, Performance)
    readonly property list<MenuItem> profileItems: [
        MenuItem {
            text: Tr.trCtx("Power saver", "power profile")
            icon: "energy_savings_leaf"
            value: PowerProfile.PowerSaver
        },
        MenuItem {
            text: Tr.trCtx("Balanced", "power profile")
            icon: "balance"
            value: PowerProfile.Balanced
        },
        MenuItem {
            text: Tr.trCtx("Performance", "power profile")
            icon: "rocket_launch"
            value: PowerProfile.Performance
        }
    ]

    title: Tr.tr("Power & security")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Power profile
        SectionHeader {
            first: true
            text: Tr.tr("Power profile")
        }

        SelectRow {
            first: true
            last: true
            label: Tr.tr("Power profile")
            subtext: Tr.tr("Balance between performance and battery life")
            menuItems: root.profileItems
            active: root.profileItems.find(i => i.value === PowerProfiles.profile) ?? null
            fallbackText: Tr.trCtx("Unknown", "power profile")
            onSelected: item => PowerProfiles.profile = item.value
        }

        // Sleep and lock
        SectionHeader {
            text: Tr.tr("Sleep and lock")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Lock before sleep")
            subtext: Tr.tr("Lock the screen as the system goes to sleep")
            checked: GlobalConfig.general.idle.lockBeforeSleep
            onToggled: GlobalConfig.general.idle.lockBeforeSleep = checked
        }

        ToggleRow {
            text: Tr.tr("Inhibit while audio plays")
            subtext: Tr.tr("Pause idle timers while media is playing")
            checked: GlobalConfig.general.idle.inhibitWhenAudio
            onToggled: GlobalConfig.general.idle.inhibitWhenAudio = checked
        }

        ToggleRow {
            text: Tr.tr("Inhibit while charging")
            subtext: Tr.tr("Stay awake while the charger is connected")
            checked: GlobalConfig.general.idle.inhibitWhenCharging
            onToggled: GlobalConfig.general.idle.inhibitWhenCharging = checked
        }

        NavRow {
            last: true
            icon: "timer"
            text: Tr.tr("Sleep timeouts")
            subtext: Tr.tr("Actions after periods of inactivity")
            onClicked: root.nState.openSubPage(1)
        }

        // Lock screen
        SectionHeader {
            text: Tr.trCtx("Lock screen", "settings page")
        }

        NavRow {
            first: true
            last: true
            icon: "lock"
            text: Tr.trCtx("Lock screen", "settings page")
            subtext: Tr.tr("Wallpaper, fingerprint and face unlock")
            onClicked: root.nState.openSubPage(2)
        }

        // Battery
        SectionHeader {
            text: Tr.tr("Battery warnings")
        }

        NavRow {
            first: true
            last: true
            icon: "battery_alert"
            text: Tr.tr("Battery warnings")
            subtext: Tr.tr("Warning levels, titles and icons")
            onClicked: root.nState.openSubPage(3)
        }

        // Session menu
        SectionHeader {
            text: Tr.tr("Session menu")
        }

        NavRow {
            first: true
            last: true
            icon: "exit_to_app"
            text: Tr.tr("Session menu")
            subtext: Tr.tr("Logout, shutdown, hibernate and reboot")
            onClicked: root.nState.openSubPage(4)
        }
    }
}
