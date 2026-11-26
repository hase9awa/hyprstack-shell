pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Hyprstack.Config
import Hyprstack.I18n
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var cfg: GlobalConfig.pointer
    // The compositor's own values, shown until the shell has been told better.
    readonly property var live: Hypr.options

    // Sentinel values must match PointerConfig: -2 and -1 mean "inherit".
    readonly property real sensitivity: Pointer.shownReal(cfg.sensitivity, -2, live["input:sensitivity"], 0)
    readonly property real scrollFactor: Pointer.shownReal(cfg.scrollFactor, -1, live["input:scroll_factor"], 1)
    readonly property real touchpadScrollFactor: Pointer.shownReal(cfg.touchpadScrollFactor, -1, live["input:touchpad:scroll_factor"], 1)
    readonly property real hideTimeout: Pointer.shownReal(cfg.cursorHideTimeout, -1, live["cursor:inactive_timeout"], 0)
    readonly property int followMouse: Pointer.shownInt(cfg.followMouse, -1, live["input:follow_mouse"], 1)
    readonly property bool naturalScroll: Pointer.shownBool(cfg.naturalScroll, live["input:natural_scroll"], false)
    readonly property bool leftHanded: Pointer.shownBool(cfg.leftHanded, live["input:left_handed"], false)
    readonly property bool touchpadNaturalScroll: Pointer.shownBool(cfg.touchpadNaturalScroll, live["input:touchpad:natural_scroll"], false)
    readonly property bool touchpadTapToClick: Pointer.shownBool(cfg.touchpadTapToClick, live["input:touchpad:tap-to-click"], true)
    readonly property bool touchpadWhileTyping: Pointer.shownBool(cfg.touchpadDisableWhileTyping, live["input:touchpad:disable_while_typing"], true)
    readonly property bool touchpadGestureScroll: Pointer.shownBool(cfg.touchpadGestureScroll, null, Pointer.varsGestureScrollEnabled)
    readonly property bool touchpadGestureWorkspace: Pointer.shownBool(cfg.touchpadGestureWorkspace, null, Pointer.varsGestureWorkspaceEnabled)
    readonly property bool touchpadGestureOverview: Pointer.shownBool(cfg.touchpadGestureOverview, null, true)
    readonly property int touchpadGestureScrollFingers: Pointer.shownInt(cfg.touchpadGestureScrollFingers, 0, null, Pointer.varsGestureScrollFingers)
    readonly property int touchpadGestureWorkspaceFingers: Pointer.shownInt(cfg.touchpadGestureWorkspaceFingers, 0, null, Pointer.varsGestureWorkspaceFingers)
    readonly property int touchpadGestureOverviewFingers: Pointer.shownInt(cfg.touchpadGestureOverviewFingers, 0, null, Pointer.varsGestureOverviewFingers)
    readonly property string accelProfile: {
        if (cfg.accelProfile !== "")
            return cfg.accelProfile;
        const current = live["input:accel_profile"];
        return typeof current === "string" && current !== "" && current !== "[[EMPTY]]" ? current : "adaptive";
    }

    readonly property list<MenuItem> accelItems: [
        MenuItem {
            text: Tr.tr("Adaptive")
            icon: "speed"
            value: "adaptive"
        },
        MenuItem {
            text: Tr.tr("Flat")
            icon: "trending_flat"
            value: "flat"
        }
    ]

    // Ordered to match the Hyprland input:focus_follow_mouse values
    readonly property list<MenuItem> focusItems: [
        MenuItem {
            text: Tr.trCtx("Never", "focus follows the pointer")
            icon: "block"
            value: 0
        },
        MenuItem {
            text: Tr.trCtx("Follow the pointer", "focus follows the pointer")
            icon: "mouse"
            value: 1
        },
        MenuItem {
            text: Tr.trCtx("Detached", "focus follows the pointer")
            icon: "near_me"
            value: 2
        },
        MenuItem {
            text: Tr.trCtx("Separate", "focus follows the pointer")
            icon: "adjust"
            value: 3
        }
    ]

    title: Tr.tr("Mouse & pointer")
    objectName: "mousePointerPage"

    // The page is rebuilt on every visit, so each build kicks one cheap scan
    // of the icon folders in case a theme was installed since the shell started.
    readonly property Timer themeScanKick: Timer {
        interval: 0
        running: true
        onTriggered: Pointer.refreshCursorThemes()
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Cursor
        SectionHeader {
            first: true
            text: Tr.tr("Cursor")
        }

        StepperRow {
            objectName: "pointerCursorSize"
            first: true
            label: Tr.tr("Pointer size")
            subtext: Tr.tr("Cursor size in pixels, from 8 to 64")
            value: Pointer.cursorSize
            from: 8
            to: 64
            stepSize: 4
            onMoved: v => root.cfg.cursorSize = Math.round(v)
        }

        SelectRow {
            objectName: "pointerCursorTheme"
            label: Tr.tr("Cursor theme")
            subtext: Tr.tr("A theme from your icon folders; the first entry keeps the Hyprland one")
            menuItems: [inheritTheme, ...themeVariants.instances]
            // The list is rebuilt when a scan finishes, so the selection must
            // stay a binding instead of being pinned to one instance.
            updateActiveOnSelection: false
            active: menuItems.find(i => i.value === root.cfg.cursorTheme) ?? inheritTheme
            onSelected: item => root.cfg.cursorTheme = item.value

            MenuItem {
                id: inheritTheme

                text: Tr.tr("Keep the Hyprland theme")
                value: ""
            }

            Variants {
                id: themeVariants

                // The scan keeps a stored theme that is no longer installed in
                // the list, so the model never has to depend on the config.
                model: Pointer.cursorThemes

                MenuItem {
                    required property string modelData

                    text: modelData
                    value: modelData
                }
            }
        }

        StepperRow {
            objectName: "pointerCursorHide"
            label: Tr.tr("Hide the pointer")
            subtext: Tr.tr("Seconds of inactivity before it disappears; 0 keeps it visible")
            value: root.hideTimeout
            from: 0
            to: 600
            stepSize: 1
            onMoved: v => root.cfg.cursorHideTimeout = Math.round(v)
            last: true
        }

        // Mouse
        SectionHeader {
            text: Tr.tr("Mouse")
        }

        SliderRow {
            objectName: "pointerSensitivity"
            first: true
            icon: "speed"
            label: Tr.tr("Sensitivity")
            value: (root.sensitivity + 1) / 2
            valueLabel: root.sensitivity.toFixed(2)
            onMoved: value => root.cfg.sensitivity = Math.round((value * 2 - 1) * 100) / 100
        }

        SelectRow {
            objectName: "pointerAcceleration"
            label: Tr.tr("Acceleration")
            subtext: Tr.tr("Adaptive speeds the pointer up as it moves, flat keeps one speed")
            menuItems: root.accelItems
            active: root.accelItems.find(i => i.value === root.accelProfile) ?? null
            onSelected: item => root.cfg.accelProfile = item.value
        }

        ToggleRow {
            objectName: "pointerInvertScrolling"
            text: Tr.tr("Invert scrolling")
            subtext: Tr.tr("The wheel scrolls in the opposite direction")
            checked: root.naturalScroll
            onToggled: root.cfg.naturalScroll = checked ? PointerTriState.On : PointerTriState.Off
        }

        SliderRow {
            objectName: "pointerScrollSpeed"
            icon: "swap_vert"
            label: Tr.tr("Scroll speed")
            value: Math.min(5, root.scrollFactor) / 5
            valueLabel: `${root.scrollFactor.toFixed(2)}×`
            onMoved: value => root.cfg.scrollFactor = Math.round(value * 500) / 100
        }

        ToggleRow {
            objectName: "pointerSwapButtons"
            text: Tr.tr("Swap mouse buttons")
            subtext: Tr.tr("The right button becomes the primary one")
            checked: root.leftHanded
            onToggled: root.cfg.leftHanded = checked ? PointerTriState.On : PointerTriState.Off
        }

        SelectRow {
            objectName: "pointerFocusFollows"
            label: Tr.tr("Focus follows the pointer")
            subtext: Tr.tr("Detached lets clicks choose the window, separate keeps clicks from moving focus")
            menuItems: root.focusItems
            active: root.focusItems.find(i => i.value === root.followMouse) ?? null
            onSelected: item => root.cfg.followMouse = item.value
            last: true
        }

        // Touchpad
        SectionHeader {
            text: Tr.tr("Touchpad")
        }

        ToggleRow {
            objectName: "pointerTouchpadInvertScrolling"
            first: true
            text: Tr.tr("Invert touchpad scrolling")
            subtext: Tr.tr("Swipes move the content the way your fingers do")
            checked: root.touchpadNaturalScroll
            onToggled: root.cfg.touchpadNaturalScroll = checked ? PointerTriState.On : PointerTriState.Off
        }

        ToggleRow {
            objectName: "pointerTouchpadTapToClick"
            text: Tr.tr("Tap to click")
            subtext: Tr.tr("A tap on the touchpad acts as a click")
            checked: root.touchpadTapToClick
            onToggled: root.cfg.touchpadTapToClick = checked ? PointerTriState.On : PointerTriState.Off
        }

        ToggleRow {
            objectName: "pointerTouchpadTyping"
            text: Tr.tr("Disable while typing")
            subtext: Tr.tr("Ignore the touchpad while you type")
            checked: root.touchpadWhileTyping
            onToggled: root.cfg.touchpadDisableWhileTyping = checked ? PointerTriState.On : PointerTriState.Off
        }

        SliderRow {
            objectName: "pointerTouchpadScrollSpeed"
            icon: "swap_vert"
            label: Tr.tr("Touchpad scroll speed")
            value: Math.min(5, root.touchpadScrollFactor) / 5
            valueLabel: `${root.touchpadScrollFactor.toFixed(2)}×`
            onMoved: value => root.cfg.touchpadScrollFactor = Math.round(value * 500) / 100
        }

        // Touchpad gestures
        SectionHeader {
            text: Tr.tr("Touchpad gestures")
        }

        ToggleRow {
            objectName: "pointerTouchpadGestureScroll"
            first: true
            text: Tr.tr("Swipe to scroll")
            subtext: Tr.tr("Scroll horizontally with a touchpad swipe")
            checked: root.touchpadGestureScroll
            onToggled: root.cfg.touchpadGestureScroll = checked ? PointerTriState.On : PointerTriState.Off
        }

        StepperRow {
            objectName: "pointerTouchpadGestureScrollFingers"
            label: Tr.tr("Scrolling fingers")
            subtext: Tr.tr("Finger count for the scrolling gesture")
            value: root.touchpadGestureScrollFingers
            from: 3
            to: 9
            stepSize: 1
            enabled: root.touchpadGestureScroll
            onMoved: v => root.cfg.touchpadGestureScrollFingers = Math.round(v)
        }

        ToggleRow {
            objectName: "pointerTouchpadGestureWorkspace"
            text: Tr.tr("Swipe to switch workspaces")
            subtext: Tr.tr("Switch workspaces with a vertical touchpad swipe")
            checked: root.touchpadGestureWorkspace
            onToggled: root.cfg.touchpadGestureWorkspace = checked ? PointerTriState.On : PointerTriState.Off
        }

        StepperRow {
            objectName: "pointerTouchpadGestureWorkspaceFingers"
            label: Tr.tr("Workspace swipe fingers")
            subtext: Tr.tr("Finger count for the workspace gesture")
            value: root.touchpadGestureWorkspaceFingers
            from: 3
            to: 9
            stepSize: 1
            enabled: root.touchpadGestureWorkspace
            onMoved: v => root.cfg.touchpadGestureWorkspaceFingers = Math.round(v)
        }

        ToggleRow {
            objectName: "pointerTouchpadGestureOverview"
            text: Tr.tr("Swipe for overview")
            subtext: Tr.tr("Swipe up to open the overview and down to accept")
            checked: root.touchpadGestureOverview
            onToggled: root.cfg.touchpadGestureOverview = checked ? PointerTriState.On : PointerTriState.Off
        }

        StepperRow {
            objectName: "pointerTouchpadGestureOverviewFingers"
            label: Tr.tr("Overview fingers")
            subtext: Tr.tr("Finger count for the overview gesture")
            value: root.touchpadGestureOverviewFingers
            from: 3
            to: 9
            stepSize: 1
            enabled: root.touchpadGestureOverview
            onMoved: v => root.cfg.touchpadGestureOverviewFingers = Math.round(v)
            last: true
        }
    }
}
