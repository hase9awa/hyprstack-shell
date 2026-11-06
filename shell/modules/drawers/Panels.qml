import QtQuick
import Quickshell
import Hyprstack.Config
import qs.components
import qs.services
import qs.modules.bar as Bar
import qs.modules.dashboard as Dashboard
import qs.modules.launcher as Launcher
import qs.modules.notifications as Notifications
import qs.modules.osd as Osd
import qs.modules.session as Session
import qs.modules.sidebar as Sidebar
import qs.modules.utilities as Utilities
import qs.modules.bar.popouts as BarPopouts
import qs.modules.utilities.toasts as Toasts

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property Bar.BarWrapper bar
    required property real borderThickness

    readonly property alias osd: osd
    readonly property alias osdWrapper: osdWrapper
    readonly property alias notifications: notifications
    readonly property alias session: session
    readonly property alias sessionWrapper: sessionWrapper
    readonly property alias launcher: launcher
    readonly property alias dashboard: dashboard
    readonly property alias popouts: popoutsWrapper.content
    readonly property alias popoutsWrapper: popoutsWrapper
    readonly property alias utilities: utilities
    readonly property alias toasts: toasts
    readonly property alias sidebar: sidebar
    readonly property real sidebarTop: bar.atBottom ? 0
        : notifications.y + notifications.height - notifications.anchors.topMargin

    function overlaps(a: Item, b: Item): bool {
        return a !== b && a.visible && b.visible && a.width > 0 && a.height > 0
            && b.width > 0 && b.height > 0
            && a.x < b.x + b.width && b.x < a.x + a.width
            && a.y < b.y + b.height && b.y < a.y + a.height;
    }

    anchors.fill: parent
    anchors.margins: borderThickness
    anchors.topMargin: bar.topInset
    anchors.bottomMargin: bar.bottomInset

    Item {
        id: osdWrapper

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: sessionWrapper.anchors.rightMargin + session.width * (1 - session.offsetScale)
        clip: sidebar.visible || session.visible

        implicitWidth: osd.implicitWidth * (1 - osd.offsetScale)
        implicitHeight: osd.implicitHeight

        Osd.Wrapper {
            id: osd

            screen: root.screen
            screenState: root.screenState
            sidebarOrSessionVisible: sidebar.visible || session.visible

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }

    Notifications.Wrapper {
        id: notifications

        screenState: root.screenState
        sidebarPanel: sidebar
        osdPanel: osdWrapper
        sessionPanel: sessionWrapper
        utilitiesPanel: utilities

        anchors.top: parent.top
        anchors.right: parent.right
    }

    Item {
        id: sessionWrapper

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: sidebar.width * (1 - sidebar.offsetScale)
        clip: sidebar.visible

        implicitWidth: session.implicitWidth * (1 - session.offsetScale)
        implicitHeight: session.implicitHeight

        Session.Wrapper {
            id: session

            screenState: root.screenState
            sidebarVisible: sidebar.visible

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }

    Launcher.Wrapper {
        id: launcher
        z: 2

        screen: root.screen
        screenState: root.screenState
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
    }

    Dashboard.Wrapper {
        id: dashboard
        z: 2

        screenState: root.screenState
        atBottom: !root.bar.atBottom

        anchors.horizontalCenter: parent.horizontalCenter
    }

    BarPopouts.ClipWrapper {
        id: popoutsWrapper
        z: 3

        screen: root.screen
        borderThickness: root.borderThickness
        atBottom: root.bar.atBottom
    }

    Utilities.Wrapper {
        id: utilities
        z: 1

        screenState: root.screenState
        sidebar: sidebar
        popouts: popoutsWrapper.content
        atBottom: screenState.sidebar || sidebar.visible || !root.bar.atBottom

        y: atBottom ? parent.height - height
            + (movesWithSidebar ? (sidebar.atBottom ? sidebar.slideDistance : 0) : height + 5) * offsetScale
            : -(height + 5) * offsetScale
        anchors.right: parent.right
    }

    Toasts.Toasts {
        id: toasts

        anchors.bottom: sidebar.visible || !utilities.atBottom ? parent.bottom : utilities.top
        anchors.right: sidebar.left
        anchors.margins: Tokens.padding.medium
    }

    Sidebar.Wrapper {
        id: sidebar

        screenState: root.screenState
        atBottom: root.bar.atBottom
        slideDistance: root.height - root.sidebarTop + 5
        readyToOpen: sidebar.contentPrepared && (!Config.utilities.enabled || utilities.contentPrepared)

        anchors.top: notifications.bottom
        anchors.bottom: utilities.atBottom ? utilities.top : parent.bottom
        anchors.right: parent.right
        anchors.topMargin: -notifications.anchors.topMargin

        states: State {
            name: "bottom"
            when: sidebar.atBottom

            AnchorChanges {
                target: sidebar
                anchors.top: undefined
                anchors.bottom: undefined
            }

            PropertyChanges {
                sidebar.y: root.sidebarTop + sidebar.slideDistance * sidebar.offsetScale
                sidebar.height: Math.max(0, root.height - root.sidebarTop - utilities.height)
            }
        }
    }

    // The joined SDF backgrounds are below all panel contents. A raised hover
    // panel also needs a backing surface where it covers notification text;
    // changing z alone would still let that text show through the shared fill.
    HoverSurface { panel: popoutsWrapper.content; bounds: popoutsWrapper }
    HoverSurface { panel: dashboard; bounds: dashboard }
    HoverSurface { panel: launcher; bounds: launcher }
    HoverSurface { panel: utilities; bounds: utilities; visible: !utilities.followSidebar && occluding }

    component HoverSurface: StyledRect {
        required property Item panel
        required property Item bounds
        readonly property bool occluding: [notifications, sidebar, utilities, dashboard, launcher]
            .some(other => bounds.z > other.z && root.overlaps(bounds, other))

        parent: panel
        anchors.fill: parent
        z: -1
        visible: occluding
        // Text from a lower panel must not bleed through translucent themes.
        color: Colours.palette.m3surface
        radius: Tokens.rounding.extraLarge
    }
}
