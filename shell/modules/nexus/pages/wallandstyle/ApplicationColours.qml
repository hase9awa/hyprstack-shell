pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var config: GlobalConfig.appearance.themeSync

    title: Tr.tr("Application colours")
    isSubPage: true
    objectName: "applicationColoursPage"

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            objectName: "themeSyncEnabled"
            first: true
            last: true
            text: Tr.tr("Synchronize application colours")
            subtext: Tr.tr("Apply the shell palette to applications. Turning this off restores previous settings.")
            checked: root.config.enabled
            onToggled: root.config.enabled = checked
        }

        SectionHeader { text: Tr.tr("Applications") }

        ToggleRow {
            objectName: "themeSyncSystem"
            first: true
            text: Tr.tr("System colour preference")
            subtext: Tr.tr("Light or dark mode for applications using desktop portals, including browsers and Electron apps")
            checked: root.config.system
            disabled: !root.config.enabled
            onToggled: root.config.system = checked
        }

        ToggleRow {
            objectName: "themeSyncGtk"
            text: "GTK 2 / 3 / 4 · libadwaita"
            checked: root.config.gtk
            disabled: !root.config.enabled
            onToggled: root.config.gtk = checked
        }

        ToggleRow {
            objectName: "themeSyncQt"
            text: "Qt 5 / 6 · KDE"
            subtext: Tr.tr("Requires qt5ct and qt6ct for Qt applications")
            checked: root.config.qt
            disabled: !root.config.enabled
            onToggled: root.config.qt = checked
        }

        ToggleRow {
            objectName: "themeSyncJava"
            last: true
            text: "Java · Swing"
            subtext: Tr.tr("Use the GTK look and feel. Requires GTK colour synchronization and an application restart.")
            checked: root.config.java
            disabled: !root.config.enabled || !root.config.gtk
            onToggled: root.config.java = checked
        }

        SectionHeader { text: Tr.tr("Terminals") }

        ToggleRow {
            objectName: "themeSyncTerminals"
            first: true
            text: Tr.tr("Synchronize terminal colours")
            subtext: Tr.tr("Background, text, cursor, selection and the 16 ANSI colours. Only installed or configured terminals are changed.")
            checked: root.config.terminals
            disabled: !root.config.enabled
            onToggled: root.config.terminals = checked
        }

        ToggleRow {
            objectName: "themeSyncLiveReload"
            last: true
            text: Tr.tr("Update running terminals")
            subtext: Tr.tr("Send the palette to open terminals in the current session")
            checked: root.config.liveReload
            disabled: !root.config.enabled || !root.config.terminals
            onToggled: root.config.liveReload = checked
        }

        SectionHeader { text: Tr.tr("Choose terminals") }

        Repeater {
            model: [{key: "kitty", label: "kitty"}, {key: "foot", label: "foot"}, {key: "alacritty", label: "Alacritty"},
                {key: "wezterm", label: "WezTerm"}, {key: "ghostty", label: "Ghostty"}, {key: "konsole", label: "Konsole"},
                {key: "xfce4Terminal", label: "Xfce Terminal"}, {key: "gnomeTerminal", label: "GNOME Terminal"},
                {key: "tilix", label: "Tilix"}, {key: "xterm", label: "XTerm"}]

            ToggleRow {
                required property var modelData
                required property int index

                objectName: "themeSync_" + modelData.key
                first: index === 0
                last: index === 9
                text: modelData.label
                checked: root.config[modelData.key]
                disabled: !root.config.enabled || !root.config.terminals
                onToggled: root.config[modelData.key] = checked
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            text: Tr.tr("Some applications need to be reopened. Applications with their own themes and sandboxed applications may require additional configuration.")
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            color: Colours.palette.m3onSurfaceVariant
        }

        IconTextButton {
            objectName: "themeSyncApply"
            Layout.topMargin: Tokens.spacing.small
            icon: "sync"
            text: ThemeSync.busy ? Tr.tr("Applying colours…") : Tr.tr("Apply colours now")
            disabled: ThemeSync.busy
            onClicked: ThemeSync.requestSync()
        }

        StyledText {
            Layout.fillWidth: true
            visible: ThemeSync.errors.length > 0
            text: ThemeSync.errors.join("\n")
            textFormat: Text.PlainText
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            color: Colours.palette.m3error
        }
    }
}
