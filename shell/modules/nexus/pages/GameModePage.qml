pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var gameConf: GlobalConfig.utilities.gameMode

    title: Tr.tr("Game mode")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Effects applied while game mode is on
        SectionHeader {
            first: true
            text: Tr.tr("Effects")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Animations")
            subtext: Tr.tr("Turn off window and shell animations")
            checked: root.gameConf.animations
            onToggled: {
                root.gameConf.animations = checked;
                GameMode.apply();
            }
        }

        ToggleRow {
            text: Tr.tr("Blur")
            subtext: Tr.tr("Disable background blur")
            checked: root.gameConf.blur
            onToggled: {
                root.gameConf.blur = checked;
                GameMode.apply();
            }
        }

        ToggleRow {
            text: Tr.tr("Shadows")
            subtext: Tr.tr("Disable window shadows")
            checked: root.gameConf.shadows
            onToggled: {
                root.gameConf.shadows = checked;
                GameMode.apply();
            }
        }

        ToggleRow {
            text: Tr.tr("Gaps and borders")
            subtext: Tr.tr("Collapse gaps and thin the borders")
            checked: root.gameConf.gaps
            onToggled: {
                root.gameConf.gaps = checked;
                GameMode.apply();
            }
        }

        ToggleRow {
            text: Tr.tr("Rounded corners")
            subtext: Tr.tr("Square off window corners")
            checked: root.gameConf.rounding
            onToggled: {
                root.gameConf.rounding = checked;
                GameMode.apply();
            }
        }

        ToggleRow {
            text: Tr.tr("Wobble")
            subtext: Tr.tr("Stop windows wobbling when dragged")
            checked: root.gameConf.wobble
            onToggled: {
                root.gameConf.wobble = checked;
                GameMode.apply();
            }
        }

        ToggleRow {
            text: Tr.tr("Glow")
            subtext: Tr.tr("Disable the glow effect")
            checked: root.gameConf.glow
            onToggled: {
                root.gameConf.glow = checked;
                GameMode.apply();
            }
        }

        ToggleRow {
            text: Tr.tr("Motion blur")
            subtext: Tr.tr("Disable motion blur")
            checked: root.gameConf.motionBlur
            onToggled: {
                root.gameConf.motionBlur = checked;
                GameMode.apply();
            }
        }

        ToggleRow {
            last: true
            text: Tr.tr("Tearing")
            subtext: Tr.tr("Allow tearing for lower latency")
            checked: root.gameConf.tearing
            onToggled: {
                root.gameConf.tearing = checked;
                GameMode.apply();
            }
        }

        // Auto-enable
        SectionHeader {
            text: Tr.tr("Auto-enable")
        }

        ToggleRow {
            first: true
            last: true
            text: Tr.tr("Fullscreen apps")
            subtext: Tr.tr("Turn on game mode while an app is fullscreen")
            checked: root.gameConf.autoFullscreen
            onToggled: root.gameConf.autoFullscreen = checked
        }

        ToggleRow {
            first: true
            last: true
            text: Tr.tr("Notify on auto-enable")
            subtext: Tr.tr("Show a toast when a rule switches game mode on or off")
            checked: root.gameConf.autoToast
            onToggled: root.gameConf.autoToast = checked
        }

        Repeater {
            model: root.gameConf.rules.values

            ColumnLayout {
                id: entry

                required property var modelData
                required property int index

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                TextFieldRow {
                    first: true
                    label: Tr.tr("Window class")
                    subtext: Tr.tr("Matched against the class of the focused window")
                    placeholderText: Tr.tr("e.g. steam")
                    value: root.gameConf.rules.at(entry.index)?.pattern ?? entry.modelData.pattern ?? ""
                    onEditingFinished: v => root.gameConf.rules.at(entry.index).pattern = v
                }

                RowButton {
                    last: true
                    icon: "delete"
                    text: Tr.tr("Remove rule")
                    onClicked: root.gameConf.rules.remove(entry.index)
                }
            }
        }

        RowButton {
            first: true
            last: true
            icon: "add"
            text: Tr.tr("Add rule")
            onClicked: root.gameConf.rules.insert({
                pattern: ""
            })
        }
    }
}
