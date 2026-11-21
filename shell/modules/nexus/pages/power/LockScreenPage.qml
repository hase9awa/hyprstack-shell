pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.trCtx("Lock screen", "settings page")
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
            subtext: Tr.tr("Show the lock screen on demand and before sleep")
            checked: Config.lock.enabled
            onToggled: GlobalConfig.lock.enabled = checked
        }

        ToggleRow {
            text: Tr.tr("Use wallpaper")
            subtext: Tr.tr("Use the wallpaper instead of a screenshot as the background")
            checked: Config.lock.useWallpaper
            onToggled: GlobalConfig.lock.useWallpaper = checked
        }

        ToggleRow {
            text: Tr.tr("Recolour logo")
            subtext: Tr.tr("Tint the logo with the current theme colour")
            checked: Config.lock.recolourLogo
            onToggled: GlobalConfig.lock.recolourLogo = checked
        }

        ToggleRow {
            text: Tr.tr("Hide notifications")
            subtext: Tr.tr("Keep notification content off the lock screen")
            checked: Config.lock.hideNotifs
            onToggled: GlobalConfig.lock.hideNotifs = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Session controls")
            subtext: Tr.tr("Show logout and power buttons on hover")
            checked: GlobalConfig.lock.enableSessionControls
            onToggled: GlobalConfig.lock.enableSessionControls = checked
        }

        // Fingerprint
        SectionHeader {
            text: Tr.tr("Fingerprint")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Fingerprint unlock")
            subtext: Tr.tr("Unlock with a fingerprint reader")
            checked: GlobalConfig.lock.enableFprint
            onToggled: GlobalConfig.lock.enableFprint = checked
        }

        StepperRow {
            last: true
            label: Tr.tr("Fingerprint tries")
            subtext: Tr.tr("Attempts before the reader gives up")
            value: GlobalConfig.lock.maxFprintTries
            from: 1
            to: 10
            stepSize: 1
            onMoved: v => GlobalConfig.lock.maxFprintTries = Math.round(v)
        }

        // Face unlock
        SectionHeader {
            text: Tr.tr("Face unlock")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Face unlock")
            subtext: Tr.tr("Unlock with Howdy")
            checked: GlobalConfig.lock.enableHowdy
            onToggled: GlobalConfig.lock.enableHowdy = checked
        }

        StepperRow {
            label: Tr.tr("Face tries")
            subtext: Tr.tr("Attempts before face recognition gives up")
            value: GlobalConfig.lock.maxHowdyTries
            from: 1
            to: 10
            stepSize: 1
            onMoved: v => GlobalConfig.lock.maxHowdyTries = Math.round(v)
        }

        ToggleRow {
            last: true
            text: Tr.tr("Face unlock on wake")
            subtext: Tr.tr("Start face recognition when the session wakes")
            checked: GlobalConfig.lock.triggerHowdyOnWake
            onToggled: GlobalConfig.lock.triggerHowdyOnWake = checked
        }
    }
}
