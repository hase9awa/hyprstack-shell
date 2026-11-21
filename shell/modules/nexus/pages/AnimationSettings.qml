pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Components
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Animations")
    isSubPage: true
    objectName: "animationSettingsPage"

    readonly property list<MenuItem> shellOptions: [
        MenuItem { text: Tr.tr("Default"); value: "default" },
        MenuItem { text: "Goop"; value: "goop" },
        MenuItem { text: "Fluent"; value: "fluent" },
        MenuItem { text: Tr.tr("Snappy"); value: "snappy" },
        MenuItem { text: Tr.tr("Cinematic"); value: "cinematic" },
        MenuItem { text: Tr.tr("Reduced motion"); value: "reduced" }
    ]
    readonly property list<MenuItem> windowOptions: [
        MenuItem { text: Tr.tr("Default"); value: "default" },
        MenuItem { text: Tr.tr("Spring"); value: "spring" },
        MenuItem { text: Tr.tr("Glide"); value: "glide" },
        MenuItem { text: Tr.tr("Snappy"); value: "snappy" },
        MenuItem { text: Tr.tr("Cinematic"); value: "cinematic" },
        MenuItem { text: Tr.tr("Reduced motion"); value: "reduced" }
    ]

    function shellDescription(): string {
        switch (Animations.shellPreset) {
        case "goop": return Tr.tr("Viscous panels, workspace splashes and drips on hover");
        case "fluent": return Tr.tr("Fluid, restrained transitions inspired by Fluent 2");
        case "snappy": return Tr.tr("Short, precise movements with a quick response");
        case "cinematic": return Tr.tr("Measured acceleration and spacious, flowing transitions");
        case "reduced": return Tr.tr("Instant shell transitions with no animated travel");
        default: return Tr.tr("Original Hyprstack animations and your existing motion tokens");
        }
    }

    function windowDescription(): string {
        switch (Animations.windowPreset) {
        case "spring": return Tr.tr("Gentle spring opening and elastic workspace transitions");
        case "glide": return Tr.tr("Windows slide into place and workspaces drift smoothly");
        case "snappy": return Tr.tr("Fast opening with a subtle zoom and short workspace travel");
        case "cinematic": return Tr.tr("Deep zoom opening and flowing vertical workspace transitions");
        case "reduced": return Tr.tr("Instant window opening, closing, movement and workspace changes");
        default: return Tr.tr("Original window and workspace animations");
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.small

        StyledText {
            Layout.fillWidth: true
            text: Tr.tr("Presets apply immediately and are saved independently.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.Wrap
        }

        SectionHeader { first: true; text: Tr.tr("Shell animations") }

        SelectRow {
            objectName: "shellAnimationPreset"
            first: true
            last: true
            label: Tr.tr("Shell preset")
            subtext: root.shellDescription()
            menuItems: root.shellOptions
            updateActiveOnSelection: false
            active: root.shellOptions.find(item => item.value === Animations.shellPreset) ?? root.shellOptions[0]
            onSelected: item => GlobalConfig.appearance.anim.shellPreset = item.value
        }

        MotionPreview {
            id: shellPreview
            objectName: "shellAnimationPreview"
            Layout.fillWidth: true
            preset: Animations.shellPreset
        }

        SliderRow {
            objectName: "shellAnimationSpeed"
            first: true
            last: true
            icon: "speed"
            label: Tr.tr("Shell animation speed")
            value: (2 - Math.max(0.5, Math.min(2, GlobalConfig.appearance.anim.durations.scale))) / 1.5
            valueLabel: `${(1 / Math.max(0.01, GlobalConfig.appearance.anim.durations.scale)).toFixed(1)}×`
            enabled: Animations.shellPreset !== "reduced"
            onMoved: value => GlobalConfig.appearance.anim.durations.scale = Math.round((2 - value * 1.5) * 100) / 100
        }

        SectionHeader { text: Tr.tr("Window animations") }

        SelectRow {
            objectName: "windowAnimationPreset"
            first: true
            last: true
            label: Tr.tr("Window preset")
            subtext: root.windowDescription()
            menuItems: root.windowOptions
            updateActiveOnSelection: false
            active: root.windowOptions.find(item => item.value === Animations.windowPreset) ?? root.windowOptions[0]
            onSelected: item => GlobalConfig.appearance.anim.windowPreset = item.value
        }

        MotionPreview {
            id: windowPreview
            objectName: "windowAnimationPreview"
            Layout.fillWidth: true
            windows: true
            preset: Animations.windowPreset
        }

        StyledText {
            Layout.fillWidth: true
            visible: GameMode.animationsSuppressed
            text: Tr.tr("Game mode temporarily disables window animations. Your preset is kept.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.Wrap
        }

        ButtonRow {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.small
            spacing: Tokens.spacing.small

            IconTextButton {
                objectName: "replayAnimationPreview"
                icon: "replay"
                text: Tr.tr("Replay preview")
                type: IconTextButton.Tonal
                onClicked: { shellPreview.replay(); windowPreview.replay(); }
            }

            IconTextButton {
                objectName: "resetAnimationPresets"
                icon: "restore"
                text: Tr.tr("Restore defaults")
                type: IconTextButton.Text
                onClicked: {
                    GlobalConfig.appearance.anim.shellPreset = "default";
                    GlobalConfig.appearance.anim.windowPreset = "default";
                    GlobalConfig.appearance.anim.durations.scale = 1;
                }
            }
        }
    }
}
