pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Components
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Wallpaper & style")

    readonly property list<MenuItem> blurVariants: [
        MenuItem { text: Tr.tr("Kawase"); value: 0 },
        MenuItem { text: Tr.tr("Frosted glass"); value: 1 },
        MenuItem { text: Tr.tr("Ripples"); value: 2 },
        MenuItem { text: Tr.tr("Drops"); value: 3 },
        MenuItem { text: Tr.tr("Water"); value: 4 },
        MenuItem { text: Tr.tr("Fluid jar"); value: 5 },
        MenuItem { text: Tr.tr("Prism"); value: 6 },
        MenuItem { text: Tr.tr("Heat shimmer"); value: 7 },
        MenuItem { text: Tr.tr("Acrylic"); value: 8 },
        MenuItem { text: Tr.tr("Aurora"); value: 9 },
        MenuItem { text: Tr.tr("Haze"); value: 10 }
    ]


    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        NavRow {
            objectName: "applicationColours"
            first: true
            last: true
            icon: "palette"
            text: Tr.tr("Application colours")
            subtext: Tr.tr("GTK, Qt, Java and terminal colour synchronization")
            onClicked: root.nState.openSubPage(4)
        }

        StyledClippingRect {
            id: wallWrapper

            Layout.alignment: Qt.AlignHCenter
            implicitWidth: {
                const screen = root.nState.screen;
                return implicitHeight / screen.height * screen.width;
            }
            implicitHeight: {
                const screen = root.nState.screen;
                const cWidth = root.cappedWidth;
                return Math.min(Math.round(cWidth * 0.4), cWidth / screen.width * screen.height);
            }

            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.large

            Loader {
                anchors.centerIn: parent
                opacity: Config.background.wallpaperEnabled ? 0 : 1
                active: opacity > 0

                sourceComponent: ColumnLayout {
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hide_image"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Tr.tr("Wallpaper disabled")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.large
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }
            }

            Item {
                anchors.fill: parent
                opacity: Config.background.wallpaperEnabled ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }

                Loader {
                    id: wallIndicatorLoader

                    anchors.centerIn: parent

                    opacity: 0
                    active: opacity > 0

                    sourceComponent: StyledRect {
                        implicitWidth: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2
                        implicitHeight: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2

                        color: Colours.palette.m3primaryContainer
                        radius: Tokens.rounding.full

                        LoadingIndicator {
                            id: wallLoadingIndicator

                            anchors.centerIn: parent
                            containsIcon: true
                            implicitSize: Math.min(wallWrapper.implicitWidth, wallWrapper.implicitHeight) * 0.4
                        }
                    }

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                Timer {
                    id: wallLoadDebounceTimer

                    interval: 100
                    onTriggered: {
                        if (wallImg.status !== Image.Ready)
                            wallIndicatorLoader.opacity = 1;
                    }
                }

                FadeImage {
                    id: wallImg

                    anchors.fill: parent
                    source: Wallpapers.current
                    preventInit: wallIndicatorLoader.opacity > 0
                    fadeOutAnim: Anim.DefaultEffects
                    fadeInAnim: Anim.SlowEffects

                    onSourceChanged: wallLoadDebounceTimer.restart()

                    onStatusChanged: {
                        if (status === Image.Ready) {
                            wallLoadDebounceTimer.stop();
                            wallIndicatorLoader.opacity = 0;
                        }
                    }
                }
            }
        }

        ButtonRow {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "wallpaper"
                text: Tr.tr("Wallpapers")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                disabled: !Config.background.wallpaperEnabled
                onClicked: root.nState.openSubPage(1) // Wallpaper page
            }

            IconTextButton {
                icon: "palette"
                text: Tr.tr("Colours")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: root.nState.openSubPage(3) // Colours page
            }
        }

        ToggleRow {
            first: true
            text: Tr.tr("Display wallpaper")
            checked: Config.background.wallpaperEnabled
            onToggled: GlobalConfig.background.wallpaperEnabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            text: Tr.tr("Transparency")
            objectName: "appearanceTransparency"
            // TRANSLATORS: %1/%2 = opacity values from 0 to 1 for the base surface and layered surfaces
            subtext: Tr.tr("Base %1, layers %2").arg(Colours.transparency.base).arg(Colours.transparency.layers)
            checked: Colours.transparency.enabled
            onToggled: GlobalConfig.appearance.transparency.enabled = checked
        }

        SliderRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            icon: "opacity"
            objectName: "appearanceOpacity"
            label: Tr.tr("Opacity")
            valueLabel: `${Math.round(value * 100)}%`
            value: GlobalConfig.appearance.transparency.base
            enabled: Colours.transparency.enabled
            onMoved: value => GlobalConfig.appearance.transparency.base = value
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            text: Tr.tr("Blur")
            objectName: "appearanceBlur"
            checked: Effects.blurEnabled
            onToggled: Effects.setBlurEnabled(checked)
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceDesktopFrame"
            text: Tr.tr("Desktop frame in tiling mode")
            checked: Tiling.desktopFrame
            onToggled: Tiling.set("desktopFrame", checked)
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceTilingGaps"
            text: Tr.tr("Gaps in tiling mode")
            subtext: Tr.tr("Toggle with Win+G")
            checked: Tiling.gaps
            onToggled: Tiling.set("gaps", checked)
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceTilingFocusOnHover"
            text: Tr.tr("Switch windows on hover in tiling mode")
            subtext: Tr.tr("When disabled, hover a partly hidden window or the screen edge, then click the arrow to switch.")
            checked: Tiling.focusOnHover
            onToggled: Tiling.set("focusOnHover", checked)
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceTilingEdgeScroll"
            text: Tr.tr("Scroll columns at screen edges on hover")
            subtext: Tr.tr("Disable to keep hover focus without moving the tape. Click a window or use shortcuts to reveal it.")
            checked: Tiling.edgeScroll
            onToggled: Tiling.set("edgeScroll", checked)
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceAutoscroll"
            text: Tr.tr("Middle-click autoscroll")
            subtext: Tr.tr("Hold the wheel briefly, then move. Short clicks keep tab and link actions; Esc stops.")
            checked: Tiling.autoscroll
            onToggled: Tiling.set("autoscroll", checked)
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceFocusBorderWidth"
            label: Tr.tr("Window border width")
            subtext: Tr.tr("Scrolling mode only; 0 hides the window border")
            value: Tiling.focusBorderWidth
            from: 0
            to: 10
            onMoved: v => Tiling.set("focusBorderWidth", v)
        }

        PaletteRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceFocusBorderColor"
            label: Tr.tr("Window border colour")
            subtext: Tr.tr("Scrolling mode; choose a colour from the current scheme independently of the theme accent")
            value: Tiling.focusBorderColor
            palette: Colours.current
            choices: Tiling.borderColorChoices.map(choice => ({role: choice.role, label: Tr.tr(choice.label)}))
            onSelected: role => Tiling.set("focusBorderColor", role)
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceWindowRounding"
            label: Tr.tr("Window corner rounding")
            subtext: Tr.tr("Radius in pixels; 0 makes window corners square")
            value: Tiling.windowRounding
            from: 0
            to: 60
            onMoved: v => Tiling.set("windowRounding", v)
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            last: true
            objectName: "appearanceDarkTheme"
            text: Tr.tr("Dark theme")
            checked: !Colours.light
            onToggled: Colours.setMode(checked ? "dark" : "light")
        }

        SectionHeader { text: Tr.tr("Window gaps") }

        StepperRow {
            first: true
            objectName: "appearanceGapsIn"
            label: Tr.tr("Inner gaps")
            subtext: Tr.tr("Padding on each side of a tiled window, in pixels")
            value: Tiling.gapsIn
            from: 0
            to: 100
            onMoved: v => Tiling.set("gapsIn", v)
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            last: true
            objectName: "appearanceGapsOut"
            label: Tr.tr("Outer gaps")
            subtext: Tr.tr("Padding at the workspace edges, in pixels; identical for every window count")
            value: Tiling.gapsOut
            from: 0
            to: 100
            onMoved: v => Tiling.set("gapsOut", v)
        }

        SectionHeader { text: Tr.tr("Background blur") }

        SelectRow {
            first: true
            objectName: "appearanceBlurVariant"
            label: Tr.tr("Blur effect")
            subtext: Tr.tr("Visible behind translucent windows and panels; animated effects use more GPU")
            menuItems: root.blurVariants
            active: root.blurVariants[Effects.blurVariant]
            enabled: Effects.blurEnabled
            onSelected: item => Effects.set("blurVariant", item.value)
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceBlurSize"
            label: Tr.tr("Blur size")
            value: Effects.blurSize
            from: 0
            to: 100
            enabled: Effects.blurEnabled
            onMoved: v => Effects.set("blurSize", v)
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceBlurPasses"
            label: Tr.tr("Blur passes")
            value: Effects.blurPasses
            from: 1
            to: 10
            enabled: Effects.blurEnabled
            onMoved: v => Effects.set("blurPasses", v)
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            last: true
            objectName: "appearanceProportionalBlur"
            text: Tr.tr("Proportional blur")
            subtext: Tr.tr("Adjust blur strength to each pixel's opacity")
            checked: Effects.proportionalBlur
            enabled: Effects.blurEnabled
            onToggled: Effects.set("proportionalBlur", checked)
        }

        SectionHeader { text: Tr.tr("Window wobble") }

        ToggleRow {
            first: true
            objectName: "appearanceWindowWobble"
            text: Tr.tr("Wobbly windows")
            subtext: Tr.tr("Elastic deformation when moving or resizing windows")
            checked: Effects.windowWobble
            onToggled: Effects.set("windowWobble", checked)
        }

        SliderRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceWobbleIntensity"
            icon: "waves"
            label: Tr.tr("Wobble intensity")
            valueLabel: `${Math.round(value * 200)}%`
            value: Effects.wobbleIntensity / 2
            enabled: Effects.windowWobble
            onMoved: v => Effects.set("wobbleIntensity", v * 2)
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceWobbleStiffness"
            label: Tr.tr("Spring stiffness")
            subtext: Tr.tr("Higher values pull the window back into shape faster")
            value: Effects.wobbleStiffness
            from: 1
            to: 1000
            enabled: Effects.windowWobble
            onMoved: v => Effects.set("wobbleStiffness", v)
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            last: true
            objectName: "appearanceWobbleDamping"
            label: Tr.tr("Spring damping")
            subtext: Tr.tr("Higher values make oscillations settle sooner")
            value: Effects.wobbleDamping
            from: 0
            to: 100
            enabled: Effects.windowWobble
            onMoved: v => Effects.set("wobbleDamping", v)
        }

        SectionHeader { text: Tr.tr("Window glow") }

        ToggleRow {
            first: true
            objectName: "appearanceWindowGlow"
            text: Tr.tr("Inner glow")
            subtext: Tr.tr("Light along the window edges in the current accent colour")
            checked: Effects.windowGlow
            onToggled: Effects.set("windowGlow", checked)
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceGlowSize"
            label: Tr.tr("Glow size")
            value: Effects.glowSize
            from: 0
            to: 100
            enabled: Effects.windowGlow
            onMoved: v => Effects.set("glowSize", v)
        }

        SliderRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            last: true
            objectName: "appearanceGlowOpacity"
            icon: "flare"
            label: Tr.tr("Glow intensity")
            valueLabel: `${Math.round(value * 100)}%`
            value: Effects.glowOpacity
            enabled: Effects.windowGlow
            onMoved: v => Effects.set("glowOpacity", v)
        }

        SectionHeader { text: Tr.tr("Motion blur") }

        ToggleRow {
            first: true
            objectName: "appearanceMotionBlur"
            text: Tr.tr("Window motion blur")
            subtext: Tr.tr("Blur trails when moving or resizing windows")
            checked: Effects.motionBlur
            onToggled: Effects.set("motionBlur", checked)
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            last: true
            objectName: "appearanceMotionBlurSamples"
            label: Tr.tr("Motion blur samples")
            value: Effects.motionBlurSamples
            from: 1
            to: 64
            enabled: Effects.motionBlur
            onMoved: v => Effects.set("motionBlurSamples", v)
        }

        SectionHeader { text: Tr.tr("Shadows") }

        ToggleRow {
            first: true
            objectName: "appearanceWindowShadows"
            text: Tr.tr("Window shadows")
            subtext: Tr.tr("The same shadow for active and inactive windows")
            checked: Effects.windowShadows
            onToggled: Effects.set("windowShadows", checked)
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceUiShadows"
            text: Tr.tr("Interface shadows")
            subtext: Tr.tr("Panels, menus and desktop widgets")
            checked: Effects.uiShadows
            onToggled: Effects.set("uiShadows", checked)
        }

        StepperRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            objectName: "appearanceShadowSize"
            label: Tr.tr("Shadow size")
            subtext: Tr.tr("Pixels; 0 disables shadows")
            value: Effects.shadowSize
            from: 0
            to: 60
            onMoved: v => Effects.set("shadowSize", v)
        }

        SliderRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            last: true
            objectName: "appearanceShadowOpacity"
            icon: "shadow"
            label: Tr.tr("Shadow intensity")
            valueLabel: `${Math.round(value * 100)}%`
            value: Effects.shadowOpacity
            onMoved: v => Effects.set("shadowOpacity", v)
        }

        SectionHeader { text: Tr.tr("Interface scale") }

        StepperRow {
            first: true
            last: true
            objectName: "appearanceShellScale"
            label: Tr.tr("Shell scale")
            subtext: Tr.tr("Panel, menus, text and desktop widgets, in percent")
            value: Math.round(GlobalConfig.appearance.scale * 100)
            from: 50
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.appearance.scale = v / 100
        }
    }
}
